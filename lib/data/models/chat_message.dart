import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

/// A single chat message exchanged over the WebRTC data channel.
///
/// `senderId` identifies the author; the UI derives whether a message is
/// outgoing by comparing it to the local user id, so no `isMine` flag travels
/// over the wire. `senderName` lets group chat show who sent each message.
@freezed
abstract class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String senderId,
    required String text,
    required DateTime sentAt,
    String? senderName,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}
