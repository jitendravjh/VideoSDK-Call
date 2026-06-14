import 'dart:async';

import 'package:meet_videosdk/core/constants.dart';
import 'package:meet_videosdk/core/logging.dart';
import 'package:nsd/nsd.dart';

/// Finds the signalling server on the local network via mDNS/DNS-SD, so the app
/// connects with no host to type and no build flag.
///
/// If a server was pinned at build time (`--dart-define=SIGNALING_HOST/URL`) it
/// is used directly and no discovery runs.
class ServerDiscovery {
  ServerDiscovery();

  final AppLogger _log = AppLogger('ServerDiscovery');

  Discovery? _discovery;
  Completer<String>? _completer;

  /// Resolves to the server URL, waiting until a server appears on the network.
  /// A given instance runs at most one discovery at a time.
  Future<String> resolve() async {
    if (AppConfig.hasExplicitServer) {
      return AppConfig.signalingUrl;
    }
    if (_completer != null) return _completer!.future;
    final completer = _completer = Completer<String>();

    try {
      final discovery = await startDiscovery(
        AppConfig.discoveryServiceType,
        ipLookupType: IpLookupType.v4,
      );
      _discovery = discovery;
      void check() {
        if (completer.isCompleted) return;
        final url = _urlFromServices(discovery.services);
        if (url != null) {
          _log.info('discovered server at $url');
          completer.complete(url);
        }
      }

      discovery.addListener(check);
      check();
    } on Object catch (error, stackTrace) {
      _log.error('discovery failed to start', error, stackTrace);
      _completer = null;
      if (!completer.isCompleted) completer.completeError(error);
    }

    return completer.future;
  }

  /// Stops any in-flight discovery. A pending [resolve] future is abandoned.
  Future<void> cancel() async {
    final discovery = _discovery;
    _discovery = null;
    _completer = null;
    if (discovery != null) {
      await stopDiscovery(discovery);
    }
  }

  static String? _urlFromServices(List<Service> services) {
    for (final service in services) {
      final port = service.port;
      final addresses = service.addresses;
      if (port != null && addresses != null && addresses.isNotEmpty) {
        return 'http://${addresses.first.address}:$port';
      }
    }
    return null;
  }
}
