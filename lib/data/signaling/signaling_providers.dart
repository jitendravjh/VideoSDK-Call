import 'package:meet_videosdk/data/signaling/signaling_service.dart';
import 'package:meet_videosdk/data/signaling/signaling_transport.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'signaling_providers.g.dart';

@Riverpod(keepAlive: true)
SignalingTransport signalingService(Ref ref) {
  final service = SignalingService();
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
Stream<SignalingConnectionState> connectionState(Ref ref) async* {
  final service = ref.watch(signalingServiceProvider);
  // The connection stream is a broadcast stream that only emits on change, so
  // a late subscriber (e.g. the in-call banner) would otherwise never learn the
  // socket is already connected. Emit the current state first.
  yield service.currentState;
  yield* service.connectionState;
}
