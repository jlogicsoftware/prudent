package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.plan.Frequency;
import prudent.plan.OccurrenceState;
import prudent.plan.PlanClock;
import prudent.plan.PlanOccurrenceEntity;
import prudent.plan.RecurrenceRule;
import prudent.proto.v1.ConfirmOccurrenceRequest;
import prudent.proto.v1.ConfirmOccurrenceResponse;
import prudent.proto.v1.ListOccurrencesResponse;
import prudent.proto.v1.OccurrenceStatus;
import prudent.proto.v1.PlanOccurrence;
import prudent.proto.v1.Record;
import prudent.proto.v1.UpdateRecordRequest;
import prudent.record.RecordEntity;
import zen.proto.v1.ZenError;

/**
 * Manual confirmation of a planned occurrence (M2, jlogicsoftware/prudent#57, ADR-040):
 * confirmation may edit date, amount, account and category, creates exactly one actual transaction
 * and retains the plan link.
 *
 * <p>"Now" is pinned to {@value #NOW}, as in {@link OccurrenceResourceTest}.
 */
@QuarkusTest
class OccurrenceConfirmationTest {

  private static final String NOW = "2026-10-15T10:00:00Z";
  private static final UUID ALICE_ID = UUID.fromString(PrudentTest.ALICE);

