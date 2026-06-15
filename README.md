# VideoSDK Call

A Flutter app for real time 1:1 and group voice and video calling over WebRTC. It has live presence, shareable call codes, and in call text chat. A small Node.js and Socket.IO server handles the signalling.

Author: Jitendra Verma (jitendravjh@gmail.com)

## What is complete and what is partial

Complete:

- 1:1 calls with SDP offer and answer plus trickle ICE. The full lifecycle is covered. The states are idle, outgoing or incoming, connecting, connected, and then ended or failed.
- Group meetings. Each pair of members forms one peer connection, which makes a mesh, and members join using a meeting code.
- A live presence lobby. Every user also gets a short call code, so anyone can dial anyone directly.
- In call chat, mute, speaker, camera on or off, camera flip, and accept or decline for an incoming call.
- A pre join screen with camera preview, mic and camera toggles, and proper permission handling. This includes the case where permission is permanently denied, which opens the settings page.
- An incoming call ringtone. On Android it uses the phone's own default ringtone.
- Automatic reconnect. The client registers again with the same code, and presence is synced again.
- Server discovery with no configuration. The app finds the server on the local network. If it cannot, it uses a public address. So it works on the same Wi-Fi and also across networks, including mobile data, by using a TURN relay.
- A native Android microphone level meter using a Kotlin EventChannel.
- Unit tests, a zero warning analyzer, and a pre commit hook.

Partial or best effort:

- Video. The layout follows the real tracks on each side. A callee sends video only if it allows the camera at the time of accepting, because a callee has no pre join screen. Otherwise it sends audio only, but it still receives the caller's video.
- The cross network setup uses a Cloudflare tunnel to the server running on the Mac. So it works only while that machine is on. A proper cloud deployment will remove this need.
- The native mic meter can show a low value during a call. Please see the Known issues section.

## How to run

Server. This also opens the public Cloudflare tunnel. Use `npm run server` if you want only the server.

    cd server
    npm install
    npm start

App.

    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter run

The `build_runner` step creates the generated files. These files are not committed to the repository.

Requirements. Flutter 3.44 or later (Dart 3.12 or later) and Node 20.12 or later.

## What it was tested on

- A real Android phone (Android 16), an iPhone (iOS 26.5), and Chrome on the web. All of them were tested against the local server.
- Calls on the same Wi-Fi between the devices, which stay direct peer to peer. The mDNS auto discovery was confirmed on the device.
- The cross network path was checked from end to end. The server creates Cloudflare TURN credentials and sends them to the clients, and Socket.IO works over `wss` through the public tunnel.
- iOS runs as a release build. A debug build runs only while it is attached to the Mac.

## How the app finds the server

The `ServerDiscovery` class finds the signalling URL without any flag.

- On mobile and desktop it uses mDNS on the local network. The server advertises the service `_videosdk._tcp`. If nothing is found within 5 seconds, it uses the public address.
- On the web there is no mDNS, so it uses the public address directly over `wss`.
- The public address is `AppConfig.fallbackUrl` in `lib/core/constants.dart`. You can override it with `--dart-define=SIGNALING_URL=...` or `--dart-define=SIGNALING_HOST=<ip>`.

On the same Wi-Fi the call stays direct, which gives the best quality. On a different network it uses the public server and a Cloudflare TURN relay. The credentials are created on the server side from `server/.env`. STUN is tried first, so a direct call is still preferred when it is possible.

## Architecture decisions

The code uses one direction layering. It goes from presentation to application to data.

    lib/
      core/          constants, logging, permissions, call code
      data/          models (freezed), signaling, webrtc, discovery, audio, native
      application/   controllers (CallController and MeetingController)
      presentation/  screens, widgets, router, theme

