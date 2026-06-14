import 'package:meet_videosdk/core/constants.dart';

/// Web has no mDNS, so a deployed web build connects to the public server
/// ([AppConfig.fallbackUrl]); local web dev can still point at localhost with
/// `--dart-define=SIGNALING_URL=...`.
class ServerDiscovery {
  ServerDiscovery();

  Future<String> resolve() async {
    if (AppConfig.hasExplicitServer) return AppConfig.signalingUrl;
    if (AppConfig.fallbackUrl.isNotEmpty) return AppConfig.fallbackUrl;
    return AppConfig.signalingUrl;
  }

  Future<void> cancel() async {}
}
