/// What a reconciliation pass did, so a screen can say so (the denied and unsupported cases are the
/// next task's to explain) and a test can pin it.
enum ReminderNotificationOutcome {
  /// This platform cannot schedule a notification for later: the web, Linux.
  unsupported,

  /// No reminder is waiting to be delivered, so no permission was asked for.
  nothingToSchedule,

  /// There were reminders and the user has not allowed notifications, so none was scheduled.
  denied,

  /// Every notification handed over was scheduled.
  scheduled,

  /// A later pass replaced this one before it reached the device, so it did nothing.
  superseded,
}

/// The result of one pass: the [outcome], how many notifications it scheduled, and how many stale
/// ones it cancelled — pending on the device but no longer a reminder that should fire.
class ReminderNotificationResult {
  const ReminderNotificationResult(this.outcome, {this.scheduled = 0, this.cancelled = 0});

  final ReminderNotificationOutcome outcome;
  final int scheduled;
  final int cancelled;
}
