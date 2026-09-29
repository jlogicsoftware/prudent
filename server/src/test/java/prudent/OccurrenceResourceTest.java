package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
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
import prudent.error.PrudentException;
import prudent.plan.Frequency;
import prudent.plan.OccurrenceState;
import prudent.plan.PlanClock;
import prudent.plan.PlanOccurrenceEntity;
import prudent.plan.RecurrenceRule;
import prudent.proto.v1.ListOccurrencesResponse;
import prudent.proto.v1.OccurrenceStatus;
import prudent.proto.v1.PlanOccurrence;
import prudent.record.RecordEntity;
import zen.proto.v1.ZenError;

/**
 * The planned-occurrence lifecycle and its two views (M2, jlogicsoftware/prudent#56, ADR-039):
 * planned, completed, skipped and overdue occurrences in the upcoming and overdue lists, and only
 * the state transitions the lifecycle allows.
 *
 * <p>"Now" is pinned to {@value #NOW}, so a test can say which day it is — and, in the time-zone
 * test, which day it is <em>somewhere else</em>.
 */
@QuarkusTest
class OccurrenceResourceTest {

  private static final String NOW = "2026-10-15T10:00:00Z";
  private static final LocalDate TODAY = LocalDate.of(2026, 10, 15);

  private UUID walletId;
  private UUID rentId;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    walletId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    rentId = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
    QuarkusMock.installMockForType(
        new PlanClock() {
          @Override
          public Instant now() {
            return Instant.parse(NOW);
          }
        },
        PlanClock.class);
  }

  private static LocalDate d(String iso) {
    return LocalDate.parse(iso);
  }

  private UUID plan(RecurrenceRule rule) {
    return PrudentTest.seedPlan(PrudentTest.ALICE, walletId, rentId, -100_00L, "PLN", rule);
  }

  /** Monthly on the 10th from August, Warsaw: 8/10 and 9/10 and 10/10 are behind, 11/10 ahead. */
  private UUID monthlyOnTheTenth() {
    return plan(
        new RecurrenceRule(
            Frequency.MONTHLY, 1, d("2026-08-10"), ZoneId.of("Europe/Warsaw"), null, null));
  }

  private static ListOccurrencesResponse list(String mode, String path) throws Exception {
    Response response = PrudentTest.request(mode).when().get(path).andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, ListOccurrencesResponse.newBuilder()).build();
  }

  private static List<String> dates(ListOccurrencesResponse response) {
    return response.getOccurrencesList().stream().map(PlanOccurrence::getOccurrenceDate).toList();
  }

  private static Response post(String mode, String path) {
    return PrudentTest.request(mode).when().post(path).andReturn();
  }

  private static ZenError refused(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  private static long rows() {
    return QuarkusTransaction.requiringNew().call(() -> PlanOccurrenceEntity.count());
  }

  // --- The views -------------------------------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void upcoming_listsFutureOccurrencesWithTheirPlansFields(String mode) throws Exception {
    UUID planId = monthlyOnTheTenth();

    ListOccurrencesResponse upcoming = list(mode, "/api/v1/occurrences/upcoming?days=60");

    // From today on: 10/10 is behind, 11/10 and 12/10 are within 60 days of 10/15.
    assertEquals(List.of("2026-11-10", "2026-12-10"), dates(upcoming));
    PlanOccurrence first = upcoming.getOccurrences(0);
    assertEquals(OccurrenceStatus.OCCURRENCE_STATUS_PLANNED, first.getStatus());
    assertEquals(planId.toString(), first.getPlanId());
    assertEquals(-100_00L, first.getAmountMinor());
    assertEquals("PLN", first.getCurrency());
    assertEquals(walletId.toString(), first.getAccountId());
    assertEquals(rentId.toString(), first.getCategoryId());
    assertEquals("Seeded plan", first.getTitle());
    assertTrue(!first.getId().isBlank());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void overdue_listsPlannedOccurrencesWhoseDateHasPassed(String mode) throws Exception {
    monthlyOnTheTenth();

    ListOccurrencesResponse overdue = list(mode, "/api/v1/occurrences/overdue");

    // Nothing was generated for the plan before this call: the view generated its own history.
    assertEquals(List.of("2026-08-10", "2026-09-10", "2026-10-10"), dates(overdue));
    assertTrue(
        overdue.getOccurrencesList().stream()
            .allMatch(o -> o.getStatus() == OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void upcomingDefaultsToThirtyDaysAndAnOccurrenceDueTodayIsPlannedNotOverdue() throws Exception {
    plan(
        new RecurrenceRule(
            Frequency.DAILY, 1, TODAY, ZoneId.of("Europe/Warsaw"), null, null));

    ListOccurrencesResponse upcoming = list(PrudentTest.JSON, "/api/v1/occurrences/upcoming");

    assertEquals(31, upcoming.getOccurrencesCount(), "today through today + 30");
    assertEquals("2026-10-15", upcoming.getOccurrences(0).getOccurrenceDate());
    assertEquals(
        OccurrenceStatus.OCCURRENCE_STATUS_PLANNED, upcoming.getOccurrences(0).getStatus());
    assertEquals("2026-11-14", upcoming.getOccurrences(30).getOccurrenceDate());
    assertEquals(
        0, list(PrudentTest.JSON, "/api/v1/occurrences/overdue").getOccurrencesCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void everyStateAppearsWhereItBelongs() throws Exception {
    UUID planId = monthlyOnTheTenth();
    UUID skippedFuture =
        PrudentTest.seedOccurrence(
            PrudentTest.ALICE, planId, d("2026-11-10"), OccurrenceState.SKIPPED);
    UUID completedFuture =
        PrudentTest.seedOccurrence(
            PrudentTest.ALICE, planId, d("2026-12-10"), OccurrenceState.COMPLETED);
    // Resolved in the past: neither is overdue, and neither is an open commitment.
    PrudentTest.seedOccurrence(
        PrudentTest.ALICE, planId, d("2026-08-10"), OccurrenceState.COMPLETED);
    PrudentTest.seedOccurrence(
        PrudentTest.ALICE, planId, d("2026-09-10"), OccurrenceState.SKIPPED);

    ListOccurrencesResponse upcoming = list(PrudentTest.JSON, "/api/v1/occurrences/upcoming?days=60");
    ListOccurrencesResponse overdue = list(PrudentTest.JSON, "/api/v1/occurrences/overdue");

    assertEquals(List.of("2026-11-10", "2026-12-10"), dates(upcoming));
    assertEquals(skippedFuture.toString(), upcoming.getOccurrences(0).getId());
    assertEquals(OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED, upcoming.getOccurrences(0).getStatus());
    assertEquals(completedFuture.toString(), upcoming.getOccurrences(1).getId());
    assertEquals(
        OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED, upcoming.getOccurrences(1).getStatus());
    // Only 10/10 is left open and past: the seeded 8/10 and 9/10 were resolved.
    assertEquals(List.of("2026-10-10"), dates(overdue));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aPlanIsOverdueOnItsOwnCalendarDayNotTheServers() throws Exception {
    // 10:00Z on 10/15: it is already 10/16 in Kiritimati (UTC+14) and still 10/14 in Pago Pago
    // (UTC-11). The same civil date, 10/15, is overdue in one zone and still ahead in the other.
    UUID early =
        plan(new RecurrenceRule(Frequency.ONCE, 1, TODAY, ZoneId.of("Pacific/Kiritimati"), null, null));
    UUID late =
        plan(new RecurrenceRule(Frequency.ONCE, 1, TODAY, ZoneId.of("Pacific/Pago_Pago"), null, null));

    ListOccurrencesResponse overdue = list(PrudentTest.JSON, "/api/v1/occurrences/overdue");
    ListOccurrencesResponse upcoming = list(PrudentTest.JSON, "/api/v1/occurrences/upcoming?days=1");

    assertEquals(1, overdue.getOccurrencesCount());
    assertEquals(early.toString(), overdue.getOccurrences(0).getPlanId());
    assertEquals(1, upcoming.getOccurrencesCount());
    assertEquals(late.toString(), upcoming.getOccurrences(0).getPlanId());
    assertEquals(OccurrenceStatus.OCCURRENCE_STATUS_PLANNED, upcoming.getOccurrences(0).getStatus());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void viewingIsIdempotent_repeatedCallsGenerateNothingNew() throws Exception {
    monthlyOnTheTenth();

    ListOccurrencesResponse firstUpcoming = list(PrudentTest.JSON, "/api/v1/occurrences/upcoming?days=60");
    ListOccurrencesResponse firstOverdue = list(PrudentTest.JSON, "/api/v1/occurrences/overdue");
    long afterFirst = rows();
    ListOccurrencesResponse secondUpcoming = list(PrudentTest.JSON, "/api/v1/occurrences/upcoming?days=60");
    ListOccurrencesResponse secondOverdue = list(PrudentTest.JSON, "/api/v1/occurrences/overdue");

    assertEquals(5, afterFirst, "8/10 9/10 10/10 11/10 12/10, each once");
    assertEquals(afterFirst, rows());
    assertEquals(firstUpcoming, secondUpcoming, "same rows, same ids");
    assertEquals(firstOverdue, secondOverdue);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aPlanStartingAfterTheWindowContributesNothingYet() throws Exception {
    plan(new RecurrenceRule(Frequency.MONTHLY, 1, d("2027-06-01"), ZoneId.of("Europe/Warsaw"), null, null));

    assertEquals(0, list(PrudentTest.JSON, "/api/v1/occurrences/upcoming").getOccurrencesCount());
    assertEquals(0, list(PrudentTest.JSON, "/api/v1/occurrences/overdue").getOccurrencesCount());
    assertEquals(0, rows());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void upcomingRefusesAnUnusableHorizon() throws Exception {
    for (String days : new String[] {"0", "-1", "367"}) {
      Response response =
          PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/occurrences/upcoming?days=" + days).andReturn();
      assertEquals("invalid", refused(response, 400).getCode(), days);
    }
    assertEquals(0, list(PrudentTest.JSON, "/api/v1/occurrences/upcoming?days=366").getOccurrencesCount());
  }

  // --- Skip and restore ------------------------------------------------------------------------

  private String firstOverdueId() throws Exception {
    return list(PrudentTest.JSON, "/api/v1/occurrences/overdue").getOccurrences(0).getId();
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void skip_resolvesAnOverdueOccurrenceAndRestoreReopensIt(String mode) throws Exception {
    monthlyOnTheTenth();
    String id = firstOverdueId();

    Response skipped = post(mode, "/api/v1/occurrences/" + id + "/skip");
    assertEquals(200, skipped.statusCode(), skipped.asString());
    PlanOccurrence afterSkip = PrudentTest.decode(mode, skipped, PlanOccurrence.newBuilder()).build();
    assertEquals(OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED, afterSkip.getStatus());
    assertEquals("2026-08-10", afterSkip.getOccurrenceDate());
    assertEquals(
        List.of("2026-09-10", "2026-10-10"),
        dates(list(mode, "/api/v1/occurrences/overdue")),
        "a skipped occurrence is no longer overdue");

    Response restored = post(mode, "/api/v1/occurrences/" + id + "/restore");
    assertEquals(200, restored.statusCode(), restored.asString());
    // Its date is still in the past, so restoring reopens it as overdue, not as planned.
    assertEquals(
        OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE,
        PrudentTest.decode(mode, restored, PlanOccurrence.newBuilder()).build().getStatus());
    assertEquals(
        List.of("2026-08-10", "2026-09-10", "2026-10-10"),
        dates(list(mode, "/api/v1/occurrences/overdue")));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void skip_aFutureOccurrenceKeepsItVisibleInUpcomingAsSkipped() throws Exception {
    monthlyOnTheTenth();
    String id = list(PrudentTest.JSON, "/api/v1/occurrences/upcoming").getOccurrences(0).getId();

    assertEquals(200, post(PrudentTest.JSON, "/api/v1/occurrences/" + id + "/skip").statusCode());

    PlanOccurrence listed = list(PrudentTest.JSON, "/api/v1/occurrences/upcoming").getOccurrences(0);
    assertEquals(id, listed.getId());
    assertEquals(OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED, listed.getStatus());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void everyInvalidTransitionIsRefusedWithAConflictAndChangesNothing() throws Exception {
    UUID planId = monthlyOnTheTenth();
    UUID planned = PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2026-11-10"));
    UUID skipped =
        PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2026-12-10"), OccurrenceState.SKIPPED);
    UUID completed =
        PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2027-01-10"), OccurrenceState.COMPLETED);

    String[][] attempts = {
      {planned.toString(), "restore"}, // nothing to restore
      {skipped.toString(), "skip"}, // already skipped
      {completed.toString(), "skip"}, // an actual transaction now
      {completed.toString(), "restore"},
    };
    for (String[] attempt : attempts) {
      Response response = post(PrudentTest.JSON, "/api/v1/occurrences/" + attempt[0] + "/" + attempt[1]);
      assertEquals("conflict", refused(response, 409).getCode(), attempt[1] + " on " + attempt[0]);
    }

    assertEquals(OccurrenceState.PLANNED, stateOf(planned));
    assertEquals(OccurrenceState.SKIPPED, stateOf(skipped));
    assertEquals(OccurrenceState.COMPLETED, stateOf(completed));
  }

  private static OccurrenceState stateOf(UUID id) {
    return QuarkusTransaction.requiringNew()
        .call(() -> PlanOccurrenceEntity.<PlanOccurrenceEntity>findById(id).state);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void skippingAndRestoringMoveNoMoney() throws Exception {
    monthlyOnTheTenth();
    String id = firstOverdueId();

    post(PrudentTest.JSON, "/api/v1/occurrences/" + id + "/skip");
    post(PrudentTest.JSON, "/api/v1/occurrences/" + id + "/restore");

    assertEquals(0, QuarkusTransaction.requiringNew().call(() -> RecordEntity.count()));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void transitionsOnSomeoneElsesOrUnknownOccurrencesAreNotFound() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Wallet", "PLN");
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Rent");
    UUID bobsPlan = PrudentTest.seedPlan(PrudentTest.BOB, bobsAccount, bobsCategory, -1L, "PLN");
    UUID bobsOccurrence = PrudentTest.seedOccurrence(PrudentTest.BOB, bobsPlan, d("2026-11-10"));

    for (String id : new String[] {bobsOccurrence.toString(), UUID.randomUUID().toString(), "not-a-uuid"}) {
      for (String action : new String[] {"skip", "restore"}) {
        assertEquals(
            "not_found",
            refused(post(PrudentTest.JSON, "/api/v1/occurrences/" + id + "/" + action), 404).getCode());
      }
    }
    assertEquals(OccurrenceState.PLANNED, stateOf(bobsOccurrence));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theViewsListOnlyTheCallersOccurrences() throws Exception {
    monthlyOnTheTenth();
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Wallet", "PLN");
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Rent");
    UUID bobsPlan = PrudentTest.seedPlan(PrudentTest.BOB, bobsAccount, bobsCategory, -1L, "PLN");
    UUID bobsOccurrence = PrudentTest.seedOccurrence(PrudentTest.BOB, bobsPlan, d("2026-10-01"));

    ListOccurrencesResponse overdue = list(PrudentTest.JSON, "/api/v1/occurrences/overdue");

    assertEquals(3, overdue.getOccurrencesCount());
    assertTrue(overdue.getOccurrencesList().stream().noneMatch(o -> o.getId().equals(bobsOccurrence.toString())));
    assertTrue(overdue.getOccurrencesList().stream().noneMatch(o -> o.getPlanId().equals(bobsPlan.toString())));
  }

  @Test
  void anUnauthenticatedCallerIsRefused() {
    for (String path : new String[] {"/api/v1/occurrences/upcoming", "/api/v1/occurrences/overdue"}) {
      assertEquals(401, PrudentTest.request(PrudentTest.JSON).when().get(path).statusCode(), path);
    }
    assertEquals(
        401,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .post("/api/v1/occurrences/" + UUID.randomUUID() + "/skip")
            .statusCode());
  }

  // --- Races -----------------------------------------------------------------------------------

  @Test
  void concurrentTransitionsOfOneOccurrenceAreSerialised_exactlyOneWins() throws Exception {
    UUID planId = monthlyOnTheTenth();
    UUID occurrence = PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2026-11-10"));
    UUID alice = UUID.fromString(PrudentTest.ALICE);
    int runners = 8;
    ExecutorService pool = Executors.newFixedThreadPool(runners);
    CountDownLatch ready = new CountDownLatch(runners);
    CountDownLatch go = new CountDownLatch(1);
    int wins = 0;
    int refusals = 0;
    try {
      List<Future<Boolean>> runs = new ArrayList<>();
      for (int i = 0; i < runners; i++) {
        runs.add(
            pool.submit(
                () -> {
                  ready.countDown();
                  go.await();
                  try {
                    QuarkusTransaction.requiringNew()
                        .run(
                            () ->
                                PlanOccurrenceEntity.findOwnedForUpdate(alice, occurrence)
                                    .transitionTo(OccurrenceState.SKIPPED));
                    return true;
                  } catch (RuntimeException refused) {
                    // The lock made the losers wait, so they saw SKIPPED and were refused.
                    Throwable cause = refused.getCause() == null ? refused : refused.getCause();
                    assertEquals(PrudentException.class, cause.getClass(), cause.toString());
                    return false;
                  }
                }));
      }
      ready.await();
      go.countDown();
      for (Future<Boolean> run : runs) {
        if (run.get()) {
          wins++;
        } else {
          refusals++;
        }
      }
    } finally {
      pool.shutdownNow();
    }

    assertEquals(1, wins);
    assertEquals(runners - 1, refusals);
    assertEquals(OccurrenceState.SKIPPED, stateOf(occurrence));
  }
}
