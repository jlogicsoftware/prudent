// Rules 3.1 and 3.3 (phase-0 §0.3): money is a signed 64-bit count of minor units, sums are exact
// and overflow is an error, held to Math.addExact & co. by test/golden/money.json.
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import 'golden.dart';

void main() {
  final file = golden('money.json');

  Object exact(int Function() operation) {
    try {
      return operation().toString();
    } on MoneyOverflow {
      return 'overflow';
    }
  }

  test('int is a 64-bit integer here (Prudent Local has no web build, where it is a double)', () {
    expect(maxMinorUnits.toString(), '9223372036854775807');
    expect(minMinorUnits.toString(), '-9223372036854775808');
    expect(int.parse('9223372036854775807'), maxMinorUnits);
  });

  test('the wire carries every currency at one fixed scale of two fraction digits', () {
    expect(wireMinorUnitDigits, 2);
  });

  group('unary', () {
    for (final entry in cases(file, 'unary')) {
      final a = int.parse(entry['a']! as String);
      test('$a', () {
        expect(exact(() => negateExact(a)), entry['negateExact'], reason: 'negateExact');
        expect(signum(a), entry['signum'], reason: 'signum');
        expect(minorUnitsToString(a), entry['toString'], reason: 'toString');
      });
    }
  });

  test('binary: addExact and subtractExact on every pair', () {
    for (final entry in cases(file, 'binary')) {
      final a = int.parse(entry['a']! as String);
      final b = int.parse(entry['b']! as String);
      expect(exact(() => addExact(a, b)), entry['addExact'], reason: '$a + $b');
      expect(exact(() => subtractExact(a, b)), entry['subtractExact'], reason: '$a - $b');
    }
  });

  group('CurrencyTotals keeps currencies apart (rule 3.3)', () {
    test('two currencies are two totals, never one', () {
      final totals = CurrencyTotals()
        ..add('PLN', 1234)
        ..add('EUR', 500)
        ..add('PLN', -34);
      expect(totals.asMap(), {'EUR': 500, 'PLN': 1200});
    });

    test('a sum that leaves 64 bits is an error, not a wrapped balance', () {
      final totals = CurrencyTotals()..add('PLN', maxMinorUnits);
      expect(() => totals.add('PLN', 1), throwsA(isA<MoneyOverflow>()));
      expect(totals.of('PLN'), maxMinorUnits);
    });
  });
}
