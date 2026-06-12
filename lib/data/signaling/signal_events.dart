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
}
