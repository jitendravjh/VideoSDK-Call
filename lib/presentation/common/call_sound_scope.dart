import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synq/application/call/call_controller.dart';
import 'package:synq/application/call/ring_action.dart';
import 'package:synq/data/audio/ringtone_providers.dart';
import 'package:synq/data/models/call_state.dart';

/// Drives the incoming-call ringtone from the call state. Mounted once above the
/// router so it observes every transition, including the first ring that arrives
/// while the lobby (not the call screen) is on top.
class CallSoundScope extends ConsumerWidget {
  const CallSoundScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<CallState>(callControllerProvider, (_, next) {
      final ringtone = ref.read(ringtoneServiceProvider);
      switch (ringActionFor(next)) {
        case RingAction.incoming:
          unawaited(ringtone.playIncoming());
        case RingAction.stop:
          unawaited(ringtone.stop());
      }
    });
    return child;
  }
}
