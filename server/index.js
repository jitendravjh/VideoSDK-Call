import http from 'http';
import { Server } from 'socket.io';

const PORT = process.env.PORT || 3000;

const httpServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', users: users.size }));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('VideoSDK signalling server');
});

const io = new Server(httpServer, {
  cors: { origin: '*' },
});

// socketId -> { userId, displayName }
const users = new Map();
// userId -> socketId
const socketByUser = new Map();
// userId -> peerUserId, tracks the other party once a call is offered
const activeCalls = new Map();

// Human-typable code charset, omitting easily confused characters (0/O, 1/I/L).
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function randomCode() {
  let code = '';
  for (let i = 0; i < 6; i += 1) {
    code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  }
  return code;
}

function uniqueCode() {
  let code = randomCode();
  while (socketByUser.has(code)) {
    code = randomCode();
  }
  return code;
}

function presenceList() {
  return [...users.values()].map((u) => ({
    userId: u.userId,
    displayName: u.displayName,
  }));
}

function socketIdFor(userId) {
  return socketByUser.get(userId);
}

function relayTo(userId, event, payload) {
  const socketId = socketIdFor(userId);
  if (socketId) {
    io.to(socketId).emit(event, payload);
    return true;
  }
  return false;
}

function clearCall(userId) {
  const peer = activeCalls.get(userId);
  if (peer) {
    activeCalls.delete(userId);
    activeCalls.delete(peer);
  }
  return peer;
}

io.on('connection', (socket) => {
  socket.on('register', (data) => {
    const displayName = data?.displayName;
    if (typeof displayName !== 'string') {
      return;
    }

    // The client passes back its previously assigned code when reconnecting so
    // its identity (and any shared code) survives the drop. A fresh client, or
    // one whose code is already taken by a live socket, gets a new code.
    const requested = typeof data?.userId === 'string' ? data.userId : '';
    let userId = requested;
    const existingSocket = requested ? socketByUser.get(requested) : undefined;
    if (existingSocket && existingSocket !== socket.id) {
      userId = uniqueCode();
    } else if (!requested) {
      userId = uniqueCode();
    }

    users.set(socket.id, { userId, displayName });
    socketByUser.set(userId, socket.id);

    socket.emit('registered', { user: { userId, displayName } });
    socket.emit('presence', { users: presenceList() });
    socket.broadcast.emit('user-joined', {
      user: { userId, displayName },
    });

    console.log(`register ${displayName} (${userId})`);
  });

  socket.on('call-offer', (data) => {
    const { from, to, sdp } = data ?? {};
    if (!from || !to) return;

    // The callee is already in a call with someone else: reject as busy
    // instead of overwriting their existing call mapping.
    const existingPeer = activeCalls.get(to);
    if (existingPeer && existingPeer !== from) {
      relayTo(from, 'call-end', { from: to, to: from, reason: 'busy' });
      return;
    }

    activeCalls.set(from, to);
    activeCalls.set(to, from);
    const delivered = relayTo(to, 'call-offer', { from, to, sdp });
    if (!delivered) {
      clearCall(from);
      relayTo(from, 'call-end', { from: to, to: from, reason: 'offline' });
    }
  });

  socket.on('call-answer', (data) => {
    const { from, to, sdp } = data ?? {};
    if (!from || !to) return;
    relayTo(to, 'call-answer', { from, to, sdp });
  });

  socket.on('call-decline', (data) => {
    const { from, to } = data ?? {};
    if (!from || !to) return;
    clearCall(from);
    relayTo(to, 'call-decline', { from, to });
  });

  socket.on('ice-candidate', (data) => {
    const { from, to, candidate } = data ?? {};
    if (!from || !to) return;
    relayTo(to, 'ice-candidate', { from, to, candidate });
  });

  socket.on('call-end', (data) => {
    const { from, to } = data ?? {};
    if (!from || !to) return;
    clearCall(from);
    relayTo(to, 'call-end', { from, to });
  });

  socket.on('disconnect', () => {
    const user = users.get(socket.id);
    if (!user) return;

    const { userId, displayName } = user;
    users.delete(socket.id);

    // Only clear the mapping if this socket is the current one for the user.
    if (socketByUser.get(userId) === socket.id) {
      socketByUser.delete(userId);
    }

    const peer = clearCall(userId);
    if (peer) {
      relayTo(peer, 'call-end', { from: userId, to: peer, reason: 'peer-left' });
    }

    io.emit('user-left', { userId });
    console.log(`disconnect ${displayName} (${userId})`);
  });
});

httpServer.listen(PORT, () => {
  console.log(`Signalling server listening on port ${PORT}`);
});
