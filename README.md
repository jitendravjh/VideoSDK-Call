# VideoSDK Call

A Flutter app for real time 1:1 and group voice and video calls over WebRTC, with live presence, shareable call codes, and in call chat. A small Node.js and Socket.IO server handles the signalling.

Author: Jitendra Verma (jitendravjh@gmail.com)

## Features

**Working**

- 1:1 calls with SDP offer and answer and trickle ICE, covering the full lifecycle from idle through outgoing or incoming, connecting, connected, and finally ended or failed.
- Group meetings, where each pair of members forms its own peer connection (a mesh) and people join with a meeting code.
- A live presence lobby. Every user also gets a short call code, so anyone can dial anyone directly.
- In call chat, mute, speaker, camera toggle, camera flip, and accept or decline for an incoming call.
- A pre join screen with a camera preview, mic and camera toggles, and full permission handling, including a path to the settings page when permission is permanently denied.
- An incoming call ringtone that uses the phone's own default ringtone on Android.
- Automatic reconnect that re-registers with the same code and re-syncs presence.
- Zero configuration server discovery. The app finds the server on the local network and falls back to a public address when it cannot, so calls work on the same Wi-Fi and across networks, including mobile data, through a TURN relay.
- A native Android microphone level meter over a Kotlin EventChannel.
- Unit tests, a zero warning analyzer, and a pre commit hook.

**Partial**

- Cross network calling runs through a Cloudflare tunnel to the server on the Mac, so it only works while that machine is on. A proper cloud deployment would remove this.
- The native mic meter can read low during a call (see Known issues).

## Running

The server command also opens the public Cloudflare tunnel. Use `npm run server` if you want only the server.

    cd server
    npm install
    npm start

Then the app:

    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter run

The build_runner step generates code that is not checked into the repository. You need Flutter 3.44 or later (Dart 3.12 or later) and Node 20.12 or later.

## Tested on

A physical Android phone (Android 16), an iPhone (iOS 26.5), and Chrome on the web, all against the local server. Calls between the devices on the same Wi-Fi stayed direct peer to peer, and mDNS discovery was confirmed on a real device. The cross network path was verified end to end: the server mints Cloudflare TURN credentials and sends them to the clients, and Socket.IO runs over wss through the public tunnel. iOS was run as a release build, since a debug build only launches while attached to the Mac.

## How the app finds the server

`ServerDiscovery` resolves the signalling URL without any flag. On mobile and desktop it uses mDNS to find the server, which advertises itself as `_videosdk._tcp` on the local network, and if nothing appears within five seconds it falls back to a public address. On the web, where there is no mDNS, it uses the public address directly over wss. That address is `AppConfig.fallbackUrl` in `lib/core/constants.dart`, and you can override it with `--dart-define=SIGNALING_URL=...` or `--dart-define=SIGNALING_HOST=<ip>`.

On the same Wi-Fi the call stays direct, which gives the best quality. On a different network it goes through the public server and a Cloudflare TURN relay, with credentials minted on the server from `server/.env`. STUN is always tried first, so a direct call still wins whenever it is possible.

## Architecture

The code follows a one way layering, from presentation to application to data.

    lib/
      core/          constants, logging, permissions, call code
      data/          models (freezed), signaling, webrtc, discovery, audio, native
      application/   controllers (CallController and MeetingController)
      presentation/  screens, widgets, router, theme

- Widgets hold no logic. They read state and call methods on the notifiers, and no widget ever owns a socket or a peer connection.
- `CallController` is the single source of truth for a call. It owns the `CallState` union, turns incoming signalling into state changes, and drives the `WebRtcEngine`. The caller always makes the offer, which avoids glare, and in a meeting a fixed `compareTo` rule decides who offers in each pair.
- Services sit behind interfaces (`WebRtcEngine` and `SignalingTransport`) and are provided through Riverpod, so the state machine can be tested with fakes. keepAlive services and autoDispose controllers keep the lifetimes clear. I chose Riverpod because it is compile time safe, generated, and easy to test.
- All signalling is one sealed `SignalMessage` type, decoded in one place by `SignalCodec`. Parsing stays centralised, never throws, and simply drops bad input.
- Discovery is mDNS first with a public fallback, so there is no address to type and it still works off the local network.
- The 1:1 chat runs over the WebRTC data channel, peer to peer, and survives a brief socket drop. Meeting chat is relayed by the server, which stamps the real sender so a client cannot fake it.

### Signalling protocol (Socket.IO)

| Direction | Event | Payload |
|---|---|---|
| client to server | `register` | `{ displayName, userId? }` |
| server to client | `registered` | `{ user, iceServers }` |
| server to clients | `presence`, `user-joined`, `user-left` | roster and changes |
| caller and callee | `call-offer`, `call-answer`, `call-decline` | `{ from, to, sdp? }` |
| both | `ice-candidate`, `call-end` | `{ from, to, ... }` |
| meeting | `meeting-host`, `meeting-join`, `meeting-leave`, `meeting-offer`, `meeting-answer`, `meeting-ice`, `meeting-chat` | room based |

The `userId` is the call code assigned by the server, and it is also the routing key. A client sends it back on reconnect to keep the same identity. On disconnect the server clears presence, notifies the peers, and ends any active call.

## Web deploy

`.github/workflows/deploy-web.yml` runs build_runner, builds the web app, and publishes it to the `gh-pages` branch on every push to `main`. The deployed build connects to the public server through `AppConfig.fallbackUrl`. Enable GitHub Pages on the `gh-pages` branch to serve it.

## Developer setup

Enable the pre commit hook, which runs `dart format` and `flutter analyze` and refuses to commit a `.env` file:

    git config core.hooksPath .githooks

TURN is optional. Copy `server/.env.example` to `server/.env` and fill in `TURN_KEY_ID` and `TURN_API_TOKEN` from Cloudflare Realtime, in the TURN section.

## Tests

    flutter test
    flutter analyze

The tests cover the call state machine, the signal codec, the presence and meeting reducers, and the ring action. The analyzer runs `very_good_analysis` and must stay at zero warnings.

## Known issues

- On iOS a debug build only launches while attached to the Mac, so use a release build. A free Apple certificate expires after seven days and needs a reinstall.
- Cross network calling depends on the Mac running `npm start`, because the public address is a tunnel to it. A cloud deployment removes this.
- A brief signalling socket drop does not end a connected call. The media keeps flowing while the socket reconnects.
- Calls are not kept alive in the background. A production app would need a foreground service on Android or CallKit on iOS.
- The native Android mic meter can read low during a call, because the OS allows only one microphone capturer and WebRTC already holds it. The production approach is to read `audioLevel` from `getStats()`.

## To production

- **TURN.** A Cloudflare TURN relay is already wired in, with credentials minted on the server and never sent to the client. At a larger scale, watch the relay bandwidth or run a dedicated coturn server, and keep STUN first so most calls stay direct.
- **Scaling.** Presence and rooms are held in memory in a single instance. Moving them to Redis, running several Socket.IO instances behind a load balancer with the Redis adapter and sticky sessions, and hosting in the cloud would scale it and remove the Mac and tunnel dependency.
- **Security.** Add authentication with a signed token on connect, and have the server check that `from` matches the authenticated socket so no one can impersonate another user. Meeting chat already stamps the sender on the server. Serve over WSS and TLS, which Cloudflare provides today, rate limit the signalling, and validate every payload on the server. Secrets stay in the environment, the `.env` file is git ignored, and the pre commit hook blocks committing it.

## AI usage

Built with help from an AI tool for scaffolding, code generation wiring, and review. I made the architecture decisions and reviewed every change.
