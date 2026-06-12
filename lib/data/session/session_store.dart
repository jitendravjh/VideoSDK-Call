import 'package:meet_videosdk/data/models/user.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'session_store.g.dart';

/// Provides the [SharedPreferences] instance. Overridden in `main` with the
/// instance loaded before the app starts.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) =>
    throw UnimplementedError('sharedPreferencesProvider must be overridden');

/// Persists the local identity so the display name (and the assigned call code,
/// when known) survive app restarts.
class SessionStore {
  const SessionStore(this._prefs);

  final SharedPreferences _prefs;

  static const _userIdKey = 'session_user_id';
  static const _displayNameKey = 'session_display_name';

  User? load() {
    final name = _prefs.getString(_displayNameKey);
    if (name == null || name.isEmpty) return null;
    return User(userId: _prefs.getString(_userIdKey) ?? '', displayName: name);
  }

  Future<void> save(User user) async {
    await _prefs.setString(_userIdKey, user.userId);
    await _prefs.setString(_displayNameKey, user.displayName);
  }

  Future<void> clear() async {
    await _prefs.remove(_userIdKey);
    await _prefs.remove(_displayNameKey);
  }
}

@Riverpod(keepAlive: true)
SessionStore sessionStore(Ref ref) =>
    SessionStore(ref.watch(sharedPreferencesProvider));
