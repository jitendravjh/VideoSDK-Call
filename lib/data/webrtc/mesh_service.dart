import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:meet_videosdk/core/constants.dart';
import 'package:meet_videosdk/data/models/ice_candidate_payload.dart';
import 'package:meet_videosdk/data/webrtc/data_channel_codec.dart';
import 'package:meet_videosdk/data/webrtc/mesh_engine.dart';

/// One remote participant: its peer connection, remote renderer, data channel,
/// and the ICE queued before the remote description is in place.
class _PeerLink {
  _PeerLink(this.pc, this.renderer);

  final RTCPeerConnection pc;
  final RTCVideoRenderer renderer;
  RTCDataChannel? channel;
  bool remoteDescriptionSet = false;
  final List<RTCIceCandidate> pendingCandidates = [];
}

/// Mesh implementation: one shared local [MediaStream] added to every peer
/// connection. Mirrors the single-peer `WebRtcService` per peer, but the shared
/// capture is owned here and is never released by a single peer's teardown.
class MeshService implements MeshEngine {
  MeshService();

  @override
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  MediaStream? _localStream;
  bool _localRendererInitialized = false;
  final Map<String, _PeerLink> _peers = {};

  // Guards an in-flight getUserMedia against a teardown that beats it home.
  int _mediaGeneration = 0;

  void Function(String peerId, IceCandidatePayload candidate)?
  _onLocalCandidate;
  void Function(String peerId)? _onConnected;
  void Function(String peerId)? _onClosed;
  void Function(String peerId)? _onChannelOpen;
  void Function(String peerId, {required bool hasVideo})? _onRemoteVideo;
  void Function(String peerId, {required bool cameraOn, required bool micOn})?
  _onRemoteMediaState;

