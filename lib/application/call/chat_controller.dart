import 'package:meet_videosdk/data/models/chat_message.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_controller.g.dart';

/// Holds the in-call chat transcript. Messages arrive over the WebRTC data
/// channel (routed in by the call controller); the local echo is appended on
/// send. The list is reset at the start of each call.
@riverpod
class ChatController extends _$ChatController {
  @override
  List<ChatMessage> build() => const [];

  void add(ChatMessage message) => state = [...state, message];

  void clear() => state = const [];
}
