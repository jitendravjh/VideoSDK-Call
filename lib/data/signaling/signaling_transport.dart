import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';

enum SignalingConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Transport-level contract for signalling. `CallController` and the lobby
/// depend on this so the socket can be replaced with a fake in tests.
abstract class SignalingTransport {
  Stream<SignalMessage> get messages;
  Stream<SignalingConnectionState> get connectionState;
  SignalingConnectionState get currentState;

  void connect(User self);
  void send(SignalMessage message);
  void disconnect();
}
