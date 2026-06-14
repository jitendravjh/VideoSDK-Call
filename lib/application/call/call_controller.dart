import 'dart:async';

import 'package:meet_videosdk/application/call/chat_controller.dart';
import 'package:meet_videosdk/application/call/remote_media_controller.dart';
import 'package:meet_videosdk/application/history/call_history_controller.dart';
import 'package:meet_videosdk/application/lobby/lobby_controller.dart';
import 'package:meet_videosdk/application/lobby/session_controller.dart';
import 'package:meet_videosdk/application/meeting/meeting_controller.dart';
import 'package:meet_videosdk/core/call_code.dart';
import 'package:meet_videosdk/core/logging.dart';
import 'package:meet_videosdk/data/models/call_record.dart';
import 'package:meet_videosdk/data/models/call_state.dart';
import 'package:meet_videosdk/data/models/chat_message.dart';
import 'package:meet_videosdk/data/models/ice_candidate_payload.dart';
import 'package:meet_videosdk/data/models/meeting_state.dart';
import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/signaling/signaling_providers.dart';
import 'package:meet_videosdk/data/signaling/signaling_transport.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_engine.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'call_controller.g.dart';

/// The single source of truth for the call lifecycle.
///
/// Owns the [CallState] union, translates inbound signalling into state
/// transitions, and drives the [WebRtcEngine]. The caller is always the
/// offerer, which avoids glare in a 1:1 call.
@riverpod
class CallController extends _$CallController {
  final AppLogger _log = AppLogger('CallController');

  static const _uuid = Uuid();

  late final WebRtcEngine _engine = ref.read(webRtcEngineProvider);
  late final SignalingTransport _signaling = ref.read(signalingServiceProvider);

  bool _localMicOn = true;
  bool _localCameraOn = false;

  // Tracking for the history record of the current call.
  CallDirection? _direction;
  User? _historyPeer;
  DateTime? _startedAt;
  DateTime? _connectedAt;
  bool _recorded = false;

  @override
  CallState build() {
    final sub = _signaling.messages.listen(_onSignal);
    ref.onDispose(sub.cancel);
    return const CallState.idle();
  }

  User? get _self => ref.read(sessionControllerProvider);

  Future<void> startCall(User peer, {bool video = false}) async {
    final self = _self;
    if (self == null || self.userId.isEmpty || state is! Idle) return;

    _beginCall(peer, CallDirection.outgoing);
    _resetMediaState(cameraOn: video);
    state = CallState.outgoing(peer: peer);
    _bindEngine();

    try {
      if (!_engine.hasLocalMedia) {
        await _engine.openLocalMedia(audio: true, video: video);
      }
      await _engine.setupConnection(asCaller: true);
      final sdp = await _engine.createOffer();
      _signaling.send(
        SignalMessage.offer(
          from: self.userId,
          to: peer.userId,
          sdp: sdp,
          fromName: self.displayName,
        ),
      );
    } on Object catch (error, stackTrace) {
      _log.error('startCall failed', error, stackTrace);
      _fail('Could not start the call');
    }
  }

  Future<void> acceptCall({bool video = false}) async {
    final self = _self;
    final current = state;
    if (self == null || self.userId.isEmpty || current is! Incoming) return;

    _resetMediaState(cameraOn: video);
    final peer = current.peer;
    final offerSdp = current.offerSdp;
    state = CallState.connecting(peer: peer);
    _bindEngine();

    try {
      if (!_engine.hasLocalMedia) {
        await _engine.openLocalMedia(audio: true, video: video);
      }
      await _engine.setupConnection(asCaller: false);
      await _engine.setRemoteDescription(offerSdp, 'offer');
      final answer = await _engine.createAnswer();
      _signaling.send(
        SignalMessage.answer(
          from: self.userId,
          to: peer.userId,
          sdp: answer,
          fromName: self.displayName,
        ),
      );
    } on Object catch (error, stackTrace) {
      _log.error('acceptCall failed', error, stackTrace);
      _fail('Could not answer the call');
    }
  }

  Future<void> declineCall() async {
    final self = _self;
    final current = state;
    if (self == null || self.userId.isEmpty || current is! Incoming) return;

    _signaling.send(
      SignalMessage.decline(from: self.userId, to: current.peer.userId),
    );
    _recordCall(CallOutcome.declined);
    state = const CallState.idle();
    // Clear any ICE the ringing caller trickled so it cannot leak into the
    // next call's peer connection.
    await _teardown();
  }

  Future<void> endCall() async {
    final self = _self;
    final peer = state.peer;
    if (self != null && peer != null) {
      _signaling.send(
        SignalMessage.callEnd(from: self.userId, to: peer.userId),
      );
    }
    _recordCall(
      _connectedAt != null ? CallOutcome.completed : CallOutcome.missed,
    );
    await _teardown();
    state = const CallState.ended(reason: 'Call ended');
  }

