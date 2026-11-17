// The large synthetic ledger of unit 7 (ADR-114) through the local backend alone: every step is
// accepted, and how long Local takes is printed. The comparison with the server's figures is
// tools/prudent_parity_server's `analytics_large_test.dart`.
@Timeout(Duration(minutes: 10))
library;

import 'package:prudent_local_core/parity.dart';
import 'package:prudent_local_store/parity.dart';
import 'package:test/test.dart';

void main() {
  test('the large ledger runs through the local backend', () async {
    final scenario = AnalyticsScenarios.large(today: DateTime.now().toUtc());
    final local = StoreBackend();
    final bindings = ParityBindings();
    await local.open(scenario.name);
    final clock = Stopwatch()..start();
    try {
      for (final (index, step) in scenario.steps.indexed) {
        final result = await local.ops[step.op]!(step.input, bindings);
        expect(
          result.observation['outcome'],
          step.outcome,
          reason: 'step $index ${step.op} ${step.input}: ${result.observation}',
        );
        if (step.bindAs != null) bindings.bind(step.bindAs!, result.createdId!);
      }
    } finally {
      await local.close();
    }
    // ignore: avoid_print
    print('${scenario.steps.length} steps in ${clock.elapsed}');
  });
}