  private UUID walletId;
  private UUID savingsId;
  private UUID rentId;
  private UUID foodId;
  private UUID planId;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    walletId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    savingsId = PrudentTest.seedAccount(PrudentTest.ALICE, "Savings", "PLN");
    rentId = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
    foodId = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
    QuarkusMock.installMockForType(
        new PlanClock() {
          @Override
          public Instant now() {
            return Instant.parse(NOW);
          }
        },
        PlanClock.class);
    planId =
        PrudentTest.seedPlan(
            PrudentTest.ALICE,
            walletId,
            rentId,
            -250_000L,
            "PLN",
            new RecurrenceRule(
                Frequency.MONTHLY,
                1,
                LocalDate.of(2026, 8, 10),
                ZoneId.of("Europe/Warsaw"),
                null,
                null));
  }

  // --- Helpers ---------------------------------------------------------------------------------

  private UUID occurrenceOn(String iso) {
    return PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, LocalDate.parse(iso));
  }

  private static Response confirm(String mode, UUID id, ConfirmOccurrenceRequest request)
      throws Exception {
    return PrudentTest.body(PrudentTest.request(mode), mode, request)
        .when()
        .post("/api/v1/occurrences/" + id + "/confirm")
        .andReturn();
  }

  private static ConfirmOccurrenceResponse confirmed(String mode, UUID id, ConfirmOccurrenceRequest request)
      throws Exception {
    Response response = confirm(mode, id, request);
    assertEquals(201, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, ConfirmOccurrenceResponse.newBuilder()).build();
  }

  private static ZenError refused(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  private static long records() {
    return QuarkusTransaction.requiringNew().call(() -> RecordEntity.count());
  }

  private static OccurrenceState stateOf(UUID id) {
    return QuarkusTransaction.requiringNew()
        .call(() -> PlanOccurrenceEntity.<PlanOccurrenceEntity>findById(id).state);
  }

  private static long netOf(UUID accountId) {
    return QuarkusTransaction.requiringNew()
        .call(() -> RecordEntity.netByAccount(ALICE_ID, accountId).getOrDefault("PLN", 0L));
  }

  private static Record getRecord(String id) throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/records/" + id).andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, Record.newBuilder()).build();
  }

  // --- Confirming as planned -------------------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void confirmingWithNothingOverriddenPostsExactlyWhatWasPlanned(String mode) throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");

    ConfirmOccurrenceResponse result =
        confirmed(mode, occurrence, ConfirmOccurrenceRequest.getDefaultInstance());

    Record record = result.getRecord();
    assertEquals("Seeded plan", record.getTitle());
    assertEquals(-250_000L, record.getAmountMinor());
    assertEquals("PLN", record.getCurrency());
    assertEquals("2026-10-10", record.getDate(), "the occurrence's own date");
    assertEquals(walletId.toString(), record.getAccountId());
    assertEquals(rentId.toString(), record.getCategoryId());
    assertFalse(record.getIsCorrection());
    assertEquals(OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED, result.getOccurrence().getStatus());
    assertEquals(occurrence.toString(), result.getOccurrence().getId());
    assertEquals(OccurrenceState.COMPLETED, stateOf(occurrence));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void confirmingCreatesExactlyOneTransactionAndItIsTheOnlyThingThatMovesTheBalance()
      throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");
    occurrenceOn("2026-11-10");
    assertEquals(0, netOf(walletId), "an unconfirmed occurrence has moved nothing");

    confirmed(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance());

    assertEquals(1, records());
    assertEquals(-250_000L, netOf(walletId));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void thePlanPayeeAndNoteTravelWithTheTransaction() throws Exception {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              prudent.plan.PlanEntity plan = prudent.plan.PlanEntity.findById(planId);
              plan.payee = "Landlord";
              plan.note = "Flat 4";
            });
    UUID occurrence = occurrenceOn("2026-10-10");

    Record record =
        confirmed(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance())
            .getRecord();

    assertEquals("Landlord", record.getPayee());
    assertEquals("Flat 4", record.getNote());
  }

  // --- Edits -----------------------------------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void confirmationMayEditDateAmountAccountAndCategory(String mode) throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");
    UUID nextMonth = occurrenceOn("2026-11-10");

    Record record =
        confirmed(
                mode,
                occurrence,
                ConfirmOccurrenceRequest.newBuilder()
                    .setDate("2026-10-12")
                    .setAmountMinor(-251_075L)
                    .setAccountId(savingsId.toString())
                    .setCategoryId(foodId.toString())
                    .build())
            .getRecord();

    assertEquals("2026-10-12", record.getDate());
    assertEquals(-251_075L, record.getAmountMinor());
    assertEquals(savingsId.toString(), record.getAccountId());
    assertEquals(foodId.toString(), record.getCategoryId());
    assertEquals(0, netOf(walletId));
    assertEquals(-251_075L, netOf(savingsId));
    // The edit is for this transaction only: the occurrence keeps its date and the plan and the
    // other occurrences are exactly as they were.
    assertEquals("2026-10-10", occurrenceDate(occurrence));
    assertEquals(OccurrenceState.PLANNED, stateOf(nextMonth));
    Record next =
        confirmed(mode, nextMonth, ConfirmOccurrenceRequest.getDefaultInstance()).getRecord();
    assertEquals(-250_000L, next.getAmountMinor());
    assertEquals(walletId.toString(), next.getAccountId());
    assertEquals(rentId.toString(), next.getCategoryId());
  }

  private static String occurrenceDate(UUID id) {
    return QuarkusTransaction.requiringNew()
        .call(
            () -> PlanOccurrenceEntity.<PlanOccurrenceEntity>findById(id).occurrenceDate.toString());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aSingleOverrideLeavesTheOtherFieldsAsPlanned() throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");

    Record record =
        confirmed(
                PrudentTest.JSON,
                occurrence,
                ConfirmOccurrenceRequest.newBuilder().setDate("2026-10-20").build())
            .getRecord();

    assertEquals("2026-10-20", record.getDate());
    assertEquals(-250_000L, record.getAmountMinor());
    assertEquals(walletId.toString(), record.getAccountId());
    assertEquals(rentId.toString(), record.getCategoryId());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aDatePaidEarlyOrLateIsAccepted_andSoIsConfirmingBeforeTheOccurrenceIsDue() throws Exception {
    UUID future = occurrenceOn("2026-12-10"); // two months ahead of "now"

    Record early =
        confirmed(PrudentTest.JSON, future, ConfirmOccurrenceRequest.getDefaultInstance())
            .getRecord();

    assertEquals("2026-12-10", early.getDate());
    ListOccurrencesResponse upcoming = upcoming();
    PlanOccurrence listed =
        upcoming.getOccurrencesList().stream()
            .filter(o -> o.getId().equals(future.toString()))
            .findFirst()
            .orElseThrow();
    assertEquals(OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED, listed.getStatus());
  }

  private static ListOccurrencesResponse upcoming() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .get("/api/v1/occurrences/upcoming?days=90")
            .andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ListOccurrencesResponse.newBuilder())
        .build();
  }

  // --- The plan link ---------------------------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void theTransactionRetainsThePlanLink_evenAfterItIsEdited(String mode) throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");

    Record record =
        confirmed(mode, occurrence, ConfirmOccurrenceRequest.getDefaultInstance()).getRecord();

    assertEquals(planId.toString(), record.getPlanId());
    assertEquals(occurrence.toString(), record.getPlanOccurrenceId());
    Record read = getRecord(record.getId());
    assertEquals(planId.toString(), read.getPlanId());
    assertEquals(occurrence.toString(), read.getPlanOccurrenceId());

    // Editing the transaction is an ordinary record edit, and it does not sever where it came from.
    Response edit =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                UpdateRecordRequest.newBuilder()
                    .setTitle("Rent, October")
                    .setAmountMinor(-260_000L)
                    .setDate("2026-10-11")
                    .setCategoryId(rentId.toString())
                    .setAccountId(walletId.toString())
                    .setCurrency("PLN")
                    .build())
            .when()
            .put("/api/v1/records/" + record.getId())
            .andReturn();
    assertEquals(200, edit.statusCode(), edit.asString());
    Record edited = PrudentTest.decode(PrudentTest.JSON, edit, Record.newBuilder()).build();
    assertEquals(-260_000L, edited.getAmountMinor());
    assertEquals(planId.toString(), edited.getPlanId());
    assertEquals(occurrence.toString(), edited.getPlanOccurrenceId());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anOrdinaryRecordHasNoPlanLink() throws Exception {
    UUID record = PrudentTest.seedRecord(PrudentTest.ALICE, walletId, rentId, -100L, "PLN");

    Record read = getRecord(record.toString());

    assertFalse(read.hasPlanId());
    assertFalse(read.hasPlanOccurrenceId());
  }

  // --- Exactly once ----------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void confirmingTwiceIsRefusedAndPostsNothingTheSecondTime() throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");
    confirmed(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance());

    Response again = confirm(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance());

    assertEquals("conflict", refused(again, 409).getCode());
    assertEquals(1, records());
    assertEquals(-250_000L, netOf(walletId));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aSkippedOccurrenceMustBeRestoredBeforeItCanBeConfirmed() throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");
    assertEquals(
        200,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .post("/api/v1/occurrences/" + occurrence + "/skip")
            .statusCode());

    Response refused = confirm(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance());
    assertEquals("conflict", refused(refused, 409).getCode());
    assertEquals(0, records());
    assertEquals(OccurrenceState.SKIPPED, stateOf(occurrence));

    assertEquals(
        200,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .post("/api/v1/occurrences/" + occurrence + "/restore")
            .statusCode());
    confirmed(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance());
    assertEquals(1, records());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aConfirmedOccurrenceCanNoLongerBeSkippedOrRestored() throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");
    confirmed(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance());

    for (String action : new String[] {"skip", "restore"}) {
      Response response =
          PrudentTest.request(PrudentTest.JSON)
              .when()
              .post("/api/v1/occurrences/" + occurrence + "/" + action)
              .andReturn();
      assertEquals("conflict", refused(response, 409).getCode(), action);
    }
    assertEquals(OccurrenceState.COMPLETED, stateOf(occurrence));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void confirmedOccurrencesLeaveTheOverdueList() throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");
    confirmed(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance());

    Response response =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/occurrences/overdue").andReturn();
    ListOccurrencesResponse overdue =
        PrudentTest.decode(PrudentTest.JSON, response, ListOccurrencesResponse.newBuilder())
            .build();

    assertTrue(
        overdue.getOccurrencesList().stream().noneMatch(o -> o.getId().equals(occurrence.toString())));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void racingConfirmationsPostExactlyOnce() throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");
    int runners = 8;
    ExecutorService pool = Executors.newFixedThreadPool(runners);
    CountDownLatch ready = new CountDownLatch(runners);
    CountDownLatch go = new CountDownLatch(1);
    int created = 0;
    int conflicts = 0;
    List<Integer> statuses = new ArrayList<>();
    try {
      List<Future<Integer>> runs = new ArrayList<>();
      for (int i = 0; i < runners; i++) {
        runs.add(
            pool.submit(
                () -> {
                  ready.countDown();
                  go.await();
                  return PrudentTest.body(
                          PrudentTest.request(PrudentTest.JSON),
                          PrudentTest.JSON,
                          ConfirmOccurrenceRequest.getDefaultInstance())
                      .when()
                      .post("/api/v1/occurrences/" + occurrence + "/confirm")
                      .statusCode();
                }));
      }
      ready.await();
      go.countDown();
      for (Future<Integer> run : runs) {
        int status = run.get();
        statuses.add(status);
        if (status == 201) {
          created++;
        } else if (status == 409) {
          conflicts++;
        }
      }
    } finally {
      pool.shutdownNow();
    }

    // The row lock serialised them: one saw PLANNED and won, the rest waited and saw COMPLETED.
    assertEquals(1, created, statuses.toString());
    assertEquals(runners - 1, conflicts, statuses.toString());
    assertEquals(1, records());
    assertEquals(-250_000L, netOf(walletId));
  }

  // --- Refusals leave nothing behind -----------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRefusedEditKeepsTheOccurrenceOpenAndPostsNothing() throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Wallet", "PLN");
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Rent");
    UUID euroOnly = PrudentTest.seedAccount(PrudentTest.ALICE, "Euro", "EUR");

    ConfirmOccurrenceRequest[] refusals = {
      ConfirmOccurrenceRequest.newBuilder().setAmountMinor(0).build(), // zero moves nothing
      ConfirmOccurrenceRequest.newBuilder().setDate("2026-02-30").build(), // no such day
      ConfirmOccurrenceRequest.newBuilder().setDate("soon").build(),
      ConfirmOccurrenceRequest.newBuilder().setAccountId(bobsAccount.toString()).build(),
      ConfirmOccurrenceRequest.newBuilder().setAccountId(UUID.randomUUID().toString()).build(),
      ConfirmOccurrenceRequest.newBuilder().setAccountId("not-a-uuid").build(),
      ConfirmOccurrenceRequest.newBuilder().setCategoryId(bobsCategory.toString()).build(),
      ConfirmOccurrenceRequest.newBuilder().setCategoryId(UUID.randomUUID().toString()).build(),
      // The plan is in PLN, and this account holds only EUR.
      ConfirmOccurrenceRequest.newBuilder().setAccountId(euroOnly.toString()).build(),
    };
    for (ConfirmOccurrenceRequest request : refusals) {
      Response response = confirm(PrudentTest.JSON, occurrence, request);
      assertEquals("invalid", refused(response, 400).getCode(), request.toString());
      // Rolled back whole: the state change did not survive the rejected record.
      assertEquals(OccurrenceState.PLANNED, stateOf(occurrence), request.toString());
      assertEquals(0, records(), request.toString());
    }

    // ... and the same occurrence then confirms normally.
    confirmed(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance());
    assertEquals(1, records());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void someoneElsesOrUnknownOccurrencesAreNotFound() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Wallet", "PLN");
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Rent");
    UUID bobsPlan = PrudentTest.seedPlan(PrudentTest.BOB, bobsAccount, bobsCategory, -1L, "PLN");
    UUID bobsOccurrence =
        PrudentTest.seedOccurrence(PrudentTest.BOB, bobsPlan, LocalDate.of(2026, 10, 1));

    for (String id :
        new String[] {bobsOccurrence.toString(), UUID.randomUUID().toString(), "not-a-uuid"}) {
      Response response =
          PrudentTest.body(
                  PrudentTest.request(PrudentTest.JSON),
                  PrudentTest.JSON,
                  ConfirmOccurrenceRequest.getDefaultInstance())
              .when()
              .post("/api/v1/occurrences/" + id + "/confirm")
              .andReturn();
      assertEquals("not_found", refused(response, 404).getCode(), id);
    }
    assertEquals(OccurrenceState.PLANNED, stateOf(bobsOccurrence));
    assertEquals(0, records());
  }

  @Test
  void anUnauthenticatedCallerIsRefused() {
    assertEquals(
        401,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .post("/api/v1/occurrences/" + UUID.randomUUID() + "/confirm")
            .statusCode());
  }

  // --- What happens when the transaction or the plan goes away ---------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void deletingTheTransactionReopensTheOccurrenceSoItCanBeConfirmedAgain() throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");
    Record record =
        confirmed(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance())
            .getRecord();

    Response deleted =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/records/" + record.getId())
            .andReturn();

    assertEquals(204, deleted.statusCode(), deleted.asString());
    assertEquals(OccurrenceState.PLANNED, stateOf(occurrence));
    assertEquals(0, records());
    assertEquals(0, netOf(walletId));
    confirmed(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance());
    assertEquals(1, records());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void deletingThePlanKeepsItsTransactionsInTheLedgerWithoutTheLink() throws Exception {
    UUID occurrence = occurrenceOn("2026-10-10");
    occurrenceOn("2026-11-10");
    Record record =
        confirmed(PrudentTest.JSON, occurrence, ConfirmOccurrenceRequest.getDefaultInstance())
            .getRecord();

    Response deleted =
        PrudentTest.request(PrudentTest.JSON).when().delete("/api/v1/plans/" + planId).andReturn();

    assertEquals(204, deleted.statusCode(), deleted.asString());
    assertEquals(0, QuarkusTransaction.requiringNew().call(() -> PlanOccurrenceEntity.count()));
    Record kept = getRecord(record.getId());
    assertEquals(-250_000L, kept.getAmountMinor());
    assertFalse(kept.hasPlanId());
    assertFalse(kept.hasPlanOccurrenceId());
    assertEquals(-250_000L, netOf(walletId), "the money it moved stays moved");
    assertNull(
        QuarkusTransaction.requiringNew()
            .call(() -> RecordEntity.<RecordEntity>findById(UUID.fromString(record.getId())).planId));
  }
}
