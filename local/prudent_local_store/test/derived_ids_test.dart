// The ids derived from natural keys (ADR-102 D3). The encoding is frozen: two devices on two app
// versions must derive the same id, so these vectors may never change. They were cross-checked
// against an independent implementation of the documented encoding
// (SHA-256 of length-prefixed "prudent-local/derived-id/v1", kind, components; first 128 bits).
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:test/test.dart';

const a = '0123456789abcdef0123456789abcdef';
const b = 'fedcba9876543210fedcba9876543210';

void main() {
  test('one pinned vector per kind', () {
    expect(DerivedIds.accountCurrency(a, 'PLN'), '16848b7a199c711bc6a3ffda6a3d6b86');
    expect(DerivedIds.budget(a, '2026-11', 'EUR'), '73b2ba66bf9b2034ea031a354d5d1ae1');
    expect(DerivedIds.occurrence(a, '2026-12-01'), 'a080b8322560bfa60fc4a4dde18aa212');
    expect(DerivedIds.confirmation(b), '65a9153226368fc5128b77053f697265');
    expect(DerivedIds.imported(a, 'v1:abc', 2), 'b31eeecda5754247b1ee6ea2bb1da2a1');
    expect(DerivedIds.starterCategory('groceries'), '2ad37f80647cf95a81cbd1db1aab00b4');
    expect(DerivedIds.transferLeg(b, source: true), '9bf004f78085756ab667c7f3e03cfd00');
    expect(DerivedIds.transferLeg(b, source: false), '8dcce47a393cf98d5fd2a6452a0c9a8e');
    expect(
      DerivedIds.goalRepair(a, 'allocate_deficit', [b, a]),
      '62503cad4315962dabd881067a5a9bba',
    );
    expect(DerivedIds.settings, 'settings');
  });

  test('every derived id has the form of a local id', () {
    for (final id in [
      DerivedIds.accountCurrency(a, 'PLN'),
      DerivedIds.budget(a, '2026-11', 'EUR'),
      DerivedIds.occurrence(a, '2026-12-01'),
      DerivedIds.confirmation(b),
      DerivedIds.imported(a, 'x', 1),
      DerivedIds.starterCategory('k'),
    ]) {
      expect(LocalIds.isValid(id), isTrue, reason: id);
    }
  });

  test('kinds and component boundaries never collide', () {
    // The same components under two kinds, and two splits of one string, give different ids.
    expect(DerivedIds.occurrence(a, '2026-12-01'), isNot(DerivedIds.confirmation(a)));
    expect(DerivedIds.imported(a, 'ab', 1), isNot(DerivedIds.imported(a, 'a', 1)));
    expect(DerivedIds.starterCategory('ab'), isNot(DerivedIds.starterCategory('a')));
    // A repair is one record whatever order the entries were read in, and another set is another.
    expect(
      DerivedIds.goalRepair(a, 'withdraw_all', [a, b]),
      DerivedIds.goalRepair(a, 'withdraw_all', [b, a]),
    );
    expect(
      DerivedIds.goalRepair(a, 'withdraw_all', [a, b]),
      isNot(DerivedIds.goalRepair(a, 'withdraw_all', [a])),
    );
    expect(
      DerivedIds.goalRepair(a, 'withdraw_all', [b]),
      isNot(DerivedIds.goalRepair(a, 'allocate_deficit', [b])),
    );
    expect(
      DerivedIds.transferLeg(a, source: true),
      isNot(DerivedIds.transferLeg(a, source: false)),
    );
  });

  test('a key spelled any way but the canonical one is refused, never derived twice', () {
    for (final spelling in <void Function()>[
      () => DerivedIds.accountCurrency(a.toUpperCase(), 'PLN'),
      () => DerivedIds.accountCurrency('0123', 'PLN'),
      () => DerivedIds.accountCurrency(a, 'pln'),
      () => DerivedIds.accountCurrency(a, 'XYZ'),
      () => DerivedIds.budget(a, '2026-1', 'PLN'),
      () => DerivedIds.budget(a, '2026-13', 'PLN'),
      () => DerivedIds.occurrence(a, '2026-12-1'),
      () => DerivedIds.occurrence(a, '2026-02-30'),
      () => DerivedIds.imported(a, '', 1),
      () => DerivedIds.imported(a, 'x', 0),
      () => DerivedIds.goalRepair(a, 'withdraw_all', const []),
      () => DerivedIds.goalRepair(a, '', [b]),
      () => DerivedIds.goalRepair(a, 'withdraw_all', [b.toUpperCase()]),
      () => DerivedIds.starterCategory(''),
    ]) {
      expect(spelling, throwsArgumentError);
    }
  });
}
