package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

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
import prudent.proto.v1.BudgetCarryOverReset;
import prudent.proto.v1.BudgetSummaryResponse;
import prudent.proto.v1.CategoryBudgetSummary;
import prudent.proto.v1.ListBudgetCarryOverResetsResponse;
import prudent.proto.v1.ListBudgetsResponse;
import prudent.proto.v1.ResetBudgetCarryOverRequest;
import zen.proto.v1.ZenError;

/**
 * Carry-over resets and their audit history (M3, jlogicsoftware/prudent#61, ADR-046): a reset
 * restarts one category's carry-over from a chosen month without deleting a budget or changing an
 * earlier month, and every reset — and every taking-back — stays in a history that names who, when
 * and what was discarded.
 */
@QuarkusTest
class BudgetCarryOverResetTest {

  private static final String RESETS = "/api/v1/budget-carry-over-resets";
  private static final YearMonth AUGUST = YearMonth.of(2026, 8);
  private static final YearMonth SEPTEMBER = YearMonth.of(2026, 9);
  private static final YearMonth OCTOBER = YearMonth.of(2026, 10);
  private static final YearMonth NOVEMBER = YearMonth.of(2026, 11);

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

  // --- Helpers -------------------------------------------------------------------------------

  private static Response post(
      String mode, UUID category, String month, String currency, String note) throws Exception {
    return post(mode, category.toString(), month, currency, note);
  }

  private static Response post(
      String mode, String category, String month, String currency, String note)
      throws Exception {
    return PrudentTest.body(
            PrudentTest.request(mode),
            mode,
            ResetBudgetCarryOverRequest.newBuilder()
                .setCategoryId(category)
                .setMonth(month)
                .setCurrency(currency)
                .setNote(note)
                .build())
        .when()
        .post(RESETS)
        .andReturn();
  }

  private static BudgetCarryOverReset resetFrom(UUID category, YearMonth month) throws Exception {
    Response response = post(PrudentTest.JSON, category, month.toString(), "PLN", "");
    assertEquals(201, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, BudgetCarryOverReset.newBuilder())
        .build();
  }

  private static Response revokeResponse(String mode, String id) {
    return PrudentTest.request(mode).when().post(RESETS + "/" + id + "/revoke").andReturn();
  }

