import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/signaling/signaling_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'session_controller.g.dart';

/// Holds the local user identity and drives the signalling connection.
///
/// `null` means signed out. Signing in generates a stable id, connects the
/// socket, and registers the user.
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  static const _uuid = Uuid();

  @override
  User? build() => null;

  void signIn(String displayName) {
    final name = displayName.trim();
    if (name.isEmpty) return;

    final user = User(userId: _uuid.v4(), displayName: name);
    state = user;
    ref.read(signalingServiceProvider).connect(user);
  }

  void signOut() {
    ref.read(signalingServiceProvider).disconnect();
    state = null;
  }
}
