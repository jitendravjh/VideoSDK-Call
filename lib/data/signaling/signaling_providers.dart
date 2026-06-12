import 'package:meet_videosdk/data/signaling/signaling_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'signaling_providers.g.dart';

@Riverpod(keepAlive: true)
SignalingService signalingService(Ref ref) {
  final service = SignalingService();
  ref.onDispose(service.dispose);
  return service;
}

@riverpod
Stream<SignalingConnectionState> connectionState(Ref ref) {
  final service = ref.watch(signalingServiceProvider);
  return service.connectionState;
}
