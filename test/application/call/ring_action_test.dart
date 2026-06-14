import 'package:flutter_test/flutter_test.dart';
import 'package:meet_videosdk/application/call/ring_action.dart';
import 'package:meet_videosdk/data/models/call_state.dart';
import 'package:meet_videosdk/data/models/user.dart';

const _peer = User(userId: 'BOBBB2', displayName: 'Bob');

void main() {
  test('the phone rings only while an incoming call is pending', () {
    expect(
      ringActionFor(const CallState.incoming(peer: _peer, offerSdp: 'sdp')),
      RingAction.incoming,
    );
  });

  test('every other phase is silent', () {
    final silent = <CallState>[
      const CallState.idle(),
      const CallState.outgoing(peer: _peer),
      const CallState.connecting(peer: _peer),
      const CallState.connected(peer: _peer),
      const CallState.ended(reason: 'Call ended'),
      const CallState.failed(error: 'Connection failed'),
    ];
    for (final state in silent) {
      expect(ringActionFor(state), RingAction.stop, reason: '$state');
    }
  });
}
