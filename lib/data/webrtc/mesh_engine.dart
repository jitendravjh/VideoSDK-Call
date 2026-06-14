import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:meet_videosdk/data/models/chat_message.dart';
import 'package:meet_videosdk/data/models/ice_candidate_payload.dart';

/// A mesh of peer connections for a group meeting: one shared local capture
/// fanned out to N independent peer connections, each with its own remote
/// renderer and data channel.
///
/// This is deliberately separate from the single-peer `WebRtcEngine` used by the
/// 1:1 call path so neither disturbs the other. Peers are keyed by their user
/// code; every callback and per-peer method takes that key. Keeping it behind an
/// interface lets `MeetingController` run against a fake with no real media.
abstract class MeshEngine {
  /// The shared local preview (one capture for the whole meeting).
  RTCVideoRenderer get localRenderer;

  /// Whether the local capture currently has a video track.
  bool get hasVideo;

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
  });

  /// Opens the single shared local capture. Call once before adding peers.
  Future<void> openLocalMedia({required bool audio, required bool video});

  /// Creates a peer connection for [peerId] and attaches the shared local
  /// tracks. When [asOfferer] it also opens the chat/data channel; the caller is
  /// then expected to follow with [createOffer]. Safe to call once per peer.
  Future<void> addPeer(String peerId, {required bool asOfferer});

  bool hasPeer(String peerId);

  Future<String> createOffer(String peerId);
  Future<String> createAnswer(String peerId);
  Future<void> setRemoteDescription(String peerId, String sdp, String type);
  Future<void> addRemoteCandidate(String peerId, IceCandidatePayload candidate);

  /// The remote renderer for [peerId], or null if no such peer.
  RTCVideoRenderer? rendererFor(String peerId);

  /// Tears down one peer connection and its renderer, leaving the shared local
  /// capture and the other peers untouched.
  Future<void> removePeer(String peerId);

  Future<void> setMicEnabled({required bool enabled});
  Future<void> setCameraEnabled({required bool enabled});

  /// Turns the local camera on mid-meeting: re-enables the shared video track,
  /// or acquires one and renegotiates with every peer (each via `onRenegotiate`).
  Future<void> enableCamera();

  Future<void> switchCamera();
  Future<void> setSpeakerphone({required bool enabled});

  /// Sends the local media state to every peer whose channel is open.
  void broadcastMediaState({required bool cameraOn, required bool micOn});

  /// Sends a chat message to every peer whose channel is open.
  void sendChat(ChatMessage message);

  /// Tears down every peer connection and the shared local capture.
  Future<void> closeAll();

  Future<void> dispose();
}
