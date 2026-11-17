// Rules 6.30 and 6.36 (phase-0 §0.3): a plan's recurrence and the dates it places, held to the
// JVM by test/golden/plans.json (unit 6b, ADR-119).
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import '../golden.dart';

PlanFrequency? _frequency(String name) => switch (name) {
  'ONCE' => PlanFrequency.once,
  'DAILY' => PlanFrequency.daily,
  'WEEKLY' => PlanFrequency.weekly,
  'MONTHLY' => PlanFrequency.monthly,
  'YEARLY' => PlanFrequency.yearly,
  _ => null,
};

void main() {
  final file = golden('plans.json');

  RecurrenceRule parse(Map<String, Object?> spec) => RecurrenceRule.parse(
    frequency: _frequency(spec['frequency']! as String),
    interval: int.parse(spec['interval']! as String),
    startDate: spec['start']! as String,
    timeZone: spec['zone']! as String,
    untilDate: spec['until'] as String?,
    occurrenceCount: spec['count'] == null ? null : int.parse(spec['count']! as String),
  );

  group('a recurrence is accepted or refused as the server does', () {
    for (final spec in cases(file, 'recurrences')) {
      final name =
          '${spec['frequency']} ${spec['interval']} ${show(spec['start'])} ${show(spec['zone'])} '
          'until ${spec['until']} count ${spec['count']}';
      test(name, () {
        expect(attempt(() => parse(spec).toString()), spec['parse']);
      });
    }
  });

  group('and places the same dates in every window', () {
    for (final spec in cases(file, 'recurrences')) {
      final windows = (spec['windows']! as List<Object?>).cast<Map<String, Object?>>();
      if (windows.isEmpty) continue;
      test('${spec['frequency']} ${spec['interval']} from ${spec['start']}', () {
        final rule = parse(spec);
        for (final window in windows) {
          final dates = rule.occurrencesBetween(
            CivilDate.parse(window['from']! as String),
            CivilDate.parse(window['to']! as String),
          );
          expect([for (final d in dates) d.toString()], window['dates'], reason: '$window');
        }
      });
    }
  });

  test('a month end is computed from the anchor, not from the previous occurrence', () {
    final rule = RecurrenceRule.parse(
      frequency: PlanFrequency.monthly,
      interval: 1,
      startDate: '2026-01-31',
      timeZone: 'Europe/Warsaw',
      occurrenceCount: 4,
    );
    expect(
      [
        for (final d in rule.occurrencesBetween(
          CivilDate.parse('2026-01-01'),
          CivilDate.parse('2026-12-31'),
        ))
          '$d',
      ],
      ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'],
    );
  });

  group('reminder lead days (finding F-08)', () {
    for (final entry in cases(file, 'leads')) {
      test('${entry['leadDays']}', () {
        final lead = entry['leadDays'] == null ? null : int.parse(entry['leadDays']! as String);
        expect(attempt(() => '${ReminderLeadTimes.parse(lead)}'), entry['parse']);
      });
    }
  });

  group('calendar arithmetic against Java\'s LocalDate', () {
    test('epoch days round-trip across the whole range', () {
      for (final text in [
        '1970-01-01',
        '2000-02-29',
        '1900-03-01',
        '-0001-12-31',
        '0000-01-01',
        '+999999999-12-31',
        '-999999999-01-01',
      ]) {
        final date = CivilDate.parse(text);
        expect(CivilDate.fromEpochDay(date.epochDay), date, reason: text);
      }
      expect(CivilDate.parse('1970-01-01').epochDay, 0);
      expect(CivilDate.parse('2026-11-16').epochDay, 20773);
    });

    test('a date beyond the last year is a CalendarOverflow, not a wrapped date', () {
      expect(
        () => CivilDate.parse('+999999999-12-31').plusDays(1),
        throwsA(isA<CalendarOverflow>()),
      );
      expect(
        () => CivilDate.parse('+999999999-12-31').plusYears(1),
        throwsA(isA<CalendarOverflow>()),
      );
    });
  });
}
