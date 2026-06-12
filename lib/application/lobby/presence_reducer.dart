import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';

/// Pure reducer that folds presence signalling messages into the current list
/// of online peers. Always excludes the local user and removes duplicates,
/// keeping the latest entry for a given id.
class PresenceReducer {
  const PresenceReducer._();

  static List<User> apply({
    required List<User> current,
    required SignalMessage message,
    required String selfId,
  }) {
    return switch (message) {
      PresenceMessage(:final users) => _normalize(users, selfId),
      UserJoinedMessage(:final user) => _normalize(
        [...current, user],
        selfId,
      ),
      UserLeftMessage(:final userId) =>
        current.where((u) => u.userId != userId).toList(),
      _ => current,
    };
  }

  static List<User> _normalize(List<User> users, String selfId) {
    final byId = <String, User>{};
    for (final user in users) {
      if (user.userId == selfId) continue;
      byId[user.userId] = user;
    }
    return byId.values.toList();
  }
}