  void reset() {
    if (state is Ended || state is Failed) {
      state = const CallState.idle();
    }
  }

  /// Opens local media for the pre-join preview. Re-acquiring with a different
  /// `video` flag swaps the track set so an audio-only call carries no video
  /// track. The stream is reused by [startCall].
  Future<void> openPreview({required bool video}) async {
    await _engine.openLocalMedia(audio: true, video: video);
  }

  Future<void> cancelPreview() async {
    if (state is Idle) {
      await _engine.closeSession();
    }
  }

  Future<void> setMicEnabled({required bool enabled}) async {
    _localMicOn = enabled;
    await _engine.setMicEnabled(enabled: enabled);
    _broadcastMediaState();
  }

  Future<void> setCameraEnabled({required bool enabled}) async {
    _localCameraOn = enabled;
    await _engine.setCameraEnabled(enabled: enabled);
    _broadcastMediaState();
  }

  /// Turns the camera on mid-call, acquiring it (and renegotiating) if the call
  /// started audio-only. Permission must already be granted by the caller.
  Future<void> enableCamera() async {
    _localCameraOn = true;
    await _engine.enableCamera();
    _broadcastMediaState();
  }

  Future<void> switchCamera() => _engine.switchCamera();

  Future<void> setSpeakerphone({required bool enabled}) =>
      _engine.setSpeakerphone(enabled: enabled);

  void _resetMediaState({required bool cameraOn}) {
    _localMicOn = true;
    _localCameraOn = cameraOn;
    ref.read(chatControllerProvider.notifier).clear();
    ref.read(chatUnreadProvider.notifier).reset();
    ref.read(remoteVideoProvider.notifier).update(hasVideo: false);
    ref.read(remoteMicProvider.notifier).update(micOn: true);
  }

  void _broadcastMediaState() =>
      _engine.sendMediaState(cameraOn: _localCameraOn, micOn: _localMicOn);

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

  void _onSignal(SignalMessage message) {
    switch (message) {
      case OfferMessage(:final from, :final sdp, :final fromName):
        _onIncomingOffer(from, sdp, fromName);
      case AnswerMessage(:final sdp, :final fromName):
        unawaited(_onAnswer(sdp, fromName));
      case DeclineMessage():
        _onDeclined();
      case IceCandidateMessage(:final from, :final candidate):
        // Only accept candidates from the peer of the current call.
        if (from == state.peer?.userId) {
          unawaited(_engine.addRemoteCandidate(candidate));
        }
      case CallEndMessage(:final reason):
        _onRemoteEnd(reason);
      case PresenceMessage() ||
          UserJoinedMessage() ||
          UserLeftMessage() ||
          RegisterMessage() ||
          RegisteredMessage() ||
          MeetingHostMessage() ||
          MeetingJoinMessage() ||
          MeetingLeaveMessage() ||
          MeetingJoinedMessage() ||
          MeetingPeerJoinedMessage() ||
          MeetingPeerLeftMessage() ||
          MeetingErrorMessage() ||
          MeetingOfferMessage() ||
          MeetingAnswerMessage() ||
          MeetingIceMessage() ||
          MeetingChatMessage():
        break;
    }
  }

  void _onIncomingOffer(String from, String sdp, String? fromName) {
    final self = _self;
    // A fresh offer from the peer we are already connected to is a
    // renegotiation (e.g. they turned their camera on mid-call): answer it in
    // place without disturbing the call state.
    final current = state;
    final currentPeer = current.peer;
    if ((current is Connected || current is Connecting) &&
        currentPeer != null &&
        from == currentPeer.userId) {
      unawaited(_answerRenegotiation(from, sdp));
      return;
    }
    // Busy if already on a 1:1 call or in a group meeting: decline so the
    // incoming call cannot yank the user out of an active meeting.
    final inMeeting = ref.read(meetingControllerProvider) is! MeetingIdle;
    if (state is! Idle || inMeeting) {
      if (self != null) {
        _signaling.send(SignalMessage.decline(from: self.userId, to: from));
      }
      return;
    }
    // Prefer the name carried on the offer (server-stamped) so a caller reached
    // by code shows a real name rather than a code placeholder.
    final peer = (fromName != null && fromName.isNotEmpty)
        ? User(userId: from, displayName: fromName)
        : _resolvePeer(from);
    _beginCall(peer, CallDirection.incoming);
    state = CallState.incoming(peer: peer, offerSdp: sdp);
  }

  Future<void> _onAnswer(String sdp, String? fromName) async {
    final peer = state.peer;
    if (peer == null) return;
    // A renegotiation answer (we enabled our camera mid-call) lands while
    // already Connected: just apply it without changing state.
    if (state is Connected) {
      await _engine.setRemoteDescription(sdp, 'answer');
      return;
    }
    if (state is! Outgoing) return;
    // The answer carries the callee's real name; adopt it so the caller stops
    // showing the code placeholder it built at join-by-code time.
    final resolved = (fromName != null && fromName.isNotEmpty)
        ? peer.copyWith(displayName: fromName)
        : peer;
    _historyPeer = resolved;
    state = CallState.connecting(peer: resolved);
    await _engine.setRemoteDescription(sdp, 'answer');
  }

