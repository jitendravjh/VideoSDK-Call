import 'dart:async';

import 'package:meet_videosdk/application/call/chat_controller.dart';
import 'package:meet_videosdk/application/lobby/session_controller.dart';
import 'package:meet_videosdk/application/meeting/meeting_reducer.dart';
import 'package:meet_videosdk/core/call_code.dart';
import 'package:meet_videosdk/core/logging.dart';
import 'package:meet_videosdk/data/models/chat_message.dart';
import 'package:meet_videosdk/data/models/meeting_state.dart';
import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/signaling/signaling_providers.dart';
import 'package:meet_videosdk/data/signaling/signaling_transport.dart';
import 'package:meet_videosdk/data/webrtc/mesh_engine.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'meeting_controller.g.dart';

/// Drives a group meeting over a [MeshEngine]: hosting/joining, the glare-free
/// offer rule, per-peer signal routing by `from`, and participant bookkeeping.
///
/// Entirely separate from `CallController`; meeting signalling uses its own
/// `meeting-*` events so the two never cross-talk.
@riverpod
class MeetingController extends _$MeetingController {
  final AppLogger _log = AppLogger('MeetingController');

  static const _uuid = Uuid();

  late final MeshEngine _engine = ref.read(meshEngineProvider);
  late final SignalingTransport _signaling = ref.read(signalingServiceProvider);

  bool _micOn = true;
  bool _cameraOn = false;
  Timer? _connectTimer;

  @override
  MeetingState build() {
    final sub = _signaling.messages.listen(_onSignal);
    ref.onDispose(() {
      _connectTimer?.cancel();
      unawaited(sub.cancel());
    });
    return const MeetingState.idle();
  }

