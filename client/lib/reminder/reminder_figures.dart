import 'package:intl/intl.dart';

import '../generated/prudent/v1/plans.pb.dart';
import '../generated/prudent/v1/reminders.pb.dart';

/// A `YYYY-MM-DD` occurrence date as a readable date; the raw text if it is somehow not one, so a
/// date is never shown blank or guessed.
String formatReminderDate(String wire, String locale) {
  final date = DateTime.tryParse(wire);
  return date == null ? wire : DateFormat.yMMMd(locale).format(date);
}

/// Whether the server says this reminder's occurrence has passed its date. The status is the
/// server's, worked out in the plan's own calendar day, so the client never compares a date with
/// the device's clock (ADR-055).
bool isOverdue(DueReminder reminder) =>
    reminder.occurrence.status == OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE;

/// The reminders that are overdue, in the order given — the server's, oldest date first.
List<DueReminder> overdueReminders(List<DueReminder> reminders) => [
  for (final reminder in reminders)
    if (isOverdue(reminder)) reminder,
];

/// The reminders that are due but not yet past their date, in the order given.
List<DueReminder> dueReminders(List<DueReminder> reminders) => [
  for (final reminder in reminders)
    if (!isOverdue(reminder)) reminder,
];
