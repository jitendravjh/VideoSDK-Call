# VideoSDK Call

Real-time 1:1 and group voice/video calling in Flutter over WebRTC, with live
presence, shareable call codes, and in-call text chat. Signalling is a small
Node.js + Socket.IO server.

Author: Jitendra Verma — jitendravjh@gmail.com

## Features

- 1:1 calls: SDP offer/answer + trickle ICE, full lifecycle
  (`idle → outgoing | incoming → connecting → connected → ended | failed`).
- Group meetings: a mesh of peer connections joined by a meeting code.
- Live presence lobby; a per-user call code to reach anyone directly.
- In-call chat, mute / speaker / camera toggle / camera flip, incoming accept/decline.
- Pre-join preview with mic/camera toggles and permission handling.
- Incoming-call ringtone (the device's default ringtone on Android).
- Auto-reconnect: re-registers the same code and re-syncs presence.
- Works same-network (direct P2P) and cross-network / cellular (TURN relay).
- Android mic-level meter via a native Kotlin `EventChannel`.

## Run

Server (also opens the public tunnel):

    cd server
    npm install
    npm start          # server on :3000 + Cloudflare tunnel; Ctrl+C stops both

App:

    flutter pub get
    dart run build_runner build   # generates *.freezed.dart / *.g.dart (not checked in)
    flutter run

Prerequisites: Flutter 3.44+ (Dart 3.12+), Node 20.12+.

## How the app finds the server

`ServerDiscovery` resolves the signalling URL with no flags:

- Mobile/desktop: mDNS on the LAN (the server advertises `_videosdk._tcp`); if
  none is found within 5s it falls back to the public URL.
- Web (no mDNS): uses the public URL directly, over `wss`.
- The public URL is `AppConfig.fallbackUrl` in `lib/core/constants.dart`.
  Override with `--dart-define=SIGNALING_URL=...` (full URL) or
  `--dart-define=SIGNALING_HOST=<ip>`.

Same Wi-Fi resolves to a direct P2P call (best quality). Different networks fall
back to the public server plus a Cloudflare TURN relay — credentials are minted
server-side from `server/.env`, and STUN is tried first so direct still wins when
possible.

## Web deploy

`.github/workflows/deploy-web.yml` builds the web app and publishes it to the
`gh-pages` branch on push to `main`. The deployed build connects to the public
server via `AppConfig.fallbackUrl` (above), so no build flag is needed. Enable
GitHub Pages on the `gh-pages` branch.

## Dev setup

- Enable the pre-commit hook (runs `dart format` + `flutter analyze`, blocks
  committing a `.env`):

      git config core.hooksPath .githooks

- Cross-network TURN (optional): `cp server/.env.example server/.env` and fill
  `TURN_KEY_ID` / `TURN_API_TOKEN` from Cloudflare Realtime → TURN.

## Architecture

One-directional layering: `presentation → application → data`.

    lib/
      core/          constants, logging, permissions, call code
      data/          models (freezed), signaling, webrtc, discovery, audio, native
      application/   controllers (CallController / MeetingController state machines)
      presentation/  screens, widgets, router, theme

- Widgets read state and call notifier methods; they never own a socket or peer
  connection. Services sit behind interfaces and are injected via Riverpod, so
  controllers are unit-testable with fakes.
- `CallController` owns the `CallState` union and drives `WebRtcEngine`; the
  caller is always the offerer (glare-free).
- All signalling payloads are a sealed `SignalMessage` decoded by one
  `SignalCodec`; decoding never throws (bad input is dropped).
- 1:1 chat runs over the WebRTC data channel; meeting chat is relayed by the
  server (with a trusted, server-stamped sender).

## Tests

    flutter test          # state machine, signal codec, presence/meeting reducers, ring action
    flutter analyze       # zero-warning very_good_analysis

## Notes

- Android is the primary target. iOS runs as a release build (a debug build only
  launches while attached to the Mac). Web is supported.
- The public URL is a Cloudflare tunnel to the locally-run server, so
  cross-network calls require the Mac running `npm start`. A cloud deploy would
  remove that dependency.
- A transient signalling-socket drop does not tear down a connected call;
  established media continues while the socket reconnects.
- No background-call support (would need a foreground service / CallKit).
- The Android mic-level meter can read low while connected: the OS allows one
  mic capturer and WebRTC holds it; the production approach is to read
  `audioLevel` from `getStats()`.

## AI usage

Built with Claude Code as a pair-programming tool (scaffolding, freezed/Riverpod
wiring, first-pass UI, adversarial review of the WebRTC and signalling code). I
directed the architecture, reviewed every file, and verified analyzer, tests, and
real multi-device calls.
