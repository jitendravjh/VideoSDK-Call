import 'package:meet_videosdk/core/constants.dart';

/// Web fallback: there is no mDNS in the browser, so the app uses the
/// compile-time server URL (defaults to localhost for web development).
class ServerDiscovery {
  ServerDiscovery();

  Future<String> resolve() async => AppConfig.signalingUrl;

  Future<void> cancel() async {}
}
