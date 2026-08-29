// Money parses and formats exactly (docs/prudent-migration-plan.md §2.1 / Phase 3 test list),
// including a value unrepresentable in binary floating point — the defect the int64 money type
// exists to remove. Nothing here goes through `double`.
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/money.dart';

void main() {
  group('parseMinorUnits', () {
    test('a plain integer amount', () {
      expect(parseMinorUnits('12'), Int64(1200));
    });

    test('two decimal places', () {
      expect(parseMinorUnits('12.34'), Int64(1234));
    });

    test('a comma decimal separator', () {
      expect(parseMinorUnits('12,34'), Int64(1234));
    });

    test('a single fraction digit is padded', () {
      expect(parseMinorUnits('12.3'), Int64(1230));
    });

    test('a value unrepresentable in binary floating point parses exactly', () {
      // 0.1 + 0.2 != 0.3 in binary floating point; the parser never touches `double`, so this
      // is not a special case for it.
      expect(parseMinorUnits('0.10')! + parseMinorUnits('0.20')!, Int64(30));
      expect(parseMinorUnits('0.30'), Int64(30));
    });

    test('a negative amount', () {
      expect(parseMinorUnits('-5.50'), Int64(-550));
    });

    test('rejects more than two fraction digits', () {
      expect(parseMinorUnits('12.345'), isNull);
    });

    test('rejects non-numeric input', () {
      expect(parseMinorUnits('abc'), isNull);
      expect(parseMinorUnits(''), isNull);
      expect(parseMinorUnits('12.34.56'), isNull);
    });

    test('an amount beyond a double\'s exact integer range stays exact', () {
      // 2^53 + 1 is the smallest integer a double cannot represent exactly.
      const beyondDouble = '90071992547409.92';
      final parsed = parseMinorUnits(beyondDouble);
      expect(parsed, Int64.parseInt('9007199254740992'));
    });
  });

  group('formatMinorUnits', () {
    test('formats whole and fractional amounts', () {
      expect(formatMinorUnits(Int64(1200)), '12.00');
      expect(formatMinorUnits(Int64(1234)), '12.34');
      expect(formatMinorUnits(Int64(5)), '0.05');
    });

    test('formats negative amounts', () {
      expect(formatMinorUnits(Int64(-550)), '-5.50');
    });

    test('round-trips through parseMinorUnits', () {
      for (final input in ['0.00', '1.00', '12.34', '999999.99', '-42.10']) {
        final parsed = parseMinorUnits(input)!;
        expect(formatMinorUnits(parsed), input);
      }
    });
  });
}
