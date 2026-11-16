// Row 6.28 (unit 6a): a goal's whole percent, its calendar months and its rounded-up monthly
// contribution, held to GoalProgressCalculator by test/golden/goal_progress.json — including the
// 64-bit edges no parity scenario reaches.
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import 'golden.dart';

void main() {
  final file = golden('goal_progress.json');

  Object answer(int Function() rule) {
    try {
      return rule();
    } on MoneyOverflow {
      return 'ArithmeticException';
    }
  }

  int long(Object? value) => switch (value) {
    final int v => v,
    final String v => int.parse(v),
    _ => throw StateError('not a long: $value'),
  };

  Object? expected(Object? value) => value is String && !RegExp(r'^-?\d+$').hasMatch(value)
      ? value
      : long(value);

  test('percent', () {
    final all = cases(file, 'percent');
    expect(all, isNotEmpty);
    for (final c in all) {
      final allocated = long(c['allocated']);
      final target = long(c['target']);
      expect(
        answer(() => GoalArithmetic.percent(allocated, target)),
        expected(c['percent']),
        reason: 'percent($allocated, $target)',
      );
    }
  });

  test('monthsRemaining', () {
    final all = cases(file, 'monthsRemaining');
    expect(all, isNotEmpty);
    for (final c in all) {
      final asOf = CivilDate.parse(c['asOf']! as String);
      final target = CivilDate.parse(c['target']! as String);
      expect(
        GoalArithmetic.monthsRemaining(asOf, target),
        expected(c['months']),
        reason: 'monthsRemaining($asOf, $target)',
      );
    }
  });

  test('ceilDiv', () {
    final all = cases(file, 'ceilDiv');
    expect(all, isNotEmpty);
    for (final c in all) {
      final remaining = long(c['remaining']);
      final months = long(c['months']);
      expect(
        GoalArithmetic.ceilDiv(remaining, months),
        expected(c['ceilDiv']),
        reason: 'ceilDiv($remaining, $months)',
      );
    }
  });
}
