import 'package:meet_videosdk/data/webrtc/mesh_engine.dart';
import 'package:meet_videosdk/data/webrtc/mesh_service.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_engine.dart';
import 'package:meet_videosdk/data/webrtc/webrtc_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'webrtc_providers.g.dart';

@Riverpod(keepAlive: true)
WebRtcEngine webRtcEngine(Ref ref) {
  final engine = WebRtcService();
  ref.onDispose(engine.dispose);
  return engine;
}

@Riverpod(keepAlive: true)
MeshEngine meshEngine(Ref ref) {
  final engine = MeshService();
  ref.onDispose(engine.dispose);
  return engine;
}
