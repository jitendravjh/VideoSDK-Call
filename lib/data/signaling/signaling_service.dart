import 'dart:async';

import 'package:meet_videosdk/core/constants.dart';
import 'package:meet_videosdk/core/logging.dart';
import 'package:meet_videosdk/data/discovery/server_discovery.dart';
import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/signaling/signal_codec.dart';
import 'package:meet_videosdk/data/signaling/signal_events.dart';
import 'package:meet_videosdk/data/signaling/signaling_transport.dart';
import 'package:meet_videosdk/data/webrtc/ice_servers.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Wraps the Socket.IO transport. Owns the socket, decodes inbound events into
/// [SignalMessage]s, and re-registers the local user on every (re)connection.
///
/// This is the only place the rest of the app touches the socket. It exposes
/// broadcast streams; it never shows UI or navigates.
class SignalingService implements SignalingTransport {
  SignalingService();

  final SignalCodec _codec = const SignalCodec();
  final AppLogger _log = AppLogger('SignalingService');
  final ServerDiscovery _discovery = ServerDiscovery();

  io.Socket? _socket;
  User? _self;
  bool _connecting = false;
  Timer? _fallbackTimer;

  final StreamController<SignalMessage> _messages =
      StreamController<SignalMessage>.broadcast();
  final StreamController<SignalingConnectionState> _connection =
      StreamController<SignalingConnectionState>.broadcast();

  SignalingConnectionState _state = SignalingConnectionState.disconnected;

  @override
  Stream<SignalMessage> get messages => _messages.stream;
  @override
  Stream<SignalingConnectionState> get connectionState => _connection.stream;
  @override
  SignalingConnectionState get currentState => _state;

  @override
  void connect(User self) {
    _self = self;
    if (_socket != null) {
      _registerSelf();
      return;
    }
    if (_connecting) return;
    _connecting = true;
    _setState(SignalingConnectionState.connecting);
    // Resolve the server first (mDNS discovery on the LAN, or the compile-time
    // override), then open the socket. The state stays "connecting" until a
    // server is found, so the UI shows the same banner throughout.
    unawaited(_resolveAndConnect());
  }

  Future<void> _resolveAndConnect() async {
    final String url;
    try {
      url = await _discovery.resolve();
    } on Object catch (error) {
      _log.warn('server discovery failed: $error');
      _connecting = false;
      _setState(SignalingConnectionState.disconnected);
      return;
    }
    // A disconnect/sign-out happened while discovering: abort.
    if (_self == null) {
      _connecting = false;
      return;
    }
    _connecting = false;
    _openSocket(url);
  }

  void _openSocket(String url) {
    _log.info('connecting to $url');

    final socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );
    _socket = socket;

    socket
      ..onConnect((_) {
        _log.info('connected');
        _fallbackTimer?.cancel();
        _setState(SignalingConnectionState.connected);
        _registerSelf();
      })
      ..onReconnectAttempt((_) {
        _setState(SignalingConnectionState.reconnecting);
      })
      ..onConnectError((error) {
        _log.warn('connect error: $error');
      })
      ..onError((error) {
        _log.warn('socket error: $error');
      })
      ..onDisconnect((_) {
        _log.warn('disconnected');
        _setState(SignalingConnectionState.disconnected);
      });

    for (final event in _inboundEvents) {
      socket.on(event, (data) => _onInbound(event, data));
    }

    socket.connect();

    // A discovered LAN server can advertise an address this device cannot reach
    // (for example when the host is on phone tethering). If the connection does
    // not come up soon, switch to the public server so the client is not stuck.
    const fallback = AppConfig.fallbackUrl;
    if (fallback.isNotEmpty && url != fallback) {
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer(const Duration(seconds: 3), () {
        if (_state == SignalingConnectionState.connected) return;
        if (_socket != socket || _self == null) return;
        _log.warn('$url did not connect, switching to $fallback');
        socket
          ..clearListeners()
          ..dispose();
        _socket = null;
        _openSocket(fallback);
      });
    }
  }

  @override
  void send(SignalMessage message) {
    final socket = _socket;
    if (socket == null) {
      _log.warn('send dropped, socket not connected');
      return;
    }
    final encoded = _codec.encode(message);
    socket.emit(encoded.event, encoded.payload);
  }

  @override
  void disconnect() {
    _self = null;
    _connecting = false;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    unawaited(_discovery.cancel());
    _socket
      ?..clearListeners()
      ..dispose();
    _socket = null;
    _setState(SignalingConnectionState.disconnected);
  }

  Future<void> dispose() async {
    disconnect();
    await _messages.close();
    await _connection.close();
  }

  void _registerSelf() {
    final self = _self;
    if (self == null) return;
    send(
      SignalMessage.register(
        displayName: self.displayName,
        userId: self.userId.isEmpty ? null : self.userId,
      ),
    );
  }

  void _onInbound(String event, Object? data) {
    final message = _codec.decode(event, data);
    if (message == null) {
      _log.warn('dropped malformed $event payload');
      return;
    }
    // Adopt the server-assigned code so a reconnect re-registers the same id,
    // and the ICE servers (which may carry fresh TURN relay credentials).
    if (message is RegisteredMessage) {
      _self = message.user;
      IceServers.update(message.iceServers);
    }
    _messages.add(message);
  }

  void _setState(SignalingConnectionState state) {
    if (_state == state) return;
    _state = state;
    if (!_connection.isClosed) {
      _connection.add(state);
    }
  }

  static const List<String> _inboundEvents = [
    SignalEvents.registered,
    SignalEvents.presence,
    SignalEvents.userJoined,
    SignalEvents.userLeft,
    SignalEvents.callOffer,
    SignalEvents.callAnswer,
    SignalEvents.callDecline,
    SignalEvents.iceCandidate,
    SignalEvents.callEnd,
    SignalEvents.meetingJoined,
    SignalEvents.meetingPeerJoined,
    SignalEvents.meetingPeerLeft,
    SignalEvents.meetingError,
    SignalEvents.meetingOffer,
    SignalEvents.meetingAnswer,
    SignalEvents.meetingIce,
    SignalEvents.meetingChat,
  ];
}
