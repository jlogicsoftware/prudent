package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.proto.v1.Budget;
import prudent.proto.v1.BudgetSummaryResponse;
import prudent.proto.v1.Category;
import prudent.proto.v1.CategoryBudgetSummary;
import prudent.proto.v1.CategorySpend;
import prudent.proto.v1.ConfirmOccurrenceRequest;
import prudent.proto.v1.ConfirmOccurrenceResponse;
import prudent.proto.v1.CreatePlanRequest;
import prudent.proto.v1.CreateRecordRequest;
import prudent.proto.v1.ListBudgetsResponse;
import prudent.proto.v1.ListCategoriesResponse;
import prudent.proto.v1.ListRecordsResponse;
import prudent.proto.v1.Plan;
import prudent.proto.v1.Record;
import prudent.proto.v1.Recurrence;
import prudent.proto.v1.ResetBudgetCarryOverRequest;
import prudent.proto.v1.RecurrenceFrequency;
import prudent.proto.v1.SetBudgetRequest;
import prudent.proto.v1.SpendByCategoryResponse;
import prudent.proto.v1.UpdateCategoryRequest;
import prudent.proto.v1.UpdatePlanRequest;
import prudent.proto.v1.UpdateRecordRequest;
import zen.proto.v1.ZenError;

/**
 * Category lifecycle (M3, jlogicsoftware/prudent#62, ADR-047): a category that has been used is
 * archived rather than deleted; an archived category stays readable and changes no total, and takes
 * nothing new; a category nothing points at can still be deleted; and a month without a budget is an
 * empty answer, never an error or a wrong figure.
 */
@QuarkusTest
class CategoryLifecycleTest {

  private static final YearMonth AUGUST = YearMonth.of(2026, 8);
  private static final YearMonth SEPTEMBER = YearMonth.of(2026, 9);
  private static final YearMonth OCTOBER = YearMonth.of(2026, 10);
  private static final String CATEGORIES = "/api/v1/categories";

