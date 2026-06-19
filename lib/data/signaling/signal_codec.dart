import 'package:synq/data/models/chat_message.dart';
import 'package:synq/data/models/ice_candidate_payload.dart';
import 'package:synq/data/models/signal_message.dart';
import 'package:synq/data/models/user.dart';
import 'package:synq/data/signaling/signal_events.dart';

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
        payload: {'displayName': displayName, 'userId': ?userId},
      ),
      RegisteredMessage(:final user, :final iceServers) => (
        event: SignalEvents.registered,
        payload: {'user': user.toJson(), 'iceServers': iceServers},
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
      OfferMessage(:final from, :final to, :final sdp, :final fromName) => (
        event: SignalEvents.callOffer,
        payload: {'from': from, 'to': to, 'sdp': sdp, 'fromName': ?fromName},
      ),
      AnswerMessage(:final from, :final to, :final sdp, :final fromName) => (
        event: SignalEvents.callAnswer,
        payload: {'from': from, 'to': to, 'sdp': sdp, 'fromName': ?fromName},
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
      MeetingHostMessage() => (
        event: SignalEvents.meetingHost,
        payload: <String, dynamic>{},
      ),
      MeetingJoinMessage(:final roomCode) => (
        event: SignalEvents.meetingJoin,
        payload: {'roomCode': roomCode},
      ),
      MeetingLeaveMessage(:final roomCode) => (
        event: SignalEvents.meetingLeave,
        payload: {'roomCode': roomCode},
      ),
      MeetingJoinedMessage(:final roomCode, :final peers) => (
        event: SignalEvents.meetingJoined,
        payload: {
          'roomCode': roomCode,
          'peers': peers.map((u) => u.toJson()).toList(),
        },
      ),
      MeetingPeerJoinedMessage(:final roomCode, :final user) => (
        event: SignalEvents.meetingPeerJoined,
        payload: {'roomCode': roomCode, 'user': user.toJson()},
      ),
      MeetingPeerLeftMessage(:final roomCode, :final userId) => (
        event: SignalEvents.meetingPeerLeft,
        payload: {'roomCode': roomCode, 'userId': userId},
      ),
      MeetingErrorMessage(:final reason) => (
        event: SignalEvents.meetingError,
        payload: {'reason': reason},
      ),
      MeetingOfferMessage(
        :final from,
        :final to,
        :final sdp,
        :final fromName,
      ) =>
        (
          event: SignalEvents.meetingOffer,
          payload: {
            'from': from,
            'to': to,
            'sdp': sdp,
            'fromName': ?fromName,
          },
        ),
      MeetingAnswerMessage(
        :final from,
        :final to,
        :final sdp,
        :final fromName,
      ) =>
        (
          event: SignalEvents.meetingAnswer,
          payload: {
            'from': from,
            'to': to,
            'sdp': sdp,
            'fromName': ?fromName,
          },
        ),
      MeetingIceMessage(:final from, :final to, :final candidate) => (
        event: SignalEvents.meetingIce,
        payload: {'from': from, 'to': to, 'candidate': candidate.toJson()},
      ),
      MeetingChatMessage(:final roomCode, :final message) => (
        event: SignalEvents.meetingChat,
        payload: {'roomCode': roomCode, 'message': message.toJson()},
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
          displayName: json['displayName'] as String,
          userId: json['userId'] as String?,
        ),
        SignalEvents.registered => SignalMessage.registered(
          user: User.fromJson(
            Map<String, dynamic>.from(json['user'] as Map),
          ),
          iceServers: _parseIceServers(json['iceServers']),
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
          fromName: json['fromName'] as String?,
        ),
        SignalEvents.callAnswer => SignalMessage.answer(
          from: json['from'] as String,
          to: json['to'] as String,
          sdp: json['sdp'] as String,
          fromName: json['fromName'] as String?,
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
        SignalEvents.meetingHost => const SignalMessage.meetingHost(),
        SignalEvents.meetingJoin => SignalMessage.meetingJoin(
          roomCode: json['roomCode'] as String,
        ),
        SignalEvents.meetingLeave => SignalMessage.meetingLeave(
          roomCode: json['roomCode'] as String,
        ),
        SignalEvents.meetingJoined => SignalMessage.meetingJoined(
          roomCode: json['roomCode'] as String,
          peers: (json['peers'] as List)
              .map((e) => User.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
        ),
        SignalEvents.meetingPeerJoined => SignalMessage.meetingPeerJoined(
          roomCode: json['roomCode'] as String,
          user: User.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
        ),
        SignalEvents.meetingPeerLeft => SignalMessage.meetingPeerLeft(
          roomCode: json['roomCode'] as String,
          userId: json['userId'] as String,
        ),
        SignalEvents.meetingError => SignalMessage.meetingError(
          reason: json['reason'] as String,
        ),
        SignalEvents.meetingOffer => SignalMessage.meetingOffer(
          from: json['from'] as String,
          to: json['to'] as String,
          sdp: json['sdp'] as String,
          fromName: json['fromName'] as String?,
        ),
        SignalEvents.meetingAnswer => SignalMessage.meetingAnswer(
          from: json['from'] as String,
          to: json['to'] as String,
          sdp: json['sdp'] as String,
          fromName: json['fromName'] as String?,
        ),
        SignalEvents.meetingIce => SignalMessage.meetingIce(
          from: json['from'] as String,
          to: json['to'] as String,
          candidate: IceCandidatePayload.fromJson(
            Map<String, dynamic>.from(json['candidate'] as Map),
          ),
        ),
        SignalEvents.meetingChat => SignalMessage.meetingChat(
          roomCode: json['roomCode'] as String,
          message: ChatMessage.fromJson(
            Map<String, dynamic>.from(json['message'] as Map),
          ),
        ),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  // ICE server entries arrive as JSON maps whose `urls` is a string or a list
  // of strings; normalise the list form to `List<String>` so flutter_webrtc
  // accepts it as-is.
  static List<Map<String, dynamic>> _parseIceServers(Object? raw) {
    if (raw is! List) return const [];
    final result = <Map<String, dynamic>>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final urls = map['urls'];
      if (urls is List) {
        map['urls'] = urls.map((u) => u.toString()).toList();
      }
      result.add(map);
    }
    return result;
  }
}
