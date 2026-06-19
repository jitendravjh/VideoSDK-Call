import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:synq/data/models/ice_candidate_payload.dart';
import 'package:synq/data/webrtc/data_channel_codec.dart';
import 'package:synq/data/webrtc/ice_servers.dart';
import 'package:synq/data/webrtc/mesh_engine.dart';

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

  // In-flight addPeer per peer, so two concurrent (unawaited) signal handlers
  // for the same peer coalesce onto one connection instead of leaking a second.
  final Map<String, Future<void>> _adding = {};

  // ICE that arrived before the peer link existed; drained into the link's
  // pending queue once addPeer creates it (otherwise it would be dropped).
  final Map<String, List<RTCIceCandidate>> _orphanCandidates = {};

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
  void Function(String peerId, String sdp)? _onRenegotiate;

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
    void Function(String peerId, String sdp)? onRenegotiate,
  }) {
    _onLocalCandidate = onLocalCandidate;
    _onConnected = onConnected;
    _onClosed = onClosed;
    _onChannelOpen = onChannelOpen;
    _onRemoteVideo = onRemoteVideo;
    _onRemoteMediaState = onRemoteMediaState;
    _onRenegotiate = onRenegotiate;
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
  Future<void> addPeer(String peerId) {
    if (_peers.containsKey(peerId)) return Future<void>.value();
    final existing = _adding[peerId];
    if (existing != null) return existing;
    final future = _addPeer(
      peerId,
    ).whenComplete(() => _adding.remove(peerId));
    _adding[peerId] = future;
    return future;
  }

  Future<void> _addPeer(String peerId) async {
    final pc = await createPeerConnection({
      'iceServers': IceServers.servers,
      'sdpSemantics': 'unified-plan',
    });
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    // Another path won the slot (or the peer left) while we awaited: discard
    // this connection rather than orphaning it outside _peers.
    if (_peers.containsKey(peerId)) {
      await pc.close();
      await renderer.dispose();
      return;
    }
    final link = _PeerLink(pc, renderer);
    _peers[peerId] = link;
    final orphans = _orphanCandidates.remove(peerId);
    if (orphans != null) {
      link.pendingCandidates.addAll(orphans);
    }

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

    // A negotiated channel (same id on both peers) avoids relying on the remote
    // `onDataChannel` event firing, which was unreliable in the mesh; both sides
    // simply open it and it works once the SCTP transport is up.
    final channel = await pc.createDataChannel(
      'chat',
      RTCDataChannelInit()
        ..negotiated = true
        ..id = 0,
    );
    _bindChannel(peerId, link, channel);
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
    final candidate = RTCIceCandidate(
      payload.candidate,
      payload.sdpMid,
      payload.sdpMLineIndex,
    );
    final link = _peers[peerId];
    if (link == null) {
      // The peer link is still being built; hold the candidate so it is not
      // lost, and addPeer will drain it into the pending queue.
      _orphanCandidates.putIfAbsent(peerId, () => []).add(candidate);
      return;
    }
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
    _orphanCandidates.remove(peerId);
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
  Future<void> enableCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    if (stream.getVideoTracks().isNotEmpty) {
      for (final track in stream.getVideoTracks()) {
        track.enabled = true;
      }
      return;
    }
    // Acquire one camera track, attach it to the shared stream, and renegotiate
    // with every peer so each learns about the new video m-line.
    final media = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'facingMode': 'user',
        'mandatory': {'minWidth': '640', 'minHeight': '480'},
      },
    });
    final track = media.getVideoTracks().first;
    await stream.addTrack(track);
    if (_localRendererInitialized) {
      localRenderer.srcObject = stream;
    }
    for (final entry in _peers.entries) {
      final link = entry.value;
      await link.pc.addTrack(track, stream);
      final offer = await link.pc.createOffer();
      await link.pc.setLocalDescription(offer);
      _onRenegotiate?.call(entry.key, offer.sdp ?? '');
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
    _broadcast(
      DataChannelCodec.encodeMediaState(cameraOn: cameraOn, micOn: micOn),
    );
  }

  void _broadcast(String payload) {
    for (final link in _peers.values) {
      final channel = link.channel;
      if (channel == null) continue;
      unawaited(channel.send(RTCDataChannelMessage(payload)));
    }
  }

  @override
  Future<void> closeAll() async {
    _mediaGeneration++;
    _orphanCandidates.clear();
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
    _onRenegotiate = null;
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
        // The mesh data channel now carries media-state only; chat goes through
        // the signalling server (see MeetingController).
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
