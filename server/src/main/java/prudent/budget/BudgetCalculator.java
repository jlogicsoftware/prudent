package prudent.budget;

import java.time.YearMonth;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import prudent.proto.v1.BudgetSummaryResponse;
import prudent.proto.v1.CategoryBudgetSummary;

/**
 * Plan, actual, carry-over and remaining amounts for one month in one currency (M3,
 * jlogicsoftware/prudent#59 and #60, ADR-044, ADR-045).
 *
 * <p>Pure arithmetic over values the caller has already fetched, so the rules can be tested
 * without a database and cannot read a row of another currency or another month: it is handed only
 * the budgets and the ledger net for the one slot it is asked about.
 */
final class BudgetCalculator {

  private BudgetCalculator() {}

  /**
   * @param budgets the budgets of the requested month and currency, already in the order the
   *     response should list them
   * @param netByCategory the signed sum of the ledger's ordinary records per category for the same
   *     month and currency — negative is net spending, and a category with no record is absent
   * @param carryOverByCategory what earlier months left per category, from {@link #carryOver}; a
   *     category with no earlier budget is absent and carries nothing
   */
  static BudgetSummaryResponse summarize(
      YearMonth month,
      String currency,
      List<BudgetEntity> budgets,
      Map<UUID, Long> netByCategory,
      Map<UUID, Long> carryOverByCategory) {
    return summarize(month, currency, budgets, netByCategory, carryOverByCategory, Map.of());
  }

  /**
   * @param resetMonthByCategory the month of the live reset that bounds each category's carry-over,
   *     from {@link #resetMonths}; a category with none is absent. Reported on its item so a
   *     carry-over that a reset cut short is visibly so.
   */
  static BudgetSummaryResponse summarize(
      YearMonth month,
      String currency,
      List<BudgetEntity> budgets,
      Map<UUID, Long> netByCategory,
      Map<UUID, Long> carryOverByCategory,
      Map<UUID, YearMonth> resetMonthByCategory) {
    BudgetSummaryResponse.Builder response =
        BudgetSummaryResponse.newBuilder().setMonth(month.toString()).setCurrency(currency);
    long totalPlan = 0;
    long totalActual = 0;
    long totalCarryOver = 0;
    for (BudgetEntity budget : budgets) {
      long plan = budget.amountMinor;
      // Spending is money out, so the ledger's signed net is negated once, here: a positive
      // "actual" is net spending everywhere downstream. A refund is money back in, so it lands on
      // the other side of the same sum and reduces the spending it refunds.
      long actual = Math.negateExact(netByCategory.getOrDefault(budget.categoryId, 0L));
      long carryOver = carryOverByCategory.getOrDefault(budget.categoryId, 0L);
      CategoryBudgetSummary.Builder item =
          CategoryBudgetSummary.newBuilder()
              .setCategoryId(budget.categoryId.toString())
              .setPlanMinor(plan)
              .setActualMinor(actual)
              .setCarryOverMinor(carryOver)
              .setRemainingMinor(Math.addExact(carryOver, Math.subtractExact(plan, actual)));
      YearMonth resetMonth = resetMonthByCategory.get(budget.categoryId);
      if (resetMonth != null) {
        item.setCarryOverResetMonth(resetMonth.toString());
      }
      response.addItems(item);
      totalPlan = Math.addExact(totalPlan, plan);
      totalActual = Math.addExact(totalActual, actual);
      totalCarryOver = Math.addExact(totalCarryOver, carryOver);
    }
    return response
        .setTotalPlanMinor(totalPlan)
        .setTotalActualMinor(totalActual)
        .setTotalCarryOverMinor(totalCarryOver)
        .setTotalRemainingMinor(
            Math.addExact(totalCarryOver, Math.subtractExact(totalPlan, totalActual)))
        .build();
  }

  /**
   * What each category's earlier budgeted months left over, positive for underspend and negative
   * for overspend (M3, jlogicsoftware/prudent#60, ADR-045): the sum of {@code plan - actual} over
   * every earlier budget, which is {@code plan + net} because the ledger's net is signed.
   *
   * <p>It is a plain sum over the months that <em>have</em> a budget, so it is deterministic and
   * order-independent: a month with no budget contributes nothing and the figure passes across it
   * unchanged, however long the gap, and an edit to any earlier budget or record changes every
   * later figure on the next read because nothing is stored.
   *
   * @param earlierBudgets the budgets of the months before the one being summarized, one currency
   * @param netByCategoryAndMonth the ledger's signed net per category and month for the same
   *     currency; a category and month with no record are absent
   */
  static Map<UUID, Long> carryOver(
      List<BudgetEntity> earlierBudgets, Map<UUID, Map<YearMonth, Long>> netByCategoryAndMonth) {
    return carryOver(earlierBudgets, netByCategoryAndMonth, Map.of());
  }

  /**
   * As {@link #carryOver(List, Map)}, counting a category only from its reset month on (M3,
   * jlogicsoftware/prudent#61, ADR-046): a budgeted month before the category's reset contributes
   * nothing, as if the figure had started again there. The budgets themselves are untouched; they
   * are simply not summed. A category with no reset is counted from its first budget, as before.
   *
   * @param resetMonthByCategory from {@link #resetMonths}, already limited to resets at or before
   *     the month being summarized
   */
  static Map<UUID, Long> carryOver(
      List<BudgetEntity> earlierBudgets,
      Map<UUID, Map<YearMonth, Long>> netByCategoryAndMonth,
      Map<UUID, YearMonth> resetMonthByCategory) {
    Map<UUID, Long> carry = new HashMap<>();
    for (BudgetEntity budget : earlierBudgets) {
      YearMonth resetMonth = resetMonthByCategory.get(budget.categoryId);
      if (resetMonth != null && budget.month().isBefore(resetMonth)) {
        continue;
      }
      long net =
          netByCategoryAndMonth
              .getOrDefault(budget.categoryId, Map.of())
              .getOrDefault(budget.month(), 0L);
      carry.merge(budget.categoryId, Math.addExact(budget.amountMinor, net), Math::addExact);
    }
    return carry;
  }

  /**
   * The effective reset month per category: the latest of its live resets. Two live resets in one
   * category (different months) are both boundaries, and the later one is the one the figure
   * restarts from, because everything it excludes the earlier one excludes too.
   */
  static Map<UUID, YearMonth> resetMonths(List<BudgetCarryResetEntity> liveResets) {
    Map<UUID, YearMonth> latest = new HashMap<>();
    for (BudgetCarryResetEntity reset : liveResets) {
      latest.merge(reset.categoryId, reset.month(), (a, b) -> a.isAfter(b) ? a : b);
    }
    return latest;
  }
}