  private static BudgetCarryOverReset revoke(String id) throws Exception {
    Response response = revokeResponse(PrudentTest.JSON, id);
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, BudgetCarryOverReset.newBuilder())
        .build();
  }

  private static List<BudgetCarryOverReset> history(String query) throws Exception {
    Response response = PrudentTest.request(PrudentTest.JSON).when().get(RESETS + query).andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(
            PrudentTest.JSON, response, ListBudgetCarryOverResetsResponse.newBuilder())
        .build()
        .getResetsList();
  }

  private static ZenError refused(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  private static CategoryBudgetSummary summaryItem(UUID category, YearMonth month)
      throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("month", month.toString())
            .queryParam("currency", "PLN")
            .when()
            .get("/api/v1/budgets/summary")
            .andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, BudgetSummaryResponse.newBuilder())
        .build()
        .getItemsList()
        .stream()
        .filter(i -> i.getCategoryId().equals(category.toString()))
        .findFirst()
        .orElseThrow(() -> new AssertionError("no item for " + category + " in " + month));
  }

  private void budget(UUID category, YearMonth month, long amountMinor) {
    PrudentTest.seedBudget(PrudentTest.ALICE, category, month, "PLN", amountMinor);
  }

  private void spend(UUID category, long amountMinor, YearMonth month) {
    PrudentTest.seedRecord(
        PrudentTest.ALICE, wallet, category, amountMinor, "PLN", month.atDay(12));
  }

  /**
   * August +500, September +700 (800 planned, 100 spent): carry into October is 1200 and into
   * November, with October's own 800 planned and 100 spent, 1900 — before any reset.
   */
  private void seedAugustToNovemberFood() {
    budget(food, AUGUST, 800_00L);
    spend(food, -300_00L, AUGUST);
    budget(food, SEPTEMBER, 800_00L);
    spend(food, -100_00L, SEPTEMBER);
    budget(food, OCTOBER, 800_00L);
    spend(food, -100_00L, OCTOBER);
    budget(food, NOVEMBER, 800_00L);
  }

  // --- Create and read, both transports ------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void reset_recordsWhoWhenWhatWasDiscardedAndWhy(String mode) throws Exception {
    budget(food, SEPTEMBER, 800_00L);
    spend(food, -300_00L, SEPTEMBER);
    long before = System.currentTimeMillis();

    Response response = post(mode, food, "2026-10", "pln", "  Fresh start after the move  ");
    assertEquals(201, response.statusCode(), response.asString());
    BudgetCarryOverReset entry =
        PrudentTest.decode(mode, response, BudgetCarryOverReset.newBuilder()).build();

    assertFalse(entry.getId().isEmpty());
    assertEquals(food.toString(), entry.getCategoryId());
    assertEquals("2026-10", entry.getMonth());
    assertEquals("PLN", entry.getCurrency());
    // The carry-over into October the reset threw away: September's +500.
    assertEquals(500_00L, entry.getDiscardedMinor());
    assertEquals("Fresh start after the move", entry.getNote());
    assertEquals(PrudentTest.ALICE, entry.getCreatedBy());
    assertTrue(entry.getCreatedAtMs() >= before, "created_at_ms should be now");
    assertEquals("", entry.getRevokedBy());
    assertEquals(0L, entry.getRevokedAtMs());

    // The same entry comes back from the history, in the same transport.
    Response all = PrudentTest.request(mode).when().get(RESETS).andReturn();
    assertEquals(200, all.statusCode(), all.asString());
    assertEquals(
        List.of(entry),
        PrudentTest.decode(mode, all, ListBudgetCarryOverResetsResponse.newBuilder())
            .build()
            .getResetsList());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void resettingAMonthWithNothingToDiscardIsAllowedAndRecordsZero() throws Exception {
    BudgetCarryOverReset entry = resetFrom(food, OCTOBER);

    assertEquals(0L, entry.getDiscardedMinor());
  }

  // --- What a reset does to the figures ------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aResetRestartsCarryOverFromItsMonthAndNamesItself() throws Exception {
    seedAugustToNovemberFood();
    assertEquals(1_200_00L, summaryItem(food, OCTOBER).getCarryOverMinor());
    assertEquals(1_900_00L, summaryItem(food, NOVEMBER).getCarryOverMinor());

    BudgetCarryOverReset entry = resetFrom(food, OCTOBER);

    assertEquals(1_200_00L, entry.getDiscardedMinor());
    CategoryBudgetSummary october = summaryItem(food, OCTOBER);
    assertEquals(0L, october.getCarryOverMinor());
    assertEquals("2026-10", october.getCarryOverResetMonth());
    assertEquals(800_00L - 100_00L, october.getRemainingMinor());
    // November counts October onward only: October's 800 planned less 100 spent.
    CategoryBudgetSummary november = summaryItem(food, NOVEMBER);
    assertEquals(700_00L, november.getCarryOverMinor());
    assertEquals("2026-10", november.getCarryOverResetMonth());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aResetDeletesNoBudgetAndChangesNoEarlierMonth() throws Exception {
    seedAugustToNovemberFood();
    CategoryBudgetSummary augustBefore = summaryItem(food, AUGUST);
    CategoryBudgetSummary septemberBefore = summaryItem(food, SEPTEMBER);

    resetFrom(food, OCTOBER);

    // Every earlier month reads exactly as it did: same plan, actual, carry-over and remaining,
    // and no reset named on it.
    assertEquals(augustBefore, summaryItem(food, AUGUST));
    assertEquals(septemberBefore, summaryItem(food, SEPTEMBER));
    assertEquals("", summaryItem(food, SEPTEMBER).getCarryOverResetMonth());
    Response budgets = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/budgets").andReturn();
    assertEquals(
        4,
        PrudentTest.decode(PrudentTest.JSON, budgets, ListBudgetsResponse.newBuilder())
            .build()
            .getBudgetsCount(),
        "no budget may be deleted by a reset");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aResetInTheMiddleOfTheHistoryKeepsOnlyTheMonthsFromItOn() throws Exception {
    seedAugustToNovemberFood();

    resetFrom(food, SEPTEMBER);

    // September itself restarts at zero; October carries September only (+700); November
    // carries September and October (+700 and +700).
    assertEquals(0L, summaryItem(food, SEPTEMBER).getCarryOverMinor());
    assertEquals(700_00L, summaryItem(food, OCTOBER).getCarryOverMinor());
    assertEquals(1_400_00L, summaryItem(food, NOVEMBER).getCarryOverMinor());
    // August is before the reset and keeps reading as it did.
    assertEquals("", summaryItem(food, AUGUST).getCarryOverResetMonth());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aResetBelongsToOneCategoryAndOneCurrency() throws Exception {
    seedAugustToNovemberFood();
    budget(rent, SEPTEMBER, 100_00L);
    budget(rent, OCTOBER, 100_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, SEPTEMBER, "EUR", 50_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "EUR", 50_00L);

    resetFrom(food, OCTOBER);

    assertEquals(100_00L, summaryItem(rent, OCTOBER).getCarryOverMinor(), "another category");
    Response eur =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("month", "2026-10")
            .queryParam("currency", "EUR")
            .when()
            .get("/api/v1/budgets/summary")
            .andReturn();
    BudgetSummaryResponse body =
        PrudentTest.decode(PrudentTest.JSON, eur, BudgetSummaryResponse.newBuilder()).build();
    assertEquals(50_00L, body.getItems(0).getCarryOverMinor(), "another currency");
    assertEquals("", body.getItems(0).getCarryOverResetMonth());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aResetAfterTheRequestedMonthSaysNothingAboutIt() throws Exception {
    seedAugustToNovemberFood();

    resetFrom(food, NOVEMBER);

    CategoryBudgetSummary october = summaryItem(food, OCTOBER);
    assertEquals(1_200_00L, october.getCarryOverMinor());
    assertEquals("", october.getCarryOverResetMonth());
    assertEquals(0L, summaryItem(food, NOVEMBER).getCarryOverMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aLaterResetDiscardsOnlyWhatTheEarlierOneLeftCounted() throws Exception {
    seedAugustToNovemberFood();
    resetFrom(food, SEPTEMBER);

    // Into November, counted from September: +700 and +700.
    BudgetCarryOverReset second = resetFrom(food, NOVEMBER);

    assertEquals(1_400_00L, second.getDiscardedMinor());
    assertEquals(0L, summaryItem(food, NOVEMBER).getCarryOverMinor());
    assertEquals("2026-11", summaryItem(food, NOVEMBER).getCarryOverResetMonth());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void whatWasDiscardedIsASnapshotNotRecalculated() throws Exception {
    seedAugustToNovemberFood();
    BudgetCarryOverReset entry = resetFrom(food, OCTOBER);

    // An earlier budget is raised afterwards: the entry still says what the user saw erased.
    budget(food, AUGUST, 900_00L);

    assertEquals(
        entry.getDiscardedMinor(), history("?categoryId=" + food).get(0).getDiscardedMinor());
  }

  // --- Taking a reset back -------------------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void revoke_restoresTheCarryOverAndKeepsTheEntryWithWhoAndWhen(String mode) throws Exception {
    seedAugustToNovemberFood();
    BudgetCarryOverReset entry = resetFrom(food, OCTOBER);
    assertEquals(0L, summaryItem(food, OCTOBER).getCarryOverMinor());
    long before = System.currentTimeMillis();

    Response response = revokeResponse(mode, entry.getId());
    assertEquals(200, response.statusCode(), response.asString());
    BudgetCarryOverReset revoked =
        PrudentTest.decode(mode, response, BudgetCarryOverReset.newBuilder()).build();

    assertEquals(entry.getId(), revoked.getId());
    assertEquals(PrudentTest.ALICE, revoked.getRevokedBy());
    assertTrue(revoked.getRevokedAtMs() >= before);
    // The original facts are untouched.
    assertEquals(entry.getCreatedBy(), revoked.getCreatedBy());
    assertEquals(entry.getCreatedAtMs(), revoked.getCreatedAtMs());
    assertEquals(entry.getDiscardedMinor(), revoked.getDiscardedMinor());
    // The figures are as if it never happened, and the entry is still in the history.
    CategoryBudgetSummary october = summaryItem(food, OCTOBER);
    assertEquals(1_200_00L, october.getCarryOverMinor());
    assertEquals("", october.getCarryOverResetMonth());
    assertEquals(List.of(revoked), history(""));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRevokedResetCanBeMadeAgainAndBothStayInTheHistory() throws Exception {
    seedAugustToNovemberFood();
    BudgetCarryOverReset first = resetFrom(food, OCTOBER);
    revoke(first.getId());

    BudgetCarryOverReset second = resetFrom(food, OCTOBER);

    List<BudgetCarryOverReset> all = history("");
    assertEquals(2, all.size());
    assertEquals(second.getId(), all.get(0).getId(), "newest first");
    assertEquals(first.getId(), all.get(1).getId());
    assertTrue(all.get(1).getRevokedAtMs() > 0);
    assertEquals(0L, all.get(0).getRevokedAtMs());
    assertEquals(0L, summaryItem(food, OCTOBER).getCarryOverMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aResetCannotBeRevokedTwice() throws Exception {
    BudgetCarryOverReset entry = resetFrom(food, OCTOBER);
    BudgetCarryOverReset revoked = revoke(entry.getId());

    ZenError error = refused(revokeResponse(PrudentTest.JSON, entry.getId()), 409);

    assertEquals("conflict", error.getCode());
    // The first revocation's name and time are the ones on record.
    assertEquals(revoked, history("").get(0));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void thereIsNoWayToDeleteAnEntry() throws Exception {
    UUID id = PrudentTest.seedCarryReset(PrudentTest.ALICE, food, OCTOBER, "PLN", 0L);

    int status =
        PrudentTest.request(PrudentTest.JSON).when().delete(RESETS + "/" + id).andReturn().statusCode();

    assertTrue(status == 404 || status == 405, "no DELETE route may exist, got " + status);
    assertEquals(1, history("").size());
  }

  // --- Refusals ------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aSecondLiveResetOfTheSameSlotIsRefused() throws Exception {
    resetFrom(food, OCTOBER);

    ZenError error = refused(post(PrudentTest.JSON, food, "2026-10", "PLN", ""), 409);

    assertEquals("conflict", error.getCode());
    assertEquals(1, history("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void invalidRequestsAreRefusedAt400() throws Exception {
    assertEquals("invalid", refused(post(PrudentTest.JSON, food, "2026-13", "PLN", ""), 400).getCode());
    assertEquals("invalid", refused(post(PrudentTest.JSON, food, "", "PLN", ""), 400).getCode());
    assertEquals("invalid", refused(post(PrudentTest.JSON, food, "2026-10", "ZZZ9", ""), 400).getCode());
    assertEquals("invalid", refused(post(PrudentTest.JSON, food, "2026-10", "", ""), 400).getCode());
    assertEquals(
        "invalid", refused(post(PrudentTest.JSON, "not-a-uuid", "2026-10", "PLN", ""), 400).getCode());
    assertEquals(
        "invalid",
        refused(post(PrudentTest.JSON, food, "2026-10", "PLN", "x".repeat(501)), 400).getCode());
    assertTrue(history("").isEmpty(), "a refused reset must leave no entry");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aNoteOfExactlyFiveHundredCharactersIsAccepted() throws Exception {
    Response response = post(PrudentTest.JSON, food, "2026-10", "PLN", "x".repeat(500));

    assertEquals(201, response.statusCode(), response.asString());
  }

  // --- Ownership -----------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anotherUsersCategoryAndEntriesAreNotFound() throws Exception {
    UUID bobsFood = PrudentTest.seedCategory(PrudentTest.BOB, "Food");
    UUID bobsReset = PrudentTest.seedCarryReset(PrudentTest.BOB, bobsFood, OCTOBER, "PLN", 10_00L);
    resetFrom(food, OCTOBER);

    assertEquals("not_found", refused(post(PrudentTest.JSON, bobsFood, "2026-10", "PLN", ""), 404).getCode());
    assertEquals("not_found", refused(revokeResponse(PrudentTest.JSON, bobsReset.toString()), 404).getCode());
    assertEquals("not_found", refused(revokeResponse(PrudentTest.JSON, "nonsense"), 404).getCode());
    // Alice sees only her own history, and Bob's entry is not revoked by her attempt.
    assertEquals(1, history("").size());
    assertEquals(food.toString(), history("").get(0).getCategoryId());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anotherUsersResetNeverBoundsMyCarryOver() throws Exception {
    seedAugustToNovemberFood();
    // Bob resets a category of his own; Alice's identical slot is unaffected.
    UUID bobsFood = PrudentTest.seedCategory(PrudentTest.BOB, "Food");
    PrudentTest.seedCarryReset(PrudentTest.BOB, bobsFood, OCTOBER, "PLN", 0L);

    assertEquals(1_200_00L, summaryItem(food, OCTOBER).getCarryOverMinor());
  }

  // --- History queries -----------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void historyCanBeNarrowedByCategoryAndCurrency() throws Exception {
    resetFrom(food, OCTOBER);
    resetFrom(rent, OCTOBER);
    Response eur = post(PrudentTest.JSON, food, "2026-10", "EUR", "");
    assertEquals(201, eur.statusCode(), eur.asString());

    assertEquals(3, history("").size());
    assertEquals(2, history("?categoryId=" + food).size());
    assertEquals(2, history("?currency=pln").size());
    assertEquals(1, history("?categoryId=" + food + "&currency=EUR").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMalformedHistoryFilterIsRefused() throws Exception {
    assertEquals(
        400,
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("categoryId", "nope")
            .when()
            .get(RESETS)
            .andReturn()
            .statusCode());
    assertEquals(
        400,
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("currency", "nope")
            .when()
            .get(RESETS)
            .andReturn()
            .statusCode());
  }

  // --- The history is not erased by deleting things around it --------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aCategoryWithResetHistoryCannotBeDeleted() throws Exception {
    resetFrom(food, OCTOBER);

    Response response =
        PrudentTest.request(PrudentTest.JSON).when().delete("/api/v1/categories/" + food).andReturn();

    assertEquals("conflict", refused(response, 409).getCode());
    assertEquals(1, history("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void deletingABudgetDoesNotRemoveTheResetThatRefersToItsMonth() throws Exception {
    budget(food, SEPTEMBER, 800_00L);
    resetFrom(food, SEPTEMBER);

    PrudentTest.request(PrudentTest.JSON)
        .when()
        .delete("/api/v1/budgets/" + food + "/2026-09/PLN")
        .then()
        .statusCode(204);

    assertEquals(1, history("").size());
  }
}
