# VideoSDK Call — Real-time 1:1 Voice/Video Calling

A Flutter app for real-time 1-to-1 voice and video calling over WebRTC, with live
presence, a shareable call code, and in-call text chat, backed by a small Node.js
Socket.IO signalling server.

Author: Jitendra Verma — jitendravjh@gmail.com

---

## Features

Complete:

- WebRTC 1:1 calling with full signalling: SDP offer/answer plus trickle ICE.
  Remote ICE candidates are queued until the remote description is set.
- Explicit, visible call lifecycle modelled as a sealed `CallState` union:
  `idle -> outgoing | incoming -> connecting -> connected -> ended | failed`.
- Live presence: a lobby that lists who is online and updates in real time on
  connect and disconnect.
- Shareable call code: every user is assigned a short, human-typable code
  (for example `ABC-DEF`). Share it and the other side connects by entering it,
  so any two people can call without being in the same lobby first.
- In-call text chat over the WebRTC data channel.
- Pre-join screen: live camera preview, mic and camera toggles, and runtime
  permission handling including the permanently-denied "open settings" path.
- In-call controls: mute, speaker toggle, camera on/off, camera flip, end call.
- Incoming call UI with accept and decline.
- Reconnection: the socket auto-reconnects, re-registers the same code, and
  re-syncs presence; connection state is surfaced in the UI.
- Audio and video calls, with a local picture-in-picture preview.
- Edge cases surfaced in the UI: callee offline, call declined, peer left,
  connection lost, permission denied.
- Unit tests for the call state machine, the signal codec, and the presence
  reducer.

Partial / best-effort:

- Video: the in-call layout follows each side's real tracks (the remote video
  shows when the peer sends it; the local picture-in-picture shows when you
  send it). A callee answers with video only if it grants camera permission at
  accept time, otherwise it is audio-only outbound while still receiving the
  caller's video.
