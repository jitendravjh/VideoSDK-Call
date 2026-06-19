import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:synq/data/signaling/signaling_service.dart';
import 'package:synq/data/signaling/signaling_transport.dart';

part 'signaling_providers.g.dart';

@Riverpod(keepAlive: true)
SignalingTransport signalingService(Ref ref) {
  final service = SignalingService();
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
Stream<SignalingConnectionState> connectionState(Ref ref) {
  final service = ref.watch(signalingServiceProvider);
  // The underlying connection stream is a broadcast that only emits on change.
  // Seeding the current state and subscribing must happen in one synchronous
  // step: an `async*` that yields current state then `yield*`s the stream
  // suspends between the two, and a change landing in that gap (e.g. an almost
  // instant connect over a local link) is dropped, stranding the banner on the
  // stale state. Doing both inside onListen closes that window.
  late final StreamController<SignalingConnectionState> controller;
  StreamSubscription<SignalingConnectionState>? subscription;
  controller = StreamController<SignalingConnectionState>(
    onListen: () {
      controller.add(service.currentState);
      subscription = service.connectionState.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    },
    onCancel: () => subscription?.cancel(),
  );
  return controller.stream;
}
