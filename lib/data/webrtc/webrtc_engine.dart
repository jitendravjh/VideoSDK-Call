import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:meet_videosdk/data/models/chat_message.dart';
import 'package:meet_videosdk/data/models/ice_candidate_payload.dart';

/// Abstraction over the WebRTC peer connection used by `CallController`.
///
/// Keeping the controller behind this interface lets the state machine be
/// driven by a fake in unit tests, with no real peer connection or media.
abstract class WebRtcEngine {
  RTCVideoRenderer get localRenderer;
  RTCVideoRenderer get remoteRenderer;
  bool get hasVideo;
  bool get hasLocalMedia;

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
  });

  Future<void> openLocalMedia({required bool audio, required bool video});
  Future<void> setupConnection({required bool asCaller});
  Future<String> createOffer();
  Future<String> createAnswer();
  Future<void> setRemoteDescription(String sdp, String type);

  /// Applies a renegotiation offer from the peer (e.g. they enabled their
  /// camera mid-call) and returns the answer SDP.
  Future<String> applyRemoteOffer(String sdp);

  Future<void> addRemoteCandidate(IceCandidatePayload candidate);
  void sendChat(ChatMessage message);
  void sendMediaState({required bool cameraOn, required bool micOn});
  Future<void> setMicEnabled({required bool enabled});
  Future<void> setCameraEnabled({required bool enabled});

  /// Turns the local camera on mid-call: re-enables an existing video track, or
  /// acquires one and renegotiates (surfaced via the `onRenegotiate` offer).
  Future<void> enableCamera();

  Future<void> switchCamera();
  Future<void> setSpeakerphone({required bool enabled});

  /// The current local microphone level (0..1) read from the peer connection's
  /// audio stats. Returns 0 when there is no active connection. Used as the
  /// cross-platform mic meter where the native Android meter is unavailable.
  Future<double> readInputLevel();

  Future<void> closeSession();
  Future<void> dispose();
}
