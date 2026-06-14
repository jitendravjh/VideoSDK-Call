import 'package:flutter_test/flutter_test.dart';
import 'package:meet_videosdk/data/models/ice_candidate_payload.dart';
import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/signaling/signal_codec.dart';

void main() {
  const codec = SignalCodec();

  SignalMessage? roundTrip(SignalMessage message) {
    final encoded = codec.encode(message);
    return codec.decode(encoded.event, encoded.payload);
  }

  group('round-trips every variant', () {
    const messages = <SignalMessage>[
      SignalMessage.register(displayName: 'Alice'),
      SignalMessage.register(displayName: 'Alice', userId: 'ABC123'),
      SignalMessage.registered(
        user: User(userId: 'ABC123', displayName: 'Alice'),
      ),
      SignalMessage.presence(
        users: [
          User(userId: 'A1', displayName: 'Alice'),
          User(userId: 'B2', displayName: 'Bob'),
        ],
      ),
      SignalMessage.userJoined(
        user: User(userId: 'B2', displayName: 'Bob'),
      ),
      SignalMessage.userLeft(userId: 'B2'),
      SignalMessage.offer(from: 'A1', to: 'B2', sdp: 'sdp-offer'),
      SignalMessage.offer(
        from: 'A1',
        to: 'B2',
        sdp: 'sdp-offer',
        fromName: 'Alice',
      ),
      SignalMessage.answer(from: 'B2', to: 'A1', sdp: 'sdp-answer'),
      SignalMessage.answer(
        from: 'B2',
        to: 'A1',
        sdp: 'sdp-answer',
        fromName: 'Bob',
      ),
      SignalMessage.decline(from: 'B2', to: 'A1'),
      SignalMessage.iceCandidate(
        from: 'A1',
        to: 'B2',
        candidate: IceCandidatePayload(
          candidate: 'candidate:1',
          sdpMid: '0',
          sdpMLineIndex: 0,
        ),
      ),
      SignalMessage.callEnd(from: 'A1', to: 'B2'),
      SignalMessage.callEnd(from: 'A1', to: 'B2', reason: 'peer-left'),
      SignalMessage.meetingHost(),
      SignalMessage.meetingJoin(roomCode: 'HOST01'),
      SignalMessage.meetingLeave(roomCode: 'HOST01'),
      SignalMessage.meetingJoined(
        roomCode: 'HOST01',
        peers: [
          User(userId: 'A1', displayName: 'Alice'),
          User(userId: 'C3', displayName: 'Carol'),
        ],
      ),
      SignalMessage.meetingPeerJoined(
        roomCode: 'HOST01',
        user: User(userId: 'D4', displayName: 'Dave'),
      ),
      SignalMessage.meetingPeerLeft(roomCode: 'HOST01', userId: 'D4'),
      SignalMessage.meetingError(reason: 'no-such-meeting'),
      SignalMessage.meetingOffer(from: 'A1', to: 'C3', sdp: 'sdp-mo'),
      SignalMessage.meetingOffer(
        from: 'A1',
        to: 'C3',
        sdp: 'sdp-mo',
        fromName: 'Alice',
      ),
      SignalMessage.meetingAnswer(
        from: 'C3',
        to: 'A1',
        sdp: 'sdp-ma',
        fromName: 'Carol',
      ),
      SignalMessage.meetingIce(
        from: 'A1',
        to: 'C3',
        candidate: IceCandidatePayload(candidate: 'candidate:2'),
      ),
    ];

    messages.asMap().forEach((index, message) {
      test('$index ${message.runtimeType}', () {
        expect(roundTrip(message), message);
      });
    });
  });

  group('decode is forgiving', () {
    test('unknown event returns null', () {
      expect(codec.decode('not-an-event', <String, dynamic>{}), isNull);
    });

    test('non-map payload returns null', () {
      expect(codec.decode('call-offer', 'garbage'), isNull);
    });

    test('missing required field returns null', () {
      expect(
        codec.decode('call-offer', <String, dynamic>{'from': 'A1'}),
        isNull,
      );
    });

    test('null payload returns null', () {
      expect(codec.decode('presence', null), isNull);
    });
  });
}
