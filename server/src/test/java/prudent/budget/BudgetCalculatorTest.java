package prudent.budget;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import prudent.proto.v1.BudgetSummaryResponse;
import prudent.proto.v1.CategoryBudgetSummary;

/**
 * The arithmetic behind a budget summary (M3, jlogicsoftware/prudent#59, ADR-044), without a
 * database: what plan, actual and remaining are for a given ledger net, and what the totals add up
 * to. Which records make up that net is asserted against the real query in
 * {@code BudgetSummaryTest}.
 */
class BudgetCalculatorTest {

  private static final YearMonth OCTOBER = YearMonth.of(2026, 10);

  private static BudgetEntity budget(UUID category, long amountMinor) {
    BudgetEntity entity = new BudgetEntity();
    entity.categoryId = category;
    entity.monthStart = OCTOBER.atDay(1);
    entity.currency = "PLN";
    entity.amountMinor = amountMinor;
    return entity;
  }

  private static BudgetSummaryResponse summarize(List<BudgetEntity> budgets, Map<UUID, Long> net) {
    return BudgetCalculator.summarize(OCTOBER, "PLN", budgets, net);
  }

  @Test
  void spendingWithinThePlanLeavesTheRest() {
    UUID food = UUID.randomUUID();

    CategoryBudgetSummary item =
        summarize(List.of(budget(food, 800_00L)), Map.of(food, -300_00L)).getItems(0);

    assertEquals(food.toString(), item.getCategoryId());
    assertEquals(800_00L, item.getPlanMinor());
    assertEquals(300_00L, item.getActualMinor());
    assertEquals(500_00L, item.getRemainingMinor());
  }

  @Test
  void overspendingIsANegativeRemainderNotAZero() {
    UUID food = UUID.randomUUID();

    CategoryBudgetSummary item =
        summarize(List.of(budget(food, 800_00L)), Map.of(food, -950_00L)).getItems(0);

    assertEquals(950_00L, item.getActualMinor());
    assertEquals(-150_00L, item.getRemainingMinor());
  }

  @Test
  void aNetPositiveLedgerIsNegativeSpendingAndRaisesTheRemainder() {
    UUID food = UUID.randomUUID();

    // Refunds outweighed spending in the month: the money that came back is not hidden by a floor
    // at zero, so the same records always give the same figures.
    CategoryBudgetSummary item =
        summarize(List.of(budget(food, 800_00L)), Map.of(food, 50_00L)).getItems(0);

    assertEquals(-50_00L, item.getActualMinor());
    assertEquals(850_00L, item.getRemainingMinor());
  }

  @Test
  void aCategoryWithNoRecordsHasSpentNothing() {
    UUID food = UUID.randomUUID();

    CategoryBudgetSummary item = summarize(List.of(budget(food, 800_00L)), Map.of()).getItems(0);

    assertEquals(0L, item.getActualMinor());
    assertEquals(800_00L, item.getRemainingMinor());
  }

  @Test
  void spendingInACategoryWithoutABudgetIsInNoItemAndNoTotal() {
    UUID food = UUID.randomUUID();
    UUID leisure = UUID.randomUUID();

    BudgetSummaryResponse response =
        summarize(List.of(budget(food, 800_00L)), Map.of(food, -100_00L, leisure, -999_00L));

    assertEquals(1, response.getItemsCount());
    assertEquals(100_00L, response.getTotalActualMinor());
  }

  @Test
  void totalsAreTheSumsOfTheItemsInTheOrderGiven() {
    UUID food = UUID.randomUUID();
    UUID rent = UUID.randomUUID();

    BudgetSummaryResponse response =
        summarize(
            List.of(budget(food, 800_00L), budget(rent, 2_500_00L)),
            Map.of(food, -900_00L, rent, -2_000_00L));

    assertEquals(food.toString(), response.getItems(0).getCategoryId());
    assertEquals(rent.toString(), response.getItems(1).getCategoryId());
    assertEquals(3_300_00L, response.getTotalPlanMinor());
    assertEquals(2_900_00L, response.getTotalActualMinor());
    // An overspent category and an underspent one net off in the total, as the sum they are.
    assertEquals(400_00L, response.getTotalRemainingMinor());
  }

  @Test
  void noBudgetsIsAnEmptySummaryOfZeros() {
    BudgetSummaryResponse response = summarize(List.of(), Map.of(UUID.randomUUID(), -100L));

    assertEquals("2026-10", response.getMonth());
    assertEquals("PLN", response.getCurrency());
    assertTrue(response.getItemsList().isEmpty());
    assertEquals(0L, response.getTotalPlanMinor());
    assertEquals(0L, response.getTotalActualMinor());
    assertEquals(0L, response.getTotalRemainingMinor());
  }

  @Test
  void anAmountThatOverflowsIsRefusedNotWrapped() {
    UUID food = UUID.randomUUID();

    assertThrows(
        ArithmeticException.class,
        () -> summarize(List.of(budget(food, 1L)), Map.of(food, Long.MIN_VALUE)));
  }
}
