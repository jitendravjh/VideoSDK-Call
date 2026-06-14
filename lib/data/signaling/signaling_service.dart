import 'dart:async';

import 'package:meet_videosdk/core/constants.dart';
import 'package:meet_videosdk/core/logging.dart';
import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/signaling/signal_codec.dart';
import 'package:meet_videosdk/data/signaling/signal_events.dart';
import 'package:meet_videosdk/data/signaling/signaling_transport.dart';
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

  io.Socket? _socket;
  User? _self;

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

    _setState(SignalingConnectionState.connecting);

    final socket = io.io(
      AppConfig.signalingUrl,
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
    // Adopt the server-assigned code so a reconnect re-registers the same id.
    if (message is RegisteredMessage) {
      _self = message.user;
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
