import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:synq/data/models/signal_message.dart';
import 'package:synq/data/models/user.dart';
import 'package:synq/data/session/session_store.dart';
import 'package:synq/data/signaling/signaling_providers.dart';

part 'session_controller.g.dart';

/// Holds the local user identity and drives the signalling connection.
///
/// `null` means signed out. Signing in connects with just a display name; the
/// server assigns a short shareable code, which arrives as a `registered`
/// message and replaces the provisional identity. The identity is persisted so
/// it is restored on the next launch.
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  @override
  User? build() {
    final store = ref.read(sessionStoreProvider);
    final sub = ref.read(signalingServiceProvider).messages.listen((message) {
      if (message is RegisteredMessage) {
        state = message.user;
        unawaited(store.save(message.user));
      }
    });
    ref.onDispose(sub.cancel);

    final saved = store.load();
    if (saved != null) {
      // Reconnect with the remembered identity (re-using the saved code keeps a
      // stable code when the server still has it free).
      unawaited(
        Future(() => ref.read(signalingServiceProvider).connect(saved)),
      );
      return saved;
    }
    return null;
  }

  void signIn(String displayName) {
    final name = displayName.trim();
    if (name.isEmpty) return;

    final user = User(userId: state?.userId ?? '', displayName: name);
    state = user;
    unawaited(ref.read(sessionStoreProvider).save(user));
    ref.read(signalingServiceProvider).connect(user);
  }

  void signOut() {
    unawaited(ref.read(sessionStoreProvider).clear());
    ref.read(signalingServiceProvider).disconnect();
    state = null;
  }
}

/// Whether a user is signed in. Watching this only rebuilds dependents when the
/// signed-in state flips, not on every identity change (the user id transitions
/// from a provisional empty value to the server-assigned code after sign-in).
@riverpod
bool signedIn(Ref ref) => ref.watch(sessionControllerProvider) != null;
