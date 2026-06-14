/// Socket.IO event names shared by client and server.
class SignalEvents {
  const SignalEvents._();

  static const String register = 'register';
  static const String registered = 'registered';
  static const String presence = 'presence';
  static const String userJoined = 'user-joined';
  static const String userLeft = 'user-left';
  static const String callOffer = 'call-offer';
  static const String callAnswer = 'call-answer';
  static const String callDecline = 'call-decline';
  static const String iceCandidate = 'ice-candidate';
  static const String callEnd = 'call-end';

  // Group meeting (mesh) lifecycle and per-pair signalling. The per-pair
  // offer/answer/ice are separate events from the 1:1 ones so meeting traffic
  // never collides with the 1:1 call controller or its busy-guard.
  static const String meetingHost = 'meeting-host';
  static const String meetingJoin = 'meeting-join';
  static const String meetingLeave = 'meeting-leave';
  static const String meetingJoined = 'meeting-joined';
  static const String meetingPeerJoined = 'meeting-peer-joined';
  static const String meetingPeerLeft = 'meeting-peer-left';
  static const String meetingError = 'meeting-error';
  static const String meetingOffer = 'meeting-offer';
  static const String meetingAnswer = 'meeting-answer';
  static const String meetingIce = 'meeting-ice';
}
