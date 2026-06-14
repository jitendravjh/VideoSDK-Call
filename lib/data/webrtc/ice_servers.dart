import 'package:meet_videosdk/core/constants.dart';

/// Runtime ICE server configuration.
///
/// Defaults to the compile-time STUN list and is replaced by the list the
/// server sends on registration, which may include short-lived TURN relay
/// credentials for cross-network/cellular calls. Held process-wide so both the
/// 1:1 and mesh peer connections use the same servers without threading them
/// through every connection setup.
class IceServers {
  IceServers._();

  static List<Map<String, dynamic>> _servers = AppConfig.iceServers;

  static List<Map<String, dynamic>> get servers => _servers;

  static void update(List<Map<String, dynamic>> servers) {
    if (servers.isEmpty) return;
    _servers = servers;
  }
}
