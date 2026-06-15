# VideoSDK Call

Real-time 1:1 and group voice/video calling in Flutter over WebRTC — live
presence, shareable call codes, and in-call text chat — backed by a small
Node.js + Socket.IO signalling server.

Author: Jitendra Verma — jitendravjh@gmail.com

## What's complete vs partial

**Complete**

- 1:1 calls: SDP offer/answer + trickle ICE; full lifecycle
  (`idle → outgoing | incoming → connecting → connected → ended | failed`).
- Group meetings: a mesh of peer connections joined by a meeting code.
- Live presence lobby; a per-user call code to dial anyone directly.
- In-call chat, mute / speaker / camera toggle / camera flip, incoming accept/decline.
- Pre-join preview with mic/camera toggles and permission handling
  (including the permanently-denied → open-settings path).
- Incoming-call ringtone (the device's default ringtone on Android).
- Auto-reconnect: re-registers the same code and re-syncs presence.
- Zero-config server discovery (mDNS) with a public fallback — works on the LAN
  and across networks / cellular (TURN relay).
- Native Android mic-level meter (Kotlin `EventChannel`).
- Unit tests, zero-warning analyzer, and a pre-commit hook.

**Partial / best-effort**

- Video: the layout follows each side's real tracks. A callee sends video only
  if it grants camera permission at accept time (a callee has no pre-join step),
  otherwise it's audio-only outbound while still receiving the caller's video.
- Cross-network is served by a Cloudflare tunnel to the locally-run server, so it
  depends on that machine being up; a cloud deploy removes this.
- The native mic meter can read low while connected (see Known issues).

## Run

Server (also opens the public Cloudflare tunnel; use `npm run server` for the
server alone):

    cd server
    npm install
    npm start        # :3000 + tunnel; Ctrl+C stops both

App:

    flutter pub get
    dart run build_runner build --delete-conflicting-outputs   # generated files are not checked in
    flutter run

Prerequisites: Flutter 3.44+ (Dart 3.12+), Node 20.12+.

## Tested on

- A physical **Android** device (Android 16) and **iPhone** (iOS 26.5), plus
  **Chrome** (web), against the local server.
- Same-Wi-Fi calls (direct P2P) between the devices; mDNS auto-discovery
  confirmed on-device.
- Cross-network path verified end-to-end: server-minted Cloudflare TURN
  credentials delivered to clients, and Socket.IO over `wss` through the public
  tunnel.
- iOS runs as a release build (a debug build only launches while attached to the
  Mac).

## How the app finds the server

`ServerDiscovery` resolves the signalling URL with no flags:

- Mobile/desktop: mDNS on the LAN (the server advertises `_videosdk._tcp`); if
  none is found within 5s it falls back to the public URL.
- Web (no mDNS): the public URL directly, over `wss`.
- The public URL is `AppConfig.fallbackUrl` in `lib/core/constants.dart`;
  override with `--dart-define=SIGNALING_URL=...` or `SIGNALING_HOST=<ip>`.

Same Wi-Fi resolves to a direct P2P call (best quality). Different networks fall
back to the public server plus a Cloudflare TURN relay — credentials are minted
server-side from `server/.env`, and STUN is tried first so direct wins when
possible.

## Architecture decisions

One-directional layering, `presentation → application → data`:

    lib/
      core/          constants, logging, permissions, call code
      data/          models (freezed), signaling, webrtc, discovery, audio, native
      application/   controllers (CallController / MeetingController)
      presentation/  screens, widgets, router, theme

- **Widgets hold no logic** — they read state and call notifier methods; no
  widget owns a socket or peer connection.
- **`CallController` is the single source of truth** for a call: it owns the
  `CallState` union, turns inbound signalling into transitions, and drives
  `WebRtcEngine`. The **caller is always the offerer**, which avoids glare; in
  meetings a deterministic `compareTo` rule picks the offerer per pair.
- **Interface-backed services + Riverpod DI** (`WebRtcEngine`,
  `SignalingTransport`), so the state machine is unit-tested with fakes;
  `keepAlive` services and `autoDispose` controllers make lifetimes explicit.
  Riverpod was chosen for compile-time-safe, generated, testable wiring.
- **All signalling is a sealed `SignalMessage` decoded by one `SignalCodec`** —
  parsing is centralized and never throws (bad input is dropped).
- **Discovery is mDNS-first with a public fallback**, so there's no host to type
  and it still works off-LAN.
- **1:1 chat over the WebRTC data channel** (peer-to-peer, survives a brief
  socket drop); **meeting chat is relayed by the server** with a trusted,
  server-stamped sender so clients can't spoof.

### Signalling protocol (Socket.IO)

| Direction | Event | Payload |
|---|---|---|
| client → server | `register` | `{ displayName, userId? }` |
| server → client | `registered` | `{ user, iceServers }` |
| server → clients | `presence` / `user-joined` / `user-left` | roster + deltas |
| caller ↔ callee | `call-offer` / `call-answer` / `call-decline` | `{ from, to, sdp? }` |
| both | `ice-candidate` / `call-end` | `{ from, to, … }` |
| meeting | `meeting-host`/`join`/`leave`, `meeting-offer`/`answer`/`ice`/`chat` | room-scoped |

`userId` is the server-assigned call code and the routing key; a client sends it
back on reconnect to keep the same identity. On disconnect the server clears
presence, notifies peers, and ends any active call.

## Web deploy

`.github/workflows/deploy-web.yml` runs `build_runner`, then `flutter build web`,
and publishes to the `gh-pages` branch on push to `main`. The deployed build
connects to the public server via `AppConfig.fallbackUrl`. Enable GitHub Pages on
the `gh-pages` branch.

## Dev setup

- Pre-commit hook (`dart format` + `flutter analyze`, blocks committing a `.env`):

      git config core.hooksPath .githooks

- TURN (optional): `cp server/.env.example server/.env` and fill `TURN_KEY_ID` /
  `TURN_API_TOKEN` from Cloudflare Realtime → TURN.

## Tests

    flutter test       # call state machine, signal codec, presence/meeting reducers, ring action
    flutter analyze    # zero-warning very_good_analysis

## Known issues

- iOS debug builds only launch while attached to the Mac — use a release build;
  a free Apple signing cert expires after 7 days (reinstall).
- Cross-network depends on the Mac running `npm start` (the public URL is a
  tunnel to it); a cloud deploy removes this.
- A transient signalling-socket drop does not tear down a connected call; media
  continues while the socket reconnects.
- No background-call support (needs a foreground service / CallKit).
- The native Android mic meter can read low while connected: the OS allows one
  mic capturer and WebRTC holds it; the production approach is reading
  `audioLevel` from `getStats()`.

## To production

- **TURN**: a Cloudflare TURN relay is already wired in (credentials minted
  server-side, never shipped to the client). At scale, monitor relay bandwidth
  or run dedicated coturn; keep STUN-first so most calls stay direct.
- **Scaling the signalling server**: presence and rooms are in-memory and
  single-instance. Move them to Redis, run multiple Socket.IO instances behind a
  load balancer with the Redis adapter + sticky sessions, and host it in the
  cloud (removing the Mac/tunnel dependency).
- **Security**: add authentication (a signed token on connect) and have the
  server validate that `from` matches the authenticated socket so a client can't
  spoof or relay as someone else (meeting chat already server-stamps the sender).
  Serve over WSS/TLS (provided by Cloudflare today), rate-limit signalling, and
  validate every payload server-side. Secrets stay in env — `.env` is git-ignored
  and the pre-commit hook refuses to commit it.

## AI usage

Built with AI assistance (Claude Code) for scaffolding, code-gen wiring, and
review. I directed the architecture and reviewed every change.