  @override
  bool get hasVideo => _localStream?.getVideoTracks().isNotEmpty ?? false;

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
  }) {
    _onLocalCandidate = onLocalCandidate;
    _onConnected = onConnected;
    _onClosed = onClosed;
    _onChannelOpen = onChannelOpen;
    _onRemoteVideo = onRemoteVideo;
    _onRemoteMediaState = onRemoteMediaState;
  }

  @override
  Future<void> openLocalMedia({
    required bool audio,
    required bool video,
  }) async {
    if (!_localRendererInitialized) {
      await localRenderer.initialize();
      _localRendererInitialized = true;
    }
    await _releaseLocalStream();
    final generation = ++_mediaGeneration;
    final constraints = <String, dynamic>{
      'audio': audio,
      'video': video
          ? {
              'facingMode': 'user',
              'mandatory': {'minWidth': '640', 'minHeight': '480'},
            }
          : false,
    };
    final stream = await navigator.mediaDevices.getUserMedia(constraints);
    if (generation != _mediaGeneration) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      return;
    }
    _localStream = stream;
    localRenderer.srcObject = stream;
  }

  @override
  bool hasPeer(String peerId) => _peers.containsKey(peerId);

  @override
  Future<void> addPeer(String peerId, {required bool asOfferer}) async {
    if (_peers.containsKey(peerId)) return;

    final pc = await createPeerConnection({
      'iceServers': AppConfig.iceServers,
      'sdpSemantics': 'unified-plan',
    });
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final link = _PeerLink(pc, renderer);
    _peers[peerId] = link;

    pc
      ..onIceCandidate = (candidate) {
        final value = candidate.candidate;
        if (value == null) return;
        _onLocalCandidate?.call(
          peerId,
          IceCandidatePayload(
            candidate: value,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex,
          ),
        );
      }
      ..onTrack = (event) {
        if (event.streams.isNotEmpty) {
          renderer.srcObject = event.streams.first;
        }
        if (event.track.kind == 'video') {
          _onRemoteVideo?.call(peerId, hasVideo: true);
        }
      }
      ..onConnectionState = (state) {
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _onConnected?.call(peerId);
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            _onClosed?.call(peerId);
          case _:
            break;
        }
      };

    final localStream = _localStream;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        await pc.addTrack(track, localStream);
      }
    }

    if (asOfferer) {
      final channel = await pc.createDataChannel('chat', RTCDataChannelInit());
      _bindChannel(peerId, link, channel);
    } else {
      pc.onDataChannel = (channel) => _bindChannel(peerId, link, channel);
    }
  }

  @override
  Future<String> createOffer(String peerId) async {
    final pc = _require(peerId).pc;
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    return offer.sdp ?? '';
  }

  @override
  Future<String> createAnswer(String peerId) async {
    final pc = _require(peerId).pc;
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return answer.sdp ?? '';
  }

  @override
  Future<void> setRemoteDescription(
    String peerId,
    String sdp,
    String type,
  ) async {
    final link = _require(peerId);
    await link.pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    link.remoteDescriptionSet = true;
    for (final candidate in link.pendingCandidates) {
      await link.pc.addCandidate(candidate);
    }
    link.pendingCandidates.clear();
  }

  @override
  Future<void> addRemoteCandidate(
    String peerId,
    IceCandidatePayload payload,
  ) async {
    final link = _peers[peerId];
    if (link == null) return;
    final candidate = RTCIceCandidate(
      payload.candidate,
      payload.sdpMid,
      payload.sdpMLineIndex,
    );
    if (!link.remoteDescriptionSet) {
      link.pendingCandidates.add(candidate);
      return;
    }
    await link.pc.addCandidate(candidate);
  }

  @override
  RTCVideoRenderer? rendererFor(String peerId) => _peers[peerId]?.renderer;

  @override
  Future<void> removePeer(String peerId) async {
    final link = _peers.remove(peerId);
    if (link == null) return;
    await link.channel?.close();
    link.pc
      ..onIceCandidate = null
      ..onTrack = null
      ..onConnectionState = null
      ..onDataChannel = null;
    link.renderer.srcObject = null;
    await link.pc.close();
    await link.renderer.dispose();
  }

  @override
  Future<void> setMicEnabled({required bool enabled}) async {
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  @override
  Future<void> setCameraEnabled({required bool enabled}) async {
    for (final track
        in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  @override
  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  @override
  Future<void> setSpeakerphone({required bool enabled}) async {
    await Helper.setSpeakerphoneOn(enabled);
  }

  @override
  void broadcastMediaState({required bool cameraOn, required bool micOn}) {
    final payload = DataChannelCodec.encodeMediaState(
      cameraOn: cameraOn,
      micOn: micOn,
    );
    for (final link in _peers.values) {
      final channel = link.channel;
      if (channel == null) continue;
      unawaited(channel.send(RTCDataChannelMessage(payload)));
    }
  }

  @override
  Future<void> closeAll() async {
    _mediaGeneration++;
    for (final peerId in _peers.keys.toList()) {
      await removePeer(peerId);
    }
    await _releaseLocalStream();
  }

  @override
  Future<void> dispose() async {
    await closeAll();
    _onLocalCandidate = null;
    _onConnected = null;
    _onClosed = null;
    _onChannelOpen = null;
    _onRemoteVideo = null;
    _onRemoteMediaState = null;
    if (_localRendererInitialized) {
      await localRenderer.dispose();
      _localRendererInitialized = false;
    }
  }

  void _bindChannel(String peerId, _PeerLink link, RTCDataChannel channel) {
    link.channel = channel;
    channel
      ..onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          _onChannelOpen?.call(peerId);
        }
      }
      ..onMessage = (message) {
        final decoded = DataChannelCodec.decode(message.text);
        switch (decoded) {
          case MediaStateData(:final cameraOn, :final micOn):
            _onRemoteMediaState?.call(peerId, cameraOn: cameraOn, micOn: micOn);
          case ChatData():
          case null:
            break;
        }
      };
  }

  Future<void> _releaseLocalStream() async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
    _localStream = null;
    if (_localRendererInitialized) {
      localRenderer.srcObject = null;
    }
  }

  _PeerLink _require(String peerId) {
    final link = _peers[peerId];
    if (link == null) {
      throw StateError('no peer connection for $peerId');
    }
    return link;
  }
}
