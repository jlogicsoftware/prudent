import 'local_notification_gateway.dart';
import 'reminder_notification.dart';
import 'reminder_notification_outcome.dart';

/// Makes the notifications pending on the device match the reminders that should fire, asking for
/// permission only when there is one to deliver.
///
/// The prompt is the platform's one chance to be heard, so it comes when a reminder exists —
/// something the user switched on (ADR-054) — and never at launch, on sign-in with nothing to
/// remind of, or on a platform that cannot deliver anything. Once the user has been asked in a
/// session, a refusal is accepted for that session rather than asked again.
class ReminderNotificationScheduler {
  ReminderNotificationScheduler(this._gateway);

  final LocalNotificationGateway _gateway;
  bool _asked = false;

  // Passes are queued, never interleaved: a pass cancels and schedules across several awaits, and
  // two running at once could leave the older one's notifications on the device.
  Future<void> _queue = Future.value();

  /// Reconciles the device with [notifications], the full set that should be pending: every one
  /// is scheduled, and every pending notification that is not among them is cancelled.
  ///
  /// Idempotent. Scheduling replaces what the device holds under an id, and a cancelled id is not
  /// cancelled twice, so the same pass repeated changes nothing — which is why it can be run on
  /// every sign-in, launch and change of state without asking what changed.
  Future<ReminderNotificationResult> reconcile(List<ReminderNotification> notifications) {
    final pass = _queue.then((_) => _reconcile(notifications));
    // The next pass waits for this one to finish, not to succeed; this pass's own failure is
    // still its caller's to see, through [pass].
    _queue = pass.then<void>((_) {}, onError: (Object _) {});
    return pass;
  }

  Future<ReminderNotificationResult> _reconcile(List<ReminderNotification> notifications) async {
    if (!_gateway.isSupported) {
      return const ReminderNotificationResult(ReminderNotificationOutcome.unsupported);
    }

    // Cancelling needs no permission and comes first: a reminder switched off, a plan deleted or an
    // occurrence confirmed must stop firing even when nothing is left to schedule, or the user has
    // refused notifications since.
    final wanted = {for (final notification in notifications) notification.id};
    final stale = (await _gateway.pendingIds()).difference(wanted);
    for (final id in stale) {
      await _gateway.cancel(id);
    }

    if (notifications.isEmpty) {
      return ReminderNotificationResult(ReminderNotificationOutcome.nothingToSchedule, cancelled: stale.length);
    }

    var permitted = await _gateway.hasPermission();
    if (!permitted && !_asked) {
      _asked = true;
      permitted = await _gateway.requestPermission();
    }
    if (!permitted) {
      return ReminderNotificationResult(ReminderNotificationOutcome.denied, cancelled: stale.length);
    }

    for (final notification in notifications) {
      await _gateway.schedule(notification);
    }
    return ReminderNotificationResult(
      ReminderNotificationOutcome.scheduled,
      scheduled: notifications.length,
      cancelled: stale.length,
    );
  }
}
