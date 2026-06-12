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
    const userId = data?.userId;
    const displayName = data?.displayName;
    if (typeof userId !== 'string' || typeof displayName !== 'string') {
      return;
    }

    // Drop a stale socket if this userId is reconnecting.
    const existingSocket = socketByUser.get(userId);
    if (existingSocket && existingSocket !== socket.id) {
      users.delete(existingSocket);
    }

    users.set(socket.id, { userId, displayName });
    socketByUser.set(userId, socket.id);

    socket.emit('presence', { users: presenceList() });
    socket.broadcast.emit('user-joined', {
      user: { userId, displayName },
    });

    console.log(`register ${displayName} (${userId})`);
  });

  socket.on('call-offer', (data) => {
    const { from, to, sdp } = data ?? {};
    if (!from || !to) return;
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
