import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:synq/data/webrtc/webrtc_providers.dart';

part 'mic_level_service.g.dart';

/// Bridges the native microphone level meter (an Android [EventChannel]) into
/// Dart as a stream of normalised 0..1 levels.
class MicLevelService {
  const MicLevelService();

  static const EventChannel _channel = EventChannel('synq/mic_level');

  /// Android has a dedicated native amplitude meter (the platform-channel
  /// bonus). Other platforms derive the level from WebRTC audio stats instead.
  bool get isNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Stream<double> levels() => _channel.receiveBroadcastStream().map(
    (event) => (event as num).toDouble().clamp(0.0, 1.0),
  );
}

/// A live 0..1 microphone level. On Android this is the native amplitude meter;
/// everywhere else (iOS, macOS, web) it polls the peer connection's local audio
/// level so the meter works without a per-platform native bridge.
@riverpod
Stream<double> micLevel(Ref ref) {
  const native = MicLevelService();
  if (native.isNative) return native.levels();

  final engine = ref.watch(webRtcEngineProvider);
  return Stream<void>.periodic(
    const Duration(milliseconds: 150),
  ).asyncMap((_) => engine.readInputLevel());
}
