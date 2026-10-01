import 'package:flutter/foundation.dart';

/// One calendar month, the unit a budget covers (budgets.proto: a budget has no day to choose).
///
/// A value type rather than a `DateTime` so that "the month before" and "the month after" are
/// stated once, and so a day of the month can never leak into the request: [wire] is exactly the
/// `YYYY-MM` the server's `month` parameter takes.
@immutable
class BudgetMonth {
  /// [month] is 1–12; any other value is normalised by `DateTime`, so `BudgetMonth(2026, 13)` is
  /// January 2027 — which is what makes [next] and [previous] one line each.
  BudgetMonth(int year, int month) : this._(DateTime(year, month));

  /// The month [moment] falls in.
  BudgetMonth.of(DateTime moment) : this(moment.year, moment.month);

  const BudgetMonth._(this.firstDay);

  /// The first day of the month, at local midnight — what a date formatter is given.
  final DateTime firstDay;

  int get year => firstDay.year;
  int get month => firstDay.month;

  BudgetMonth get previous => BudgetMonth(year, month - 1);
  BudgetMonth get next => BudgetMonth(year, month + 1);

  /// ISO-8601 `YYYY-MM`, as the budget endpoints take it.
  String get wire => '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is BudgetMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => wire;
}
