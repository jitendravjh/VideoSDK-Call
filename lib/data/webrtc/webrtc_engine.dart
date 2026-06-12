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
  });

  Future<void> openLocalMedia({required bool audio, required bool video});
  Future<void> setupConnection({required bool asCaller});
  Future<String> createOffer();
  Future<String> createAnswer();
  Future<void> setRemoteDescription(String sdp, String type);
  Future<void> addRemoteCandidate(IceCandidatePayload candidate);
  void sendChat(ChatMessage message);
  void sendMediaState({required bool cameraOn, required bool micOn});
  Future<void> setMicEnabled({required bool enabled});
  Future<void> setCameraEnabled({required bool enabled});
  Future<void> switchCamera();
  Future<void> setSpeakerphone({required bool enabled});
  Future<void> closeSession();
  Future<void> dispose();
}
