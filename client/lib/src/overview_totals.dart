import 'package:fixnum/fixnum.dart';

import 'generated/prudent/v1/accounts.pb.dart';

/// Sums every `includeInTotal && isActive` account's balances by currency — the arithmetic behind
/// the Overview screen's totals section (docs/prudent-migration-plan.md Phase 4).
///
/// PER-CURRENCY, NEVER BLENDED (docs/DECISIONS.md ADR-009): Prudent does no FX, so there is no
/// single "total balance" figure — the result is a `Map`, one entry per currency actually held by
/// a total-eligible account, ordered with [mainCurrency] first when it is one of them.
///
/// A pure function, kept apart from the widget, so the flag combinations (inactive, excluded from
/// total, excluded from overview) are testable without pumping a screen.
Map<String, Int64> totalsByCurrency(List<Account> accounts, String? mainCurrency) {
  final totals = <String, Int64>{};
  for (final account in accounts) {
    if (!account.isActive || !account.includeInTotal) continue;
    for (final balance in account.balances) {
      totals.update(balance.currency, (sum) => sum + balance.amountMinor, ifAbsent: () => balance.amountMinor);
    }
  }
  if (mainCurrency == null || !totals.containsKey(mainCurrency)) return totals;
  final ordered = <String, Int64>{mainCurrency: totals[mainCurrency]!};
  for (final entry in totals.entries) {
    if (entry.key != mainCurrency) ordered[entry.key] = entry.value;
  }
  return ordered;
}

/// Accounts eligible for the Overview screen's account list — active and `includeInOverview`.
/// The same two-flag distinction [totalsByCurrency] applies, kept separate because a savings
/// account can be visible without counting toward spendable funds.
List<Account> accountsForOverview(List<Account> accounts) =>
    accounts.where((a) => a.isActive && a.includeInOverview).toList();