- Widgets hold no logic. They read state and call methods on the notifiers. No widget owns a socket or a peer connection.
- `CallController` is the single source of truth for a call. It owns the `CallState` union, it turns incoming signalling into state changes, and it drives the `WebRtcEngine`. The caller is always the one who makes the offer, which avoids glare. In a meeting, a fixed `compareTo` rule decides who makes the offer in each pair.
- Services sit behind interfaces (`WebRtcEngine` and `SignalingTransport`) and are provided through Riverpod. So the state machine can be tested with fakes. The `keepAlive` services and `autoDispose` controllers make the lifetimes clear. Riverpod was chosen because it is compile time safe, generated, and easy to test.
- All signalling is one sealed `SignalMessage` type, and one `SignalCodec` decodes it. So all parsing stays in one place, and it never throws. Bad input is simply dropped.
- Discovery is mDNS first with a public fallback. So there is no host to type, and it still works when off the local network.
- The 1:1 chat goes over the WebRTC data channel. It is peer to peer, and it survives a short socket drop. The meeting chat is relayed by the server. The server stamps the real sender, so a client cannot fake it.

### Signalling protocol (Socket.IO)

| Direction | Event | Payload |
|---|---|---|
| client to server | `register` | `{ displayName, userId? }` |
| server to client | `registered` | `{ user, iceServers }` |
| server to clients | `presence`, `user-joined`, `user-left` | roster and changes |
| caller and callee | `call-offer`, `call-answer`, `call-decline` | `{ from, to, sdp? }` |
| both | `ice-candidate`, `call-end` | `{ from, to, ... }` |
| meeting | `meeting-host`, `meeting-join`, `meeting-leave`, `meeting-offer`, `meeting-answer`, `meeting-ice`, `meeting-chat` | room based |

The `userId` is the call code given by the server, and it is also the routing key. A client sends it back on reconnect to keep the same identity. On disconnect the server clears presence, tells the peers, and ends any active call.

## Web deploy

The file `.github/workflows/deploy-web.yml` runs `build_runner`, then `flutter build web`, and publishes to the `gh-pages` branch on every push to `main`. The deployed build connects to the public server using `AppConfig.fallbackUrl`. Please enable GitHub Pages on the `gh-pages` branch.

## Developer setup

- Turn on the pre commit hook. It runs `dart format` and `flutter analyze`, and it blocks committing a `.env` file.

      git config core.hooksPath .githooks

- TURN is optional. Run `cp server/.env.example server/.env` and fill in `TURN_KEY_ID` and `TURN_API_TOKEN` from Cloudflare Realtime, in the TURN section.

## Tests

    flutter test
    flutter analyze

The tests cover the call state machine, the signal codec, the presence and meeting reducers, and the ring action. The analyzer uses `very_good_analysis` and must show zero warnings.

## Known issues

- On iOS, a debug build runs only while attached to the Mac, so please use a release build. A free Apple certificate expires after 7 days, so you have to reinstall.
- The cross network setup needs the Mac to be running `npm start`, because the public address is a tunnel to it. A cloud deployment will remove this.
- A short signalling socket drop does not end a connected call. The media keeps flowing while the socket reconnects.
- There is no support for calls in the background. A production app needs a foreground service on Android, or CallKit on iOS.
- The native Android mic meter can show a low value during a call. The OS allows only one microphone capturer, and WebRTC is already holding it. The correct production approach is to read `audioLevel` from `getStats()`.

## Going to production

- TURN. A Cloudflare TURN relay is already added. The credentials are created on the server and never sent to the client. At a larger scale, please watch the relay bandwidth, or run a dedicated coturn server. Keep STUN first so most calls stay direct.
- Scaling the server. Presence and rooms are kept in memory in a single instance. Move them to Redis, run many Socket.IO instances behind a load balancer with the Redis adapter and sticky sessions, and host it in the cloud. This also removes the Mac and tunnel dependency.
- Security. Add authentication with a signed token on connect. Make the server check that `from` matches the authenticated socket, so a client cannot pretend to be someone else. The meeting chat already stamps the sender on the server. Serve over WSS and TLS, which Cloudflare provides today. Limit the signalling rate, and validate every payload on the server. Secrets stay in the environment. The `.env` file is git ignored, and the pre commit hook refuses to commit it.

## AI usage

This was built with help from an AI tool (Claude Code) for scaffolding, code generation wiring, and review. I decided the architecture and reviewed every change.
