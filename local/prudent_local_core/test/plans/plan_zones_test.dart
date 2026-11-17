// Rules 6.31 and 6.42 (phase-0 §0.3): the zones a plan may name and the calendar day it is in one,
// held to the JVM by test/golden/plans.json (unit 6b, ADR-119).
import 'dart:io';

import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import '../../tool/generate_java_zone_ids.dart' show render;

import '../golden.dart';

void main() {
  final file = golden('plans.json');
  final ids = (file['zoneIds']! as List<Object?>).cast<String>();

  test('the committed zone file is what the generator writes (dart run tool/generate_java_zone_ids.dart)', () {
    expect(
      File('lib/src/plans/java_zone_ids.dart').readAsStringSync(),
      render(ids),
      reason: 'run: dart run tool/generate_java_zone_ids.dart',
    );
  });

  test('exactly the ids ZoneId.getAvailableZoneIds() answers are valid zones', () {
    for (final id in ids) {
      expect(PlanZones.isValid(id), !PlanZones.unsupported.contains(id), reason: id);
    }
    expect(
      ids,
      containsAll(PlanZones.unsupported),
      reason: 'only a zone the server accepts is refused here',
    );
    expect(attempt(() => PlanZones.parse('Africa/Casablanca')), {'refused': 400});
    for (final bad in [
      '',
      ' ',
      'Z',
      '+02:00',
      'GMT+2',
      'UTC+1',
      'EST',
      'europe/warsaw',
      'Europe/Warsaw ',
    ]) {
      expect(PlanZones.isValid(bad), isFalse, reason: show(bad));
      expect(attempt(() => PlanZones.parse(bad)), {'refused': 400}, reason: show(bad));
    }
  });

  test('the time-zone database resolves every id the server accepts', () {
    final unresolved = <String>[];
    for (final id in ids.where(PlanZones.isValid)) {
      try {
        PlanZones.dayAt(id, DateTime.utc(2026, 11, 16, 12));
      } on StateError {
        unresolved.add(id);
      }
    }
    expect(unresolved, isEmpty, reason: 'ids the server accepts that the local database lacks');
  });

  group('the calendar day in a zone, at each zone\'s own midnight', () {
    for (final entry in cases(file, 'days')) {
      final zone = entry['zone']! as String;
      final epochMs = int.parse(entry['epochMs']! as String);
      test('$zone at $epochMs', () {
        final instant = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
        expect(PlanZones.dayAt(zone, instant).toString(), entry['date']);
      });
    }
  });
}
