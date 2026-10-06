package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.proto.v1.Account;
import prudent.proto.v1.AccountType;
import prudent.proto.v1.CreatePlanRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.ListAccountsResponse;
import prudent.proto.v1.ListPlansResponse;
import prudent.proto.v1.ListRecordsResponse;
import prudent.proto.v1.Plan;
import prudent.proto.v1.Recurrence;
import prudent.proto.v1.RecurrenceFrequency;
import prudent.proto.v1.Reminder;
import prudent.proto.v1.UpdateAccountRequest;
import prudent.proto.v1.UpdatePlanRequest;
import zen.proto.v1.ZenError;

/**
 * The plan surface (M2, jlogicsoftware/prudent#34, ADR-037): one-off and recurring plans, modelled
 * separately from transactions — saving one must move no balance and create no record — and the
 * refusals that keep a plan confirmable into a record later.
 */
@QuarkusTest
class PlanResourceTest {

  private UUID walletId;
  private UUID rentId;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    walletId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN", "EUR");
    rentId = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
  }

  private Recurrence.Builder monthly() {
    return Recurrence.newBuilder()
        .setFrequency(RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY)
        .setInterval(1)
        .setStartDate("2026-10-31")
        .setTimeZone("Europe/Warsaw");
  }

  private CreatePlanRequest.Builder validCreate() {
    return CreatePlanRequest.newBuilder()
        .setTitle("Rent")
        .setAmountMinor(-2_500_00L)
        .setCurrency("PLN")
        .setAccountId(walletId.toString())
        .setCategoryId(rentId.toString())
        .setRecurrence(monthly());
  }

  private static Response post(String mode, CreatePlanRequest request) throws Exception {
    return PrudentTest.body(PrudentTest.request(mode), mode, request)
        .when()
        .post("/api/v1/plans")
        .andReturn();
  }

  private static Plan created(String mode, CreatePlanRequest request) throws Exception {
    Response response = post(mode, request);
    assertEquals(201, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, Plan.newBuilder()).build();
  }

  private static ZenError refused(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  // --- Create and read, both transports ------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void create_roundTripsEveryField(String mode) throws Exception {
    Plan plan =
        created(
            mode,
            validCreate()
                .setPayee("Landlord")
                .setNote("Due on the last day")
                .setRecurrence(monthly().setOccurrenceCount(12))
                .build());

    assertFalse(plan.getId().isBlank(), "the create response must carry a server-minted id");
    assertEquals("Rent", plan.getTitle());
    assertEquals(-2_500_00L, plan.getAmountMinor());
    assertEquals("PLN", plan.getCurrency());
    assertEquals(walletId.toString(), plan.getAccountId());
    assertEquals(rentId.toString(), plan.getCategoryId());
    assertEquals("Landlord", plan.getPayee());
    assertEquals("Due on the last day", plan.getNote());
    Recurrence recurrence = plan.getRecurrence();
    assertEquals(RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY, recurrence.getFrequency());
    assertEquals(1, recurrence.getInterval());
    assertEquals("2026-10-31", recurrence.getStartDate());
    assertEquals("Europe/Warsaw", recurrence.getTimeZone());
    assertEquals(Recurrence.EndCase.OCCURRENCE_COUNT, recurrence.getEndCase());
    assertEquals(12, recurrence.getOccurrenceCount());

    Response read = PrudentTest.request(mode).when().get("/api/v1/plans/" + plan.getId()).andReturn();
    assertEquals(200, read.statusCode());
    assertEquals(plan, PrudentTest.decode(mode, read, Plan.newBuilder()).build());

    Response listed = PrudentTest.request(mode).when().get("/api/v1/plans").andReturn();
    assertEquals(200, listed.statusCode());
    assertEquals(
        List.of(plan),
        PrudentTest.decode(mode, listed, ListPlansResponse.newBuilder()).build().getPlansList());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_oneOffOmitsIntervalAndEnd() throws Exception {
    Plan plan =
        created(
            PrudentTest.JSON,
            validCreate()
                .setRecurrence(
                    Recurrence.newBuilder()
                        .setFrequency(RecurrenceFrequency.RECURRENCE_FREQUENCY_ONCE)
                        .setStartDate("2026-12-24")
                        .setTimeZone("Europe/Warsaw"))
                .build());

    assertEquals(RecurrenceFrequency.RECURRENCE_FREQUENCY_ONCE, plan.getRecurrence().getFrequency());
    assertEquals(1, plan.getRecurrence().getInterval());
    assertEquals(Recurrence.EndCase.END_NOT_SET, plan.getRecurrence().getEndCase());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_customIntervalWithAnUntilDate() throws Exception {
    Plan plan =
        created(
            PrudentTest.JSON,
            validCreate()
                .setAmountMinor(4_000_00L)
                .setRecurrence(
                    Recurrence.newBuilder()
                        .setFrequency(RecurrenceFrequency.RECURRENCE_FREQUENCY_WEEKLY)
                        .setInterval(2)
                        .setStartDate("2026-10-02")
                        .setTimeZone("America/New_York")
                        .setUntilDate("2027-06-30"))
                .build());

    assertEquals(4_000_00L, plan.getAmountMinor(), "positive is planned income");
    assertEquals(2, plan.getRecurrence().getInterval());
    assertEquals("America/New_York", plan.getRecurrence().getTimeZone());
    assertEquals("2027-06-30", plan.getRecurrence().getUntilDate());
  }

  // --- Reminder settings (M5, jlogicsoftware/prudent#40, ADR-054) ---------------------------

  private static Reminder reminder(boolean enabled, int leadDays) {
    return Reminder.newBuilder().setEnabled(enabled).setLeadDays(leadDays).build();
  }

  private ZenError createRefused(CreatePlanRequest request) throws Exception {
    return refused(post(PrudentTest.JSON, request), 400);
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void create_withoutAReminderIsOffWithTheDefaultLeadTime(String mode) throws Exception {
    Plan plan = created(mode, validCreate().build());

    assertTrue(plan.hasReminder(), "a plan always states its reminder setting");
    assertFalse(plan.getReminder().getEnabled(), "reminders are opt-in");
    assertEquals(1, plan.getReminder().getLeadDays());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void create_storesTheChosenReminderAndReadsItBack(String mode) throws Exception {
    Plan plan = created(mode, validCreate().setReminder(reminder(true, 3)).build());

    assertEquals(reminder(true, 3), plan.getReminder());
    Response read = PrudentTest.request(mode).when().get("/api/v1/plans/" + plan.getId()).andReturn();
    assertEquals(reminder(true, 3), PrudentTest.decode(mode, read, Plan.newBuilder()).build().getReminder());
    Response listed = PrudentTest.request(mode).when().get("/api/v1/plans").andReturn();
    assertEquals(
        reminder(true, 3),
        PrudentTest.decode(mode, listed, ListPlansResponse.newBuilder()).build().getPlans(0).getReminder());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void create_zeroDaysIsTheDayItselfNotTheDefault(String mode) throws Exception {
    Plan plan = created(mode, validCreate().setReminder(reminder(true, 0)).build());

    assertTrue(plan.getReminder().getEnabled());
    assertEquals(0, plan.getReminder().getLeadDays());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_enabledWithNoLeadTimeTakesTheDefault() throws Exception {
    Plan plan =
        created(
            PrudentTest.JSON,
            validCreate().setReminder(Reminder.newBuilder().setEnabled(true)).build());

    assertEquals(reminder(true, 1), plan.getReminder());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_aDisabledReminderKeepsTheLeadTimeItWasGiven() throws Exception {
    Plan plan = created(PrudentTest.JSON, validCreate().setReminder(reminder(false, 7)).build());

    assertEquals(reminder(false, 7), plan.getReminder());
  }

  @ParameterizedTest
  @ValueSource(ints = {4, 5, 8, 30, 366, -1})
  @TestSecurity(user = PrudentTest.ALICE)
  void create_anUnsupportedLeadTimeIsRefusedAndNothingIsSaved(int days) throws Exception {
    ZenError error = createRefused(validCreate().setReminder(reminder(true, days)).build());

    assertEquals("invalid", error.getCode());
    assertTrue(error.getMessage().contains("[0, 1, 2, 3, 7]"), error.getMessage());
    Response listed = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/plans").andReturn();
    assertEquals(
        0, PrudentTest.decode(PrudentTest.JSON, listed, ListPlansResponse.newBuilder()).build().getPlansCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_anUnsupportedLeadTimeIsRefusedEvenWhileTheReminderIsOff() throws Exception {
    // The kept lead time is what a later switch-on uses, so it must be one the server supports.
    createRefused(validCreate().setReminder(reminder(false, 4)).build());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aPlanSavedBeforeRemindersExistedReadsAsOff() throws Exception {
    UUID legacy = PrudentTest.seedPlan(PrudentTest.ALICE, walletId, rentId, -100L, "PLN");

    Response read = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/plans/" + legacy).andReturn();

    Plan plan = PrudentTest.decode(PrudentTest.JSON, read, Plan.newBuilder()).build();
    assertEquals(reminder(false, 1), plan.getReminder());
  }

  private Response replaceReminder(Plan plan, Reminder reminder) throws Exception {
    UpdatePlanRequest.Builder update =
        UpdatePlanRequest.newBuilder()
            .setTitle(plan.getTitle())
            .setAmountMinor(plan.getAmountMinor())
            .setCurrency(plan.getCurrency())
            .setAccountId(plan.getAccountId())
            .setCategoryId(plan.getCategoryId())
            .setRecurrence(plan.getRecurrence());
    if (reminder != null) {
      update.setReminder(reminder);
    }
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, update.build())
        .when()
        .put("/api/v1/plans/" + plan.getId())
        .andReturn();
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void replace_changesTheReminder() throws Exception {
    Plan plan = created(PrudentTest.JSON, validCreate().build());

    Response response = replaceReminder(plan, reminder(true, 2));

    assertEquals(200, response.statusCode(), response.asString());
    assertEquals(
        reminder(true, 2),
        PrudentTest.decode(PrudentTest.JSON, response, Plan.newBuilder()).build().getReminder());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void replace_anAbsentReminderResetsToTheDefault() throws Exception {
    Plan plan = created(PrudentTest.JSON, validCreate().setReminder(reminder(true, 7)).build());

    Response response = replaceReminder(plan, null);

    assertEquals(200, response.statusCode(), response.asString());
    assertEquals(
        reminder(false, 1),
        PrudentTest.decode(PrudentTest.JSON, response, Plan.newBuilder()).build().getReminder(),
        "a PUT is a full replacement, so an absent reminder is the default, not 'unchanged'");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void replace_anUnsupportedLeadTimeIsRefusedAndTheSettingIsUnchanged() throws Exception {
    Plan plan = created(PrudentTest.JSON, validCreate().setReminder(reminder(true, 3)).build());

    refused(replaceReminder(plan, reminder(true, 4)), 400);

    Response read = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/plans/" + plan.getId()).andReturn();
    assertEquals(
        reminder(true, 3), PrudentTest.decode(PrudentTest.JSON, read, Plan.newBuilder()).build().getReminder());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void replace_changingOnlyTheReminderKeepsTheGeneratedOccurrences() throws Exception {
    Plan plan = created(PrudentTest.JSON, validCreate().build());
    PrudentTest.seedOccurrence(
        PrudentTest.ALICE, UUID.fromString(plan.getId()), java.time.LocalDate.of(2026, 10, 31));

    Response response = replaceReminder(plan, reminder(true, 1));

    assertEquals(200, response.statusCode(), response.asString());
    assertEquals(
        1,
        occurrenceCount(plan.getId()),
        "a reminder is not part of the recurrence, so it must not drop still-planned occurrences");
  }

  // --- Separate from transactions ------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aPlanMovesNoBalanceAndCreatesNoRecord() throws Exception {
    created(PrudentTest.JSON, validCreate().build());

    Response records = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/records").andReturn();
    assertEquals(
        0,
        PrudentTest.decode(PrudentTest.JSON, records, ListRecordsResponse.newBuilder())
            .build()
            .getRecordsCount(),
        "saving a plan must not write a record — a plan is not a transaction");

    Response accounts =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/accounts").andReturn();
    for (Account account :
        PrudentTest.decode(PrudentTest.JSON, accounts, ListAccountsResponse.newBuilder())
            .build()
            .getAccountsList()) {
      for (CurrencyBalance balance : account.getBalancesList()) {
        assertEquals(0L, balance.getAmountMinor(), "a plan must not move a balance");
      }
    }
  }

  // --- Validation ----------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_refusesAZeroAmountOrBlankTitle() throws Exception {
    assertEquals("invalid", refused(post(PrudentTest.JSON, validCreate().setAmountMinor(0).build()), 400).getCode());
    assertEquals("invalid", refused(post(PrudentTest.JSON, validCreate().setTitle("  ").build()), 400).getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_refusesAnotherUsersAccountOrCategory() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's wallet", "PLN");
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Bob's rent");

    refused(post(PrudentTest.JSON, validCreate().setAccountId(bobsAccount.toString()).build()), 400);
    refused(post(PrudentTest.JSON, validCreate().setCategoryId(bobsCategory.toString()).build()), 400);
    refused(post(PrudentTest.JSON, validCreate().clearAccountId().build()), 400);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_refusesACurrencyTheAccountDoesNotHold() throws Exception {
    ZenError error = refused(post(PrudentTest.JSON, validCreate().setCurrency("USD").build()), 400);
    assertTrue(error.getMessage().contains("USD"), error.getMessage());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_refusesAMissingOrInvalidRecurrence() throws Exception {
    refused(post(PrudentTest.JSON, validCreate().clearRecurrence().build()), 400);
    refused(
        post(
            PrudentTest.JSON,
            validCreate()
                .setRecurrence(
                    monthly().setFrequency(RecurrenceFrequency.RECURRENCE_FREQUENCY_UNSPECIFIED))
                .build()),
        400);
    refused(post(PrudentTest.JSON, validCreate().setRecurrence(monthly().clearInterval()).build()), 400);
    refused(post(PrudentTest.JSON, validCreate().setRecurrence(monthly().clearTimeZone()).build()), 400);
    refused(post(PrudentTest.JSON, validCreate().setRecurrence(monthly().setTimeZone("+02:00")).build()), 400);
    refused(
        post(PrudentTest.JSON, validCreate().setRecurrence(monthly().setUntilDate("2026-10-30")).build()),
        400);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_persistsNothingOnRefusal() throws Exception {
    refused(post(PrudentTest.JSON, validCreate().setRecurrence(monthly().clearTimeZone()).build()), 400);
    Response listed = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/plans").andReturn();
    assertEquals(
        0,
        PrudentTest.decode(PrudentTest.JSON, listed, ListPlansResponse.newBuilder())
            .build()
            .getPlansCount());
  }

  // --- Replace and delete --------------------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void replace_isAFullReplacement(String mode) throws Exception {
    Plan plan = created(mode, validCreate().setNote("old note").build());

    UpdatePlanRequest update =
        UpdatePlanRequest.newBuilder()
            .setTitle("Rent (new flat)")
            .setAmountMinor(-2_800_00L)
            .setCurrency("EUR")
            .setAccountId(walletId.toString())
            .setCategoryId(rentId.toString())
            .setRecurrence(
                monthly().setStartDate("2027-01-01").setTimeZone("Europe/Lisbon").setUntilDate("2027-12-31"))
            .build();
    Response response =
        PrudentTest.body(PrudentTest.request(mode), mode, update)
            .when()
            .put("/api/v1/plans/" + plan.getId())
            .andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    Plan replaced = PrudentTest.decode(mode, response, Plan.newBuilder()).build();

    assertEquals(plan.getId(), replaced.getId());
    assertEquals("Rent (new flat)", replaced.getTitle());
    assertEquals("EUR", replaced.getCurrency());
    assertFalse(replaced.hasNote(), "an absent note on a full replacement clears it");
    assertEquals("Europe/Lisbon", replaced.getRecurrence().getTimeZone());
    assertEquals(Recurrence.EndCase.UNTIL_DATE, replaced.getRecurrence().getEndCase());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void delete_removesThePlan() throws Exception {
    Plan plan = created(PrudentTest.JSON, validCreate().build());

    Response deleted =
        PrudentTest.request(PrudentTest.JSON).when().delete("/api/v1/plans/" + plan.getId()).andReturn();
    assertEquals(204, deleted.statusCode());
    Response read =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/plans/" + plan.getId()).andReturn();
    assertEquals("not_found", refused(read, 404).getCode());
  }

  // --- Occurrences follow the plan (jlogicsoftware/prudent#55, ADR-038) ------------------------

  private static long occurrenceCount(String planId) {
    return io.quarkus.narayana.jta.QuarkusTransaction.requiringNew()
        .call(() -> prudent.plan.PlanOccurrenceEntity.count("planId", UUID.fromString(planId)));
  }

  private Response replaceWith(Plan plan, Recurrence.Builder recurrence, String title) throws Exception {
    UpdatePlanRequest update =
        UpdatePlanRequest.newBuilder()
            .setTitle(title)
            .setAmountMinor(plan.getAmountMinor())
            .setCurrency("PLN")
            .setAccountId(walletId.toString())
            .setCategoryId(rentId.toString())
            .setRecurrence(recurrence)
            .build();
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, update)
        .when()
        .put("/api/v1/plans/" + plan.getId())
        .andReturn();
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void delete_removesTheGeneratedOccurrencesToo() throws Exception {
    Plan plan = created(PrudentTest.JSON, validCreate().build());
    PrudentTest.seedOccurrence(
        PrudentTest.ALICE, UUID.fromString(plan.getId()), java.time.LocalDate.of(2026, 10, 31));

    Response deleted =
        PrudentTest.request(PrudentTest.JSON).when().delete("/api/v1/plans/" + plan.getId()).andReturn();

    assertEquals(204, deleted.statusCode(), deleted.asString());
    assertEquals(0, occurrenceCount(plan.getId()));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void replace_changingTheRuleDropsOccurrencesTheOldRuleGenerated() throws Exception {
    Plan plan = created(PrudentTest.JSON, validCreate().build());
    PrudentTest.seedOccurrence(
        PrudentTest.ALICE, UUID.fromString(plan.getId()), java.time.LocalDate.of(2026, 10, 31));

    Response response = replaceWith(plan, monthly().setStartDate("2026-11-15"), "Rent");

    assertEquals(200, response.statusCode(), response.asString());
    assertEquals(0, occurrenceCount(plan.getId()));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void replace_leavingTheRuleAloneKeepsItsOccurrences() throws Exception {
    Plan plan = created(PrudentTest.JSON, validCreate().build());
    PrudentTest.seedOccurrence(
        PrudentTest.ALICE, UUID.fromString(plan.getId()), java.time.LocalDate.of(2026, 10, 31));

    Response response = replaceWith(plan, monthly(), "Rent, renamed");

    assertEquals(200, response.statusCode(), response.asString());
    assertEquals(1, occurrenceCount(plan.getId()), "a title edit does not move any date");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void replace_changingTheRuleKeepsWhatTheUserResolvedAndWhatTheNewRuleStillProduces()
      throws Exception {
    Plan plan = created(PrudentTest.JSON, validCreate().build());
    UUID id = UUID.fromString(plan.getId());
    // Monthly on the 31st: 10/31 planned, 11/30 skipped, 12/31 completed, 1/31 and 3/31 planned.
    PrudentTest.seedOccurrence(PrudentTest.ALICE, id, java.time.LocalDate.of(2026, 10, 31));
    PrudentTest.seedOccurrence(
        PrudentTest.ALICE, id, java.time.LocalDate.of(2026, 11, 30),
        prudent.plan.OccurrenceState.SKIPPED);
    PrudentTest.seedOccurrence(
        PrudentTest.ALICE, id, java.time.LocalDate.of(2026, 12, 31),
        prudent.plan.OccurrenceState.COMPLETED);
    PrudentTest.seedOccurrence(PrudentTest.ALICE, id, java.time.LocalDate.of(2027, 1, 31));
    PrudentTest.seedOccurrence(PrudentTest.ALICE, id, java.time.LocalDate.of(2027, 3, 31));

    // Every second month from the same anchor: 10/31, 12/31, 2/28 ...
    Response response = replaceWith(plan, monthly().setInterval(2), "Rent");

    assertEquals(200, response.statusCode(), response.asString());
    List<java.time.LocalDate> kept =
        io.quarkus.narayana.jta.QuarkusTransaction.requiringNew()
            .call(
                () ->
                    prudent.plan.PlanOccurrenceEntity.listForPlan(
                            UUID.fromString(PrudentTest.ALICE), id)
                        .stream()
                        .map(o -> o.occurrenceDate)
                        .toList());
    assertEquals(
        List.of(
            java.time.LocalDate.of(2026, 10, 31), // planned, and the new rule still lands here
            java.time.LocalDate.of(2026, 11, 30), // skipped: the user's decision survives
            java.time.LocalDate.of(2026, 12, 31)), // completed: an actual transaction survives
        kept,
        "only the planned dates the new rule no longer produces (1/31, 3/31) are dropped");
  }

  // --- Ownership -----------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anotherUsersPlan_isInvisibleAndUntouchable() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's wallet", "PLN");
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Bob's rent");
    UUID bobsPlan = PrudentTest.seedPlan(PrudentTest.BOB, bobsAccount, bobsCategory, -1_00L, "PLN");

    Response listed = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/plans").andReturn();
    assertEquals(
        0,
        PrudentTest.decode(PrudentTest.JSON, listed, ListPlansResponse.newBuilder())
            .build()
            .getPlansCount());
    refused(PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/plans/" + bobsPlan).andReturn(), 404);
    refused(
        PrudentTest.request(PrudentTest.JSON).when().delete("/api/v1/plans/" + bobsPlan).andReturn(), 404);
    UpdatePlanRequest update =
        UpdatePlanRequest.newBuilder()
            .setTitle("Hijacked")
            .setAmountMinor(-1L)
            .setCurrency("PLN")
            .setAccountId(walletId.toString())
            .setCategoryId(rentId.toString())
            .setRecurrence(monthly())
            .build();
    refused(
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, update)
            .when()
            .put("/api/v1/plans/" + bobsPlan)
            .andReturn(),
        404);
  }

  // --- What a plan protects ------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void deletingAnAccountWithPlans_isRefused() throws Exception {
    created(PrudentTest.JSON, validCreate().build());

    ZenError error =
        refused(
            PrudentTest.request(PrudentTest.JSON).when().delete("/api/v1/accounts/" + walletId).andReturn(),
            409);
    assertEquals("conflict", error.getCode());
    assertTrue(error.getMessage().contains("/api/v1/plans"), error.getMessage());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void deletingACategoryWithPlans_isRefused() throws Exception {
    created(PrudentTest.JSON, validCreate().build());

    ZenError error =
        refused(
            PrudentTest.request(PrudentTest.JSON).when().delete("/api/v1/categories/" + rentId).andReturn(),
            409);
    assertTrue(error.getMessage().contains("plans"), error.getMessage());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void droppingACurrencyAPlanUses_isRefused() throws Exception {
    created(PrudentTest.JSON, validCreate().setCurrency("EUR").build());

    UpdateAccountRequest update =
        UpdateAccountRequest.newBuilder()
            .setName("Wallet")
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .setIsActive(true)
            .addBalances(CurrencyBalance.newBuilder().setCurrency("PLN").setAmountMinor(0L))
            .build();
    ZenError error =
        refused(
            PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, update)
                .when()
                .put("/api/v1/accounts/" + walletId)
                .andReturn(),
            409);
    assertTrue(error.getMessage().contains("EUR"), error.getMessage());
    assertTrue(error.getMessage().contains("plans"), error.getMessage());
  }
}
