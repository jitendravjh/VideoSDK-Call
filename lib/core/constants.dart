import 'package:flutter/foundation.dart';

/// Network and WebRTC configuration constants.
///
/// The signalling server host can be overridden at build/run time, which is how
/// a physical device points at the host machine on the LAN:
///
/// ```sh
/// flutter run --dart-define=SIGNALING_HOST=192.168.1.50
/// ```
///
/// With no override, the Android emulator reaches the host loopback via
/// `10.0.2.2` and every other target uses `localhost`. A physical phone cannot
/// use `10.0.2.2` (that alias only exists inside the emulator), so it needs the
/// override set to the host machine's LAN IP.
class AppConfig {
  const AppConfig._();

  static const String _hostOverride = String.fromEnvironment('SIGNALING_HOST');
  static const String _urlOverride = String.fromEnvironment('SIGNALING_URL');

  static const int signalingPort = int.fromEnvironment(
    'SIGNALING_PORT',
    defaultValue: 3000,
  );

  /// Whether a server location was pinned at build time. When false, the app
  /// auto-discovers the server on the LAN via mDNS instead.
  static bool get hasExplicitServer =>
      _hostOverride.isNotEmpty || _urlOverride.isNotEmpty;

  /// The mDNS/DNS-SD service type the server advertises and the app browses for.
  static const String discoveryServiceType = '_videosdk._tcp';

  /// Public signalling server, reachable over the internet, used when no LAN
  /// server is found via mDNS, so calls work across networks (incl. cellular).
  /// mDNS is tried first, so the direct LAN server still wins on the home Wi-Fi.
  static const String fallbackUrl = String.fromEnvironment(
    'SIGNALING_FALLBACK_URL',
    defaultValue: 'https://signal.jitendravjh.in',
  );

  static String get signalingHost {
    if (_hostOverride.isNotEmpty) {
      return _hostOverride;
    }
    if (kIsWeb) {
      return 'localhost';
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => '10.0.2.2',
      _ => 'localhost',
    };
  }

  static String get signalingUrl {
    if (_urlOverride.isNotEmpty) {
      return _urlOverride;
    }
    return 'http://$signalingHost:$signalingPort';
  }

  static const List<Map<String, dynamic>> iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];
}
