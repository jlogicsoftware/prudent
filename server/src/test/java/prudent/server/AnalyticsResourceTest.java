package prudent.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.proto.v1.CategorySpend;
import prudent.proto.v1.Granularity;
import prudent.proto.v1.PeriodSpend;
import prudent.proto.v1.SpendByCategoryResponse;
import prudent.proto.v1.SpendByPeriodResponse;
import zen.proto.v1.ZenError;

/**
 * Prudent's analytics: spend by category, spend by period, and the rules analytics.proto states —
 * the empty case, the currency refusal, and period boundaries.
 */
@QuarkusTest
class AnalyticsResourceTest {

  private UUID accountId;
  private UUID food;
  private UUID leisure;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN", "EUR");
    food = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
    leisure = PrudentTest.seedCategory(PrudentTest.ALICE, "Leisure");
  }

  // -----------------------------------------------------------------------------------------
  // spend-by-category
  // -----------------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByCategory_theEmptyCase_isAnEmptyListNotAZero() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("year", 2026)
            .when()
            .get("/api/v1/analytics/spend-by-category")
            .andReturn();

    assertEquals(200, response.statusCode());
    SpendByCategoryResponse body =
        PrudentTest.decode(PrudentTest.JSON, response, SpendByCategoryResponse.newBuilder())
            .build();
    assertEquals("PLN", body.getCurrency());
    assertEquals(0, body.getItemsCount(), "no expenses in scope must be an empty list");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByCategory_sumsExpensesAndIgnoresIncome() throws Exception {
    // Two expenses in Food, one in Leisure, and one income row that must not appear at all —
    // "spend" means expense only (analytics.proto).
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -20_00L, "PLN", LocalDate.of(2026, 8, 5));
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -15_00L, "PLN", LocalDate.of(2026, 8, 20));
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, leisure, -10_00L, "PLN", LocalDate.of(2026, 8, 12));
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, 1000_00L, "PLN", LocalDate.of(2026, 8, 1));

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("year", 2026)
            .queryParam("month", 8)
            .when()
            .get("/api/v1/analytics/spend-by-category")
            .andReturn();

    SpendByCategoryResponse body =
        PrudentTest.decode(PrudentTest.JSON, response, SpendByCategoryResponse.newBuilder())
            .build();
    assertEquals(2, body.getItemsCount());
    long foodTotal =
        body.getItemsList().stream()
            .filter(item -> item.getCategoryId().equals(food.toString()))
            .mapToLong(CategorySpend::getAmountMinor)
            .findFirst()
            .orElseThrow();
    assertEquals(35_00L, foodTotal, "spend is a POSITIVE magnitude, not the signed ledger amount");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByCategory_aRecordOutsideTheMonth_isExcluded() throws Exception {
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -20_00L, "PLN", LocalDate.of(2026, 7, 31));
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -30_00L, "PLN", LocalDate.of(2026, 9, 1));

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("year", 2026)
            .queryParam("month", 8)
            .when()
            .get("/api/v1/analytics/spend-by-category")
            .andReturn();

    SpendByCategoryResponse body =
        PrudentTest.decode(PrudentTest.JSON, response, SpendByCategoryResponse.newBuilder())
            .build();
    assertEquals(0, body.getItemsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByCategory_theFirstAndLastDayOfTheMonth_areIncluded() throws Exception {
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -10_00L, "PLN", LocalDate.of(2026, 8, 1));
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -5_00L, "PLN", LocalDate.of(2026, 8, 31));

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("year", 2026)
            .queryParam("month", 8)
            .when()
            .get("/api/v1/analytics/spend-by-category")
            .andReturn();

    SpendByCategoryResponse body =
        PrudentTest.decode(PrudentTest.JSON, response, SpendByCategoryResponse.newBuilder())
            .build();
    assertEquals(1, body.getItemsCount());
    assertEquals(15_00L, body.getItems(0).getAmountMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByCategory_singleCurrency_othersAreExcludedRatherThanMixed() throws Exception {
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -20_00L, "PLN", LocalDate.of(2026, 8, 5));
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -20_00L, "EUR", LocalDate.of(2026, 8, 5));

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("year", 2026)
            .when()
            .get("/api/v1/analytics/spend-by-category")
            .andReturn();

    SpendByCategoryResponse body =
        PrudentTest.decode(PrudentTest.JSON, response, SpendByCategoryResponse.newBuilder())
            .build();
    assertEquals("PLN", body.getCurrency());
    assertEquals(1, body.getItemsCount());
    assertEquals(
        20_00L,
        body.getItemsList().stream().mapToLong(CategorySpend::getAmountMinor).sum(),
        "the EUR expense must not be added to the PLN total");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByCategory_missingCurrency_isRefusedRatherThanSummed() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("year", 2026)
            .when()
            .get("/api/v1/analytics/spend-by-category")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByCategory_missingYear_isRejected() {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .when()
            .get("/api/v1/analytics/spend-by-category")
            .andReturn();

    assertEquals(400, response.statusCode());
  }

  // -----------------------------------------------------------------------------------------
  // spend-by-period
  // -----------------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByPeriod_theEmptyCase_isAnEmptyListNotAZero() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("granularity", "MONTH")
            .queryParam("count", 12)
            .when()
            .get("/api/v1/analytics/spend-by-period")
            .andReturn();

    assertEquals(200, response.statusCode());
    SpendByPeriodResponse body =
        PrudentTest.decode(PrudentTest.JSON, response, SpendByPeriodResponse.newBuilder()).build();
    assertEquals(Granularity.GRANULARITY_MONTH, body.getGranularity());
    assertEquals(0, body.getPeriodsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByPeriod_bucketsByMonthAndOrdersOldestToNewest() throws Exception {
    LocalDate currentMonth = LocalDate.now(ZoneOffset.UTC).withDayOfMonth(1);
    LocalDate twoMonthsAgo = currentMonth.minusMonths(2);
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -10_00L, "PLN", twoMonthsAgo);
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -25_00L, "PLN", currentMonth);
    // A different currency in the same months must not be added into the PLN total.
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -99_00L, "EUR", currentMonth);

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("granularity", "MONTH")
            .queryParam("count", 12)
            .when()
            .get("/api/v1/analytics/spend-by-period")
            .andReturn();

    SpendByPeriodResponse body =
        PrudentTest.decode(PrudentTest.JSON, response, SpendByPeriodResponse.newBuilder()).build();
    assertEquals(2, body.getPeriodsCount(), "only the two PLN-bearing months, oldest to newest");
    List<PeriodSpend> periods = body.getPeriodsList();
    assertTrue(periods.get(0).getPeriod().compareTo(periods.get(1).getPeriod()) < 0);
    assertEquals(25_00L, periods.get(1).getAmountMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByPeriod_aRecordOutsideTheTrailingWindow_isExcluded() throws Exception {
    LocalDate currentMonth = LocalDate.now(ZoneOffset.UTC).withDayOfMonth(1);
    // 13 months back, with a 12-month window ending at the current month — one bucket too old.
    PrudentTest.seedRecord(
        PrudentTest.ALICE, accountId, food, -10_00L, "PLN", currentMonth.minusMonths(13));

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("granularity", "MONTH")
            .queryParam("count", 12)
            .when()
            .get("/api/v1/analytics/spend-by-period")
            .andReturn();

    SpendByPeriodResponse body =
        PrudentTest.decode(PrudentTest.JSON, response, SpendByPeriodResponse.newBuilder()).build();
    assertEquals(0, body.getPeriodsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByPeriod_yearGranularity() throws Exception {
    int thisYear = LocalDate.now(ZoneOffset.UTC).getYear();
    PrudentTest.seedRecord(
        PrudentTest.ALICE, accountId, food, -40_00L, "PLN", LocalDate.of(thisYear, 3, 15));

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("granularity", "YEAR")
            .queryParam("count", 3)
            .when()
            .get("/api/v1/analytics/spend-by-period")
            .andReturn();

    SpendByPeriodResponse body =
        PrudentTest.decode(PrudentTest.JSON, response, SpendByPeriodResponse.newBuilder()).build();
    assertEquals(Granularity.GRANULARITY_YEAR, body.getGranularity());
    assertEquals(1, body.getPeriodsCount());
    assertEquals(String.valueOf(thisYear), body.getPeriods(0).getPeriod());
    assertEquals(40_00L, body.getPeriods(0).getAmountMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByPeriod_invalidGranularity_isRejected() {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("granularity", "FORTNIGHT")
            .queryParam("count", 12)
            .when()
            .get("/api/v1/analytics/spend-by-period")
            .andReturn();

    assertEquals(400, response.statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendByPeriod_countOutOfRange_isRejected() {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("granularity", "MONTH")
            .queryParam("count", 0)
            .when()
            .get("/api/v1/analytics/spend-by-period")
            .andReturn();

    assertEquals(400, response.statusCode());
  }

  // -----------------------------------------------------------------------------------------
  // User scoping
  // -----------------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void analytics_areScopedToTheCaller() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's wallet", "PLN");
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Bob's food");
    PrudentTest.seedRecord(
        PrudentTest.BOB, bobsAccount, bobsCategory, -500_00L, "PLN", LocalDate.of(2026, 8, 10));
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, food, -20_00L, "PLN", LocalDate.of(2026, 8, 10));

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "PLN")
            .queryParam("year", 2026)
            .queryParam("month", 8)
            .when()
            .get("/api/v1/analytics/spend-by-category")
            .andReturn();

    SpendByCategoryResponse body =
        PrudentTest.decode(PrudentTest.JSON, response, SpendByCategoryResponse.newBuilder())
            .build();
    assertEquals(1, body.getItemsCount());
    assertEquals(20_00L, body.getItems(0).getAmountMinor(), "Bob's 500 PLN must not appear here");
  }
}
