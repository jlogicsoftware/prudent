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

  private static BudgetEntity budgetIn(UUID category, YearMonth month, long amountMinor) {
    BudgetEntity entity = budget(category, amountMinor);
    entity.monthStart = month.atDay(1);
    return entity;
  }

  private static BudgetSummaryResponse summarize(List<BudgetEntity> budgets, Map<UUID, Long> net) {
    return BudgetCalculator.summarize(OCTOBER, "PLN", budgets, net, Map.of());
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

  // --- Carry-over (jlogicsoftware/prudent#60, ADR-045) ---------------------------------------

  @Test
  void anUnderspendCarriesForwardAndAnOverspendCarriesForwardNegative() {
    UUID food = UUID.randomUUID();
    UUID rent = UUID.randomUUID();
    YearMonth august = YearMonth.of(2026, 8);

    Map<UUID, Long> carry =
        BudgetCalculator.carryOver(
            List.of(budgetIn(food, august, 800_00L), budgetIn(rent, august, 100_00L)),
            Map.of(food, Map.of(august, -300_00L), rent, Map.of(august, -130_00L)));

    assertEquals(500_00L, carry.get(food));
    assertEquals(-30_00L, carry.get(rent));
  }

  @Test
  void carryOverAccumulatesAcrossEveryEarlierBudgetedMonth() {
    UUID food = UUID.randomUUID();

    Map<UUID, Long> carry =
        BudgetCalculator.carryOver(
            List.of(
                budgetIn(food, YearMonth.of(2026, 7), 100_00L),
                budgetIn(food, YearMonth.of(2026, 8), 100_00L),
                budgetIn(food, YearMonth.of(2026, 9), 100_00L)),
            Map.of(
                food,
                Map.of(
                    YearMonth.of(2026, 7), -60_00L,
                    YearMonth.of(2026, 8), -150_00L,
                    YearMonth.of(2026, 9), -10_00L)));

    // +40, -50, +90 = +80
    assertEquals(80_00L, carry.get(food));
  }

  @Test
  void aGapMonthContributesNothingSoTheFigurePassesAcrossIt() {
    UUID food = UUID.randomUUID();

    // Budgeted in July and September only; August has spending but no budget, so it is not a
    // month the carry measures and cannot change it.
    Map<UUID, Long> carry =
        BudgetCalculator.carryOver(
            List.of(
                budgetIn(food, YearMonth.of(2026, 7), 100_00L),
                budgetIn(food, YearMonth.of(2026, 9), 100_00L)),
            Map.of(
                food,
                Map.of(
                    YearMonth.of(2026, 7), -70_00L,
                    YearMonth.of(2026, 8), -999_00L,
                    YearMonth.of(2026, 9), -100_00L)));

    assertEquals(30_00L, carry.get(food));
  }

  @Test
  void aBudgetedMonthWithNoSpendingCarriesItsWholePlan() {
    UUID food = UUID.randomUUID();

    Map<UUID, Long> carry =
        BudgetCalculator.carryOver(
            List.of(budgetIn(food, YearMonth.of(2026, 9), 250_00L)), Map.of());

    assertEquals(250_00L, carry.get(food));
  }

  @Test
  void carryOverIsPartOfRemainingAndOfTheTotals() {
    UUID food = UUID.randomUUID();
    UUID rent = UUID.randomUUID();

    BudgetSummaryResponse response =
        BudgetCalculator.summarize(
            OCTOBER,
            "PLN",
            List.of(budget(food, 800_00L), budget(rent, 500_00L)),
            Map.of(food, -300_00L, rent, -600_00L),
            Map.of(food, 100_00L, rent, -40_00L));

    CategoryBudgetSummary foodItem = response.getItems(0);
    assertEquals(100_00L, foodItem.getCarryOverMinor());
    assertEquals(600_00L, foodItem.getRemainingMinor());
    CategoryBudgetSummary rentItem = response.getItems(1);
    assertEquals(-40_00L, rentItem.getCarryOverMinor());
    assertEquals(-140_00L, rentItem.getRemainingMinor());
    assertEquals(60_00L, response.getTotalCarryOverMinor());
    assertEquals(460_00L, response.getTotalRemainingMinor());
  }

  @Test
  void aFirstBudgetedMonthCarriesNothing() {
    UUID food = UUID.randomUUID();

    CategoryBudgetSummary item = summarize(List.of(budget(food, 800_00L)), Map.of()).getItems(0);

    assertEquals(0L, item.getCarryOverMinor());
    assertEquals(800_00L, item.getRemainingMinor());
  }
}
