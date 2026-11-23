import 'package:shared_preferences/shared_preferences.dart';
import 'package:zen_core/zen_core.dart';

/// Keeps the chosen language in the platform's preference storage (`NSUserDefaults`,
/// `SharedPreferences`, `localStorage`).
///
/// A device preference, not data and not a secret: it is not in Prudent Local's encrypted store,
/// which syncs between devices, and it is not on the server. The instance is loaded before
/// `runApp`, which is what lets [read] answer synchronously for the first frame.
final class SharedPreferencesLocaleStore implements ZenLocaleStore {
  SharedPreferencesLocaleStore(this._preferences);

  static const String key = 'prudent.language';

  final SharedPreferences _preferences;

  @override
  String? read() => _preferences.getString(key);

  @override
  Future<void> write(String tag) async {
    // setString answers false when the platform could not write; reporting success then would
    // tell the person their choice was saved when the next launch will not find it.
    if (!await _preferences.setString(key, tag)) {
      throw StateError('The language could not be saved on this device.');
    }
  }
}
