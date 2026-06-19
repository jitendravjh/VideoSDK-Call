import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:synq/data/models/chat_message.dart';
import 'package:synq/data/models/ice_candidate_payload.dart';
import 'package:synq/data/models/user.dart';

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

  const factory SignalMessage.registered({
    required User user,
    @Default(<Map<String, dynamic>>[]) List<Map<String, dynamic>> iceServers,
  }) = RegisteredMessage;

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

  // Group meeting (mesh). The room code is the host's user code; per-pair
  // offer/answer/ice mirror the 1:1 ones on their own meeting-specific events.
  const factory SignalMessage.meetingHost() = MeetingHostMessage;

  const factory SignalMessage.meetingJoin({required String roomCode}) =
      MeetingJoinMessage;

  const factory SignalMessage.meetingLeave({required String roomCode}) =
      MeetingLeaveMessage;

  const factory SignalMessage.meetingJoined({
    required String roomCode,
    required List<User> peers,
  }) = MeetingJoinedMessage;

  const factory SignalMessage.meetingPeerJoined({
    required String roomCode,
    required User user,
  }) = MeetingPeerJoinedMessage;

  const factory SignalMessage.meetingPeerLeft({
    required String roomCode,
    required String userId,
  }) = MeetingPeerLeftMessage;

  const factory SignalMessage.meetingError({required String reason}) =
      MeetingErrorMessage;

  const factory SignalMessage.meetingOffer({
    required String from,
    required String to,
    required String sdp,
    String? fromName,
  }) = MeetingOfferMessage;

  const factory SignalMessage.meetingAnswer({
    required String from,
    required String to,
    required String sdp,
    String? fromName,
  }) = MeetingAnswerMessage;

  const factory SignalMessage.meetingIce({
    required String from,
    required String to,
    required IceCandidatePayload candidate,
  }) = MeetingIceMessage;

  const factory SignalMessage.meetingChat({
    required String roomCode,
    required ChatMessage message,
  }) = MeetingChatMessage;
}
