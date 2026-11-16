// Every committed parity scenario parses, names the rules it covers, and runs through the local
// backend without an unknown operation or a broken binding. The comparison with the server is
// tools/prudent_parity_server's (it needs the live stack, task test:e2e).
import 'dart:io';

import 'package:prudent_local_core/parity.dart';
import 'package:test/test.dart';

void main() {
  final files =
      Directory('parity/scenarios')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('there are scenarios', () => expect(files, isNotEmpty));

  for (final file in files) {
    test(file.uri.pathSegments.last, () async {
      final scenario = ParityScenario.parse(file.readAsStringSync());
      expect(
        '${scenario.name}.json',
        file.uri.pathSegments.last,
        reason: 'file name is the scenario name',
      );
      final local = LocalRulesBackend();
      final bindings = ParityBindings();
      await local.open(scenario.name);
      for (final step in scenario.steps) {
        final op = local.ops[step.op];
        expect(op, isNotNull, reason: 'the local backend has no "${step.op}"');
        final result = await op!(step.input, bindings);
        if (step.outcome != null) {
          // The scenario's stated outcome is the server's; the local backend must agree with it here
          // already, so a scenario that cannot pass is caught without the live stack.
          expect(result.observation['outcome'], step.outcome, reason: '${step.op} ${step.input}');
        }
        if (step.bindAs != null) bindings.bind(step.bindAs!, result.createdId!);
      }
      await local.close();
    });
  }
}
