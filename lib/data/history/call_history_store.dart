import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synq/data/models/call_record.dart';
import 'package:synq/data/session/session_store.dart';

part 'call_history_store.g.dart';

/// Persists the call history as a JSON list in shared preferences.
class CallHistoryStore {
  const CallHistoryStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'call_history';

  List<CallRecord> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => CallRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<void> save(List<CallRecord> records) {
    return _prefs.setString(
      _key,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }
}

@Riverpod(keepAlive: true)
CallHistoryStore callHistoryStore(Ref ref) =>
    CallHistoryStore(ref.watch(sharedPreferencesProvider));
