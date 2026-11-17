// The parity clock (finding F-07, ADR-119): a scenario names dates relative to today in a zone, both
// backends read the same one, and a scenario that straddled a zone's midnight is run again rather
// than reported as a difference nobody caused.
import 'package:prudent_local_core/parity.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

void main() {
  // 2026-11-16 23:30 UTC: already the 17th in Warsaw (UTC+1), still the 16th in Pago Pago (UTC−11).
  final now = DateTime.utc(2026, 11, 16, 23, 30);

  test('a token is today in its zone, plus or minus days, through maps and lists', () {
    final clock = ParityClock(now: now, wall: () => now);
    expect(clock.expand('@today(UTC)'), '2026-11-16');
    expect(clock.expand('@today(Europe/Warsaw)'), '2026-11-17');
    expect(clock.expand('@today(Pacific/Pago_Pago)-1'), '2026-11-15');
    expect(clock.expand('@today(Pacific/Kiritimati)+2'), '2026-11-19');
    expect(
      clock.expand({
        'a': ['@today(UTC)+30', 7, null],
        'b': 'plain',
      }),
      {
        'a': ['2026-12-16', 7, null],
        'b': 'plain',
      },
    );
  });

  test('a token that names no plan zone is refused, never read as UTC', () {
    final clock = ParityClock(now: now, wall: () => now);
    expect(() => clock.expand('@today(+02:00)'), throwsFormatException);
    expect(() => clock.expand('@today(Mars/Olympus)'), throwsFormatException);
  });

  test('it says whether a named zone passed midnight since it was pinned', () {
    var wall = now;
    final clock = ParityClock(now: now, wall: () => wall);
    clock.expand('@today(Europe/Warsaw)');
    expect(clock.crossedMidnight, isFalse);
    wall = DateTime.utc(2026, 11, 17, 22, 59); // Warsaw is still on the 17th
    expect(clock.crossedMidnight, isFalse);
    wall = DateTime.utc(2026, 11, 17, 23); // and now it is the 18th there
    expect(clock.crossedMidnight, isTrue);
  });

  test('a zone no step named cannot make a scenario run again', () {
    var wall = now;
    final clock = ParityClock(now: now, wall: () => wall);
    clock.expand('@today(UTC)');
    wall = DateTime.utc(2026, 11, 17, 5);
    expect(clock.crossedMidnight, isTrue, reason: 'UTC is named, and it passed midnight');
    final unnamed = ParityClock(now: now, wall: () => wall);
    expect(unnamed.crossedMidnight, isFalse);
  });

  test('the dates a day apart in two zones 25 hours apart are never equal', () {
    for (var hour = 0; hour < 24; hour++) {
      for (final day in [1, 15, 28]) {
        final at = DateTime.utc(2026, 3, day, hour);
        final kiritimati = PlanZones.dayAt('Pacific/Kiritimati', at);
        final pago = PlanZones.dayAt('Pacific/Pago_Pago', at);
        expect(kiritimati.compareTo(pago), greaterThan(0), reason: '$at');
      }
    }
  });
}
