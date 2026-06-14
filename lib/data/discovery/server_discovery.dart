// Resolves the signalling server URL. On platforms with `dart:io` (Android,
// iOS, macOS, desktop) this is mDNS auto-discovery; on the web (no mDNS) it
// falls back to the compile-time URL.
export 'server_discovery_stub.dart'
    if (dart.library.io) 'server_discovery_io.dart';
