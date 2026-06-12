import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'remote_media_controller.g.dart';

/// Whether the remote peer is currently sending video. Driven by the engine's
/// remote-track callback so the in-call layout follows the remote stream rather
/// than the local one (which matters for asymmetric audio/video calls).
///
/// Kept alive because the remote video track can arrive while the call is still
/// connecting, before the connected view starts watching this; an auto-dispose
/// provider would reset that flag to false in the meantime.
@Riverpod(keepAlive: true)
class RemoteVideo extends _$RemoteVideo {
  @override
  bool build() => false;

  void update({required bool hasVideo}) {
    if (state != hasVideo) state = hasVideo;
  }
}
