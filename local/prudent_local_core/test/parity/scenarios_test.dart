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

  // The server's analytics sum every record of its one user in a currency, and the parity run shares
  // that user across scenarios (ADR-107): a scenario's figures are its own only while nobody else
  // writes in its currencies. analytics.json owns SEK, NOK and DKK; the generated large ledger owns
  // AnalyticsScenarios.currencies; both sets are reserved.
  test('the analytics currencies are used by their own scenarios and no other', () {
    const own = {'SEK', 'NOK', 'DKK'};
    final large = AnalyticsScenarios.currencies.toSet();
    expect(own.intersection(large), isEmpty);
    final currency = RegExp(
      r'"[A-Za-z ]*(?:SEK|NOK|DKK|CZK|HUF|ISK|RON)[A-Za-z ]*"',
      caseSensitive: false,
    );
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final text = file.readAsStringSync();
      if (name == 'analytics.json') continue;
      expect(
        currency.hasMatch(text),
        isFalse,
        reason: '$name uses a currency reserved for the analytics scenarios',
      );
    }
    // And the generated ledger uses nothing but its own.
    final generated = AnalyticsScenarios.large(today: DateTime.utc(2026, 11, 16), records: 200);
    for (final step in generated.steps) {
      for (final key in const ['currency', 'fromCurrency', 'toCurrency']) {
        final value = step.input[key];
        if (value != null) expect(large, contains(value), reason: '${step.op} uses $value');
      }
    }
    // analytics.json uses only its own.
    final scenario = ParityScenario.parse(
      File('parity/scenarios/analytics.json').readAsStringSync(),
    );
    for (final step in scenario.steps) {
      if (step.op.startsWith('analytics.') && step.outcome == 'refused') continue;
      for (final key in const ['currency', 'fromCurrency', 'toCurrency']) {
        final value = (step.input[key] as String?)?.trim().toUpperCase();
        if (value != null) expect(own, contains(value), reason: '${step.op} uses $value');
      }
    }
  });
}