- Native bridge bonus: a Kotlin audio-level meter (Android only). See
  [Native bridge](#native-bridge-android).

Out of scope (per the brief): auth/login, group calls, call history, push
notifications, backend scalability, pixel-perfect theming.

---

## Running

Prerequisites: Flutter 3.44+ (Dart 3.12+), Node.js 18+.

### 1. Signalling server

```
cd server
npm install
npm start
```

The server listens on port `3000` and logs registrations and disconnects.
`GET /health` returns a small JSON status.

### 2. Flutter app

```
flutter pub get
dart run build_runner build
flutter run
```

`build_runner` generates the `freezed`, `json_serializable`, and
`riverpod_generator` outputs (the `*.freezed.dart` / `*.g.dart` files are not
checked in).

### Server host configuration

The server address is a single constant in
[`lib/core/constants.dart`](lib/core/constants.dart):

| Target | Host used |
|---|---|
| Android emulator | `10.0.2.2` (host loopback) |
| Web / desktop | `localhost` |
| Physical device | set to your machine's LAN IP |

Change `AppConfig.signalingHost` for a physical device or a deployed server.

### Two-client test setup

Tested with two clients against one locally-run server:

- one Android emulator (reaches the server on `10.0.2.2`), and
- a Chrome window (reaches it on `localhost`).

To try it: start the server, launch the app on two clients, enter a name on
each. Either tap a user in the lobby, or copy one client's code and enter it on
the other via "Join with a code", set mic/camera on the pre-join screen, and
call. Both clients show every lifecycle state; chat works once connected.

---

## Architecture

Strict one-directional layering:

```
presentation  -->  application  -->  data  -->  (nothing upward)
  widgets          notifiers        services
```

```
lib/
  core/           constants (server host, STUN), logging, permissions, call code
  data/
    models/       User, CallState, ChatMessage, SignalMessage (freezed unions)
    signaling/    SignalingService + SignalingTransport, SignalCodec, events
    webrtc/       WebRtcService + WebRtcEngine (peer connection, media, channel)
  application/
    lobby/        SessionController, LobbyController, PresenceReducer
    call/         CallController (the state machine), ChatController
  presentation/
    lobby/ prejoin/ call/ common/   screens, widgets, theme, router
  main.dart
```

- Widgets never own a peer connection or a socket. They read state and call
  notifier methods. The only data-layer object a widget touches is the
  `RTCVideoRenderer` it binds to an `RTCVideoView`, which is view binding, not
  logic.
- `CallController` is the single source of truth for the call. It owns the
  `CallState` union, translates inbound signalling into transitions, and drives
  the `WebRtcEngine`. The caller is always the offerer, which avoids glare.
- `WebRtcService` and `SignalingService` are data-layer services exposed behind
  the `WebRtcEngine` and `SignalingTransport` interfaces, so the controller can
  be unit-tested with fakes and neither service ever shows UI or navigates.
- Services are injected via Riverpod providers.

### Why Riverpod

A single, consistent, compile-time-safe state solution. Code generation
(`riverpod_generator`) keeps providers terse; `keepAlive` services and
`autoDispose` controllers make lifetimes explicit; and provider overrides make
the state machine trivially testable with fake services (see
`test/application/call/call_controller_test.dart`). The full-screen call UI is
rendered as a state-driven overlay in `MaterialApp.router`'s builder, so an
incoming call interrupts any screen without imperative navigation.

### Signalling protocol

Socket.IO events. Inbound and outbound payloads are modelled as a sealed
`SignalMessage` union and translated by a single `SignalCodec`, so all parsing
is centralized and tested. Decoding never throws: malformed or unknown input is
dropped.

| Direction | Event | Payload |
|---|---|---|
| client -> server | `register` | `{ displayName, userId? }` |
| server -> client | `registered` | `{ user: { userId, displayName } }` |
| server -> clients | `presence` | `{ users: [ { userId, displayName } ] }` |
| server -> clients | `user-joined` | `{ user }` |
| server -> clients | `user-left` | `{ userId }` |
| caller -> callee | `call-offer` | `{ from, to, sdp }` |
| callee -> caller | `call-answer` | `{ from, to, sdp }` |
| callee -> caller | `call-decline` | `{ from, to }` |
| both | `ice-candidate` | `{ from, to, candidate }` |
| either | `call-end` | `{ from, to, reason? }` |

`userId` is the server-assigned call code and the routing key. A client omits
it on first `register` (the server assigns one and replies with `registered`)
and sends it back on reconnect to keep the same identity. On `disconnect` the
server removes the user from presence, broadcasts `user-left`, and sends
`call-end` to any peer that was in a call with them. On reconnect the client
re-registers and the server replays the current presence snapshot.

### Chat: data channel vs socket

Chat uses the WebRTC **data channel**, not the socket. The caller creates the
channel before the offer; the callee picks it up via `onDataChannel`. The
trade-off: messages flow peer-to-peer with no server hop and keep working even
if the signalling socket briefly drops, but chat is only available once the peer
connection is established and is not persisted (no offline history). For a 1:1
in-call chat this is the right trade; routing through the socket would have been
simpler but adds a server hop and couples chat to signalling availability.

---

## Native bridge (Android)

A Kotlin platform channel exposes the microphone's real-time amplitude to
Flutter, shown as a live "Mic level (native)" bar during a call.

- Native: `MainActivity.kt` registers an `EventChannel` (`videosdk/mic_level`).
  While Dart is listening it reads raw 16-bit PCM from `AudioRecord` on a
  background thread, computes the RMS amplitude per buffer, normalises it to
  `0..1`, and posts it to the event sink on the main looper.
- Dart: `MicLevelService` (in `lib/data/native/`) wraps the channel as a
  `Stream<double>` behind a Riverpod provider; `MicLevelBar` renders it. It is
  Android-only and hidden elsewhere.

No extra build steps: it builds with the app (`flutter run` / `flutter build
apk`).

Honest caveat: from Android 10 the OS generally allows only one active
microphone capturer at a time, and WebRTC already holds the mic during a call.
On many devices the second `AudioRecord` is therefore silenced and the bar
reads low while connected. The platform-channel bridge itself works; the
production-correct way to meter in-call level is to tap WebRTC's own audio
samples (a custom audio processor) or read `audioLevel` from
`RTCPeerConnection.getStats()` rather than opening a second recorder.

---

## Known issues and limitations

- Android is the primary target and was tested on an emulator plus a Chrome
  client. iOS is not tested (the iOS simulator has no camera).
- A callee sends video only if it grants camera permission when accepting;
  otherwise the call is audio-only outbound while still receiving the caller's
  video. This is intentional (a callee has no pre-join step).
- A transient signalling-socket drop does **not** tear down an already-connected
  call: established media flows peer-to-peer and continues while the socket
  reconnects. A true peer departure is handled via the server's `call-end`, and
  an unrecoverable peer-connection failure surfaces as `Failed`.
- No TURN server, so a call can fail behind symmetric NATs (see below).
- Background calls are not kept alive; a production app needs a foreground
  service (Android) / CallKit (iOS).

---

## Path to production

- **TURN.** STUN alone fails when both peers are behind symmetric NATs, which
  rewrite ports per destination so the discovered candidates do not work. A TURN
  server (for example coturn) relays media as a fallback. Add its URL plus
  short-lived credentials to `AppConfig.iceServers`; issue the credentials from
  the backend with a TTL rather than shipping static secrets.
- **Scaling the signalling server.** Presence and routing are in-memory and
  single-instance. To scale, move the registry to Redis, run multiple Socket.IO
  instances behind a load balancer with the Redis adapter and sticky sessions,
  and shard or namespace presence.
- **Security.** Add authentication (signed tokens on connect), and have the
  server validate that `from` matches the socket's authenticated identity so a
  client cannot spoof or relay on someone else's behalf. Serve over TLS/WSS,
  rate-limit signalling, and validate every payload server-side.
- **Background and reliability.** A foreground service (Android) and CallKit /
  ConnectionService integration to survive backgrounding and show system call
  UI; reconnection/renegotiation (ICE restart) for network changes.

---

## Tests

```
flutter test
```

- `test/application/call/call_controller_test.dart` drives the state machine
  through outgoing connect/end and incoming decline with faked services.
- `test/data/signaling/signal_codec_test.dart` round-trips every
  `SignalMessage` variant and checks malformed/unknown input is dropped.
- `test/application/lobby/presence_reducer_test.dart` covers the presence
  snapshot, join, and leave reducers including dedup and self-exclusion.

Run `flutter analyze` for a zero-warning `very_good_analysis` pass.

---

## AI tool usage

I used an AI coding assistant (Claude Code) as a pair-programming tool: to
scaffold boilerplate, draft the freezed models and Riverpod wiring, write the
first pass of the screens, and run an adversarial review pass over the WebRTC
and signalling code. I directed the architecture (the layering, the
interface-backed services, the data-channel chat decision, the server-assigned
call-code flow), reviewed and edited every file, verified the signalling server
with a Socket.IO smoke test, and confirmed the analyzer, tests, and a real
two-client call. I understand and stand behind all of the code in this repo.