  // If the server never acknowledges host/join (e.g. an old build with no
  // meeting support), fail with a message rather than spinning forever.
  void _startConnectTimeout() {
    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(seconds: 12), () {
      if (state is MeetingConnecting) {
        unawaited(_fail('Could not reach the meeting'));
      }
    });
  }

  User? get _self => ref.read(sessionControllerProvider);

  /// Hosts a new meeting; the server generates and returns its code.
  Future<void> host({bool video = false}) async {
    final self = _self;
    if (self == null || self.userId.isEmpty || state is! MeetingIdle) return;
    _micOn = true;
    _cameraOn = video;
    _resetChat();
    // The code is unknown until the server replies with `meeting-joined`.
    state = const MeetingState.connecting(roomCode: '', isHost: true);
    _bindEngine();
    try {
      await _engine.openLocalMedia(audio: true, video: video);
      _signaling.send(const SignalMessage.meetingHost());
      _startConnectTimeout();
    } on Object catch (error, stackTrace) {
      _log.error('host failed', error, stackTrace);
      await _fail('Could not start the meeting');
    }
  }

  /// Joins an existing meeting by its code (the host's code).
  Future<void> join(String roomCode, {bool video = false}) async {
    final self = _self;
    if (self == null || self.userId.isEmpty || state is! MeetingIdle) return;
    if (roomCode.isEmpty) return;
    _micOn = true;
    _cameraOn = video;
    _resetChat();
    state = MeetingState.connecting(roomCode: roomCode, isHost: false);
    _bindEngine();
    try {
      await _engine.openLocalMedia(audio: true, video: video);
      _signaling.send(SignalMessage.meetingJoin(roomCode: roomCode));
      _startConnectTimeout();
    } on Object catch (error, stackTrace) {
      _log.error('join failed', error, stackTrace);
      await _fail('Could not join the meeting');
    }
  }

  Future<void> leave() async {
    _connectTimer?.cancel();
    final code = state.roomCode;
    if (code != null) {
      _signaling.send(SignalMessage.meetingLeave(roomCode: code));
    }
    await _engine.closeAll();
    state = const MeetingState.idle();
  }

  void reset() {
    if (state is MeetingEnded) state = const MeetingState.idle();
  }

  Future<void> setMicEnabled({required bool enabled}) async {
    _micOn = enabled;
    await _engine.setMicEnabled(enabled: enabled);
    _engine.broadcastMediaState(cameraOn: _cameraOn, micOn: _micOn);
  }

  Future<void> setCameraEnabled({required bool enabled}) async {
    _cameraOn = enabled;
    await _engine.setCameraEnabled(enabled: enabled);
    _engine.broadcastMediaState(cameraOn: _cameraOn, micOn: _micOn);
  }

  /// Turns the camera on mid-meeting, acquiring it (and renegotiating with every
  /// peer) if the meeting started audio-only. Permission must already be
  /// granted by the caller.
  Future<void> enableCamera() async {
    _cameraOn = true;
    await _engine.enableCamera();
    _engine.broadcastMediaState(cameraOn: _cameraOn, micOn: _micOn);
  }

  Future<void> switchCamera() => _engine.switchCamera();

  Future<void> setSpeakerphone({required bool enabled}) =>
      _engine.setSpeakerphone(enabled: enabled);

  void sendChat(String text) {
    final self = _self;
    final trimmed = text.trim();
    if (self == null || self.userId.isEmpty || trimmed.isEmpty) return;
    final message = ChatMessage(
      id: _uuid.v4(),
      senderId: self.userId,
      senderName: self.displayName,
      text: trimmed,
      sentAt: DateTime.now(),
    );
    _engine.sendChat(message);
    ref.read(chatControllerProvider.notifier).add(message);
  }

  void _resetChat() {
    ref.read(chatControllerProvider.notifier).clear();
    ref.read(chatUnreadProvider.notifier).reset();
  }

  void _onSignal(SignalMessage message) {
    // Only act on meeting traffic while actually in a meeting; everything else
    // (presence, 1:1 calls) is handled by the other controllers.
    final inMeeting = state is MeetingConnecting || state is MeetingActive;
    if (!inMeeting) return;
    switch (message) {
      case MeetingJoinedMessage(:final roomCode, :final peers):
        unawaited(_onJoined(roomCode, peers));
      case MeetingPeerJoinedMessage(:final user):
        unawaited(_onPeerJoined(user));
      case MeetingPeerLeftMessage(:final userId):
        unawaited(_onPeerLeft(userId));
      case MeetingOfferMessage(:final from, :final sdp, :final fromName):
        unawaited(_onOffer(from, sdp, fromName));
      case MeetingAnswerMessage(:final from, :final sdp):
        unawaited(_onAnswer(from, sdp));
      case MeetingIceMessage(:final from, :final candidate):
        unawaited(_engine.addRemoteCandidate(from, candidate));
      case MeetingErrorMessage(:final reason):
        unawaited(_onError(reason));
      case _:
        break;
    }
  }

  Future<void> _onJoined(String roomCode, List<User> peers) async {
    _connectTimer?.cancel();
    final isHost = state.isHost;
    state = MeetingState.active(
      roomCode: roomCode,
      isHost: isHost,
      participants: peers
          .map(
            (u) => MeetingParticipant(
              userId: u.userId,
              displayName: u.displayName,
            ),
          )
          .toList(),
    );
    for (final peer in peers) {
      await _connectToPeer(peer.userId);
    }
  }

  Future<void> _onPeerJoined(User user) async {
    _updateParticipants(
      (list) => MeetingReducer.upsert(
        list,
        MeetingParticipant(userId: user.userId, displayName: user.displayName),
      ),
    );
    await _connectToPeer(user.userId);
  }

  Future<void> _onPeerLeft(String userId) async {
    await _engine.removePeer(userId);
    _updateParticipants((list) => MeetingReducer.remove(list, userId));
  }

  /// Establishes (or prepares) the connection to [peerId] following the glare
  /// rule: the smaller id offers, the larger awaits the offer. The peer link is
  /// created up front either way so incoming ICE/offer always has a home.
  Future<void> _connectToPeer(String peerId) async {
    final self = _self;
    if (self == null) return;
    final offerer = MeetingReducer.shouldOffer(self.userId, peerId);
    if (!_engine.hasPeer(peerId)) {
      await _engine.addPeer(peerId, asOfferer: offerer);
    }
    // The peer may have left during addPeer; bail rather than negotiate a
    // connection that no longer exists.
    if (offerer && _engine.hasPeer(peerId)) {
      final sdp = await _engine.createOffer(peerId);
      if (!_engine.hasPeer(peerId)) return;
      _signaling.send(
        SignalMessage.meetingOffer(
          from: self.userId,
          to: peerId,
          sdp: sdp,
          fromName: self.displayName,
        ),
      );
    }
  }

  Future<void> _onOffer(String from, String sdp, String? fromName) async {
    final self = _self;
    if (self == null) return;
    if (!_engine.hasPeer(from)) {
      await _engine.addPeer(from, asOfferer: false);
    }
    if (!_engine.hasPeer(from)) return;
    _ensureParticipant(from, fromName);
    await _engine.setRemoteDescription(from, sdp, 'offer');
    if (!_engine.hasPeer(from)) return;
    final answer = await _engine.createAnswer(from);
    if (!_engine.hasPeer(from)) return;
    _signaling.send(
      SignalMessage.meetingAnswer(
        from: self.userId,
        to: from,
        sdp: answer,
        fromName: self.displayName,
      ),
    );
  }

  Future<void> _onAnswer(String from, String sdp) async {
    if (!_engine.hasPeer(from)) return;
    await _engine.setRemoteDescription(from, sdp, 'answer');
  }

  Future<void> _onError(String reason) async {
    _connectTimer?.cancel();
    await _engine.closeAll();
    state = MeetingState.ended(reason: _reasonLabel(reason));
  }

  Future<void> _fail(String message) async {
    _connectTimer?.cancel();
    await _engine.closeAll();
    state = MeetingState.ended(reason: message);
  }

  void _bindEngine() {
    _engine.bind(
      onLocalCandidate: (peerId, candidate) {
        final self = _self;
        if (self == null) return;
        _signaling.send(
          SignalMessage.meetingIce(
            from: self.userId,
            to: peerId,
            candidate: candidate,
          ),
        );
      },
      onConnected: (peerId) =>
          _updateParticipant(peerId, (p) => p.copyWith(connected: true)),
      onClosed: (peerId) =>
          _updateParticipant(peerId, (p) => p.copyWith(connected: false)),
      onChannelOpen: (_) =>
          _engine.broadcastMediaState(cameraOn: _cameraOn, micOn: _micOn),
      onRemoteVideo: (peerId, {required hasVideo}) =>
          _updateParticipant(peerId, (p) => p.copyWith(hasVideo: hasVideo)),
      onRemoteMediaState: (peerId, {required cameraOn, required micOn}) =>
          _updateParticipant(
            peerId,
            (p) => p.copyWith(hasVideo: cameraOn, micOn: micOn),
          ),
      onRenegotiate: (peerId, sdp) {
        final self = _self;
        if (self == null) return;
        _signaling.send(
          SignalMessage.meetingOffer(
            from: self.userId,
            to: peerId,
            sdp: sdp,
            fromName: self.displayName,
          ),
        );
      },
      onChat: (message) {
        ref.read(chatControllerProvider.notifier).add(message);
        ref.read(chatUnreadProvider.notifier).increment();
      },
    );
  }

  void _updateParticipants(
    List<MeetingParticipant> Function(List<MeetingParticipant>) change,
  ) {
    final current = state;
    if (current is! MeetingActive) return;
    state = current.copyWith(participants: change(current.participants));
  }

  void _updateParticipant(
    String userId,
    MeetingParticipant Function(MeetingParticipant) change,
  ) => _updateParticipants(
    (list) => MeetingReducer.update(list, userId, change),
  );

  void _ensureParticipant(String userId, String? name) {
    _updateParticipants((list) {
      if (list.any((p) => p.userId == userId)) return list;
      return MeetingReducer.upsert(
        list,
        MeetingParticipant(
          userId: userId,
          displayName: (name != null && name.isNotEmpty)
              ? name
              : CallCode.format(userId),
        ),
      );
    });
  }

  String _reasonLabel(String reason) => switch (reason) {
    'no-such-meeting' => 'Meeting not found',
    'host-left' => 'The host ended the meeting',
    _ => 'Meeting ended',
  };
}
