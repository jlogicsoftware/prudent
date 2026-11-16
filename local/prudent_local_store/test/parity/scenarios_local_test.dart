// Every committed parity scenario (local/prudent_local_core/parity/scenarios) runs through the local
// backend — the ledger over a real store — without the live stack: every operation is registered,
// every binding resolves, and every outcome a step states for the server is the local answer too. So
// a scenario that cannot pass is caught here, in seconds, before `task test:e2e` compares it with the
// server step by step (tools/prudent_parity_server).
import 'dart:io';

import 'package:prudent_local_core/parity.dart';
import 'package:prudent_local_store/parity.dart';
import 'package:test/test.dart';

void main() {
  final files =
      Directory('../prudent_local_core/parity/scenarios')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('there are scenarios', () => expect(files, isNotEmpty));

  for (final file in files) {
    test(file.uri.pathSegments.last, () async {
      final scenario = ParityScenario.parse(file.readAsStringSync());
      final local = StoreBackend();
      final bindings = ParityBindings();
      await local.open(scenario.name);
      try {
        for (final (index, step) in scenario.steps.indexed) {
          final op = local.ops[step.op];
          expect(op, isNotNull, reason: 'the local backend has no "${step.op}"');
          final result = await op!(step.input, bindings);
          if (step.outcome != null) {
            expect(
              result.observation['outcome'],
              step.outcome,
              reason: 'step $index ${step.op} ${step.input}: ${result.observation}',
            );
          }
          if (step.bindAs != null) bindings.bind(step.bindAs!, result.createdId!);
        }
      } finally {
        await local.close();
      }
    });
  }
}
