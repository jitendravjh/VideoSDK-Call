import 'dart:async';

import 'package:meet_videosdk/application/call/chat_controller.dart';
import 'package:meet_videosdk/application/call/remote_media_controller.dart';
import 'package:meet_videosdk/application/lobby/lobby_controller.dart';
import 'package:meet_videosdk/application/lobby/session_controller.dart';
import 'package:meet_videosdk/core/logging.dart';
import 'package:meet_videosdk/data/models/call_state.dart';
import 'package:meet_videosdk/data/models/chat_message.dart';
import 'package:meet_videosdk/data/models/ice_candidate_payload.dart';
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
        SignalMessage.offer(from: self.userId, to: peer.userId, sdp: sdp),
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
        SignalMessage.answer(from: self.userId, to: peer.userId, sdp: answer),
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

  Future<void> switchCamera() => _engine.switchCamera();

  Future<void> setSpeakerphone({required bool enabled}) =>
      _engine.setSpeakerphone(enabled: enabled);

  void _resetMediaState({required bool cameraOn}) {
    _localMicOn = true;
    _localCameraOn = cameraOn;
    ref.read(chatControllerProvider.notifier).clear();
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
      text: trimmed,
      sentAt: DateTime.now(),
    );
    _engine.sendChat(message);
    ref.read(chatControllerProvider.notifier).add(message);
  }

  void _onSignal(SignalMessage message) {
    switch (message) {
      case OfferMessage(:final from, :final sdp):
        _onIncomingOffer(from, sdp);
      case AnswerMessage(:final sdp):
        unawaited(_onAnswer(sdp));
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
          RegisteredMessage():
        break;
    }
  }

  void _onIncomingOffer(String from, String sdp) {
    final self = _self;
    if (state is! Idle) {
      if (self != null) {
        _signaling.send(SignalMessage.decline(from: self.userId, to: from));
      }
      return;
    }
    state = CallState.incoming(peer: _resolvePeer(from), offerSdp: sdp);
  }

  Future<void> _onAnswer(String sdp) async {
    final peer = state.peer;
    if (state is! Outgoing || peer == null) return;
    state = CallState.connecting(peer: peer);
    await _engine.setRemoteDescription(sdp, 'answer');
  }

  void _onDeclined() {
    if (state is! Outgoing) return;
    unawaited(_teardown());
    state = const CallState.ended(reason: 'Call declined');
  }

  void _onRemoteEnd(String? reason) {
    if (!state.isActive) return;
    unawaited(_teardown());
    state = CallState.ended(reason: _reasonLabel(reason));
  }

  void _handleConnected() {
    final peer = state.peer;
    if (peer != null && state.isActive) {
      state = CallState.connected(peer: peer);
    }
  }

  void _handleFailed() {
    if (!state.isActive) return;
    unawaited(_teardown());
    state = const CallState.failed(error: 'Connection failed');
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
      onChatMessage: (message) =>
          ref.read(chatControllerProvider.notifier).add(message),
      onRemoteMedia: ({required hasVideo}) =>
          ref.read(remoteVideoProvider.notifier).update(hasVideo: hasVideo),
      onRemoteMediaState: ({required cameraOn, required micOn}) {
        ref.read(remoteVideoProvider.notifier).update(hasVideo: cameraOn);
        ref.read(remoteMicProvider.notifier).update(micOn: micOn);
      },
    );
  }

  void _fail(String message) {
    unawaited(_teardown());
    state = CallState.failed(error: message);
  }

  Future<void> _teardown() => _engine.closeSession();

  User _resolvePeer(String userId) {
    final users = ref.read(lobbyControllerProvider);
    return users.firstWhere(
      (u) => u.userId == userId,
      orElse: () => User(userId: userId, displayName: userId),
    );
  }

  String _reasonLabel(String? reason) => switch (reason) {
    'offline' => 'User is offline',
    'busy' => 'User is busy',
    'peer-left' => 'Peer left the call',
    _ => 'Call ended',
  };
}
