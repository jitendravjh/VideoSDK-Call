import 'package:flutter/foundation.dart';

/// Network and WebRTC configuration constants.
///
/// The signalling server host is the single place to change when pointing the
/// app at a different machine. Android emulators reach the host loopback via
/// `10.0.2.2`; every other target uses `localhost`.
class AppConfig {
  const AppConfig._();

  static const int signalingPort = 3000;

  static String get signalingHost {
    if (kIsWeb) {
      return 'localhost';
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => '10.0.2.2',
      _ => 'localhost',
    };
  }

  static String get signalingUrl => 'http://$signalingHost:$signalingPort';

  static const List<Map<String, dynamic>> iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];
}
