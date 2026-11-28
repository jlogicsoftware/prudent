// The generated large ledger (ADR-118) holds what its questions need to mean anything — spend on
// both sides of every window's edge, as the ledger stands after its edits and deletes — and the check
// both large runs apply to each answer refuses an empty or short one. Whether server and local agree
// on the figures is the parity suite's (tools/prudent_parity_server).
import 'dart:convert';

import 'package:prudent_local_core/parity.dart';
import 'package:test/test.dart';

/// The days that still hold an expense in each currency once every step has run: what spend by
/// category and by period read. Transfers and corrections are not spending and are not records here.
Map<String, Set<String>> spendDays(ParityScenario scenario) {
  final live = <Object, (String, String)>{};
  for (final (index, step) in scenario.steps.indexed) {
    final input = step.input;
    final Object key;
    switch (step.op) {
      case 'record.create':
        key = step.bindAs == null ? index : '\$${step.bindAs}';
      case 'record.update':
        key = input['record']!;
      case 'record.delete':
        // Absent already when it was income: only expenses are held here.
        live.remove(input['record']);
        continue;
      default:
        continue;
    }
    if ((input['amountMinor']! as String).startsWith('-')) {
      live[key] = (input['currency']! as String, input['date']! as String);
    } else {
      live.remove(key);
    }
  }
  final days = <String, Set<String>>{};
  for (final (currency, day) in live.values) {
    days.putIfAbsent(currency, () => {}).add(day);
  }
  return days;
}

String iso(DateTime day) => day.toIso8601String().substring(0, 10);

void main() {
  // A month's last day, a year's first month, a leap February and an ordinary day: where the
  // calendar arithmetic of an edge goes wrong.
  final todays = [
    DateTime.utc(2026, 11, 28),
    DateTime.utc(2027, 1, 1),
    DateTime.utc(2028, 2, 29),
    DateTime.utc(2026, 3, 31),
  ];

  for (final today in todays) {
    test('as of ${iso(today)}: both sides of every window edge hold spend', () {
      // Few random records, so that only what the generator guarantees can satisfy this.
      final scenario = AnalyticsScenarios.large(today: today, records: 40);
      final days = spendDays(scenario);
      for (final currency in AnalyticsScenarios.currencies) {
        for (final count in AnalyticsScenarios.monthCounts) {
          final firstInside = DateTime.utc(today.year, today.month - (count - 1));
          final lastOutside = firstInside.subtract(const Duration(days: 1));
          expect(
            days[currency],
            containsAll([iso(firstInside), iso(lastOutside)]),
            reason: '$currency, spend by month, last $count',
          );
        }
        for (final count in AnalyticsScenarios.yearCounts) {
          final first = today.year - (count - 1);
          expect(
            days[currency],
            containsAll(['$first-01-01', '${first - 1}-12-31']),
            reason: '$currency, spend by year, last $count',
          );
        }
      }
    });
  }

  test('the counts asked are the counts whose edges are guaranteed, 60 among them', () {
    final scenario = AnalyticsScenarios.large(today: todays.first, records: 40);
    Set<int> asked(String granularity) => {
      for (final step in scenario.steps)
        if (step.op == 'analytics.spendByPeriod' && step.input['granularity'] == granularity)
          step.input['count']! as int,
    };
    expect(asked('MONTH'), AnalyticsScenarios.monthCounts.toSet());
    expect(asked('YEAR'), AnalyticsScenarios.yearCounts.toSet());
    expect(AnalyticsScenarios.monthCounts, contains(60));
    expect(AnalyticsScenarios.yearCounts, contains(60));
  });

  test('one seed and one UTC day build one ledger; it reads the year and month of the day', () {
    String build(DateTime today) => jsonEncode([
      for (final step in AnalyticsScenarios.large(today: today, records: 200).steps)
        [step.op, step.input, step.bindAs],
    ]);
    final one = build(DateTime.utc(2026, 11, 28));
    expect(build(DateTime.utc(2026, 11, 28, 23, 59)), one);
    expect(build(DateTime.utc(2026, 11, 1)), one);
    expect(build(DateTime.utc(2026, 12, 1)), isNot(one));
  });

  group('shortfall', () {
    final today = DateTime.utc(2026, 1, 15);
    String? byCategory(Map<String, Object?> observation) => AnalyticsScenarios.shortfall(
      'analytics.spendByCategory',
      {'currency': 'CAD', 'year': 2026},
      observation,
      today: today,
    );
    String? byPeriod(String granularity, int count, Map<String, String> periods) =>
        AnalyticsScenarios.shortfall(
          'analytics.spendByPeriod',
          {'currency': 'CAD', 'granularity': granularity, 'count': count},
          ParityObservation.accepted({'periods': periods}),
          today: today,
        );

    test('a figure that is there passes', () {
      expect(
        byCategory(
          ParityObservation.accepted({
            'items': {'cat0': '5'},
          }),
        ),
        isNull,
      );
      // Three months back from January crosses the year.
      expect(byPeriod('MONTH', 3, {'2025-11': '1', '2026-01': '2'}), isNull);
      expect(byPeriod('YEAR', 2, {'2025': '1', '2026': '2'}), isNull);
    });

    test('a refusal, an empty answer and a zero are shortfalls', () {
      expect(byCategory(ParityObservation.refused(400)), isNotNull);
      expect(byCategory(ParityObservation.accepted()), isNotNull);
      expect(byCategory(ParityObservation.accepted({'items': <String, String>{}})), isNotNull);
      expect(
        byCategory(
          ParityObservation.accepted({
            'items': {'cat0': '0'},
          }),
        ),
        isNotNull,
      );
      expect(byPeriod('MONTH', 3, {}), isNotNull);
    });

    test('a window short of its oldest or current bucket, or past its edge, is a shortfall', () {
      expect(byPeriod('MONTH', 3, {'2025-12': '1', '2026-01': '2'}), isNotNull);
      expect(byPeriod('MONTH', 3, {'2025-11': '1', '2025-12': '2'}), isNotNull);
      expect(byPeriod('MONTH', 3, {'2025-10': '1', '2026-01': '2'}), isNotNull);
      expect(byPeriod('YEAR', 2, {'2026': '2'}), isNotNull);
      expect(byPeriod('YEAR', 2, {'2024': '1', '2026': '2'}), isNotNull);
    });
  });
}
