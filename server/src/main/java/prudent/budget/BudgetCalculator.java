package prudent.budget;

import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import prudent.proto.v1.BudgetSummaryResponse;
import prudent.proto.v1.CategoryBudgetSummary;

/**
 * Plan, actual and remaining amounts for one month in one currency (M3,
 * jlogicsoftware/prudent#59, ADR-044).
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
   */
  static BudgetSummaryResponse summarize(
      YearMonth month,
      String currency,
      List<BudgetEntity> budgets,
      Map<UUID, Long> netByCategory) {
    BudgetSummaryResponse.Builder response =
        BudgetSummaryResponse.newBuilder().setMonth(month.toString()).setCurrency(currency);
    long totalPlan = 0;
    long totalActual = 0;
    for (BudgetEntity budget : budgets) {
      long plan = budget.amountMinor;
      // Spending is money out, so the ledger's signed net is negated once, here: a positive
      // "actual" is net spending everywhere downstream. A refund is money back in, so it lands on
      // the other side of the same sum and reduces the spending it refunds.
      long actual = Math.negateExact(netByCategory.getOrDefault(budget.categoryId, 0L));
      response.addItems(
          CategoryBudgetSummary.newBuilder()
              .setCategoryId(budget.categoryId.toString())
              .setPlanMinor(plan)
              .setActualMinor(actual)
              .setRemainingMinor(Math.subtractExact(plan, actual)));
      totalPlan = Math.addExact(totalPlan, plan);
      totalActual = Math.addExact(totalActual, actual);
    }
    return response
        .setTotalPlanMinor(totalPlan)
        .setTotalActualMinor(totalActual)
        .setTotalRemainingMinor(Math.subtractExact(totalPlan, totalActual))
        .build();
  }
}
