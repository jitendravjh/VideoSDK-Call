import 'package:flutter_test/flutter_test.dart';
import 'package:synq/data/models/call_record.dart';

void main() {
  test('CallRecord round-trips through JSON, enums included', () {
    final record = CallRecord(
      id: 'c1',
      peerId: 'ABC123',
      peerName: 'Bob',
      direction: CallDirection.incoming,
      outcome: CallOutcome.completed,
      startedAt: DateTime.utc(2026, 6, 13, 14, 30),
      durationSeconds: 95,
    );

    expect(CallRecord.fromJson(record.toJson()), record);
  });

  test('each outcome and direction survives serialization', () {
    for (final direction in CallDirection.values) {
      for (final outcome in CallOutcome.values) {
        final record = CallRecord(
          id: '$direction-$outcome',
          peerId: 'p',
          peerName: 'Peer',
          direction: direction,
          outcome: outcome,
          startedAt: DateTime.utc(2026),
          durationSeconds: 0,
        );
        expect(CallRecord.fromJson(record.toJson()), record);
      }
    }
  });
}
