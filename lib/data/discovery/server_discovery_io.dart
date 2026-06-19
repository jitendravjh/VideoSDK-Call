import 'dart:async';
import 'dart:convert';

import 'package:nsd/nsd.dart';
import 'package:synq/core/constants.dart';
import 'package:synq/core/logging.dart';

/// Finds the signalling server on the local network via mDNS/DNS-SD, so the app
/// connects with no host to type and no build flag.
///
/// If a server was pinned at build time (`--dart-define=SIGNALING_HOST/URL`) it
/// is used directly and no discovery runs. Otherwise mDNS is tried first (so the
/// direct LAN server wins at home), then, if nothing is found in time, the app
/// falls back to the public server ([AppConfig.fallbackUrl]) so off-network and
/// cellular clients still connect.
class ServerDiscovery {
  ServerDiscovery();

  final AppLogger _log = AppLogger('ServerDiscovery');

  static const Duration _discoveryTimeout = Duration(seconds: 5);

  Discovery? _discovery;
  Completer<String>? _completer;
  Timer? _fallbackTimer;

  /// Resolves to the server URL: the LAN server if mDNS finds one quickly, else
  /// the public fallback. A given instance runs at most one discovery at a time.
  Future<String> resolve() async {
    if (AppConfig.hasExplicitServer) {
      return AppConfig.signalingUrl;
    }
    if (_completer != null) return _completer!.future;
    final completer = _completer = Completer<String>();

    void completeWith(String url) {
      if (completer.isCompleted) return;
      _fallbackTimer?.cancel();
      completer.complete(url);
    }

    try {
      final discovery = await startDiscovery(
        AppConfig.discoveryServiceType,
        ipLookupType: IpLookupType.v4,
      );
      _discovery = discovery;
      void check() {
        final url = _urlFromServices(discovery.services);
        if (url != null) {
          _log.info('discovered server at $url');
          completeWith(url);
        }
      }

      discovery.addListener(check);
      check();
    } on Object catch (error, stackTrace) {
      _log.error('discovery failed to start', error, stackTrace);
      // mDNS unavailable (blocked/no permission): use the public server when
      // one is configured, otherwise surface the error.
      if (AppConfig.fallbackUrl.isNotEmpty) {
        completeWith(AppConfig.fallbackUrl);
      } else {
        _completer = null;
        if (!completer.isCompleted) completer.completeError(error);
      }
      return completer.future;
    }

    if (AppConfig.fallbackUrl.isNotEmpty) {
      _fallbackTimer = Timer(_discoveryTimeout, () {
        if (completer.isCompleted) return;
        _log.info('no LAN server found; using ${AppConfig.fallbackUrl}');
        completeWith(AppConfig.fallbackUrl);
      });
    }

    return completer.future;
  }

  /// Stops any in-flight discovery. A pending [resolve] future is abandoned.
  Future<void> cancel() async {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
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
      if (port == null) continue;
      // Prefer the IP carried in the TXT record: the advertised hostname can be
      // unresolvable (router-assigned domain suffix with no mDNS A record).
      final txtIp = service.txt?['ip'];
      if (txtIp != null && txtIp.isNotEmpty) {
        return 'http://${utf8.decode(txtIp)}:$port';
      }
      final addresses = service.addresses;
      if (addresses != null && addresses.isNotEmpty) {
        return 'http://${addresses.first.address}:$port';
      }
    }
    return null;
  }
}
