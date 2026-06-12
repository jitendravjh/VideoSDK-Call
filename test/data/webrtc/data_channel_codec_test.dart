import 'package:flutter_test/flutter_test.dart';
import 'package:meet_videosdk/data/models/chat_message.dart';
import 'package:meet_videosdk/data/webrtc/data_channel_codec.dart';

void main() {
  test('chat message round-trips', () {
    final message = ChatMessage(
      id: 'm1',
      senderId: 'A1',
      text: 'hello',
      sentAt: DateTime.utc(2026, 6, 12, 10, 30),
    );

    final decoded = DataChannelCodec.decode(
      DataChannelCodec.encodeChat(message),
    );

    expect(decoded, isA<ChatData>());
    expect((decoded! as ChatData).message, message);
  });

  test('media state round-trips', () {
    final decoded = DataChannelCodec.decode(
      DataChannelCodec.encodeMediaState(cameraOn: false, micOn: true),
    );

    expect(decoded, isA<MediaStateData>());
    final media = decoded! as MediaStateData;
    expect(media.cameraOn, isFalse);
    expect(media.micOn, isTrue);
  });

  test('malformed and unknown payloads decode to null', () {
    expect(DataChannelCodec.decode('not json'), isNull);
    expect(DataChannelCodec.decode('{"type":"other"}'), isNull);
    expect(DataChannelCodec.decode('123'), isNull);
  });
}
