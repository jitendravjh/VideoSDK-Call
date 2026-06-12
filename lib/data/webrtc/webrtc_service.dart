import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:meet_videosdk/core/constants.dart';
import 'package:meet_videosdk/core/logging.dart';
import 'package:meet_videosdk/data/models/chat_message.dart';
import 'package:meet_videosdk/data/models/ice_candidate_payload.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_engine.dart';

/// Owns a single [RTCPeerConnection] and the media attached to it.
///
/// The service is transport agnostic: it surfaces local ICE candidates,
/// connection lifecycle, and chat through callbacks, and `CallController`
/// wires those to the signalling layer. It never touches the socket or UI.
///
/// Remote ICE candidates that arrive before the remote description is set are
/// queued and flushed once the description is in place.
class WebRtcService implements WebRtcEngine {
  WebRtcService();

  final AppLogger _log = AppLogger('WebRtcService');

  @override
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  @override
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCDataChannel? _dataChannel;
  bool _renderersInitialized = false;

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;

  void Function(IceCandidatePayload candidate)? _onLocalCandidate;
  void Function()? _onConnected;
  void Function()? _onFailed;
  void Function()? _onDataChannelOpen;
  void Function(ChatMessage message)? _onChatMessage;

  @override
  void bind({
    void Function(IceCandidatePayload candidate)? onLocalCandidate,
    void Function()? onConnected,
    void Function()? onFailed,
    void Function()? onDataChannelOpen,
    void Function(ChatMessage message)? onChatMessage,
  }) {
    _onLocalCandidate = onLocalCandidate;
    _onConnected = onConnected;
    _onFailed = onFailed;
    _onDataChannelOpen = onDataChannelOpen;
    _onChatMessage = onChatMessage;
  }

  @override
  bool get hasVideo => _localStream?.getVideoTracks().isNotEmpty ?? false;

  @override
  bool get hasLocalMedia => _localStream != null;

  Future<void> _ensureRenderers() async {
    if (_renderersInitialized) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersInitialized = true;
  }

  @override
  Future<void> openLocalMedia({
    required bool audio,
    required bool video,
  }) async {
    await _ensureRenderers();
    await _releaseLocalStream();
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
    _localStream = stream;
    localRenderer.srcObject = stream;
  }

  @override
  Future<void> setupConnection({required bool asCaller}) async {
    final pc = await createPeerConnection({
      'iceServers': AppConfig.iceServers,
      'sdpSemantics': 'unified-plan',
    });

    pc
      ..onIceCandidate = (candidate) {
        final value = candidate.candidate;
        if (value == null) return;
        _onLocalCandidate?.call(
          IceCandidatePayload(
            candidate: value,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex,
          ),
        );
      }
      ..onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        }
      }
      ..onConnectionState = (state) {
        _log.info('connection state $state');
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _onConnected?.call();
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _onFailed?.call();
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

    if (asCaller) {
      final channel = await pc.createDataChannel('chat', RTCDataChannelInit());
      _bindDataChannel(channel);
    } else {
      pc.onDataChannel = _bindDataChannel;
    }

    _pc = pc;
  }

  @override
  Future<String> createOffer() async {
    final pc = _requirePc();
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    return offer.sdp ?? '';
  }

  @override
  Future<String> createAnswer() async {
    final pc = _requirePc();
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return answer.sdp ?? '';
  }

  @override
  Future<void> setRemoteDescription(String sdp, String type) async {
    final pc = _requirePc();
    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionSet = true;
    for (final candidate in _pendingRemoteCandidates) {
      await pc.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  @override
  Future<void> addRemoteCandidate(IceCandidatePayload payload) async {
    final candidate = RTCIceCandidate(
      payload.candidate,
      payload.sdpMid,
      payload.sdpMLineIndex,
    );
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    await _requirePc().addCandidate(candidate);
  }

  @override
  void sendChat(ChatMessage message) {
    final channel = _dataChannel;
    if (channel == null) {
      _log.warn('chat dropped, data channel not open');
      return;
    }
    unawaited(
      channel.send(RTCDataChannelMessage(jsonEncode(message.toJson()))),
    );
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

  /// Tears down the peer connection and media for one call while keeping the
  /// renderers and callbacks so the service can be reused for the next call.
  @override
  Future<void> closeSession() async {
    _pendingRemoteCandidates.clear();
    _remoteDescriptionSet = false;

    await _dataChannel?.close();
    _dataChannel = null;

    final pc = _pc;
    if (pc != null) {
      pc
        ..onIceCandidate = null
        ..onTrack = null
        ..onConnectionState = null
        ..onDataChannel = null;
    }

    await _releaseLocalStream();
    remoteRenderer.srcObject = null;

    await pc?.close();
    _pc = null;
  }

  Future<void> _releaseLocalStream() async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
    _localStream = null;
    localRenderer.srcObject = null;
  }

  @override
  Future<void> dispose() async {
    await closeSession();

    _onLocalCandidate = null;
    _onConnected = null;
    _onFailed = null;
    _onDataChannelOpen = null;
    _onChatMessage = null;

    if (_renderersInitialized) {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
      _renderersInitialized = false;
    }
  }

  void _bindDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    channel
      ..onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          _onDataChannelOpen?.call();
        }
      }
      ..onMessage = (message) {
        try {
          final json = jsonDecode(message.text) as Map<String, dynamic>;
          _onChatMessage?.call(ChatMessage.fromJson(json));
        } on Object catch (error) {
          _log.warn('dropped malformed chat payload: $error');
        }
      };
  }

  RTCPeerConnection _requirePc() {
    final pc = _pc;
    if (pc == null) {
      throw StateError('peer connection not created');
    }
    return pc;
  }
}
