import { randomUUID } from 'node:crypto';
import http from 'http';
import os from 'node:os';
import { Bonjour } from 'bonjour-service';
import { Server } from 'socket.io';

const PORT = process.env.PORT || 3000;
const MAX_CHAT_LEN = 2000;

// Non-internal IPv4 addresses, so the operator can see (and apps can reach) the
// server on the LAN.
function lanAddresses() {
  const result = [];
  for (const nets of Object.values(os.networkInterfaces())) {
    for (const net of nets ?? []) {
      const isV4 = net.family === 'IPv4' || net.family === 4;
      // Skip loopback and link-local (169.254.x), which apps cannot reach.
      if (isV4 && !net.internal && !net.address.startsWith('169.254.')) {
        result.push(net.address);
      }
    }
  }
  return result;
}

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
// roomCode -> Set<userId>. The room code is the host's user code.
const rooms = new Map();
// userId -> roomCode the user is currently in
const roomByUser = new Map();

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
  while (socketByUser.has(code) || rooms.has(code)) {
    code = randomCode();
  }
  return code;
}

// A fresh meeting-room code, distinct from every live user code and room code so
// the two namespaces never collide.
function uniqueRoomCode() {
  let code = randomCode();
  while (rooms.has(code) || socketByUser.has(code)) {
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

// The members of a room as {userId, displayName}, resolving live display names.
function meetingMembers(roomCode) {
  const set = rooms.get(roomCode);
  if (!set) return [];
  return [...set].map((uid) => {
    const socketId = socketByUser.get(uid);
    const record = socketId ? users.get(socketId) : undefined;
    return {
      userId: uid,
      displayName: record ? record.displayName : uid,
    };
  });
}

// Removes a user from their room and tells the remaining members. The meeting
// lives on under its generated code until the last member leaves (the host is
// not special). Deletes the room once empty. Safe to call for a user in no room.
function leaveRoom(userId) {
  const roomCode = roomByUser.get(userId);
  if (!roomCode) return;
  roomByUser.delete(userId);
  const set = rooms.get(roomCode);
  if (!set) return;
  set.delete(userId);
  for (const member of set) {
    relayTo(member, 'meeting-peer-left', { roomCode, userId });
  }
  if (set.size === 0) {
    rooms.delete(roomCode);
  }
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
    // Broadcast the full authoritative roster to everyone (not just the
    // joiner) so every client converges on the same list across reconnects and
    // missed deltas. Without this, a peer reached purely by code is never
    // advertised to the caller and keeps looking offline even after a call.
    io.emit('presence', { users: presenceList() });

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
    // Attach the caller's trusted display name so the callee shows a real name
    // even when the caller is not in the callee's presence list (join by code).
    const fromName = users.get(socket.id)?.displayName;
    const delivered = relayTo(to, 'call-offer', { from, to, sdp, fromName });
    if (!delivered) {
      clearCall(from);
      relayTo(from, 'call-end', { from: to, to: from, reason: 'offline' });
    }
  });

  socket.on('call-answer', (data) => {
    const { from, to, sdp } = data ?? {};
    if (!from || !to) return;
    const fromName = users.get(socket.id)?.displayName;
    relayTo(to, 'call-answer', { from, to, sdp, fromName });
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

  // Hosting generates a fresh meeting code (independent of the host's own code)
  // and opens a room under it; others join with that code.
  socket.on('meeting-host', () => {
    const user = users.get(socket.id);
    if (!user) return;
    const { userId } = user;
    leaveRoom(userId);
    const roomCode = uniqueRoomCode();
    rooms.set(roomCode, new Set([userId]));
    roomByUser.set(userId, roomCode);
    socket.emit('meeting-joined', { roomCode, peers: [] });
    console.log(`meeting-host ${userId} -> ${roomCode}`);
  });

  socket.on('meeting-join', (data) => {
    const user = users.get(socket.id);
    if (!user) return;
    const { userId } = user;
    const roomCode = typeof data?.roomCode === 'string' ? data.roomCode : '';
    const set = rooms.get(roomCode);
    if (!set) {
      socket.emit('meeting-error', { reason: 'no-such-meeting' });
      return;
    }
    // Already in this room (idempotent retry): re-send the roster without
    // churning the other members with a spurious leave/join.
    if (roomByUser.get(userId) === roomCode) {
      socket.emit('meeting-joined', {
        roomCode,
        peers: meetingMembers(roomCode).filter((p) => p.userId !== userId),
      });
      return;
    }
    leaveRoom(userId);
    // Existing members are sent to the joiner so it can establish a connection
    // to each; the joiner is then announced to those members.
    const peers = meetingMembers(roomCode).filter((p) => p.userId !== userId);
    set.add(userId);
    roomByUser.set(userId, roomCode);
    socket.emit('meeting-joined', { roomCode, peers });
    for (const member of set) {
      if (member !== userId) {
        relayTo(member, 'meeting-peer-joined', {
          roomCode,
          user: { userId, displayName: user.displayName },
        });
      }
    }
    console.log(`meeting-join ${userId} -> ${roomCode}`);
  });

  socket.on('meeting-leave', () => {
    const user = users.get(socket.id);
    if (user) leaveRoom(user.userId);
  });

  // Mesh per-pair signalling: stateless userId-addressed relays with no
  // busy-guard, so one participant can negotiate with many peers at once.
  socket.on('meeting-offer', (data) => {
    const { from, to, sdp } = data ?? {};
    if (!from || !to) return;
    const fromName = users.get(socket.id)?.displayName;
    relayTo(to, 'meeting-offer', { from, to, sdp, fromName });
  });

  socket.on('meeting-answer', (data) => {
    const { from, to, sdp } = data ?? {};
    if (!from || !to) return;
    const fromName = users.get(socket.id)?.displayName;
    relayTo(to, 'meeting-answer', { from, to, sdp, fromName });
  });

  socket.on('meeting-ice', (data) => {
    const { from, to, candidate } = data ?? {};
    if (!from || !to) return;
    relayTo(to, 'meeting-ice', { from, to, candidate });
  });

  // Group chat is relayed through the room rather than peer data channels, so it
  // reaches everyone reliably. The relayed message is rebuilt from an explicit
  // allowlist: sender id/name and the timestamp are stamped from the trusted
  // server side (only the text and an optional client id are accepted), so a
  // client cannot spoof the sender, inject extra fields, or amplify a huge body.
  socket.on('meeting-chat', (data) => {
    const user = users.get(socket.id);
    if (!user) return;
    const roomCode = roomByUser.get(user.userId);
    if (!roomCode) return;
    const set = rooms.get(roomCode);
    if (!set) return;
    const incoming = data?.message;
    const text = incoming?.text;
    if (typeof text !== 'string' || text.length === 0) return;
    if (text.length > MAX_CHAT_LEN) return;
    const id =
      typeof incoming.id === 'string' && incoming.id.length <= 64
        ? incoming.id
        : randomUUID();
    const message = {
      id,
      text,
      senderId: user.userId,
      senderName: user.displayName,
      sentAt: new Date().toISOString(),
    };
    for (const member of set) {
      if (member !== user.userId) {
        relayTo(member, 'meeting-chat', { roomCode, message });
      }
    }
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

    // Drop out of any meeting and tell the remaining members.
    leaveRoom(userId);

    io.emit('user-left', { userId });
    console.log(`disconnect ${displayName} (${userId})`);
  });
});

httpServer.listen(PORT, () => {
  console.log(`Signalling server listening on port ${PORT}`);
  const addresses = lanAddresses();
  for (const address of addresses) {
    console.log(`  reachable on this network at http://${address}:${PORT}`);
  }
  // Advertise on the LAN (mDNS/Bonjour) so apps on the same Wi-Fi discover and
  // connect automatically, with no host to type or build flag to pass.
  try {
    const bonjour = new Bonjour();
    bonjour.publish({
      name: 'VideoSDK Signalling',
      type: 'videosdk',
      port: Number(PORT),
      // Carry the IP in the TXT record. Some routers give the host a domain
      // suffix (e.g. ".bbrouter") whose hostname has no mDNS A record, so a
      // client resolving the SRV target gets no address. The TXT ip always works.
      txt: addresses.length > 0 ? { ip: addresses[0] } : undefined,
    });
    console.log('  advertising via mDNS as _videosdk._tcp');
  } catch (error) {
    console.warn('mDNS advertise failed (auto-discovery disabled):', error);
  }
});
