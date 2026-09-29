package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.budget.BudgetEntity;
import prudent.proto.v1.Budget;
import prudent.proto.v1.ListBudgetsResponse;
import prudent.proto.v1.SetBudgetRequest;
import zen.proto.v1.ZenError;

/**
 * The budget surface (M3, jlogicsoftware/prudent#36, ADR-043): one amount per category, month and
 * currency, addressed by that slot; validated edits; and the refusals that keep a budget from
 * pointing at a category that is not there.
 */
@QuarkusTest
class BudgetResourceTest {

  private UUID groceries;
  private UUID rent;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    groceries = PrudentTest.seedCategory(PrudentTest.ALICE, "Groceries");
    rent = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
  }

  private static String slot(UUID category, String month, String currency) {
    return "/api/v1/budgets/" + category + "/" + month + "/" + currency;
  }

  private static Response put(String mode, String path, long amountMinor) throws Exception {
    return PrudentTest.body(
            PrudentTest.request(mode),
            mode,
            SetBudgetRequest.newBuilder().setAmountMinor(amountMinor).build())
        .when()
        .put(path)
        .andReturn();
  }

  private static Budget set(String mode, String path, long amountMinor, int expectedStatus)
      throws Exception {
    Response response = put(mode, path, amountMinor);
    assertEquals(expectedStatus, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, Budget.newBuilder()).build();
  }

  private static ZenError refused(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  private static Response get(String path) {
    return PrudentTest.request(PrudentTest.JSON).when().get(path).andReturn();
  }

  private static List<Budget> listed(String query) throws Exception {
    Response response = get("/api/v1/budgets" + query);
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ListBudgetsResponse.newBuilder())
        .build()
        .getBudgetsList();
  }

  // --- Set and read, both transports ---------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void set_createsThenReplacesAndRoundTripsEveryField(String mode) throws Exception {
    String path = slot(groceries, "2026-10", "PLN");

    Budget created = set(mode, path, 800_00L, 201);
    assertEquals(groceries.toString(), created.getCategoryId());
    assertEquals("2026-10", created.getMonth());
    assertEquals("PLN", created.getCurrency());
    assertEquals(800_00L, created.getAmountMinor());

    Budget replaced = set(mode, path, 950_00L, 200);
    assertEquals(950_00L, replaced.getAmountMinor());

    Response read = PrudentTest.request(mode).when().get(path).andReturn();
    assertEquals(200, read.statusCode(), read.asString());
    assertEquals(replaced, PrudentTest.decode(mode, read, Budget.newBuilder()).build());

    Response all = PrudentTest.request(mode).when().get("/api/v1/budgets").andReturn();
    assertEquals(200, all.statusCode(), all.asString());
    assertEquals(
        List.of(replaced),
        PrudentTest.decode(mode, all, ListBudgetsResponse.newBuilder()).build().getBudgetsList());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aSlotHoldsAtMostOneAmount() throws Exception {
    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 800_00L, 201);
    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 900_00L, 200);
    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 700_00L, 200);

    assertEquals(1, listed("").size());
    assertEquals(700_00L, listed("").get(0).getAmountMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aSlotIsCategoryMonthAndCurrencyTogether() throws Exception {
    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 800_00L, 201);
    // Each differs from the first in exactly one part, so each is a new slot, not a replacement.
    set(PrudentTest.JSON, slot(groceries, "2026-11", "PLN"), 810_00L, 201);
    set(PrudentTest.JSON, slot(groceries, "2026-10", "EUR"), 200_00L, 201);
    set(PrudentTest.JSON, slot(rent, "2026-10", "PLN"), 2_500_00L, 201);

    assertEquals(4, listed("").size());
    assertEquals(
        800_00L,
        PrudentTest.decode(
                PrudentTest.JSON,
                get(slot(groceries, "2026-10", "PLN")),
                Budget.newBuilder())
            .build()
            .getAmountMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aLowerCaseCurrencyIsTheSameSlotAsItsUpperCase() throws Exception {
    set(PrudentTest.JSON, slot(groceries, "2026-10", "pln"), 800_00L, 201);
    Budget replaced = set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 900_00L, 200);

    assertEquals("PLN", replaced.getCurrency());
    assertEquals(1, listed("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aBudgetMovesNoBalanceAndCreatesNoRecord() throws Exception {
    UUID wallet = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 800_00L, 201);

    Response records = get("/api/v1/records");
    assertEquals(200, records.statusCode());
    assertEquals(
        0,
        PrudentTest.decode(
                PrudentTest.JSON, records, prudent.proto.v1.ListRecordsResponse.newBuilder())
            .build()
            .getRecordsCount());
    Response accounts = get("/api/v1/accounts/" + wallet);
    assertEquals(200, accounts.statusCode());
    assertEquals(
        0L,
        PrudentTest.decode(PrudentTest.JSON, accounts, prudent.proto.v1.Account.newBuilder())
            .build()
            .getBalances(0)
            .getAmountMinor());
  }

  @Test
  void racingWritersToAnEmptySlotLeaveOneRow() throws Exception {
    // The upsert is one INSERT ... ON CONFLICT, so this must not surface the unique constraint as
    // an error to the loser. A find-then-insert would.
    int writers = 8;
    java.util.concurrent.CountDownLatch start = new java.util.concurrent.CountDownLatch(1);
    java.util.concurrent.ExecutorService pool =
        java.util.concurrent.Executors.newFixedThreadPool(writers);
    try {
      List<java.util.concurrent.Future<?>> results = new java.util.ArrayList<>();
      for (int i = 1; i <= writers; i++) {
        long amount = i * 100L;
        results.add(
            pool.submit(
                () -> {
                  start.await();
                  QuarkusTransaction.requiringNew()
                      .run(
                          () ->
                              BudgetEntity.upsert(
                                  UUID.fromString(PrudentTest.ALICE),
                                  groceries,
                                  YearMonth.of(2026, 10),
                                  "PLN",
                                  amount));
                  return null;
                }));
      }
      start.countDown();
      for (java.util.concurrent.Future<?> result : results) {
        result.get(30, java.util.concurrent.TimeUnit.SECONDS); // rethrows any writer's failure
      }
    } finally {
      pool.shutdownNow();
    }

    long rows =
        QuarkusTransaction.requiringNew()
            .call(() -> BudgetEntity.count("userId", UUID.fromString(PrudentTest.ALICE)));
    assertEquals(1, rows);
  }

  // --- Listing --------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void list_filtersByMonthAndCategoryAndOrdersTotally() throws Exception {
    set(PrudentTest.JSON, slot(groceries, "2026-11", "PLN"), 1_00L, 201);
    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 2_00L, 201);
    set(PrudentTest.JSON, slot(groceries, "2026-10", "EUR"), 3_00L, 201);
    set(PrudentTest.JSON, slot(rent, "2026-10", "PLN"), 4_00L, 201);

    // Month, then currency, then category id — so the order does not depend on insertion.
    List<Budget> all = listed("");
    assertEquals(
        List.of("2026-10", "2026-10", "2026-10", "2026-11"),
        all.stream().map(Budget::getMonth).toList());
    assertEquals(
        List.of("EUR", "PLN", "PLN", "PLN"), all.stream().map(Budget::getCurrency).toList());

    assertEquals(3, listed("?month=2026-10").size());
    assertEquals(3, listed("?categoryId=" + groceries).size());
    List<Budget> narrowed = listed("?month=2026-10&categoryId=" + rent);
    assertEquals(1, narrowed.size());
    assertEquals(4_00L, narrowed.get(0).getAmountMinor());
    assertEquals(0, listed("?month=2030-01").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void list_refusesAMalformedMonthOrCategory() throws Exception {
    refused(get("/api/v1/budgets?month=2026-13"), 400);
    refused(get("/api/v1/budgets?categoryId=not-a-uuid"), 400);
  }

  // --- Refusals ------------------------------------------------------------------------------

  @ParameterizedTest
  @ValueSource(longs = {0L, -1L, -800_00L})
  @TestSecurity(user = PrudentTest.ALICE)
  void set_refusesAnAmountThatIsNotPositive(long amount) throws Exception {
    ZenError error = refused(put(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), amount), 400);
    assertEquals("invalid", error.getCode());
    assertEquals(0, listed("").size(), "a refused write must persist nothing");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void set_refusesABodyThatOmitsTheAmount() throws Exception {
    // An omitted proto3 scalar decodes to zero; that must not become a real budget.
    Response response =
        PrudentTest.request(PrudentTest.JSON).body("{}").when()
            .put(slot(groceries, "2026-10", "PLN"))
            .andReturn();
    refused(response, 400);
    assertEquals(0, listed("").size());
  }

  @ParameterizedTest
  @ValueSource(strings = {"2026-13", "2026-00", "2026-1", "202610", "2026-10-01", "+2026-10", "abcd-ef"})
  @TestSecurity(user = PrudentTest.ALICE)
  void set_refusesAMalformedMonth(String month) throws Exception {
    refused(put(PrudentTest.JSON, slot(groceries, month, "PLN"), 100L), 400);
    assertEquals(0, listed("").size());
  }

  @ParameterizedTest
  @ValueSource(strings = {"XXY", "PL", "PLNN", "12A"})
  @TestSecurity(user = PrudentTest.ALICE)
  void set_refusesACurrencyThatIsNotIso4217(String currency) throws Exception {
    refused(put(PrudentTest.JSON, slot(groceries, "2026-10", currency), 100L), 400);
    assertEquals(0, listed("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void set_refusesACategoryThatDoesNotExist() throws Exception {
    refused(put(PrudentTest.JSON, slot(UUID.randomUUID(), "2026-10", "PLN"), 100L), 404);
    refused(put(PrudentTest.JSON, "/api/v1/budgets/not-a-uuid/2026-10/PLN", 100L), 404);
    assertEquals(0, listed("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRefusedEditLeavesTheExistingAmountAlone() throws Exception {
    String path = slot(groceries, "2026-10", "PLN");
    set(PrudentTest.JSON, path, 800_00L, 201);

    refused(put(PrudentTest.JSON, path, -5L), 400);

    assertEquals(800_00L, listed("").get(0).getAmountMinor());
  }

  // --- Reading and deleting an empty slot ----------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void get_andDelete_answer404ForASlotThatHoldsNothing() throws Exception {
    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 800_00L, 201);

    // The category exists and has a budget elsewhere; only this slot is empty.
    refused(get(slot(groceries, "2026-11", "PLN")), 404);
    refused(get(slot(groceries, "2026-10", "EUR")), 404);
    refused(
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete(slot(groceries, "2026-11", "PLN"))
            .andReturn(),
        404);
    assertEquals(1, listed("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void delete_removesOnlyThatSlot() throws Exception {
    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 800_00L, 201);
    set(PrudentTest.JSON, slot(groceries, "2026-11", "PLN"), 810_00L, 201);

    Response deleted =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete(slot(groceries, "2026-10", "PLN"))
            .andReturn();
    assertEquals(204, deleted.statusCode(), deleted.asString());

    assertEquals(List.of("2026-11"), listed("").stream().map(Budget::getMonth).toList());
    refused(get(slot(groceries, "2026-10", "PLN")), 404);
    // An emptied slot can be filled again.
    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 500_00L, 201);
  }

  // --- Ownership ------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anotherUsersBudget_isInvisibleAndUntouchable() throws Exception {
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Bob's food");
    PrudentTest.seedBudget(PrudentTest.BOB, bobsCategory, YearMonth.of(2026, 10), "PLN", 100_00L);

    assertEquals(0, listed("").size(), "Bob's budget must not appear in Alice's list");
    assertEquals(0, listed("?categoryId=" + bobsCategory).size());
    refused(get(slot(bobsCategory, "2026-10", "PLN")), 404);
    refused(put(PrudentTest.JSON, slot(bobsCategory, "2026-10", "PLN"), 999L), 404);
    refused(
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete(slot(bobsCategory, "2026-10", "PLN"))
            .andReturn(),
        404);

    // Bob's amount is untouched by all of the above.
    BudgetEntity bobs =
        QuarkusTransaction.requiringNew()
            .call(
                () ->
                    BudgetEntity.findSlot(
                        UUID.fromString(PrudentTest.BOB),
                        bobsCategory,
                        YearMonth.of(2026, 10),
                        "PLN"));
    assertEquals(100_00L, bobs.amountMinor, "Bob's budget must be unchanged");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void twoUsersCanBudgetTheSameMonthAndCurrencyIndependently() throws Exception {
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Bob's food");
    PrudentTest.seedBudget(PrudentTest.BOB, bobsCategory, YearMonth.of(2026, 10), "PLN", 100_00L);

    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 800_00L, 201);

    assertEquals(1, listed("").size());
    assertEquals(800_00L, listed("").get(0).getAmountMinor());
  }

  // --- What a budget protects ----------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void deletingACategoryWithBudgets_isRefusedUntilTheyAreDeleted() throws Exception {
    set(PrudentTest.JSON, slot(groceries, "2026-10", "PLN"), 800_00L, 201);

    ZenError error =
        refused(
            PrudentTest.request(PrudentTest.JSON)
                .when()
                .delete("/api/v1/categories/" + groceries)
                .andReturn(),
            409);
    assertTrue(error.getMessage().contains("budgets"), error.getMessage());
    assertEquals(1, listed("").size(), "the refused delete must leave the budget in place");

    PrudentTest.request(PrudentTest.JSON)
        .when()
        .delete(slot(groceries, "2026-10", "PLN"))
        .then()
        .statusCode(204);
    PrudentTest.request(PrudentTest.JSON)
        .when()
        .delete("/api/v1/categories/" + groceries)
        .then()
        .statusCode(204);
  }
}
