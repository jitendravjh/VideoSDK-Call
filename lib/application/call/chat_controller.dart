import 'package:meet_videosdk/data/models/chat_message.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_controller.g.dart';

/// Holds the in-call chat transcript. Messages arrive over the WebRTC data
/// channel (routed in by the call controller); the local echo is appended on
/// send. The list is reset at the start of each call.
///
/// Kept alive so the transcript survives the chat sheet being closed and so
/// messages received while it is closed are not lost.
@Riverpod(keepAlive: true)
class ChatController extends _$ChatController {
  @override
  List<ChatMessage> build() => const [];

  void add(ChatMessage message) => state = [...state, message];

  void clear() => state = const [];
}

/// Count of messages received from the peer while the chat sheet is closed,
/// shown as a badge on the chat button. Reset when the sheet is opened (and on
/// each new message while it is open) and at the start of each call.
@Riverpod(keepAlive: true)
class ChatUnread extends _$ChatUnread {
  @override
  int build() => 0;

  void increment() => state = state + 1;

  void reset() {
    if (state != 0) state = 0;
  }
}
