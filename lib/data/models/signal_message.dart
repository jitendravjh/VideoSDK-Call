import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:meet_videosdk/data/models/ice_candidate_payload.dart';
import 'package:meet_videosdk/data/models/user.dart';

part 'signal_message.freezed.dart';

/// Typed representation of every signalling payload exchanged with the server.
///
/// The wire format carries no type discriminator; the Socket.IO event name
/// identifies the variant. Encoding and decoding live in `SignalCodec` so all
/// parsing stays in one testable place.
@freezed
sealed class SignalMessage with _$SignalMessage {
  const factory SignalMessage.register({
    required String displayName,
    String? userId,
  }) = RegisterMessage;

  const factory SignalMessage.registered({required User user}) =
      RegisteredMessage;

  const factory SignalMessage.presence({required List<User> users}) =
      PresenceMessage;

  const factory SignalMessage.userJoined({required User user}) =
      UserJoinedMessage;

  const factory SignalMessage.userLeft({required String userId}) =
      UserLeftMessage;

  const factory SignalMessage.offer({
    required String from,
    required String to,
    required String sdp,
    String? fromName,
  }) = OfferMessage;

  const factory SignalMessage.answer({
    required String from,
    required String to,
    required String sdp,
    String? fromName,
  }) = AnswerMessage;

  const factory SignalMessage.decline({
    required String from,
    required String to,
  }) = DeclineMessage;

  const factory SignalMessage.iceCandidate({
    required String from,
    required String to,
    required IceCandidatePayload candidate,
  }) = IceCandidateMessage;

  const factory SignalMessage.callEnd({
    required String from,
    required String to,
    String? reason,
  }) = CallEndMessage;
}
