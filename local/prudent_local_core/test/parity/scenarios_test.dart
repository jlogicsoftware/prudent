// Every committed parity scenario parses and names the rules it covers. Running each one through the
// local backend without the live stack — every operation registered, every binding resolved, every
// stated server outcome met — is prudent_local_store's `test/parity/scenarios_local_test.dart`, since
// the local backend is the ledger over a real store (ADR-113). The comparison with the server is
// tools/prudent_parity_server's (task test:e2e).
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
    test(file.uri.pathSegments.last, () {
      final scenario = ParityScenario.parse(file.readAsStringSync());
      expect(
        '${scenario.name}.json',
        file.uri.pathSegments.last,
        reason: 'file name is the scenario name',
      );
      expect(scenario.rules, isNotEmpty);
    });
  }
}
