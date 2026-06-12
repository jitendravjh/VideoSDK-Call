import 'package:meet_videosdk/application/lobby/presence_reducer.dart';
import 'package:meet_videosdk/application/lobby/session_controller.dart';
import 'package:meet_videosdk/data/models/user.dart';
import 'package:meet_videosdk/data/signaling/signaling_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'lobby_controller.g.dart';

/// Maintains the live list of online peers by folding presence messages
/// through [PresenceReducer]. Excludes the local user.
@riverpod
class LobbyController extends _$LobbyController {
  @override
  List<User> build() {
    final self = ref.watch(sessionControllerProvider);
    if (self == null) {
      return const [];
    }

    final service = ref.watch(signalingServiceProvider);
    final sub = service.messages.listen((message) {
      state = PresenceReducer.apply(
        current: state,
        message: message,
        selfId: self.userId,
      );
    });
    ref.onDispose(sub.cancel);

    return const [];
  }
}
