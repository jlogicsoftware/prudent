import 'package:shared_preferences/shared_preferences.dart';

import 'notification_permission_memory.dart';

/// Keeps the "already asked" fact in the platform's preferences, which survive a restart and an
/// app update.
class SharedPreferencesPermissionMemory implements NotificationPermissionMemory {
  const SharedPreferencesPermissionMemory();

  static const _key = 'notification_permission_asked';

  @override
  Future<bool> hasAsked() async => (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> markAsked() async {
    final saved = await (await SharedPreferences.getInstance()).setBool(_key, true);
    // A refusal that is not remembered is a prompt on every launch, so a failed write is loud.
    if (!saved) {
      throw StateError('Could not record that notification permission was asked for');
    }
  }
}