  private UUID wallet;
  private UUID food;
  private UUID rent;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    wallet = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN", "EUR");
    food = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
    rent = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
  }

  // --- Helpers ----------------------------------------------------------------------------------

  private static Response post(String path) {
    return PrudentTest.request(PrudentTest.JSON).when().post(path).andReturn();
  }

  private static Response archiveResponse(UUID category) {
    return post(CATEGORIES + "/" + category + "/archive");
  }

  private static Response restoreResponse(UUID category) {
    return post(CATEGORIES + "/" + category + "/restore");
  }

  private static void archive(UUID category) {
    Response response = archiveResponse(category);
    assertEquals(200, response.statusCode(), response.asString());
  }

  private static ZenError refused(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  private static Category category(String mode, Response response) throws Exception {
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, Category.newBuilder()).build();
  }

  private static List<Category> listed(String mode) throws Exception {
    Response response = PrudentTest.request(mode).when().get(CATEGORIES).andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, ListCategoriesResponse.newBuilder())
        .build()
        .getCategoriesList();
  }

  private static Response deleteResponse(UUID category) {
    return PrudentTest.request(PrudentTest.JSON)
        .when()
        .delete(CATEGORIES + "/" + category)
        .andReturn();
  }

  private static String slot(UUID category, YearMonth month, String currency) {
    return "/api/v1/budgets/" + category + "/" + month + "/" + currency;
  }

  private static Response putBudget(UUID category, YearMonth month, long amountMinor) throws Exception {
    return PrudentTest.body(
            PrudentTest.request(PrudentTest.JSON),
            PrudentTest.JSON,
            SetBudgetRequest.newBuilder().setAmountMinor(amountMinor).build())
        .when()
        .put(slot(category, month, "PLN"))
        .andReturn();
  }

  private static BudgetSummaryResponse summary(YearMonth month) throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("month", month.toString())
            .queryParam("currency", "PLN")
            .when()
            .get("/api/v1/budgets/summary")
            .andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, BudgetSummaryResponse.newBuilder())
        .build();
  }

  private static SpendByCategoryResponse spend() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("year", 2026)
            .queryParam("currency", "PLN")
            .when()
            .get("/api/v1/analytics/spend-by-category")
            .andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, SpendByCategoryResponse.newBuilder())
        .build();
  }

  private CreateRecordRequest.Builder newRecord(UUID category) {
    return CreateRecordRequest.newBuilder()
        .setTitle("Coffee")
        .setAmountMinor(-12_50L)
        .setDate("2026-10-14")
        .setCategoryId(category.toString())
        .setAccountId(wallet.toString())
        .setCurrency("PLN");
  }

  private static Response postRecord(CreateRecordRequest request) throws Exception {
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, request)
        .when()
        .post("/api/v1/records")
        .andReturn();
  }

  private static Response putRecord(String id, UpdateRecordRequest request) throws Exception {
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, request)
        .when()
        .put("/api/v1/records/" + id)
        .andReturn();
  }

  private static long recordCount() throws Exception {
    Response response = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/records").andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ListRecordsResponse.newBuilder())
        .build()
        .getRecordsCount();
  }

  private CreatePlanRequest.Builder newPlan(UUID category) {
    return CreatePlanRequest.newBuilder()
        .setTitle("Rent")
        .setAmountMinor(-2_500_00L)
        .setCurrency("PLN")
        .setAccountId(wallet.toString())
        .setCategoryId(category.toString())
        .setRecurrence(
            Recurrence.newBuilder()
                .setFrequency(RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY)
                .setInterval(1)
                .setStartDate("2026-09-01")
                .setTimeZone("Europe/Warsaw")
                .build());
  }

  // --- Archive and restore ----------------------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void archiveAndRestoreRoundTripInBothTransports(String mode) throws Exception {
    assertFalse(listed(mode).stream().anyMatch(Category::getArchived), "categories start active");

    Category archived =
        category(
            mode,
            PrudentTest.request(mode).when().post(CATEGORIES + "/" + food + "/archive").andReturn());
    assertTrue(archived.getArchived());
    assertEquals("Food", archived.getTitle());

    // Still listed, still named, and the flag is the only difference: that is what keeps a record
    // filed under it readable.
    List<Category> afterArchive = listed(mode);
    assertEquals(2, afterArchive.size());
    assertTrue(
        afterArchive.stream().filter(c -> c.getId().equals(food.toString())).findFirst().orElseThrow()
            .getArchived());
    assertFalse(
        afterArchive.stream().filter(c -> c.getId().equals(rent.toString())).findFirst().orElseThrow()
            .getArchived());

    Category read =
        category(mode, PrudentTest.request(mode).when().get(CATEGORIES + "/" + food).andReturn());
    assertEquals(archived, read);

    Category restored =
        category(
            mode,
            PrudentTest.request(mode).when().post(CATEGORIES + "/" + food + "/restore").andReturn());
    assertFalse(restored.getArchived());
    assertEquals("Food", restored.getTitle());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void archivingAnArchivedCategoryAndRestoringAnActiveOneAreRefused() throws Exception {
    assertEquals("conflict", refused(restoreResponse(food), 409).getCode());
    archive(food);
    assertEquals("conflict", refused(archiveResponse(food), 409).getCode());
    assertEquals(200, restoreResponse(food).statusCode());
    assertEquals("conflict", refused(restoreResponse(food), 409).getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void archiveAndRestoreAreNotFoundForAnotherUsersOrAnUnknownCategory() throws Exception {
    UUID bobs = PrudentTest.seedCategory(PrudentTest.BOB, "Bob's");

    assertEquals("not_found", refused(archiveResponse(bobs), 404).getCode());
    assertEquals("not_found", refused(restoreResponse(bobs), 404).getCode());
    assertEquals("not_found", refused(archiveResponse(UUID.randomUUID()), 404).getCode());
    assertEquals("not_found", refused(post(CATEGORIES + "/not-a-uuid/archive"), 404).getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void editingAnArchivedCategoryDoesNotRestoreIt() throws Exception {
    archive(food);

    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                UpdateCategoryRequest.newBuilder()
                    .setTitle("Groceries")
                    .setIconKey("food")
                    .setDescription("")
                    .setColorArgb(0xFF4CAF50)
                    .build())
            .when()
            .put(CATEGORIES + "/" + food)
            .andReturn();

    Category edited = category(PrudentTest.JSON, response);
    assertEquals("Groceries", edited.getTitle());
    assertTrue(edited.getArchived(), "only restore un-archives; an edit is not a restore");
  }

  // --- An archived category takes nothing new ---------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anArchivedCategoryTakesNoNewRecordAndRestoreReopensIt() throws Exception {
    archive(food);

    ZenError error = refused(postRecord(newRecord(food).build()), 409);
    assertEquals("conflict", error.getCode());
    assertTrue(error.getMessage().contains("archived"), error.getMessage());
    assertEquals(0, recordCount(), "a refused write must persist nothing");

    // Another category is unaffected.
    assertEquals(201, postRecord(newRecord(rent).build()).statusCode());

    assertEquals(200, restoreResponse(food).statusCode());
    assertEquals(201, postRecord(newRecord(food).build()).statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRecordAlreadyInAnArchivedCategoryCanStillBeEditedButNotMovedIntoAnother() throws Exception {
    UUID existing = PrudentTest.seedRecord(PrudentTest.ALICE, wallet, food, -40_00L, "PLN");
    UUID elsewhere = PrudentTest.seedRecord(PrudentTest.ALICE, wallet, rent, -10_00L, "PLN");
    archive(food);

    UpdateRecordRequest.Builder keep =
        UpdateRecordRequest.newBuilder()
            .setTitle("Corrected")
            .setAmountMinor(-45_00L)
            .setDate("2026-08-17")
            .setCategoryId(food.toString())
            .setAccountId(wallet.toString())
            .setCurrency("PLN");
    Response edited = putRecord(existing.toString(), keep.build());
    assertEquals(200, edited.statusCode(), "an edit that keeps the category adds nothing to it");
    assertEquals(
        -45_00L,
        PrudentTest.decode(PrudentTest.JSON, edited, Record.newBuilder()).build().getAmountMinor());

    // Moving a record INTO the archived category is a new reference.
    assertEquals(
        "conflict",
        refused(putRecord(elsewhere.toString(), keep.setTitle("Moved").build()), 409).getCode());

    // Moving it OUT is always fine.
    UpdateRecordRequest.Builder out = keep.setCategoryId(rent.toString());
    assertEquals(200, putRecord(existing.toString(), out.build()).statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anArchivedCategoryTakesNoNewPlanButAnExistingPlanCanBeEdited() throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, newPlan(rent).build())
            .when()
            .post("/api/v1/plans")
            .andReturn();
    assertEquals(201, created.statusCode(), created.asString());
    Plan plan = PrudentTest.decode(PrudentTest.JSON, created, Plan.newBuilder()).build();
    archive(rent);

    Response newOne =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, newPlan(rent).build())
            .when()
            .post("/api/v1/plans")
            .andReturn();
    assertEquals("conflict", refused(newOne, 409).getCode());

    UpdatePlanRequest keep =
        UpdatePlanRequest.newBuilder()
            .setTitle("Rent (raised)")
            .setAmountMinor(-2_700_00L)
            .setCurrency("PLN")
            .setAccountId(wallet.toString())
            .setCategoryId(rent.toString())
            .setRecurrence(plan.getRecurrence())
            .build();
    Response edited =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, keep)
            .when()
            .put("/api/v1/plans/" + plan.getId())
            .andReturn();
    assertEquals(200, edited.statusCode(), edited.asString());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void confirmingIntoAnArchivedCategoryIsRefusedUntilAnotherIsChosen() throws Exception {
    UUID plan = PrudentTest.seedPlan(PrudentTest.ALICE, wallet, rent, -2_500_00L, "PLN");
    UUID occurrence = PrudentTest.seedOccurrence(PrudentTest.ALICE, plan, LocalDate.of(2026, 9, 1));
    archive(rent);

    Response refusedConfirm =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                ConfirmOccurrenceRequest.getDefaultInstance())
            .when()
            .post("/api/v1/occurrences/" + occurrence + "/confirm")
            .andReturn();
    assertEquals("conflict", refused(refusedConfirm, 409).getCode());
    assertEquals(0, recordCount(), "a refused confirmation must create no record");

    // The user is not stuck: choosing another category for this transaction alone is allowed.
    Response chosen =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                ConfirmOccurrenceRequest.newBuilder().setCategoryId(food.toString()).build())
            .when()
            .post("/api/v1/occurrences/" + occurrence + "/confirm")
            .andReturn();
    assertEquals(201, chosen.statusCode(), chosen.asString());
    ConfirmOccurrenceResponse confirmed =
        PrudentTest.decode(PrudentTest.JSON, chosen, ConfirmOccurrenceResponse.newBuilder())
            .build();
    assertEquals(food.toString(), confirmed.getRecord().getCategoryId());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anArchivedCategoryTakesNoNewBudgetButAnExistingOneCanBeCorrectedOrDeleted() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    archive(food);

    // An empty slot stays empty.
    assertEquals("conflict", refused(putBudget(food, SEPTEMBER, 500_00L), 409).getCode());
    Response none =
        PrudentTest.request(PrudentTest.JSON).when().get(slot(food, SEPTEMBER, "PLN")).andReturn();
    assertEquals(404, none.statusCode(), "a refused write must persist nothing");

    // A filled slot is history being corrected.
    Response corrected = putBudget(food, OCTOBER, 900_00L);
    assertEquals(200, corrected.statusCode(), corrected.asString());
    assertEquals(
        900_00L,
        PrudentTest.decode(PrudentTest.JSON, corrected, Budget.newBuilder()).build().getAmountMinor());

    assertEquals(
        204,
        PrudentTest.request(PrudentTest.JSON).when().delete(slot(food, OCTOBER, "PLN")).statusCode());

    // Restored, the slot can be filled again.
    assertEquals(200, restoreResponse(food).statusCode());
    assertEquals(201, putBudget(food, SEPTEMBER, 500_00L).statusCode());
  }

  // --- Archiving changes no figure --------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void archivingChangesNoSummaryNoAnalyticsAndNoRecord() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, AUGUST, "PLN", 300_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, rent, OCTOBER, "PLN", 2_500_00L);
    PrudentTest.seedRecord(
        PrudentTest.ALICE, wallet, food, -100_00L, "PLN", LocalDate.of(2026, 8, 5));
    PrudentTest.seedRecord(
        PrudentTest.ALICE, wallet, food, -120_00L, "PLN", LocalDate.of(2026, 10, 5));
    PrudentTest.seedRecord(
        PrudentTest.ALICE, wallet, rent, -2_500_00L, "PLN", LocalDate.of(2026, 10, 1));
    PrudentTest.seedCarryReset(PrudentTest.ALICE, food, SEPTEMBER, "PLN", 200_00L);

    BudgetSummaryResponse before = summary(OCTOBER);
    BudgetSummaryResponse beforeAugust = summary(AUGUST);
    SpendByCategoryResponse spendBefore = spend();
    long recordsBefore = recordCount();

    archive(food);

    assertEquals(before, summary(OCTOBER), "an archived category keeps its figures");
    assertEquals(beforeAugust, summary(AUGUST));
    assertEquals(spendBefore, spend());
    assertEquals(recordsBefore, recordCount());

    // And it is still IN the summary, so the totals are the sum of what is listed.
    BudgetSummaryResponse after = summary(OCTOBER);
    assertEquals(2, after.getItemsCount());
    assertEquals(
        after.getItemsList().stream().mapToLong(CategoryBudgetSummary::getPlanMinor).sum(),
        after.getTotalPlanMinor());
    assertEquals(
        after.getItemsList().stream().mapToLong(CategoryBudgetSummary::getActualMinor).sum(),
        after.getTotalActualMinor());
    assertEquals(
        after.getItemsList().stream().mapToLong(CategoryBudgetSummary::getRemainingMinor).sum(),
        after.getTotalRemainingMinor());
    assertTrue(
        spend().getItemsList().stream()
            .map(CategorySpend::getCategoryId)
            .anyMatch(food.toString()::equals),
        "spending in an archived category stays in the analytics");

    // Budgets of an archived category are still listed.
    Response budgets = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/budgets").andReturn();
    assertEquals(
        3,
        PrudentTest.decode(PrudentTest.JSON, budgets, ListBudgetsResponse.newBuilder())
            .build()
            .getBudgetsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aCarryOverResetCanStillBeMadeAndRevokedOnAnArchivedCategory() throws Exception {
    PrudentTest.seedBudget(PrudentTest.ALICE, food, AUGUST, "PLN", 300_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    archive(food);

    // The audit action is on history that already exists, so retiring the category does not lock
    // the user out of correcting it.
    Response reset =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                ResetBudgetCarryOverRequest.newBuilder()
                    .setCategoryId(food.toString())
                    .setMonth("2026-10")
                    .setCurrency("PLN")
                    .build())
            .when()
            .post("/api/v1/budget-carry-over-resets")
            .andReturn();
    assertEquals(201, reset.statusCode(), reset.asString());
    assertEquals(0, summary(OCTOBER).getItems(0).getCarryOverMinor());
  }

  // --- Months without a budget ------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMonthWithNoBudgetIsAnEmptyAnswerWhateverWasSpent() throws Exception {
    // Spending exists, and an earlier month is budgeted; the requested month has no budget.
    PrudentTest.seedBudget(PrudentTest.ALICE, food, AUGUST, "PLN", 300_00L);
    PrudentTest.seedRecord(
        PrudentTest.ALICE, wallet, food, -999_00L, "PLN", LocalDate.of(2026, 9, 10));
    archive(food);

    BudgetSummaryResponse empty = summary(SEPTEMBER);

    assertEquals(0, empty.getItemsCount());
    assertEquals(0L, empty.getTotalPlanMinor());
    assertEquals(0L, empty.getTotalActualMinor());
    assertEquals(0L, empty.getTotalCarryOverMinor());
    assertEquals(0L, empty.getTotalRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anArchivedCategoryCarriesAcrossAGapAsAnActiveOneDoes() throws Exception {
    // Budgeted in August and October, none in September (the gap). Underspent 200 in August.
    PrudentTest.seedBudget(PrudentTest.ALICE, food, AUGUST, "PLN", 300_00L);
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    PrudentTest.seedRecord(
        PrudentTest.ALICE, wallet, food, -100_00L, "PLN", LocalDate.of(2026, 8, 5));
    PrudentTest.seedRecord(
        PrudentTest.ALICE, wallet, food, -50_00L, "PLN", LocalDate.of(2026, 9, 5));

    CategoryBudgetSummary active = summary(OCTOBER).getItems(0);
    archive(food);
    CategoryBudgetSummary archived = summary(OCTOBER).getItems(0);

    assertEquals(200_00L, archived.getCarryOverMinor(), "the gap contributes nothing");
    assertEquals(active, archived);
  }

  // --- Deleting ---------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aCategoryNothingPointsAtCanBeDeletedAndTotalsAreUntouched() throws Exception {
    UUID unused = PrudentTest.seedCategory(PrudentTest.ALICE, "Unused");
    PrudentTest.seedBudget(PrudentTest.ALICE, food, OCTOBER, "PLN", 800_00L);
    PrudentTest.seedRecord(
        PrudentTest.ALICE, wallet, food, -120_00L, "PLN", LocalDate.of(2026, 10, 5));
    BudgetSummaryResponse before = summary(OCTOBER);

    assertEquals(204, deleteResponse(unused).statusCode());

    assertEquals(before, summary(OCTOBER));
    assertFalse(listed(PrudentTest.JSON).stream().anyMatch(c -> c.getId().equals(unused.toString())));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anArchivedCategoryNothingPointsAtCanBeDeleted() throws Exception {
    UUID unused = PrudentTest.seedCategory(PrudentTest.ALICE, "Unused");
    archive(unused);

    assertEquals(204, deleteResponse(unused).statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aCategoryWithAnyHistoryCannotBeDeletedAndTheRefusalPointsToArchiving() throws Exception {
    UUID withRecord = PrudentTest.seedCategory(PrudentTest.ALICE, "Has record");
    PrudentTest.seedRecord(PrudentTest.ALICE, wallet, withRecord, -10_00L, "PLN");
    UUID withPlan = PrudentTest.seedCategory(PrudentTest.ALICE, "Has plan");
    PrudentTest.seedPlan(PrudentTest.ALICE, wallet, withPlan, -10_00L, "PLN");
    UUID withBudget = PrudentTest.seedCategory(PrudentTest.ALICE, "Has budget");
    PrudentTest.seedBudget(PrudentTest.ALICE, withBudget, OCTOBER, "PLN", 100_00L);
    UUID withReset = PrudentTest.seedCategory(PrudentTest.ALICE, "Has reset");
    PrudentTest.seedCarryReset(PrudentTest.ALICE, withReset, OCTOBER, "PLN", 0L);

    for (UUID used : List.of(withRecord, withPlan, withBudget, withReset)) {
      ZenError error = refused(deleteResponse(used), 409);
      assertEquals("conflict", error.getCode());
      assertTrue(error.getMessage().toLowerCase().contains("archive"), error.getMessage());

      // Archiving it does not change that: history outlives the category's use.
      archive(used);
      refused(deleteResponse(used), 409);
      assertTrue(
          listed(PrudentTest.JSON).stream()
              .anyMatch(c -> c.getId().equals(used.toString()) && c.getArchived()),
          "the category and its name must survive the refused delete");
    }
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void recordsStayReadableThroughTheirArchivedCategory() throws Exception {
    PrudentTest.seedRecord(PrudentTest.ALICE, wallet, food, -40_00L, "PLN");
    archive(food);

    Response response = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/records").andReturn();
    ListRecordsResponse records =
        PrudentTest.decode(PrudentTest.JSON, response, ListRecordsResponse.newBuilder()).build();
    assertEquals(1, records.getRecordsCount());
    String categoryId = records.getRecords(0).getCategoryId();
    assertEquals(food.toString(), categoryId);
    Category named =
        listed(PrudentTest.JSON).stream()
            .filter(c -> c.getId().equals(categoryId))
            .findFirst()
            .orElseThrow();
    assertEquals("Food", named.getTitle(), "the record's category still resolves to a name");
  }
}
