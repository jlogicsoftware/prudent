// Overview totals (docs/prudent-migration-plan.md Phase 4): the flag combinations
// (inactive account, excluded from total, excluded from overview) and the multi-currency
// presentation (docs/DECISIONS.md ADR-009 — per-currency, never blended).
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/overview/overview_totals.dart';

Account _account({
  required String name,
  bool isActive = true,
  bool includeInTotal = true,
  bool includeInOverview = true,
  List<CurrencyBalance> balances = const [],
}) => Account(
  id: name,
  name: name,
  type: AccountType.ACCOUNT_TYPE_CASH,
  isActive: isActive,
  includeInTotal: includeInTotal,
  includeInOverview: includeInOverview,
  balances: balances,
);

CurrencyBalance _balance(String currency, int amountMinor) =>
    CurrencyBalance(currency: currency, amountMinor: Int64(amountMinor));

void main() {
  group('totalsByCurrency', () {
    test('sums balances across accounts in the same currency', () {
      final accounts = [
        _account(name: 'Wallet', balances: [_balance('PLN', 10000)]),
        _account(name: 'Bank', balances: [_balance('PLN', 5000)]),
      ];
      expect(totalsByCurrency(accounts, null), {'PLN': Int64(15000)});
    });

    test('an inactive account is excluded from the total', () {
      final accounts = [
        _account(name: 'Active', balances: [_balance('PLN', 10000)]),
        _account(name: 'Archived', isActive: false, balances: [_balance('PLN', 999900)]),
      ];
      expect(totalsByCurrency(accounts, null), {'PLN': Int64(10000)});
    });

    test('an account excluded from the total (includeInTotal=false) does not contribute', () {
      final accounts = [
        _account(name: 'Counted', balances: [_balance('PLN', 10000)]),
        _account(name: 'Excluded', includeInTotal: false, balances: [_balance('PLN', 500000)]),
      ];
      expect(totalsByCurrency(accounts, null), {'PLN': Int64(10000)});
    });

    test('includeInOverview does not affect the total — the two flags are independent', () {
      final accounts = [
        _account(name: 'Hidden from overview', includeInOverview: false, balances: [_balance('PLN', 10000)]),
      ];
      expect(totalsByCurrency(accounts, null), {'PLN': Int64(10000)});
    });

    test('never blended: different currencies stay in separate entries', () {
      final accounts = [
        _account(name: 'PLN wallet', balances: [_balance('PLN', 10000)]),
        _account(name: 'USD wallet', balances: [_balance('USD', 5000)]),
      ];
      final totals = totalsByCurrency(accounts, null);
      expect(totals, {'PLN': Int64(10000), 'USD': Int64(5000)});
      expect(totals.values.fold<Int64>(Int64.ZERO, (a, b) => a + b), Int64(15000),
          reason: 'sanity: this sum is never rendered as a single figure by the screen');
    });

    test('main currency is ordered first', () {
      final accounts = [
        _account(name: 'Wallet', balances: [_balance('PLN', 10000), _balance('USD', 5000), _balance('EUR', 2000)]),
      ];
      final totals = totalsByCurrency(accounts, 'EUR');
      expect(totals.keys.first, 'EUR');
    });

    test('the empty case: no eligible accounts is an empty map, not a zero total', () {
      final accounts = [
        _account(name: 'Archived', isActive: false, balances: [_balance('PLN', 10000)]),
      ];
      expect(totalsByCurrency(accounts, null), isEmpty);
    });
  });

  group('accountsForOverview', () {
    test('an inactive account is excluded', () {
      final accounts = [_account(name: 'A', isActive: false)];
      expect(accountsForOverview(accounts), isEmpty);
    });

    test('an account with includeInOverview=false is excluded', () {
      final accounts = [_account(name: 'A', includeInOverview: false)];
      expect(accountsForOverview(accounts), isEmpty);
    });

    test('includeInTotal does not affect overview visibility', () {
      final accounts = [_account(name: 'A', includeInTotal: false)];
      expect(accountsForOverview(accounts), hasLength(1));
    });
  });
}
