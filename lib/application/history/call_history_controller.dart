import 'dart:async';

import 'package:meet_videosdk/data/history/call_history_store.dart';
import 'package:meet_videosdk/data/models/call_record.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'call_history_controller.g.dart';

/// Owns the call history, newest first, persisting changes. Capped so the
/// stored list cannot grow without bound.
@Riverpod(keepAlive: true)
class CallHistoryController extends _$CallHistoryController {
  static const _maxEntries = 50;

  @override
  List<CallRecord> build() => ref.read(callHistoryStoreProvider).load();

  void add(CallRecord record) {
    final next = [record, ...state].take(_maxEntries).toList();
    state = next;
    unawaited(ref.read(callHistoryStoreProvider).save(next));
  }

  Future<void> clear() async {
    state = const [];
    await ref.read(callHistoryStoreProvider).save(const []);
  }
}
