import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:meet_videosdk/application/call/chat_controller.dart';
import 'package:meet_videosdk/application/lobby/session_controller.dart';
import 'package:meet_videosdk/application/meeting/meeting_controller.dart';
import 'package:meet_videosdk/data/models/chat_message.dart';
import 'package:meet_videosdk/data/models/ice_candidate_payload.dart';
import 'package:meet_videosdk/data/models/meeting_state.dart';
import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/session/session_store.dart';
import 'package:meet_videosdk/data/signaling/signaling_providers.dart';
import 'package:meet_videosdk/data/signaling/signaling_transport.dart';
import 'package:meet_videosdk/data/webrtc/mesh_engine.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// self id 'ALICE1' sorts before 'BOBBB2' (so it offers Bob) and after 'AA0000'
// (so it waits for Aaron's offer) — exercises both sides of the glare rule.
const _self = User(userId: 'ALICE1', displayName: 'Alice');
const _bob = User(userId: 'BOBBB2', displayName: 'Bob');
const _aaron = User(userId: 'AA0000', displayName: 'Aaron');

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FakeSignaling signaling;
  late _FakeMesh mesh;
  late ProviderContainer container;

  setUp(() async {
    signaling = _FakeSignaling();
    mesh = _FakeMesh();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        signalingServiceProvider.overrideWithValue(signaling),
        meshEngineProvider.overrideWithValue(mesh),
        sessionControllerProvider.overrideWith(() => _StubSession(_self)),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      meetingControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
  });

  MeetingState read() => container.read(meetingControllerProvider);
  MeetingController notifier() =>
      container.read(meetingControllerProvider.notifier);

  test('hosting adopts the server-assigned meeting code', () async {
    await notifier().host();
    expect(read(), isA<MeetingConnecting>());
    expect(signaling.sent.whereType<MeetingHostMessage>(), hasLength(1));

    signaling.emit(
      const SignalMessage.meetingJoined(roomCode: 'MEET01', peers: []),
    );
    await _pump();

    final state = read();
    expect(state, isA<MeetingActive>());
    expect((state as MeetingActive).roomCode, 'MEET01');
    expect(state.isHost, isTrue);
    expect(state.participants, isEmpty);
  });

  test(
    'joining a room of N seeds participants and offers per the glare rule',
    () async {
      await notifier().join('HOST01');
      signaling.emit(
        const SignalMessage.meetingJoined(
          roomCode: 'HOST01',
          peers: [_bob, _aaron],
        ),
      );
      await _pump();

      final state = read();
      expect(state, isA<MeetingActive>());
      expect(
        (state as MeetingActive).participants.map((p) => p.userId).toSet(),
        {'BOBBB2', 'AA0000'},
      );

      // A peer connection is created for every participant...
      expect(mesh.peers, {'BOBBB2', 'AA0000'});
      // ...but we only offer the larger id (Bob); we await Aaron's offer.
      expect(mesh.offers, ['BOBBB2']);
      final offers = signaling.sent.whereType<MeetingOfferMessage>().toList();
      expect(offers, hasLength(1));
      expect(offers.single.to, 'BOBBB2');
    },
  );

  test('an incoming meeting-offer is answered', () async {
    await notifier().join('HOST01');
    signaling.emit(
      const SignalMessage.meetingJoined(roomCode: 'HOST01', peers: [_aaron]),
    );
    await _pump();

    signaling.emit(
      const SignalMessage.meetingOffer(
        from: 'AA0000',
        to: 'ALICE1',
        sdp: 'their-offer',
        fromName: 'Aaron',
      ),
    );
    await _pump();

    expect(mesh.remoteDescriptions, contains(('AA0000', 'offer')));
    expect(mesh.answers, contains('AA0000'));
    final answers = signaling.sent.whereType<MeetingAnswerMessage>().toList();
    expect(answers, hasLength(1));
    expect(answers.single.to, 'AA0000');
  });

  test(
    'a peer-joined connects and a peer-left prunes the participant',
    () async {
      await notifier().join('HOST01');
      signaling.emit(
        const SignalMessage.meetingJoined(roomCode: 'HOST01', peers: [_bob]),
      );
      await _pump();

      signaling.emit(
        const SignalMessage.meetingPeerJoined(
          roomCode: 'HOST01',
          user: _aaron,
        ),
      );
      await _pump();
      expect(
        (read() as MeetingActive).participants.map((p) => p.userId).toSet(),
        {'BOBBB2', 'AA0000'},
      );

      mesh.fireConnected('BOBBB2');
      await _pump();
      final bob = (read() as MeetingActive).participants.firstWhere(
        (p) => p.userId == 'BOBBB2',
      );
      expect(bob.connected, isTrue);

      signaling.emit(
        const SignalMessage.meetingPeerLeft(
          roomCode: 'HOST01',
          userId: 'BOBBB2',
        ),
      );
      await _pump();
      expect(mesh.removed, contains('BOBBB2'));
      expect(
        (read() as MeetingActive).participants.map((p) => p.userId).toList(),
        ['AA0000'],
      );
    },
  );

  test('leaving tears down the mesh and returns to idle', () async {
    await notifier().host();
    signaling.emit(
      const SignalMessage.meetingJoined(roomCode: 'ALICE1', peers: []),
    );
    await _pump();

    await notifier().leave();
    expect(read(), isA<MeetingIdle>());
    expect(signaling.sent.whereType<MeetingLeaveMessage>(), hasLength(1));
    expect(mesh.closed, isTrue);
  });

  test('sending a chat echoes it into the shared transcript', () async {
    await notifier().host();
    signaling.emit(
      const SignalMessage.meetingJoined(roomCode: 'MEET01', peers: []),
    );
    await _pump();

    notifier().sendChat('hello team');
    final messages = container.read(chatControllerProvider);
    expect(messages, hasLength(1));
    expect(messages.single.text, 'hello team');
    expect(messages.single.senderId, 'ALICE1');
    expect(messages.single.senderName, 'Alice');
  });

  test(
    'an incoming chat is added to the transcript and bumps unread',
    () async {
      await notifier().host();
      signaling.emit(
        const SignalMessage.meetingJoined(roomCode: 'MEET01', peers: []),
      );
      await _pump();

      mesh.fireChat(
        ChatMessage(
          id: 'm1',
          senderId: 'BOBBB2',
          senderName: 'Bob',
          text: 'hi all',
          sentAt: DateTime(2026),
        ),
      );
      await _pump();

      expect(container.read(chatControllerProvider).single.text, 'hi all');
      expect(container.read(chatUnreadProvider), 1);
    },
  );

  test('a meeting-error ends the meeting with a readable reason', () async {
    await notifier().join('NOPE99');
    signaling.emit(
      const SignalMessage.meetingError(reason: 'no-such-meeting'),
    );
    await _pump();

    final state = read();
    expect(state, isA<MeetingEnded>());
    expect((state as MeetingEnded).reason, 'Meeting not found');
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

class _FakeMesh implements MeshEngine {
  final Set<String> peers = {};
  final List<String> offers = [];
  final List<String> answers = [];
  final List<(String, String)> remoteDescriptions = [];
  final List<String> removed = [];
  bool closed = false;

  void Function(String peerId)? _onConnected;
  void Function(ChatMessage message)? _onChat;

  void fireConnected(String peerId) => _onConnected?.call(peerId);
  void fireChat(ChatMessage message) => _onChat?.call(message);

  @override
  RTCVideoRenderer get localRenderer => throw UnimplementedError();

  @override
  bool get hasVideo => false;

  @override
  void bind({
    void Function(String peerId, IceCandidatePayload candidate)?
    onLocalCandidate,
    void Function(String peerId)? onConnected,
    void Function(String peerId)? onClosed,
    void Function(String peerId)? onChannelOpen,
    void Function(String peerId, {required bool hasVideo})? onRemoteVideo,
    void Function(String peerId, {required bool cameraOn, required bool micOn})?
    onRemoteMediaState,
    void Function(String peerId, String sdp)? onRenegotiate,
    void Function(ChatMessage message)? onChat,
  }) {
    _onConnected = onConnected;
    _onChat = onChat;
  }

  @override
  Future<void> openLocalMedia({
    required bool audio,
    required bool video,
  }) async {}

  @override
  Future<void> addPeer(String peerId, {required bool asOfferer}) async {
    peers.add(peerId);
  }

  @override
  bool hasPeer(String peerId) => peers.contains(peerId);

  @override
  Future<String> createOffer(String peerId) async {
    offers.add(peerId);
    return 'offer-$peerId';
  }

  @override
  Future<String> createAnswer(String peerId) async {
    answers.add(peerId);
    return 'answer-$peerId';
  }

  @override
  Future<void> setRemoteDescription(
    String peerId,
    String sdp,
    String type,
  ) async {
    remoteDescriptions.add((peerId, type));
  }

  @override
  Future<void> addRemoteCandidate(
    String peerId,
    IceCandidatePayload candidate,
  ) async {}

  @override
  RTCVideoRenderer? rendererFor(String peerId) => null;

  @override
  Future<void> removePeer(String peerId) async {
    peers.remove(peerId);
    removed.add(peerId);
  }

  @override
  Future<void> setMicEnabled({required bool enabled}) async {}

  @override
  Future<void> setCameraEnabled({required bool enabled}) async {}

  @override
  Future<void> enableCamera() async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> setSpeakerphone({required bool enabled}) async {}

  @override
  void broadcastMediaState({required bool cameraOn, required bool micOn}) {}

  @override
  void sendChat(ChatMessage message) {}

  @override
  Future<void> closeAll() async {
    closed = true;
    peers.clear();
  }

  @override
  Future<void> dispose() async {}
}
