// End-to-end proof that two real WebRTC peers complete a call through the
// signalling server: register -> offer/answer -> trickle ICE -> data channel
// chat -> peer connection 'connected'. Mirrors the app's CallController logic.
import { io } from 'socket.io-client';
import wrtc from '@roamhq/wrtc';

const { RTCPeerConnection, RTCSessionDescription, RTCIceCandidate } = wrtc;
const URL = 'http://localhost:3000';
const ICE = [{ urls: 'stun:stun.l.google.com:19302' }];
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

let passed = 0;
let failed = 0;
const ok = (n, c) => {
  if (c) { passed++; console.log('PASS', n); }
  else { failed++; console.log('FAIL', n); }
};

function makePeer(socket, selfCode, peerCode) {
  const pc = new RTCPeerConnection({ iceServers: ICE });
  const pending = [];
  let remoteSet = false;
  pc.onicecandidate = (e) => {
    if (e.candidate) {
      socket.emit('ice-candidate', {
        from: selfCode,
        to: peerCode,
        candidate: {
          candidate: e.candidate.candidate,
          sdpMid: e.candidate.sdpMid,
          sdpMLineIndex: e.candidate.sdpMLineIndex,
        },
      });
    }
  };
  socket.on('ice-candidate', async (msg) => {
    if (msg.from !== peerCode) return;
    const cand = new RTCIceCandidate(msg.candidate);
    if (!remoteSet) pending.push(cand);
    else await pc.addIceCandidate(cand);
  });
  const drain = async () => {
    remoteSet = true;
    for (const c of pending) await pc.addIceCandidate(c);
    pending.length = 0;
  };
  return { pc, drain };
}

async function register(socket, name) {
  return new Promise((resolve) => {
    socket.once('registered', (m) => resolve(m.user.userId));
    socket.emit('register', { displayName: name });
  });
}

async function main() {
  const a = io(URL, { forceNew: true });
  const b = io(URL, { forceNew: true });
  await Promise.all([
    new Promise((r) => a.on('connect', r)),
    new Promise((r) => b.on('connect', r)),
  ]);

  const aCode = await register(a, 'Alice');
  const bCode = await register(b, 'Bob');
  ok('both peers registered with codes', !!aCode && !!bCode && aCode !== bCode);

  const caller = makePeer(a, aCode, bCode);
  const callee = makePeer(b, bCode, aCode);

  // Caller creates the data channel before the offer.
  const callerDc = caller.pc.createDataChannel('chat');
  let calleeDc = null;
  callee.pc.ondatachannel = (e) => { calleeDc = e.channel; };

  // Callee handles the offer.
  b.on('call-offer', async (msg) => {
    if (msg.from !== aCode) return;
    await callee.pc.setRemoteDescription(new RTCSessionDescription({ type: 'offer', sdp: msg.sdp }));
    await callee.drain();
    const answer = await callee.pc.createAnswer();
    await callee.pc.setLocalDescription(answer);
    b.emit('call-answer', { from: bCode, to: aCode, sdp: answer.sdp });
  });

  // Caller handles the answer.
  a.on('call-answer', async (msg) => {
    if (msg.from !== bCode) return;
    await caller.pc.setRemoteDescription(new RTCSessionDescription({ type: 'answer', sdp: msg.sdp }));
    await caller.drain();
  });

  const offer = await caller.pc.createOffer();
  await caller.pc.setLocalDescription(offer);
  a.emit('call-offer', { from: aCode, to: bCode, sdp: offer.sdp });

  // Wait for both peer connections to reach connected.
  const connected = (pc) => new Promise((resolve) => {
    if (pc.connectionState === 'connected') return resolve(true);
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === 'connected') resolve(true);
      if (pc.connectionState === 'failed') resolve(false);
    };
  });
  const deadline = wait(15000).then(() => 'timeout');
  const result = await Promise.race([
    Promise.all([connected(caller.pc), connected(callee.pc)]).then((r) => r.every(Boolean)),
    deadline,
  ]);
  ok('both peer connections reached connected', result === true);

  // Data channel chat round-trip.
  const dcOpen = (dc) => new Promise((resolve) => {
    if (!dc) return resolve(false);
    if (dc.readyState === 'open') return resolve(true);
    dc.onopen = () => resolve(true);
  });
  await Promise.race([dcOpen(callerDc), wait(5000)]);
  await wait(300);
  await Promise.race([dcOpen(calleeDc), wait(5000)]);

  const received = new Promise((resolve) => {
    if (calleeDc) calleeDc.onmessage = (e) => resolve(e.data);
  });
  callerDc.send(JSON.stringify({ id: '1', senderId: aCode, text: 'hello', sentAt: '2026-06-12T00:00:00.000Z' }));
  const got = await Promise.race([received, wait(5000)]);
  ok('chat message delivered over the data channel', typeof got === 'string' && got.includes('hello'));

  // Clean end.
  a.emit('call-end', { from: aCode, to: bCode });
  await wait(150);
  caller.pc.close();
  callee.pc.close();
  a.close();
  b.close();

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(2); });
