/// What a scheduling pass did, so a screen can say so (the denied and unsupported cases are the
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
}

/// The result of one pass: the [outcome], and how many notifications it scheduled.
class ReminderNotificationResult {
  const ReminderNotificationResult(this.outcome, [this.scheduled = 0]);

  final ReminderNotificationOutcome outcome;
  final int scheduled;
}
