import 'package:intl/intl.dart';

import '../generated/prudent/v1/plans.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import 'reminder_notification.dart';

/// The time of day a reminder notification appears, on the device. A plan's reminder is in whole
/// days (ADR-054), so the hour is a device matter: morning, when a day's obligations are worth
/// hearing about.
const int reminderNotificationHour = 9;

/// How many notifications are scheduled at once. iOS keeps at most 64 pending local notifications
/// and silently drops the rest, so the nearest ones are kept and the later ones are scheduled on
/// a later pass, once these have fired.
const int maxScheduledReminderNotifications = 60;

/// How far ahead occurrences are looked at. The longest lead time is 7 days (ADR-054); a month
/// leaves room for the cap above to be what limits the list.
const int reminderNotificationHorizonDays = 30;

/// The notification id of an occurrence's reminder: a stable, non-negative 31-bit hash of its id,
/// because platforms identify a notification by a 32-bit integer and the same occurrence must
/// always land on the same one. FNV-1a, so the value does not depend on the Dart runtime.
int reminderNotificationId(String occurrenceId) {
  var hash = 0x811c9dc5;
  for (final unit in occurrenceId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// The notifications to schedule: one for each still-planned occurrence whose plan's reminder is
/// on and whose reminder date — the occurrence's date less the plan's lead time, in calendar days
/// — has not yet passed at [now]. Nearest first, at most [limit].
///
/// A reminder that has already fallen due is not here: it is in the reminder centre, and a
/// notification for a moment that has passed would only appear at once. What an occurrence's
/// reminder is *for* (due, overdue, read) stays the server's (ADR-055); this only turns a future
/// reminder date into a moment on the device.
///
/// **No amount by default.** A notification is shown on the lock screen, where anyone can read it,
/// so the text names the plan and the date and leaves the amount out unless [showAmounts] is set
/// (ADR-056).
List<ReminderNotification> planReminderNotifications({
  required Iterable<Plan> plans,
  required Iterable<PlanOccurrence> occurrences,
  required DateTime now,
  required PrudentLocalizations t,
  required String locale,
  bool showAmounts = false,
  int limit = maxScheduledReminderNotifications,
}) {
  final reminders = {
    for (final plan in plans)
      if (plan.reminder.enabled) plan.id: plan.reminder,
  };

  final planned = <ReminderNotification>[];
  for (final occurrence in occurrences) {
    if (occurrence.status != OccurrenceStatus.OCCURRENCE_STATUS_PLANNED) continue;
    final reminder = reminders[occurrence.planId];
    if (reminder == null) continue;
    final date = DateTime.tryParse(occurrence.occurrenceDate);
    if (date == null) {
      throw FormatException('Occurrence ${occurrence.id} has no calendar date', occurrence.occurrenceDate);
    }

    // An absent lead time is the default the contract names (plans.proto Reminder.lead_days): 1.
    final leadDays = reminder.hasLeadDays() ? reminder.leadDays : 1;
    // Built from calendar fields, never by subtracting a Duration, so a daylight-saving change
    // between the two dates cannot move the reminder to the wrong day.
    final fireAt = DateTime(date.year, date.month, date.day - leadDays, reminderNotificationHour);
    if (!fireAt.isAfter(now)) continue;

    final when = DateFormat.yMMMd(locale).format(date);
    planned.add(
      ReminderNotification(
        id: reminderNotificationId(occurrence.id),
        occurrenceId: occurrence.id,
        fireAt: fireAt,
        title: t.reminderNotificationTitle,
        body:
            showAmounts
                ? t.reminderNotificationBodyWithAmount(
                  occurrence.title,
                  '${formatMinorUnits(occurrence.amountMinor)} ${occurrence.currency}',
                  when,
                )
                : t.reminderNotificationBody(occurrence.title, when),
        channelName: t.reminderNotificationChannel,
      ),
    );
  }

  planned.sort((a, b) {
    final byTime = a.fireAt.compareTo(b.fireAt);
    return byTime != 0 ? byTime : a.occurrenceId.compareTo(b.occurrenceId);
  });
  return planned.take(limit).toList(growable: false);
}
