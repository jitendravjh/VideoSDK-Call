import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mic_level_service.g.dart';

/// Bridges the native microphone level meter (an Android [EventChannel]) into
/// Dart as a stream of normalised 0..1 levels. On platforms without the native
/// implementation it yields nothing.
class MicLevelService {
  const MicLevelService();

  static const EventChannel _channel = EventChannel('videosdk/mic_level');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Stream<double> levels() {
    if (!isSupported) return const Stream<double>.empty();
    return _channel.receiveBroadcastStream().map(
      (event) => (event as num).toDouble().clamp(0.0, 1.0),
    );
  }
}

@riverpod
Stream<double> micLevel(Ref ref) => const MicLevelService().levels();
