# Synq

Real time 1:1 and group voice and video calling, built in Flutter on WebRTC. It has live presence, shareable call codes, and in call chat. A small Node.js and Socket.IO server handles the signalling.

| | |
|---|---|
| Live web demo | https://jitendravjh.in/Synq/ |
| Platforms | Android, iOS, Web |
| Author | Jitendra Verma (jitendravjh@gmail.com) |

## Features

**Calling**

- 1:1 voice and video calls with a full lifecycle: idle, outgoing or incoming, connecting, connected, then ended or failed.
- Group meetings as a mesh, one peer connection per pair, joined with a meeting code.
- In call controls: mute, speaker, camera on or off, camera flip, and end call.
- Incoming call screen with accept or decline, and the device's own default ringtone on Android.

**Find and connect**

- Live presence lobby that updates as people join and leave.
- A short call code per user, so anyone can dial anyone directly.
- Zero configuration discovery. The app finds the server on the LAN over mDNS, and falls back to a public address when it cannot.
- Works across networks and cellular through a Cloudflare TURN relay.

**Chat and extras**

- In call text chat. The 1:1 chat goes over the WebRTC data channel, group chat is relayed by the server.
- Pre join screen with a camera preview, mic and camera toggles, and full permission handling.
- A native Android microphone level meter over a Kotlin EventChannel.
- Automatic reconnect, unit tests, a zero warning analyzer, and a pre commit hook.

## Tech stack

| Area | Used | Why |
|---|---|---|
| App framework | Flutter, Dart | One codebase for Android, iOS, and web |
| Real time media | flutter_webrtc (WebRTC) | Peer to peer audio, video, and data |
| State and DI | Riverpod with generator | Compile time safe, testable with fake services |
| Data models | Freezed | Immutable sealed unions, equality, and JSON |
| Signalling client | socket_io_client | Named events, auto reconnect, rooms |
| Navigation | go_router | The screen is chosen from app state |
| LAN discovery | nsd (mDNS) | Find the server with no address to type |
| Ringtone | flutter_ringtone_player | The phone's own default ringtone on Android |
| Server | Node.js, Socket.IO | Small single file signalling server |
| Direct connect | Google STUN | Helps two devices find a direct path |
| Relay fallback | Cloudflare TURN | Carries the media when a direct path is not possible |
| Public access | Cloudflare Tunnel | Exposes the local server over the internet |

## Run

The server command also opens the public tunnel. Use `npm run server` for the server alone.

    cd server
    npm install
    npm start

Then the app:

    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter run

- `build_runner` generates code that is not committed to the repository.
- Requirements: Flutter 3.44 or later (Dart 3.12 or later), Node 20.12 or later.

## How the app finds the server

`ServerDiscovery` resolves the signalling URL with no flag. It tries the LAN first and falls back to the public server, and it also falls back if a discovered LAN server does not actually connect.

| Situation | Server used | Media path |
|---|---|---|
| Same Wi-Fi | LAN server found over mDNS | Direct peer to peer, best quality |
| LAN server not reachable (for example tethering) | Public server after a 3 second fallback | Direct or TURN relay |
| Different network or cellular | Public server | TURN relay |
| Web (no mDNS) | Public server over wss | Direct or TURN relay |

- The public address is `AppConfig.fallbackUrl` in `lib/core/constants.dart`.
- Override it with `--dart-define=SIGNALING_URL=...` or `--dart-define=SIGNALING_HOST=<ip>`.
- STUN is always tried first, so a direct call wins whenever it is possible. TURN credentials are minted on the server from `server/.env` and never reach the client.

## Tested on

- Android 16 (Physical Device)
- iOS 26.5 (Physical Device)
- Web (Deployed) (https://jitendravjh.in/Synq/)

Same Wi-Fi calls stay direct peer to peer. The cross network path was verified end to end with Cloudflare TURN over the public tunnel.

## Architecture

One direction layering. Presentation uses application, application uses data, and data does not call up.

| Layer | Holds | Examples |
|---|---|---|
| presentation | screens and widgets, no logic | lobby, pre join, call, meeting |
| application | controllers (state and logic) | CallController, MeetingController, LobbyController |
| data | services and models | SignalingService, WebRtcService, MeshService, stores |

Key decisions:

- `CallController` is the single source of truth for a call. The caller always makes the offer, which avoids glare. In a meeting a fixed `compareTo` rule picks the offerer for each pair.
- Services sit behind interfaces (`WebRtcEngine` and `SignalingTransport`) and are injected with Riverpod, so the state machine can be tested with fakes.
- All signalling is one sealed `SignalMessage` decoded by one `SignalCodec`, which never throws and simply drops bad input.
- The 1:1 chat runs over the WebRTC data channel and survives a brief socket drop. Meeting chat is relayed by the server, which stamps the real sender so a client cannot fake it.

### Signalling protocol (Socket.IO)

| Direction | Event | Payload |
|---|---|---|
| client to server | `register` | `{ displayName, userId? }` |
| server to client | `registered` | `{ user, iceServers }` |
| server to clients | `presence`, `user-joined`, `user-left` | roster and changes |
| caller and callee | `call-offer`, `call-answer`, `call-decline` | `{ from, to, sdp? }` |
| both | `ice-candidate`, `call-end` | `{ from, to, ... }` |
| meeting | `meeting-host`, `meeting-join`, `meeting-leave`, `meeting-offer`, `meeting-answer`, `meeting-ice`, `meeting-chat` | room based |

The `userId` is the call code assigned by the server and the routing key. A client sends it back on reconnect to keep the same identity.

## Web deploy

- `.github/workflows/deploy-web.yml` runs `build_runner`, builds the web app, and publishes to the `gh-pages` branch on every push to `main`.
- The deployed build connects to the public server through `AppConfig.fallbackUrl`.
- It is live at https://jitendravjh.in/Synq/.

## Developer setup

- Enable the pre commit hook. It runs `dart format` and `flutter analyze`, and it refuses to commit a `.env` file.

      git config core.hooksPath .githooks

- TURN is optional. Copy `server/.env.example` to `server/.env` and fill in `TURN_KEY_ID` and `TURN_API_TOKEN` from Cloudflare Realtime.

## Tests

    flutter test
    flutter analyze

The tests cover the call state machine, the signal codec, the presence and meeting reducers, and the ring action. The analyzer runs `very_good_analysis` and must stay at zero warnings.

## Known issues

- Cross network calling needs the server running via `npm start`, because the public address is a tunnel to it. A cloud deployment would remove this.
- A brief signalling socket drop does not end a connected call. The media keeps flowing while the socket reconnects.
- There is no background call support. A production app would need a foreground service on Android or CallKit on iOS.
- The native Android mic meter can read low during a call, because the OS allows only one microphone capturer and WebRTC already holds it. The production approach is to read `audioLevel` from `getStats()`.

## To production

| Area | Now | Next step |
|---|---|---|
| TURN | Cloudflare TURN, credentials minted on the server | Watch relay bandwidth or run a dedicated coturn server |
| Signalling scale | In memory, single instance | Redis adapter, several Socket.IO instances, a load balancer, sticky sessions |
| Hosting | Local server behind a Cloudflare tunnel | Deploy to the cloud to drop the Mac dependency |
| Security | TLS via Cloudflare, server stamped meeting sender | Auth token on connect, validate `from`, rate limit signalling |

## AI usage

Built with help from an AI tool for scaffolding, code generation wiring, and review. I made the architecture decisions and reviewed every change.