  Future<void> _answerRenegotiation(String from, String sdp) async {
    final self = _self;
    if (self == null) return;
    final answer = await _engine.applyRemoteOffer(sdp);
    _signaling.send(
      SignalMessage.answer(
        from: self.userId,
        to: from,
        sdp: answer,
        fromName: self.displayName,
      ),
    );
  }

  void _onDeclined() {
    if (state is! Outgoing) return;
    _recordCall(CallOutcome.declined);
    unawaited(_teardown());
    state = const CallState.ended(reason: 'Call declined');
  }

  void _onRemoteEnd(String? reason) {
    if (!state.isActive) return;
    _recordCall(_outcomeForRemoteEnd(reason));
    unawaited(_teardown());
    state = CallState.ended(reason: _reasonLabel(reason));
  }

  void _handleConnected() {
    final peer = state.peer;
    if (peer != null && state.isActive) {
      _connectedAt ??= DateTime.now();
      state = CallState.connected(peer: peer);
    }
  }

  void _handleFailed() {
    if (!state.isActive) return;
    _recordCall(CallOutcome.failed);
    unawaited(_teardown());
    state = const CallState.failed(error: 'Connection failed');
  }

  CallOutcome _outcomeForRemoteEnd(String? reason) {
    if (_connectedAt != null) return CallOutcome.completed;
    if (reason == 'offline') return CallOutcome.unreachable;
    return CallOutcome.missed;
  }

  void _sendLocalCandidate(IceCandidatePayload candidate) {
    final self = _self;
    final peer = state.peer;
    if (self == null || self.userId.isEmpty || peer == null) return;
    _signaling.send(
      SignalMessage.iceCandidate(
        from: self.userId,
        to: peer.userId,
        candidate: candidate,
      ),
    );
  }

  void _bindEngine() {
    _engine.bind(
      onLocalCandidate: _sendLocalCandidate,
      onConnected: _handleConnected,
      onFailed: _handleFailed,
      onDataChannelOpen: _broadcastMediaState,
      onChatMessage: (message) {
        ref.read(chatControllerProvider.notifier).add(message);
        ref.read(chatUnreadProvider.notifier).increment();
      },
      onRemoteMedia: ({required hasVideo}) =>
          ref.read(remoteVideoProvider.notifier).update(hasVideo: hasVideo),
      onRemoteMediaState: ({required cameraOn, required micOn}) {
        ref.read(remoteVideoProvider.notifier).update(hasVideo: cameraOn);
        ref.read(remoteMicProvider.notifier).update(micOn: micOn);
      },
      onRenegotiate: (sdp) {
        final self = _self;
        final peer = state.peer;
        if (self == null || peer == null) return;
        _signaling.send(
          SignalMessage.offer(
            from: self.userId,
            to: peer.userId,
            sdp: sdp,
            fromName: self.displayName,
          ),
        );
      },
    );
  }

  void _fail(String message) {
    _recordCall(CallOutcome.failed);
    unawaited(_teardown());
    state = CallState.failed(error: message);
  }

  void _beginCall(User peer, CallDirection direction) {
    _direction = direction;
    _historyPeer = peer;
    _startedAt = DateTime.now();
    _connectedAt = null;
    _recorded = false;
  }

  void _recordCall(CallOutcome outcome) {
    final peer = _historyPeer;
    final direction = _direction;
    final startedAt = _startedAt;
    if (_recorded || peer == null || direction == null || startedAt == null) {
      return;
    }
    _recorded = true;
    final connectedAt = _connectedAt;
    final duration = connectedAt == null
        ? Duration.zero
        : DateTime.now().difference(connectedAt);
    ref
        .read(callHistoryControllerProvider.notifier)
        .add(
          CallRecord(
            id: _uuid.v4(),
            peerId: peer.userId,
            peerName: peer.displayName,
            direction: direction,
            outcome: outcome,
            startedAt: startedAt,
            durationSeconds: duration.inSeconds,
          ),
        );
  }

  Future<void> _teardown() => _engine.closeSession();

  User _resolvePeer(String userId) {
    final users = ref.read(lobbyControllerProvider);
    return users.firstWhere(
      (u) => u.userId == userId,
      orElse: () => User(userId: userId, displayName: CallCode.format(userId)),
    );
  }

  String _reasonLabel(String? reason) => switch (reason) {
    'offline' => 'User is offline',
    'busy' => 'User is busy',
    'peer-left' => 'User left the call',
    _ => 'Call ended',
  };
}
