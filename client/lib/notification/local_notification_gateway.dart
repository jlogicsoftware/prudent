import 'reminder_notification.dart';

/// What the device can do about local notifications, behind one seam so the scheduling rules can
/// be tested without a plugin, and so a platform that cannot schedule one (the web and Linux)
/// answers "unsupported" instead of throwing from a method channel that is not there.
///
/// Nothing here prompts by itself: initialising the platform never asks for permission, only
/// [requestPermission] does.
abstract interface class LocalNotificationGateway {
  /// Whether this platform can show a notification at a time chosen in advance, with the app not
  /// running. A browser cannot, and Linux has no scheduler API to hand one to.
  bool get isSupported;

  /// Whether the user has allowed this app to show notifications. Asking never prompts.
  Future<bool> hasPermission();

  /// Asks the operating system for permission, which may show its prompt, and answers whether it
  /// was granted. A system that has already been asked and refused answers false without a prompt.
  Future<bool> requestPermission();

  /// Schedules [notification] for its [ReminderNotification.fireAt]. The same
  /// [ReminderNotification.id] replaces what was scheduled under it.
  Future<void> schedule(ReminderNotification notification);
}
