import 'package:flutter_test/flutter_test.dart';
import 'package:meet_videosdk/application/lobby/presence_reducer.dart';
import 'package:meet_videosdk/data/models/signal_message.dart';
import 'package:meet_videosdk/data/models/user.dart';

void main() {
  const selfId = 'SELF01';
  const alice = User(userId: 'ALICE1', displayName: 'Alice');
  const bob = User(userId: 'BOBBB2', displayName: 'Bob');

  List<String> ids(List<User> users) => users.map((u) => u.userId).toList();

  test('presence snapshot excludes self and dedups', () {
    final result = PresenceReducer.apply(
      current: const [],
      message: const SignalMessage.presence(
        users: [
          User(userId: selfId, displayName: 'Me'),
          alice,
          bob,
          User(userId: 'ALICE1', displayName: 'Alice again'),
        ],
      ),
      selfId: selfId,
    );

    expect(ids(result), ['ALICE1', 'BOBBB2']);
  });

  test('user-joined appends without duplicating, and ignores self', () {
    final afterAlice = PresenceReducer.apply(
      current: const [alice],
      message: const SignalMessage.userJoined(user: bob),
      selfId: selfId,
    );
    expect(ids(afterAlice), ['ALICE1', 'BOBBB2']);

    final duplicate = PresenceReducer.apply(
      current: afterAlice,
      message: const SignalMessage.userJoined(user: alice),
      selfId: selfId,
    );
    expect(ids(duplicate), ['ALICE1', 'BOBBB2']);

    final withSelf = PresenceReducer.apply(
      current: afterAlice,
      message: const SignalMessage.userJoined(
        user: User(userId: selfId, displayName: 'Me'),
      ),
      selfId: selfId,
    );
    expect(ids(withSelf), ['ALICE1', 'BOBBB2']);
  });

  test('user-left removes the matching user', () {
    final result = PresenceReducer.apply(
      current: const [alice, bob],
      message: const SignalMessage.userLeft(userId: 'ALICE1'),
      selfId: selfId,
    );
    expect(ids(result), ['BOBBB2']);
  });

  test('unrelated messages leave the list unchanged', () {
    const current = [alice, bob];
    final result = PresenceReducer.apply(
      current: current,
      message: const SignalMessage.offer(from: 'x', to: 'y', sdp: 'z'),
      selfId: selfId,
    );
    expect(result, same(current));
  });
}
