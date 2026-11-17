@TestOn('vm')
@Timeout(Duration(minutes: 20))
library;

// Unit 7's large synthetic ledger (ADR-118): thousands of records over six years, edited and
// deleted in part, then every analytics question answered by the live server and by Local's
// analytics over a real store, and compared to the cent. The ledger is built here, not committed,
// because `spend-by-period` is relative to "now" in UTC.
//
// Run by `task test:e2e` beside parity_test.dart, with ZEN_API_URL naming the live server. Without
// it this suite FAILS rather than skips.
//
// The ledger is seeded but its dates are relative to today (UTC), so a failure repeats only on the same
// UTC day.
//
// One honest limit: the server resolves "now" per request and Local resolves it per request too, so
// a run that crosses midnight UTC at a month's end compares two different windows and fails; rerun.
import 'dart:io';

import 'package:prudent_local_core/parity.dart';
import 'package:prudent_local_store/parity.dart';
import 'package:prudent_parity_server/server_backend.dart';
import 'package:test/test.dart';

void main() {
  final baseUrl = Platform.environment['ZEN_API_URL'];

  test('the live server is named', () {
    expect(baseUrl, isNotNull, reason: 'ZEN_API_URL must name the live server (task test:e2e)');
  });

  test('the large ledger: server and local agree on every figure', () async {
    final session = await ServerSession.register(baseUrl!);
    try {
      final scenario = AnalyticsScenarios.large(today: DateTime.now().toUtc());
      final clock = Stopwatch()..start();
      final report = await ParityEngine(
        server: ServerBackend(session),
        local: StoreBackend(),
      ).run(scenario);
      // ignore: avoid_print
      print('${scenario.steps.length} steps, server and local, in ${clock.elapsed}');
      expect(report.matches, isTrue, reason: report.describe());
    } finally {
      session.close();
    }
  });
}
