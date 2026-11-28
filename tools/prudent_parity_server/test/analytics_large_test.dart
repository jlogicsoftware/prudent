@TestOn('vm')
@Timeout(Duration(minutes: 20))
library;

// Unit 7's large synthetic ledger (ADR-118): thousands of records over six years, edited and
// deleted in part, then every analytics question answered by the live server and by Local's
// analytics over a real store, and compared to the cent. The ledger is built here, not committed,
// because `spend-by-period` is relative to "now" in UTC. Two empty answers would agree, so every
// answer of the server's must also hold a figure that reaches its window's edge.
//
// Run by `task test:e2e` beside parity_test.dart, with ZEN_API_URL naming the live server. Without
// it this suite FAILS rather than skips.
//
// **This run is deterministic only per UTC day.** The ledger is seeded, but its dates are relative to
// today (UTC), so a failure is repeated by running it again on the same UTC day, and may not be on a
// later one.
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
      final today = DateTime.now().toUtc();
      final scenario = AnalyticsScenarios.large(today: today);
      final server = _Figured(ServerBackend(session), today);
      final clock = Stopwatch()..start();
      final report = await ParityEngine(server: server, local: StoreBackend()).run(scenario);
      // ignore: avoid_print
      print('${scenario.steps.length} steps, server and local, in ${clock.elapsed}');
      expect(report.matches, isTrue, reason: report.describe());
      expect(server.shortfalls, isEmpty);
      expect(server.questions, greaterThan(0));
    } finally {
      session.close();
    }
  });
}

/// [inner], noting each analytics answer that holds nothing to compare
/// ([AnalyticsScenarios.shortfall]).
final class _Figured extends ParityBackend {
  _Figured(this.inner, this.today);

  final ParityBackend inner;
  final DateTime today;
  final shortfalls = <String>[];
  var questions = 0;

  @override
  String get name => inner.name;

  @override
  late final Map<String, ParityOp> ops = {
    for (final MapEntry(key: op, value: run) in inner.ops.entries)
      op: (input, bindings) async {
        final result = await run(input, bindings);
        if (op.startsWith('analytics.')) {
          questions++;
          final lack = AnalyticsScenarios.shortfall(op, input, result.observation, today: today);
          if (lack != null) shortfalls.add(lack);
        }
        return result;
      },
  };

  @override
  Future<void> open(String scenarioName) {
    inner.clock = clock;
    return inner.open(scenarioName);
  }

  @override
  Future<void> close() => inner.close();
}
