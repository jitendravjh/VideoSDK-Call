import 'dart:convert';

import 'package:synq/data/models/chat_message.dart';

/// Messages carried over the WebRTC data channel.
sealed class DataChannelMessage {
  const DataChannelMessage();
}

class ChatData extends DataChannelMessage {
  const ChatData(this.message);
  final ChatMessage message;
}

class MediaStateData extends DataChannelMessage {
  const MediaStateData({required this.cameraOn, required this.micOn});
  final bool cameraOn;
  final bool micOn;
}

/// Encodes/decodes data-channel payloads as tagged JSON so chat and media-state
/// share one channel. Decoding never throws: malformed input returns `null`.
class DataChannelCodec {
  const DataChannelCodec._();

  static String encodeChat(ChatMessage message) =>
      jsonEncode({'type': 'chat', 'message': message.toJson()});

  static String encodeMediaState({
    required bool cameraOn,
    required bool micOn,
  }) => jsonEncode({'type': 'media', 'cameraOn': cameraOn, 'micOn': micOn});

  static DataChannelMessage? decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      switch (json['type']) {
        case 'chat':
          return ChatData(
            ChatMessage.fromJson(
              Map<String, dynamic>.from(json['message'] as Map),
            ),
          );
        case 'media':
          return MediaStateData(
            cameraOn: json['cameraOn'] as bool? ?? true,
            micOn: json['micOn'] as bool? ?? true,
          );
        case _:
          return null;
      }
    } on Object {
      return null;
    }
  }
}
