import 'package:fixnum/fixnum.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../generated/prudent/v1/plans.pb.dart';

/// How far ahead the overview looks for planned money. The overdue ones are added on top, so this
/// is "everything still expected that is due within a month", not a forecast horizon the user picks.
const int plannedCashFlowDays = 30;

/// Money still expected in one currency: [income] is positive, [spending] is negative (the wire's
/// own sign convention, ADR-014), so [net] is a plain sum and nothing needs translating.
class PlannedCashFlow {
  const PlannedCashFlow({required this.income, required this.spending});

  final Int64 income;
  final Int64 spending;

  Int64 get net => income + spending;
}

/// Sums the occurrences the user still expects — planned and overdue — by currency, for the
/// overview's planned section.
///
/// NEVER MERGED WITH ACTUAL BALANCES, and never blended across currencies (ADR-009): the result is
/// its own map and is drawn in its own section, because an occurrence is not a transaction until
/// the user confirms it (ADR-037, ADR-040). Completed and skipped occurrences are resolved — a
/// completed one is already a record and is in the balance, so counting it here would count it twice.
///
/// Only occurrences on an account that is active and `includeInTotal` count, the same rule the
/// totals above apply, so hiding an account from the total hides its planned money too. An
/// occurrence whose account is not in [accounts] (deleted meanwhile) is dropped rather than guessed.
///
/// A pure function, kept apart from the widget, so the state and account-flag combinations are
/// testable without pumping a screen.
Map<String, PlannedCashFlow> plannedCashFlowByCurrency(
  List<PlanOccurrence> occurrences,
  List<Account> accounts,
  String? mainCurrency,
) {
  final eligible = {
    for (final account in accounts)
      if (account.isActive && account.includeInTotal) account.id,
  };
  final income = <String, Int64>{};
  final spending = <String, Int64>{};
  for (final occurrence in occurrences) {
    final open =
        occurrence.status == OccurrenceStatus.OCCURRENCE_STATUS_PLANNED ||
        occurrence.status == OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE;
    if (!open || !eligible.contains(occurrence.accountId)) continue;
    final bucket = occurrence.amountMinor.isNegative ? spending : income;
    bucket.update(
      occurrence.currency,
      (sum) => sum + occurrence.amountMinor,
      ifAbsent: () => occurrence.amountMinor,
    );
  }

  final currencies = {...income.keys, ...spending.keys}.toList()..sort();
  if (mainCurrency != null && currencies.remove(mainCurrency)) currencies.insert(0, mainCurrency);
  return {
    for (final currency in currencies)
      currency: PlannedCashFlow(
        income: income[currency] ?? Int64.ZERO,
        spending: spending[currency] ?? Int64.ZERO,
      ),
  };
}
