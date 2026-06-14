import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:meet_videosdk/core/logging.dart';

/// Plays the incoming-call ringtone.
///
/// On Android it rings with the phone's own default ringtone. iOS exposes no
/// API to read the user's ringtone, so it falls back to a built-in system
/// sound. The plugin only loops (and only honours `stop`) on Android, so on iOS
/// the sound is re-fired on a timer to keep it ringing. The plugin only ships
/// android/ios implementations, so every call is a no-op elsewhere (web,
/// desktop) where the method channel would otherwise reject asynchronously.
class RingtoneService {
  RingtoneService();

  final AppLogger _log = AppLogger('RingtoneService');
  final FlutterRingtonePlayer _player = FlutterRingtonePlayer();

  Timer? _repeater;

  // The plugin discards the method channel's returned Future, so a missing
  // implementation surfaces as an *unhandled* async error rather than something
  // our try/catch can absorb. Gate playback on the platforms it actually ships.
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // iOS plays system sounds one-shot and ignores the looping flag, so we
  // re-fire the sound ourselves to keep it ringing until told to stop.
  bool get _manualLoop => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> playIncoming() async {
    _repeater?.cancel();
    if (!_supported) return;
    _playOnce();
    if (_manualLoop) {
      _repeater = Timer.periodic(
        const Duration(milliseconds: 2200),
        (_) => _playOnce(),
      );
    }
  }

  Future<void> stop() async {
    _repeater?.cancel();
    _repeater = null;
    if (!_supported) return;
    try {
      await _player.stop();
    } on Object catch (error) {
      _log.warn('ringtone stop failed: $error');
    }
  }

  void _playOnce() => unawaited(_playSafely());

  Future<void> _playSafely() async {
    try {
      await _player.play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.bell,
        looping: !_manualLoop,
        asAlarm: false,
      );
    } on Object catch (error) {
      _log.warn('ringtone play failed: $error');
    }
  }

  void dispose() => unawaited(stop());
}
