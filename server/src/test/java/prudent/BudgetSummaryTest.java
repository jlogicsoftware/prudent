package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.plan.OccurrenceState;
import prudent.record.RecordEntity;
import prudent.proto.v1.BudgetSummaryResponse;
import prudent.proto.v1.CategoryBudgetSummary;
import zen.proto.v1.ZenError;

/**
 * Plan, actual and remaining amounts (M3, jlogicsoftware/prudent#59, ADR-044): which records make
 * up "actual" — posted expenses, net of refunds, in the requested month and currency only — and
 * that the request's month and currency are never widened.
 */
@QuarkusTest
class BudgetSummaryTest {

  private static final YearMonth OCTOBER = YearMonth.of(2026, 10);
  private static final LocalDate IN_OCTOBER = LocalDate.of(2026, 10, 14);

  private UUID wallet;
  private UUID food;
  private UUID rent;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    wallet = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN", "EUR");
    food = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
    rent = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
  }

  private static Response summaryResponse(String mode, String month, String currency) {
    var request = PrudentTest.request(mode);
    if (month != null) {
      request = request.queryParam("month", month);
    }
    if (currency != null) {
      request = request.queryParam("currency", currency);
    }
    return request.when().get("/api/v1/budgets/summary").andReturn();
  }

  private static BudgetSummaryResponse summary(String month, String currency) throws Exception {
    Response response = summaryResponse(PrudentTest.JSON, month, currency);
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, BudgetSummaryResponse.newBuilder())
        .build();
  }

  private static CategoryBudgetSummary item(BudgetSummaryResponse response, UUID category) {
    return response.getItemsList().stream()
        .filter(i -> i.getCategoryId().equals(category.toString()))
        .findFirst()
        .orElseThrow(() -> new AssertionError("no item for " + category));
  }

  private void spend(UUID category, long amountMinor, String currency, LocalDate date) {
    PrudentTest.seedRecord(PrudentTest.ALICE, wallet, category, amountMinor, currency, date);
  }

  // --- The arithmetic, end to end, in both transports ----------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void planActualAndRemainingRoundTripInBothTransports(String mode) throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    spend(food, -120_00L, "PLN", IN_OCTOBER);
    spend(food, -30_00L, "PLN", LocalDate.of(2026, 10, 20));

    Response response = summaryResponse(mode, "2026-10", "PLN");
    assertEquals(200, response.statusCode(), response.asString());
    BudgetSummaryResponse body =
        PrudentTest.decode(mode, response, BudgetSummaryResponse.newBuilder()).build();

    assertEquals("2026-10", body.getMonth());
    assertEquals("PLN", body.getCurrency());
    assertEquals(1, body.getItemsCount());
    CategoryBudgetSummary item = body.getItems(0);
    assertEquals(food.toString(), item.getCategoryId());
    assertEquals(800_00L, item.getPlanMinor());
    assertEquals(150_00L, item.getActualMinor());
    assertEquals(650_00L, item.getRemainingMinor());
    assertEquals(800_00L, body.getTotalPlanMinor());
    assertEquals(150_00L, body.getTotalActualMinor());
    assertEquals(650_00L, body.getTotalRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anOverspentCategoryHasANegativeRemainder() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 100_00L);
    spend(food, -130_00L, "PLN", IN_OCTOBER);

    CategoryBudgetSummary item = item(summary("2026-10", "PLN"), food);

    assertEquals(130_00L, item.getActualMinor());
    assertEquals(-30_00L, item.getRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aBudgetWithNoSpendingHasSpentNothing() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);

    CategoryBudgetSummary item = item(summary("2026-10", "PLN"), food);

    assertEquals(0L, item.getActualMinor());
    assertEquals(800_00L, item.getRemainingMinor());
  }

  // --- Posted expenses only ------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void transfersAndCorrectionsAreNotSpending() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    spend(food, -100_00L, "PLN", IN_OCTOBER);
    // Both rows are dated in the month and negative, exactly like an expense, and carry no category
    // — the two markers that keep them out of a budget.
    PrudentTest.seedTransferLeg(PrudentTest.ALICE, wallet, -500_00L, "PLN", UUID.randomUUID());
    PrudentTest.seedCorrection(PrudentTest.ALICE, wallet, -75_00L, "PLN");

    assertEquals(100_00L, item(summary("2026-10", "PLN"), food).getActualMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aPlannedOccurrenceIsNotSpendingUntilItIsConfirmed() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, rent, OCTOBER, "PLN", 2_500_00L);
    UUID plan = PrudentTest.seedPlan(PrudentTest.ALICE, wallet, rent, -2_500_00L, "PLN");
    PrudentTest.seedOccurrence(PrudentTest.ALICE, plan, IN_OCTOBER, OccurrenceState.PLANNED);
    PrudentTest.seedOccurrence(
        PrudentTest.ALICE, plan, LocalDate.of(2026, 10, 20), OccurrenceState.SKIPPED);

    CategoryBudgetSummary item = item(summary("2026-10", "PLN"), rent);

    assertEquals(0L, item.getActualMinor());
    assertEquals(2_500_00L, item.getRemainingMinor());
  }

  // --- Refunds -------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRefundInTheCategoryReducesActualAndRaisesRemaining() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    spend(food, -200_00L, "PLN", IN_OCTOBER);
    spend(food, 60_00L, "PLN", LocalDate.of(2026, 10, 18)); // a refund

    CategoryBudgetSummary item = item(summary("2026-10", "PLN"), food);

    assertEquals(140_00L, item.getActualMinor());
    assertEquals(660_00L, item.getRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRefundLandsInTheMonthItIsDatedNotTheMonthOfTheExpense() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, YearMonth.of(2026, 11), "PLN", 800_00L);
    spend(food, -200_00L, "PLN", IN_OCTOBER);
    spend(food, 200_00L, "PLN", LocalDate.of(2026, 11, 3));

    assertEquals(200_00L, item(summary("2026-10", "PLN"), food).getActualMinor());
    assertEquals(-200_00L, item(summary("2026-11", "PLN"), food).getActualMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRefundInAnotherCategoryDoesNotReduceThisOne() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, rent, OCTOBER, "PLN", 2_500_00L);
    spend(food, -100_00L, "PLN", IN_OCTOBER);
    spend(rent, 999_00L, "PLN", IN_OCTOBER);

    BudgetSummaryResponse body = summary("2026-10", "PLN");

    assertEquals(100_00L, item(body, food).getActualMinor());
    assertEquals(-999_00L, item(body, rent).getActualMinor());
  }

  // --- The month, the currency, the owner ----------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void onlyRecordsDatedInTheMonthCount_includingItsFirstAndLastDay() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    spend(food, -1_00L, "PLN", LocalDate.of(2026, 9, 30));
    spend(food, -10_00L, "PLN", LocalDate.of(2026, 10, 1));
    spend(food, -20_00L, "PLN", LocalDate.of(2026, 10, 31));
    spend(food, -40_00L, "PLN", LocalDate.of(2026, 11, 1));

    assertEquals(30_00L, item(summary("2026-10", "PLN"), food).getActualMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void currenciesAreNeverMixed() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "EUR", 200_00L);
    spend(food, -100_00L, "PLN", IN_OCTOBER);
    spend(food, -30_00L, "EUR", IN_OCTOBER);
    // A category budgeted only in PLN, with spending only in EUR: it is not in the EUR summary at
    // all, and its EUR spending is not netted against its PLN plan.
    PrudentTest.seedBudget(PrudentTest.ALICE, rent, OCTOBER, "PLN", 2_500_00L);
    spend(rent, -700_00L, "EUR", IN_OCTOBER);

    BudgetSummaryResponse pln = summary("2026-10", "PLN");
    BudgetSummaryResponse eur = summary("2026-10", "EUR");

    assertEquals(100_00L, item(pln, food).getActualMinor());
    assertEquals(0L, item(pln, rent).getActualMinor());
    assertEquals(3_300_00L, pln.getTotalPlanMinor());
    assertEquals(1, eur.getItemsCount());
    assertEquals(200_00L, eur.getItems(0).getPlanMinor());
    assertEquals(30_00L, eur.getItems(0).getActualMinor());
    assertEquals(170_00L, eur.getItems(0).getRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aLowerCaseCurrencyIsTheSameSummary() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);

    BudgetSummaryResponse body = summary("2026-10", "pln");

    assertEquals("PLN", body.getCurrency());
    assertEquals(1, body.getItemsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMonthWithNoBudgetsIsAnEmptySummary() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    spend(food, -100_00L, "PLN", LocalDate.of(2026, 12, 3));

    BudgetSummaryResponse body = summary("2026-12", "PLN");

    assertTrue(body.getItemsList().isEmpty());
    assertEquals(0L, body.getTotalPlanMinor());
    assertEquals(0L, body.getTotalActualMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendingInAnUnbudgetedCategoryIsNotListed() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    spend(rent, -2_000_00L, "PLN", IN_OCTOBER);

    BudgetSummaryResponse body = summary("2026-10", "PLN");

    assertEquals(1, body.getItemsCount());
    assertEquals(0L, body.getTotalActualMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void itsOrderIsByCategoryId() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, rent, OCTOBER, "PLN", 2_500_00L);

    BudgetSummaryResponse body = summary("2026-10", "PLN");

    String first = body.getItems(0).getCategoryId();
    String second = body.getItems(1).getCategoryId();
    assertTrue(first.compareTo(second) < 0, first + " should sort before " + second);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anotherUsersBudgetsAndRecordsAreNeverRead() throws Exception {
    UUID bobsWallet = PrudentTest.seedAccount(PrudentTest.BOB, "Wallet", "PLN");
    UUID bobsFood = PrudentTest.seedCategory(PrudentTest.BOB, "Food");
    PrudentTest.seedBudget(PrudentTest.BOB, bobsFood, OCTOBER, "PLN", 999_00L);
    PrudentTest.seedRecord(PrudentTest.BOB, bobsWallet, bobsFood, -500_00L, "PLN", IN_OCTOBER);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);

    BudgetSummaryResponse body = summary("2026-10", "PLN");

    assertEquals(1, body.getItemsCount());
    assertEquals(0L, body.getTotalActualMinor());
    assertEquals(800_00L, body.getTotalPlanMinor());
  }

  // --- Carry-over (jlogicsoftware/prudent#60, ADR-045) ---------------------------------------

  private static final YearMonth AUGUST = YearMonth.of(2026, 8);
  private static final YearMonth SEPTEMBER = YearMonth.of(2026, 9);
  private static final LocalDate IN_AUGUST = LocalDate.of(2026, 8, 12);
  private static final LocalDate IN_SEPTEMBER = LocalDate.of(2026, 9, 12);

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void anUnderspendAndAnOverspendCarryIntoTheNextMonthInBothTransports(String mode)
      throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, SEPTEMBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, rent, SEPTEMBER, "PLN", 100_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, rent, OCTOBER, "PLN", 100_00L);
    spend(food, -300_00L, "PLN", IN_SEPTEMBER);
    spend(rent, -130_00L, "PLN", IN_SEPTEMBER);
    spend(food, -50_00L, "PLN", IN_OCTOBER);

    Response response = summaryResponse(mode, "2026-10", "PLN");
    assertEquals(200, response.statusCode(), response.asString());
    BudgetSummaryResponse body =
        PrudentTest.decode(mode, response, BudgetSummaryResponse.newBuilder()).build();

    CategoryBudgetSummary foodItem = item(body, food);
    assertEquals(500_00L, foodItem.getCarryOverMinor());
    assertEquals(50_00L, foodItem.getActualMinor());
    assertEquals(1_250_00L, foodItem.getRemainingMinor());
    CategoryBudgetSummary rentItem = item(body, rent);
    assertEquals(-30_00L, rentItem.getCarryOverMinor());
    assertEquals(70_00L, rentItem.getRemainingMinor());
    assertEquals(470_00L, body.getTotalCarryOverMinor());
    assertEquals(1_320_00L, body.getTotalRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aFirstBudgetedMonthCarriesNothing() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    // Spending before the first budget is not measured against anything.
    spend(food, -900_00L, "PLN", IN_SEPTEMBER);

    CategoryBudgetSummary item = item(summary("2026-10", "PLN"), food);

    assertEquals(0L, item.getCarryOverMinor());
    assertEquals(800_00L, item.getRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aGapMonthPassesTheCarryAcrossUnchanged() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, AUGUST, "PLN", 800_00L);
    spend(food, -300_00L, "PLN", IN_AUGUST);
    // September has no budget, so its spending is not measured and changes nothing.
    spend(food, -999_00L, "PLN", IN_SEPTEMBER);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);

    CategoryBudgetSummary item = item(summary("2026-10", "PLN"), food);

    assertEquals(500_00L, item.getCarryOverMinor());
    assertEquals(1_300_00L, item.getRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void carryOverCrossesAYearBoundaryAndSpansEveryEarlierMonth() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, YearMonth.of(2026, 11), "PLN", 100_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, YearMonth.of(2026, 12), "PLN", 100_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, YearMonth.of(2027, 1), "PLN", 100_00L);
    spend(food, -60_00L, "PLN", LocalDate.of(2026, 11, 30));
    spend(food, -150_00L, "PLN", LocalDate.of(2026, 12, 1));
    spend(food, -10_00L, "PLN", LocalDate.of(2026, 12, 31));
    spend(food, -20_00L, "PLN", LocalDate.of(2027, 1, 1));

    CategoryBudgetSummary item = item(summary("2027-01", "PLN"), food);

    // +40 (Nov) and -60 (Dec); January's own 20 is the month's actual, not carried.
    assertEquals(-20_00L, item.getCarryOverMinor());
    assertEquals(20_00L, item.getActualMinor());
    assertEquals(60_00L, item.getRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void editingAHistoricalBudgetOrRecordRecalculatesTheLaterMonth() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, SEPTEMBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    UUID groceries =
        PrudentTest.seedRecord(PrudentTest.ALICE, wallet, food, -300_00L, "PLN", IN_SEPTEMBER);
    assertEquals(500_00L, item(summary("2026-10", "PLN"), food).getCarryOverMinor());

    // The earlier month's budget is raised: the later month follows on the next read.
    PrudentTest.seedBudget(PrudentTest.ALICE, food, SEPTEMBER, "PLN", 900_00L);
    assertEquals(600_00L, item(summary("2026-10", "PLN"), food).getCarryOverMinor());

    // A record in the earlier month is deleted: the overspend or underspend is recalculated.
    QuarkusTransaction.requiringNew().run(() -> RecordEntity.deleteById(groceries));
    CategoryBudgetSummary item = item(summary("2026-10", "PLN"), food);
    assertEquals(900_00L, item.getCarryOverMinor());
    assertEquals(1_700_00L, item.getRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void carryOverIsPerCategoryAndPerCurrency() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, SEPTEMBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, SEPTEMBER, "EUR", 100_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, rent, SEPTEMBER, "PLN", 2_500_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "EUR", 100_00L);
    spend(food, -300_00L, "PLN", IN_SEPTEMBER);
    spend(food, -40_00L, "EUR", IN_SEPTEMBER);
    spend(rent, -2_000_00L, "PLN", IN_SEPTEMBER);

    BudgetSummaryResponse pln = summary("2026-10", "PLN");
    BudgetSummaryResponse eur = summary("2026-10", "EUR");

    // Rent has no October budget, so it is not listed and its September underspend is not food's.
    assertEquals(1, pln.getItemsCount());
    assertEquals(500_00L, item(pln, food).getCarryOverMinor());
    assertEquals(500_00L, pln.getTotalCarryOverMinor());
    assertEquals(60_00L, item(eur, food).getCarryOverMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void refundsTransfersAndCorrectionsFollowTheSameRulesWhenCarried() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, SEPTEMBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    spend(food, -300_00L, "PLN", IN_SEPTEMBER);
    // A refund lowers September's spending; a transfer leg and a correction are not spending.
    spend(food, 100_00L, "PLN", IN_SEPTEMBER);
    PrudentTest.seedTransferLeg(PrudentTest.ALICE, wallet, -500_00L, "PLN", UUID.randomUUID());
    PrudentTest.seedCorrection(PrudentTest.ALICE, wallet, -75_00L, "PLN");

    assertEquals(600_00L, item(summary("2026-10", "PLN"), food).getCarryOverMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anotherUsersEarlierMonthsAreNeverCarried() throws Exception {
    UUID bobsWallet = PrudentTest.seedAccount(PrudentTest.BOB, "Wallet", "PLN");
    UUID bobsFood = PrudentTest.seedCategory(PrudentTest.BOB, "Food");
    PrudentTest.seedBudget(PrudentTest.BOB, bobsFood, SEPTEMBER, "PLN", 999_00L);
    PrudentTest.seedRecord(PrudentTest.BOB, bobsWallet, bobsFood, -50_00L, "PLN", IN_SEPTEMBER);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);

    assertEquals(0L, item(summary("2026-10", "PLN"), food).getCarryOverMinor());
  }

  // --- Refusals ------------------------------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {"2026-13", "2026-1", "202610", "2026-10-01", "October", ""})
  @TestSecurity(user = PrudentTest.ALICE)
  void aMalformedMonthIsRefused(String month) throws Exception {
    Response response = summaryResponse(PrudentTest.JSON, month, "PLN");

    assertEquals(400, response.statusCode(), response.asString());
    PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMissingMonthIsRefused() {
    assertEquals(400, summaryResponse(PrudentTest.JSON, null, "PLN").statusCode());
  }

  @ParameterizedTest
  @ValueSource(strings = {"ZLOTY", "PL", "12A", " "})
  @TestSecurity(user = PrudentTest.ALICE)
  void anInvalidCurrencyIsRefused(String currency) {
    assertEquals(400, summaryResponse(PrudentTest.JSON, "2026-10", currency).statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMissingCurrencyIsRefusedNotInferredOrSummed() {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "EUR", 200_00L);

    assertEquals(400, summaryResponse(PrudentTest.JSON, "2026-10", null).statusCode());
  }
}
