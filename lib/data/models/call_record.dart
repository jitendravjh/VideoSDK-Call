import 'package:freezed_annotation/freezed_annotation.dart';

part 'call_record.freezed.dart';
part 'call_record.g.dart';

enum CallDirection { incoming, outgoing }

/// How a call ended, for the history list.
enum CallOutcome { completed, missed, declined, failed, unreachable }

/// A single entry in the call history.
@freezed
abstract class CallRecord with _$CallRecord {
  const factory CallRecord({
    required String id,
    required String peerId,
    required String peerName,
    required CallDirection direction,
    required CallOutcome outcome,
    required DateTime startedAt,
    required int durationSeconds,
  }) = _CallRecord;

  factory CallRecord.fromJson(Map<String, dynamic> json) =>
      _$CallRecordFromJson(json);
}
