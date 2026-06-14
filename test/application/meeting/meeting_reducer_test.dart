import 'package:flutter_test/flutter_test.dart';
import 'package:meet_videosdk/application/meeting/meeting_reducer.dart';
import 'package:meet_videosdk/data/models/meeting_state.dart';

void main() {
  MeetingParticipant p(String id, {bool connected = false}) =>
      MeetingParticipant(userId: id, displayName: id, connected: connected);

  group('shouldOffer is total and glare-free', () {
    const ids = ['A1', 'B2', 'C3', 'HOST01', 'ZZ9'];

    test('exactly one side offers for every unordered pair', () {
      for (final a in ids) {
        for (final b in ids) {
          if (a == b) continue;
          final ab = MeetingReducer.shouldOffer(a, b);
          final ba = MeetingReducer.shouldOffer(b, a);
          expect(ab, isNot(ba), reason: 'pair ($a,$b) must have one offerer');
        }
      }
    });

    test('a peer never offers itself', () {
      for (final id in ids) {
        expect(MeetingReducer.shouldOffer(id, id), isFalse);
      }
    });
  });

  group('participant bookkeeping', () {
    test('upsert appends a new participant', () {
      final result = MeetingReducer.upsert([p('A1')], p('B2'));
      expect(result.map((e) => e.userId), ['A1', 'B2']);
    });

    test('upsert replaces an existing participant in place', () {
      final result = MeetingReducer.upsert(
        [p('A1'), p('B2')],
        p('A1', connected: true),
      );
      expect(result.map((e) => e.userId), ['A1', 'B2']);
      expect(result.first.connected, isTrue);
    });

    test('remove drops the matching participant', () {
      final result = MeetingReducer.remove([p('A1'), p('B2')], 'A1');
      expect(result.map((e) => e.userId), ['B2']);
    });

    test('update changes only the matching participant', () {
      final result = MeetingReducer.update(
        [p('A1'), p('B2')],
        'B2',
        (participant) => participant.copyWith(hasVideo: true),
      );
      expect(result.firstWhere((e) => e.userId == 'A1').hasVideo, isFalse);
      expect(result.firstWhere((e) => e.userId == 'B2').hasVideo, isTrue);
    });
  });
}
