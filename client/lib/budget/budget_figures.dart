import 'package:fixnum/fixnum.dart';

import '../generated/prudent/v1/budgets.pb.dart';
import '../generated/prudent/v1/categories.pb.dart';

/// What the budget overview shows for one plan/actual/carry-over/remaining quartet — a category's,
/// or the month's totals. Derived from the server's figures and never a second calculation of
/// them: [remaining] is the server's, so the screen cannot disagree with the summary it was
/// given (ADR-044, ADR-045).
///
/// Pure, so the overspent and empty cases are testable without pumping a screen.
class BudgetFigures {
  const BudgetFigures({
    required this.plan,
    required this.actual,
    required this.carryOver,
    required this.remaining,
  });

  factory BudgetFigures.ofItem(CategoryBudgetSummary item) => BudgetFigures(
    plan: item.planMinor,
    actual: item.actualMinor,
    carryOver: item.carryOverMinor,
    remaining: item.remainingMinor,
  );

  factory BudgetFigures.ofTotals(BudgetSummaryResponse summary) => BudgetFigures(
    plan: summary.totalPlanMinor,
    actual: summary.totalActualMinor,
    carryOver: summary.totalCarryOverMinor,
    remaining: summary.totalRemainingMinor,
  );

  final Int64 plan;
  final Int64 actual;
  final Int64 carryOver;
  final Int64 remaining;

  /// What the month could spend: its own plan and what was carried in (ADR-045). The percentage
  /// is measured against this, because [remaining] is.
  Int64 get available => plan + carryOver;

  /// Spent beyond what was available. True for an overspend carried in from an earlier month too,
  /// even when nothing was spent this month — the figure to act on is the same.
  bool get isOverspent => remaining.isNegative;

  /// How far past the available amount the spending went; zero unless [isOverspent].
  Int64 get overspentBy => isOverspent ? -remaining : Int64.ZERO;

  /// Whole percent of [available] that [actual] used, rounded down so a month that has not quite
  /// used its money never reads as 100%. Over 100 once overspent. Zero when refunds outweigh
  /// spending (a negative actual is not "less than none used").
  ///
  /// `null` when there is nothing to measure against — the carry-over has consumed the whole
  /// plan, so [available] is zero or negative. A percentage of nothing would be a number the user
  /// could read as meaningful; the overspent state says what is true instead.
  int? get percentUsed {
    if (available <= Int64.ZERO) return null;
    if (actual <= Int64.ZERO) return 0;
    return (actual * 100 ~/ available).toInt();
  }
}

/// The summary's items in the order a user can scan: by category title, case-insensitively.
/// The server orders by category id, which is stable but meaningless to read.
///
/// A category missing from [categories] (not loaded yet, or deleted meanwhile — a budgeted one
/// cannot be, ADR-043) sorts under [unknownTitle], which is what the row will be labelled with.
List<CategoryBudgetSummary> budgetItemsByTitle(
  List<CategoryBudgetSummary> items,
  Map<String, Category> categories,
  String unknownTitle,
) {
  String title(CategoryBudgetSummary item) =>
      (categories[item.categoryId]?.title ?? unknownTitle).toLowerCase();
  return [...items]..sort((a, b) {
    final byTitle = title(a).compareTo(title(b));
    return byTitle != 0 ? byTitle : a.categoryId.compareTo(b.categoryId);
  });
}
