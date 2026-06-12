import 'package:meet_videosdk/data/models/ice_candidate_payload.dart';
import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/signaling/signal_events.dart';

/// Translates between [SignalMessage] values and the (event name, payload)
/// pairs that travel over Socket.IO.
///
/// Decoding never throws: malformed or unknown input returns `null` so the
/// transport layer can drop it without crashing.
class SignalCodec {
  const SignalCodec();

  ({String event, Map<String, dynamic> payload}) encode(SignalMessage message) {
    return switch (message) {
      RegisterMessage(:final userId, :final displayName) => (
          event: SignalEvents.register,
          payload: {'userId': userId, 'displayName': displayName},
        ),
      PresenceMessage(:final users) => (
          event: SignalEvents.presence,
          payload: {'users': users.map((u) => u.toJson()).toList()},
        ),
      UserJoinedMessage(:final user) => (
          event: SignalEvents.userJoined,
          payload: {'user': user.toJson()},
        ),
      UserLeftMessage(:final userId) => (
          event: SignalEvents.userLeft,
          payload: {'userId': userId},
        ),
      OfferMessage(:final from, :final to, :final sdp) => (
          event: SignalEvents.callOffer,
          payload: {'from': from, 'to': to, 'sdp': sdp},
        ),
      AnswerMessage(:final from, :final to, :final sdp) => (
          event: SignalEvents.callAnswer,
          payload: {'from': from, 'to': to, 'sdp': sdp},
        ),
      DeclineMessage(:final from, :final to) => (
          event: SignalEvents.callDecline,
          payload: {'from': from, 'to': to},
        ),
      IceCandidateMessage(:final from, :final to, :final candidate) => (
          event: SignalEvents.iceCandidate,
          payload: {'from': from, 'to': to, 'candidate': candidate.toJson()},
        ),
      CallEndMessage(:final from, :final to, :final reason) => (
          event: SignalEvents.callEnd,
          payload: {
            'from': from,
            'to': to,
            'reason': ?reason,
          },
        ),
    };
  }

  SignalMessage? decode(String event, Object? data) {
    if (data is! Map) {
      return null;
    }
    final json = Map<String, dynamic>.from(data);
    try {
      return switch (event) {
        SignalEvents.register => SignalMessage.register(
            userId: json['userId'] as String,
            displayName: json['displayName'] as String,
          ),
        SignalEvents.presence => SignalMessage.presence(
            users: (json['users'] as List)
                .map((e) => User.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList(),
          ),
        SignalEvents.userJoined => SignalMessage.userJoined(
            user: User.fromJson(
              Map<String, dynamic>.from(json['user'] as Map),
            ),
          ),
        SignalEvents.userLeft => SignalMessage.userLeft(
            userId: json['userId'] as String,
          ),
        SignalEvents.callOffer => SignalMessage.offer(
            from: json['from'] as String,
            to: json['to'] as String,
            sdp: json['sdp'] as String,
          ),
        SignalEvents.callAnswer => SignalMessage.answer(
            from: json['from'] as String,
            to: json['to'] as String,
            sdp: json['sdp'] as String,
          ),
        SignalEvents.callDecline => SignalMessage.decline(
            from: json['from'] as String,
            to: json['to'] as String,
          ),
        SignalEvents.iceCandidate => SignalMessage.iceCandidate(
            from: json['from'] as String,
            to: json['to'] as String,
            candidate: IceCandidatePayload.fromJson(
              Map<String, dynamic>.from(json['candidate'] as Map),
            ),
          ),
        SignalEvents.callEnd => SignalMessage.callEnd(
            from: json['from'] as String,
            to: json['to'] as String,
            reason: json['reason'] as String?,
          ),
        _ => null,
      };
    } on Object {
      return null;
    }
  }
}
