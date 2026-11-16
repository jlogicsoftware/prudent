@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

// The parity suite (ADR-107, unit 3 of docs/plans/PRUDENT-LOCAL-PLAN.md): every scenario in
// local/prudent_local_core/parity/scenarios runs through the live Quarkus server and through
// prudent_local_core, and every step's answer must be the same — figures to the cent, normalised
// text character for character, refusals by status.
//
// Run by `task test:e2e` after the server is healthy, with ZEN_API_URL pointing at it. Without the
// variable this suite FAILS rather than skips: a parity suite that quietly ran nothing would read as
// green.
import 'dart:io';

import 'package:prudent_local_core/parity.dart';
import 'package:prudent_parity_server/server_backend.dart';
import 'package:test/test.dart';

void main() {
  final baseUrl = Platform.environment['ZEN_API_URL'];
  final files =
      Directory('../../local/prudent_local_core/parity/scenarios')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('the live server is named and there are scenarios to run', () {
    expect(baseUrl, isNotNull, reason: 'ZEN_API_URL must name the live server (task test:e2e)');
    expect(files, isNotEmpty);
  });

  late ServerSession session;
  setUpAll(() async {
    if (baseUrl != null) session = await ServerSession.register(baseUrl);
  });
  tearDownAll(() {
    if (baseUrl != null) session.close();
  });

  for (final file in files) {
    test(file.uri.pathSegments.last, () async {
      final scenario = ParityScenario.parse(file.readAsStringSync());
      final report = await ParityEngine(
        server: ServerBackend(session),
        local: LocalRulesBackend(),
      ).run(scenario);
      expect(report.matches, isTrue, reason: report.describe());
    });
  }
}
