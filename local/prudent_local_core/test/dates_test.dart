// Rules 3.4 and 3.5 (phase-0 §0.3): ISO-8601 dates as LocalDate.parse reads them and months as
// BudgetResource.parseMonth reads them, held to the JVM by test/golden/dates.json.
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import 'golden.dart';

void main() {
  final file = golden('dates.json');

  group('dates', () {
    for (final entry in cases(file, 'dates')) {
      final input = entry['input'] as String?;
      test(show(input), () {
        expect(attempt(() => CivilDate.parse(input).toString()), entry['parse']);
      });
    }
  });

  group('months', () {
    for (final entry in cases(file, 'months')) {
      final input = entry['input'] as String?;
      test(show(input), () {
        expect(
          attempt(() {
            final month = CivilMonth.parse(input);
            return '$month|${month.firstDay}';
          }),
          entry['parse'],
        );
      });
    }
  });

  test('dates order by calendar, not by text', () {
    final dates = ['+10000-01-01', '2026-11-15', '-0001-12-31', '0000-01-01'].map(CivilDate.parse);
    expect(dates.toList()..sort(), [
      CivilDate.parse('-0001-12-31'),
      CivilDate.parse('0000-01-01'),
      CivilDate.parse('2026-11-15'),
      CivilDate.parse('+10000-01-01'),
    ]);
  });
}
