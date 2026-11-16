// Rule 3.6 (phase-0 §0.3, ADR-090): the account-number normal form and identity token, held to the
// server's AccountNumbers.java by test/golden/account_numbers.json (mirrors AccountNumberTest).
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import 'golden.dart';

void main() {
  final file = golden('account_numbers.json');
  const errors = {ArgumentError: 'IllegalArgumentException'};

  for (final entry in cases(file, 'cases')) {
    final input = entry['input'] as String?;
    test(show(input), () {
      expect(AccountNumbers.canonical(input), entry['canonical'], reason: 'canonical');
      expect(
        AccountNumbers.normalizeOrNull(input),
        entry['normalizeOrNull'],
        reason: 'normalizeOrNull',
      );
      expect(
        attempt(() => AccountNumbers.normalize(input)),
        entry['normalize'],
        reason: 'normalize',
      );
      expect(
        attempt(() => AccountNumbers.identityOf(input), errors: errors),
        entry['identityOf'],
        reason: 'identityOf',
      );
    });
  }

  test('a refusal never carries the number', () {
    try {
      AccountNumbers.normalize('PL00 0000 ı');
      fail('should refuse');
    } on Refusal catch (refusal) {
      expect(refusal.toString(), isNot(contains('0000')));
    }
  });
}
