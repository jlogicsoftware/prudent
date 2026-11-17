@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

// Unit 10b's proof (ADR-103, ADR-123): a history built on the LIVE server, the server's own privacy
// export moved into an empty Prudent Local store exactly as the app moves a file in, and then every
// figure answered by both and compared to the cent — balances, records, budget summaries,
// carry-over, envelopes, free money, goal progress, occurrences, reminders and spend — and the same
// statement imported again is a duplicate on both.
//
// The scenario is local/prudent_local_core/parity/move_in/move_in.json. Its steps before `move_in`
// run on the server only (the history); `move_in` fetches the export, writes it to JSON text as the
// app saves it, reads it back with `MoveIn.read` and moves it in; every step after runs on both
// backends, the server's names carried over to the ids the export gave the Local store
// (`LocalIds.fromServerId`), and is compared with the parity engine's own rule.
//
// At run time the app checks only the balances (ADR-103); everything else is proven here, not by
// the app. Run by `task test:e2e` with ZEN_API_URL naming the live server; without it this suite
// FAILS rather than skips.
import 'dart:convert';
import 'dart:io';

import 'package:prudent_local_core/parity.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_local_store/parity.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_parity_server/server_backend.dart';
import 'package:test/test.dart';

void main() {
  final baseUrl = Platform.environment['ZEN_API_URL'];

  test('the live server is named', () {
    expect(baseUrl, isNotNull, reason: 'ZEN_API_URL must name the live server (task test:e2e)');
  });

  test('a history moved from the server agrees with the server on every figure', () async {
    final scenario = ParityScenario.parse(
      File('../../local/prudent_local_core/parity/move_in/move_in.json').readAsStringSync(),
    );
    final split = scenario.steps.indexWhere((step) => step.op == 'move_in');
    expect(split, greaterThan(0), reason: 'the scenario names the moment of the move');

    final session = await ServerSession.register(baseUrl!);
    final server = ServerBackend(session);
    final local = StoreBackend();
    final clock = ParityClock();
    server.clock = clock;
    local.clock = clock;
    final serverBindings = ParityBindings();
    final localBindings = ParityBindings();
    final differences = <ParityDifference>[];

    await server.open(scenario.name);
    await local.open(scenario.name);
    try {
      // ── The history, on the server only ─────────────────────────────────────────────────────
      for (var index = 0; index < split; index++) {
        final step = scenario.steps[index];
        final where = 'step ${index + 1} (${step.op})';
        final result = await server.ops[step.op]!(
          clock.expand(step.input)! as Map<String, Object?>,
          serverBindings,
        );
        expect(result.observation['outcome'], step.outcome ?? 'accepted', reason: '$where: ${result.observation}');
        if (step.bindAs != null) serverBindings.bind(step.bindAs!, result.createdId!);
      }

      // ── The move: the server's file, as a person saves it, read and moved in ────────────────
      final json = await session.privacyExport();
      final file = utf8.encode(const JsonEncoder.withIndent('  ').convert(json));
      final export = MoveIn.read(file);
      expect(export.recordImportKeys, hasLength(5), reason: 'the committed statement\'s keys');
      final moved = await local.moveIn(export);
      final summary = switch (moved) {
        MovedIn(:final summary) => summary,
        MoveInRefused(:final refusal) => fail('the server\'s export was refused: $refusal'),
      };
      expect(summary.importKeys, 5);
      expect(summary.droppedImportSessions, greaterThanOrEqualTo(1));
      for (final MapEntry(key: name, value: id) in serverBindings.entries.entries) {
        localBindings.bind(name, LocalIds.fromServerId(id));
      }

      // ── Every figure, on both ───────────────────────────────────────────────────────────────
      for (var index = split + 1; index < scenario.steps.length; index++) {
        final step = scenario.steps[index];
        final where = 'step ${index + 1} (${step.op})';
        final input = clock.expand(step.input)! as Map<String, Object?>;
        final serverResult = await server.ops[step.op]!(input, serverBindings);
        final localResult = await local.ops[step.op]!(input, localBindings);
        if (step.outcome != null && serverResult.observation['outcome'] != step.outcome) {
          differences.add(
            ParityDifference(
              where,
              'outcome (the scenario says the server must answer "${step.outcome}")',
              serverResult.observation['outcome'],
              step.outcome,
            ),
          );
        }
        differences.addAll(
          ParityEngine.differences(where, serverResult.observation, localResult.observation),
        );
        if (step.bindAs != null) {
          serverBindings.bind(step.bindAs!, serverResult.createdId!);
          localBindings.bind(step.bindAs!, localResult.createdId!);
        }
      }
    } finally {
      await local.close();
      await server.close();
      session.close();
    }
    expect(
      clock.crossedMidnight,
      isFalse,
      reason: 'a zone the scenario names passed midnight during the run; run it again',
    );
    expect(
      differences,
      isEmpty,
      reason: [
        'move_in: ${differences.length} difference(s) between server and local:',
        for (final d in differences) '  $d',
      ].join('\n'),
    );
  });
}
