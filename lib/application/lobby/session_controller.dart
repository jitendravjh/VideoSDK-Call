import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/signaling/signaling_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_controller.g.dart';

/// Holds the local user identity and drives the signalling connection.
///
/// `null` means signed out. Signing in connects with just a display name; the
/// server assigns a short shareable code, which arrives as a `registered`
/// message and replaces the provisional identity.
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  @override
  User? build() {
    final sub = ref.read(signalingServiceProvider).messages.listen((message) {
      if (message is RegisteredMessage) {
        state = message.user;
      }
    });
    ref.onDispose(sub.cancel);
    return null;
  }

  void signIn(String displayName) {
    final name = displayName.trim();
    if (name.isEmpty) return;

    final provisional = User(userId: '', displayName: name);
    state = provisional;
    ref.read(signalingServiceProvider).connect(provisional);
  }

  void signOut() {
    ref.read(signalingServiceProvider).disconnect();
    state = null;
  }
}
