import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synq/application/call/call_controller.dart';
import 'package:synq/application/lobby/session_controller.dart';
import 'package:synq/data/models/call_state.dart';
import 'package:synq/data/models/chat_message.dart';
import 'package:synq/data/models/ice_candidate_payload.dart';
import 'package:synq/data/models/signal_message.dart';
import 'package:synq/data/models/user.dart';
import 'package:synq/data/session/session_store.dart';
import 'package:synq/data/signaling/signaling_providers.dart';
import 'package:synq/data/signaling/signaling_transport.dart';
import 'package:synq/data/webrtc/webrtc_engine.dart';
import 'package:synq/data/webrtc/webrtc_providers.dart';

const _alice = User(userId: 'ALICE1', displayName: 'Alice');
const _bob = User(userId: 'BOBBB2', displayName: 'Bob');

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeSignaling signaling;
  late _FakeEngine engine;
  late ProviderContainer container;

  setUp(() async {
    signaling = _FakeSignaling();
    engine = _FakeEngine();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        signalingServiceProvider.overrideWithValue(signaling),
        webRtcEngineProvider.overrideWithValue(engine),
        sessionControllerProvider.overrideWith(() => _StubSession(_alice)),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    // Keep the auto-dispose controller (and its signalling subscription) alive
    // for the duration of each test.
    container.listen(callControllerProvider, (_, _) {}, fireImmediately: true);
  });

  CallState read() => container.read(callControllerProvider);
  CallController notifier() => container.read(callControllerProvider.notifier);

  test('outgoing call drives idle -> outgoing -> connecting -> connected -> '
      'ended', () async {
    final states = <CallState>[];
    container.listen(
      callControllerProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );

    expect(read(), isA<Idle>());

    await notifier().startCall(_bob);
    expect(read(), isA<Outgoing>());
    expect(signaling.sent.whereType<OfferMessage>(), hasLength(1));
    expect(engine.offersCreated, 1);

    signaling.emit(
      const SignalMessage.answer(from: 'BOBBB2', to: 'ALICE1', sdp: 'answer'),
    );
    await _tick();
    expect(read(), isA<Connecting>());
    expect(engine.remoteDescriptions, contains('answer'));

    engine.fireConnected();
    expect(read(), isA<Connected>());

    await notifier().endCall();
    expect(read(), isA<Ended>());
    expect(signaling.sent.whereType<CallEndMessage>(), hasLength(1));
    expect(engine.sessionsClosed, greaterThanOrEqualTo(1));

    expect(states.map((s) => s.runtimeType).toList(), [
      Idle,
      Outgoing,
      Connecting,
      Connected,
      Ended,
    ]);
  });

  test('incoming call can be declined back to idle', () async {
    signaling.emit(
      const SignalMessage.offer(from: 'BOBBB2', to: 'ALICE1', sdp: 'offer'),
    );
    await _tick();

    final incoming = read();
    expect(incoming, isA<Incoming>());
    expect((incoming as Incoming).peer.userId, 'BOBBB2');

    await notifier().declineCall();
    expect(read(), isA<Idle>());
    expect(signaling.sent.whereType<DeclineMessage>(), hasLength(1));
  });

  test('a remote call-end while ringing ends the call', () async {
    await notifier().startCall(_bob);
    expect(read(), isA<Outgoing>());

    signaling.emit(
      const SignalMessage.callEnd(
        from: 'BOBBB2',
        to: 'ALICE1',
        reason: 'peer-left',
      ),
    );
    await _tick();

    final state = read();
    expect(state, isA<Ended>());
    expect((state as Ended).reason, 'User left the call');
  });

  test('remote ICE candidates are forwarded to the engine', () async {
    await notifier().startCall(_bob);
    signaling.emit(
      const SignalMessage.iceCandidate(
        from: 'BOBBB2',
        to: 'ALICE1',
        candidate: IceCandidatePayload(candidate: 'cand', sdpMLineIndex: 0),
      ),
    );
    await _tick();
    expect(engine.remoteCandidates, hasLength(1));
  });
}

class _StubSession extends SessionController {
  _StubSession(this._user);

  final User _user;

  @override
  User? build() => _user;
}

class _FakeSignaling implements SignalingTransport {
  final _messages = StreamController<SignalMessage>.broadcast();
  final List<SignalMessage> sent = [];

  void emit(SignalMessage message) => _messages.add(message);

  @override
  Stream<SignalMessage> get messages => _messages.stream;

  @override
  Stream<SignalingConnectionState> get connectionState => const Stream.empty();

  @override
  SignalingConnectionState get currentState =>
      SignalingConnectionState.connected;

  @override
  void connect(User self) {}

  @override
  void send(SignalMessage message) => sent.add(message);

  @override
  void disconnect() {}
}

class _FakeEngine implements WebRtcEngine {
  void Function()? _onConnected;
  bool hasLocalMediaValue = false;
  int offersCreated = 0;
  int sessionsClosed = 0;
  final List<String> remoteDescriptions = [];
  final List<IceCandidatePayload> remoteCandidates = [];

  void fireConnected() => _onConnected?.call();

  @override
  void bind({
    void Function(IceCandidatePayload candidate)? onLocalCandidate,
    void Function()? onConnected,
    void Function()? onFailed,
    void Function()? onDataChannelOpen,
    void Function(ChatMessage message)? onChatMessage,
    void Function({required bool hasVideo})? onRemoteMedia,
    void Function({required bool cameraOn, required bool micOn})?
    onRemoteMediaState,
    void Function(String sdp)? onRenegotiate,
  }) {
    _onConnected = onConnected;
  }

  @override
  void sendMediaState({required bool cameraOn, required bool micOn}) {}

  @override
  bool get hasLocalMedia => hasLocalMediaValue;

  @override
  bool get hasVideo => false;

  @override
  Future<void> openLocalMedia({
    required bool audio,
    required bool video,
  }) async {
    hasLocalMediaValue = true;
  }

  @override
  Future<void> setupConnection({required bool asCaller}) async {}

  @override
  Future<String> createOffer() async {
    offersCreated++;
    return 'offer';
  }

  @override
  Future<String> createAnswer() async => 'answer';

  @override
  Future<void> setRemoteDescription(String sdp, String type) async {
    remoteDescriptions.add(sdp);
  }

  @override
  Future<String> applyRemoteOffer(String sdp) async {
    remoteDescriptions.add(sdp);
    return 'answer';
  }

  @override
  Future<void> enableCamera() async {}

  @override
  Future<void> addRemoteCandidate(IceCandidatePayload candidate) async {
    remoteCandidates.add(candidate);
  }

  @override
  void sendChat(ChatMessage message) {}

  @override
  Future<void> setMicEnabled({required bool enabled}) async {}

  @override
  Future<void> setCameraEnabled({required bool enabled}) async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> setSpeakerphone({required bool enabled}) async {}

  @override
  Future<double> readInputLevel() async => 0;

  @override
  Future<void> closeSession() async {
    sessionsClosed++;
    hasLocalMediaValue = false;
  }

  @override
  Future<void> dispose() async {}

  @override
  RTCVideoRenderer get localRenderer => throw UnimplementedError();

  @override
  RTCVideoRenderer get remoteRenderer => throw UnimplementedError();
}
