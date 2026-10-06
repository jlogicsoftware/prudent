// The reminder centre's pure helpers (jlogicsoftware/prudent#68, ADR-055): grouping by the status
// the server gave, and the date line. Nothing here compares a date with the device's clock, so
// there is no clock to pin.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prudent/generated/prudent/v1/plans.pb.dart';
import 'package:prudent/generated/prudent/v1/reminders.pb.dart';
import 'package:prudent/reminder/reminder_figures.dart';

DueReminder _reminder(String id, OccurrenceStatus status) =>
    DueReminder(occurrence: PlanOccurrence(id: id, status: status));

void main() {
  test('overdue and due reminders split on the server status and keep its order', () {
    final reminders = [
      _reminder('a', OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE),
      _reminder('b', OccurrenceStatus.OCCURRENCE_STATUS_PLANNED),
      _reminder('c', OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE),
      _reminder('d', OccurrenceStatus.OCCURRENCE_STATUS_PLANNED),
    ];

    expect(overdueReminders(reminders).map((r) => r.occurrence.id), ['a', 'c']);
    expect(dueReminders(reminders).map((r) => r.occurrence.id), ['b', 'd']);
    expect(overdueReminders(const []), isEmpty);
    expect(dueReminders(const []), isEmpty);
  });

  test('every reminder lands in exactly one group', () {
    final reminders = [
      for (final status in [
        OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
        OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE,
        OccurrenceStatus.OCCURRENCE_STATUS_UNSPECIFIED,
      ])
        _reminder('$status', status),
    ];

    expect(
      overdueReminders(reminders).length + dueReminders(reminders).length,
      reminders.length,
    );
  });

  test('a date is shown in the locale, and text that is not a date is shown as it came', () async {
    await initializeDateFormatting('en');
    expect(formatReminderDate('2026-10-17', 'en'), 'Oct 17, 2026');
    expect(formatReminderDate('not a date', 'en'), 'not a date');
  });
}
