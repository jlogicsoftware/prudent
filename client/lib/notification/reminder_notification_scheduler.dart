import 'local_notification_gateway.dart';
import 'reminder_notification.dart';
import 'reminder_notification_outcome.dart';

/// Hands reminder notifications to the device, asking for permission only when there is one to
/// deliver.
///
/// The prompt is the platform's one chance to be heard, so it comes when a reminder exists —
/// something the user switched on (ADR-054) — and never at launch, on sign-in with nothing to
/// remind of, or on a platform that cannot deliver anything. Once the user has been asked in a
/// session, a refusal is accepted for that session rather than asked again.
class ReminderNotificationScheduler {
  ReminderNotificationScheduler(this._gateway);

  final LocalNotificationGateway _gateway;
  bool _asked = false;

  /// Schedules [notifications]. Idempotent: each notification replaces what the device holds under
  /// its id, so a repeated pass never doubles one up.
  Future<ReminderNotificationResult> schedule(List<ReminderNotification> notifications) async {
    if (!_gateway.isSupported) {
      return const ReminderNotificationResult(ReminderNotificationOutcome.unsupported);
    }
    if (notifications.isEmpty) {
      return const ReminderNotificationResult(ReminderNotificationOutcome.nothingToSchedule);
    }

    var permitted = await _gateway.hasPermission();
    if (!permitted && !_asked) {
      _asked = true;
      permitted = await _gateway.requestPermission();
    }
    if (!permitted) {
      return const ReminderNotificationResult(ReminderNotificationOutcome.denied);
    }

    for (final notification in notifications) {
      await _gateway.schedule(notification);
    }
    return ReminderNotificationResult(ReminderNotificationOutcome.scheduled, notifications.length);
  }
}
