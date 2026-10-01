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
      response.addItems(
          CategoryBudgetSummary.newBuilder()
              .setCategoryId(budget.categoryId.toString())
              .setPlanMinor(plan)
              .setActualMinor(actual)
              .setCarryOverMinor(carryOver)
              .setRemainingMinor(Math.addExact(carryOver, Math.subtractExact(plan, actual))));
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
    Map<UUID, Long> carry = new HashMap<>();
    for (BudgetEntity budget : earlierBudgets) {
      long net =
          netByCategoryAndMonth
              .getOrDefault(budget.categoryId, Map.of())
              .getOrDefault(budget.month(), 0L);
      carry.merge(budget.categoryId, Math.addExact(budget.amountMinor, net), Math::addExact);
    }
    return carry;
  }
}
