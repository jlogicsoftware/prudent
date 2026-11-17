import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

void main() {
  group('SpendWindow', () {
    test('a month and a year are whole months', () {
      final march = SpendWindow.ofYearOrMonth(year: 2026, month: 3);
      expect(march.contains(2026, 3), isTrue);
      expect(march.contains(2026, 2), isFalse);
      expect(march.contains(2026, 4), isFalse);
      final year = SpendWindow.ofYearOrMonth(year: 2026, month: null);
      expect(year.contains(2026, 1), isTrue);
      expect(year.contains(2026, 12), isTrue);
      expect(year.contains(2025, 12), isFalse);
      expect(year.contains(2027, 1), isFalse);
    });

    test('a trailing month window crosses a year end', () {
      final window = SpendWindow.trailing(
        granularity: SpendGranularity.month,
        count: 3,
        anchorYear: 2026,
        anchorMonth: 1,
      );
      expect(window.contains(2025, 11), isTrue);
      expect(window.contains(2026, 1), isTrue);
      expect(window.contains(2025, 10), isFalse);
      expect(window.contains(2026, 2), isFalse);
    });

    test('a trailing year window ends with the whole current year', () {
      final window = SpendWindow.trailing(
        granularity: SpendGranularity.year,
        count: 2,
        anchorYear: 2026,
        anchorMonth: 1,
      );
      expect(window.contains(2025, 1), isTrue);
      expect(window.contains(2026, 12), isTrue);
      expect(window.contains(2024, 12), isFalse);
      expect(window.contains(2027, 1), isFalse);
    });

    test('the server\'s checks: year, month, count and granularity', () {
      Matcher refusal400() => throwsA(isA<Refusal>().having((r) => r.status, 'status', 400));
      expect(() => SpendWindow.ofYearOrMonth(year: null, month: 3), refusal400());
      expect(() => SpendWindow.ofYearOrMonth(year: 2026, month: 0), refusal400());
      expect(() => SpendWindow.ofYearOrMonth(year: 2026, month: 13), refusal400());
      expect(() => SpendWindow.ofYearOrMonth(year: 1000000000, month: null), refusal400());
      for (final count in [null, 0, 61, -1]) {
        expect(
          () => SpendWindow.trailing(
            granularity: SpendGranularity.month,
            count: count,
            anchorYear: 2026,
            anchorMonth: 1,
          ),
          refusal400(),
        );
      }
      expect(SpendWindow.parseGranularity('month'), SpendGranularity.month);
      expect(SpendWindow.parseGranularity('YEAR'), SpendGranularity.year);
      for (final bad in [null, '', 'WEEK', ' MONTH', 'MONTHS']) {
        expect(() => SpendWindow.parseGranularity(bad), refusal400());
      }
    });

    test('labels sort as the calendar does', () {
      expect(SpendWindow.label(SpendGranularity.month, 2026, 8), '2026-08');
      expect(SpendWindow.label(SpendGranularity.year, 2026, 8), '2026');
      expect(SpendWindow.label(SpendGranularity.month, 99, 1), '0099-01');
    });
  });
}
