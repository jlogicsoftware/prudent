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
import prudent.proto.v1.CreateGoalAllocationRequest;
import prudent.proto.v1.CreateGoalRequest;
import prudent.proto.v1.Goal;
import prudent.proto.v1.GoalAllocation;
import prudent.proto.v1.GoalAllocationKind;
import prudent.proto.v1.GoalEnvelope;
import prudent.proto.v1.ListGoalAllocationsResponse;
import prudent.proto.v1.ListGoalEnvelopesResponse;
import zen.proto.v1.ZenError;

/**
 * Envelope allocation actions (M4, jlogicsoftware/prudent#64, ADR-050): money is allocated to a
 * goal, withdrawn from it or moved between goals in one currency, each as an immutable history
 * entry; an envelope is calculated from that history; and none of it moves an account balance or
 * an analytics total.
 */
@QuarkusTest
class GoalAllocationTest {

  private static final String GOALS = "/api/v1/goals";
  private static final String ALLOCATIONS = "/api/v1/goal-allocations";

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    // Every test but the ones about the cap itself starts with more free money than it can use, so
    // the rules under test are the only thing standing between an entry and the history.
    PrudentTest.seedEligibleAccount(
        PrudentTest.ALICE, "Savings", Long.MAX_VALUE, "PLN", "EUR");
  }

  // --- Helpers ----------------------------------------------------------------------------------

  private static Goal goal(String name, String currency) throws Exception {
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                CreateGoalRequest.newBuilder()
                    .setName(name)
                    .setCurrency(currency)
                    .setTargetAmountMinor(10_000_00L)
                    .build())
            .when()
            .post(GOALS)
            .andReturn();
    assertEquals(201, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, Goal.newBuilder()).build();
  }

  private static Response post(String mode, CreateGoalAllocationRequest request) throws Exception {
    return PrudentTest.body(PrudentTest.request(mode), mode, request).when().post(ALLOCATIONS).andReturn();
  }

  private static Response post(CreateGoalAllocationRequest request) throws Exception {
    return post(PrudentTest.JSON, request);
  }

  private static CreateGoalAllocationRequest.Builder allocate(Goal target, long amount) {
    return CreateGoalAllocationRequest.newBuilder()
        .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE)
        .setTargetGoalId(target.getId())
        .setAmountMinor(amount);
  }

  private static CreateGoalAllocationRequest.Builder withdraw(Goal source, long amount) {
    return CreateGoalAllocationRequest.newBuilder()
        .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW)
        .setSourceGoalId(source.getId())
        .setAmountMinor(amount);
  }

  private static CreateGoalAllocationRequest.Builder move(Goal source, Goal target, long amount) {
    return CreateGoalAllocationRequest.newBuilder()
        .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE)
        .setSourceGoalId(source.getId())
        .setTargetGoalId(target.getId())
        .setAmountMinor(amount);
  }

  private static GoalAllocation recorded(CreateGoalAllocationRequest request) throws Exception {
    Response response = post(request);
    assertEquals(201, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, GoalAllocation.newBuilder()).build();
  }

  private static ZenError refused(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  private static Response get(String path) {
    return PrudentTest.request(PrudentTest.JSON).when().get(path).andReturn();
  }

  private static List<GoalAllocation> history(String query) throws Exception {
    Response response = get(ALLOCATIONS + query);
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ListGoalAllocationsResponse.newBuilder())
        .build()
        .getAllocationsList();
  }

  private static long envelope(Goal goal) throws Exception {
    Response response = get(ALLOCATIONS + "/envelopes");
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ListGoalEnvelopesResponse.newBuilder())
        .build()
        .getEnvelopesList()
        .stream()
        .filter(e -> e.getGoalId().equals(goal.getId()))
        .findFirst()
        .orElseThrow()
        .getAmountMinor();
  }

  private static Response transition(Goal goal, String action) {
    return PrudentTest.request(PrudentTest.JSON)
        .when()
        .post(GOALS + "/" + goal.getId() + "/" + action)
        .andReturn();
  }

  // --- Allocate, withdraw, move -----------------------------------------------------------------

  @ParameterizedTest(name = "{0}")
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void anAllocationIsRecordedAndReadBackIdentically(String mode) throws Exception {
    Goal holiday = goal("Holiday", "PLN");

    Response response = post(mode, allocate(holiday, 250_00L).setNote(" first month ").build());
    assertEquals(201, response.statusCode(), response.asString());
    GoalAllocation entry =
        PrudentTest.decode(mode, response, GoalAllocation.newBuilder()).build();

    assertFalse(entry.getId().isEmpty(), "the server mints the id");
    assertEquals(GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE, entry.getKind());
    assertEquals(holiday.getId(), entry.getTargetGoalId());
    assertFalse(entry.hasSourceGoalId());
    assertEquals("PLN", entry.getCurrency());
    assertEquals(250_00L, entry.getAmountMinor());
    assertEquals("first month", entry.getNote());
    assertEquals(PrudentTest.ALICE, entry.getCreatedBy());
    assertTrue(entry.getCreatedAtMs() > 0);

    Response read =
        PrudentTest.request(mode).when().get(ALLOCATIONS + "/" + entry.getId()).andReturn();
    assertEquals(200, read.statusCode(), read.asString());
    assertEquals(entry, PrudentTest.decode(mode, read, GoalAllocation.newBuilder()).build());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void allocatingAndWithdrawingChangeTheEnvelopeByExactlyTheAmount() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    assertEquals(0, envelope(holiday), "a goal with no entries holds nothing");

    recorded(allocate(holiday, 300_00L).build());
    recorded(allocate(holiday, 50_00L).build());
    assertEquals(350_00L, envelope(holiday));

    GoalAllocation withdrawn = recorded(withdraw(holiday, 120_00L).build());
    assertEquals(GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW, withdrawn.getKind());
    assertEquals(holiday.getId(), withdrawn.getSourceGoalId());
    assertFalse(withdrawn.hasTargetGoalId());
    assertEquals(230_00L, envelope(holiday));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMoveIsOneEntryThatShiftsMoneyBetweenTwoEnvelopes() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    Goal car = goal("Car", "PLN");
    recorded(allocate(holiday, 500_00L).build());

    GoalAllocation moved = recorded(move(holiday, car, 200_00L).setNote("car first").build());

    assertEquals(GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE, moved.getKind());
    assertEquals(holiday.getId(), moved.getSourceGoalId());
    assertEquals(car.getId(), moved.getTargetGoalId());
    assertEquals(300_00L, envelope(holiday));
    assertEquals(200_00L, envelope(car));
    assertEquals(2, history("").size(), "the allocation and the move, not one entry per half");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aWithdrawalMayEmptyAnEnvelopeButNotOverdrawIt() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    recorded(allocate(holiday, 100_00L).build());

    refused(post(withdraw(holiday, 100_01L).build()), 409);
    assertEquals(100_00L, envelope(holiday), "a refused entry changes nothing");

    recorded(withdraw(holiday, 100_00L).build());
    assertEquals(0, envelope(holiday));
    refused(post(withdraw(holiday, 1L).build()), 409);
    assertEquals(2, history("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMoveCannotTakeMoreThanTheSourceHolds() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    Goal car = goal("Car", "PLN");
    recorded(allocate(holiday, 100_00L).build());

    refused(post(move(holiday, car, 100_01L).build()), 409);
    // The target's own balance is irrelevant: only the source is drawn on.
    refused(post(move(car, holiday, 1L).build()), 409);

    assertEquals(100_00L, envelope(holiday));
    assertEquals(0, envelope(car));
    assertEquals(1, history("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anEnvelopeCannotHoldMoreThanAnAmountCan() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    recorded(allocate(holiday, Long.MAX_VALUE).build());

    refused(post(allocate(holiday, 1L).build()), 400);

    assertEquals(Long.MAX_VALUE, envelope(holiday));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anEnvelopeIsTheNetOfItsHistoryEvenWhenTheTotalsWouldOverflow() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    // Each credit alone fits, and so does the net; the running credit total does not.
    recorded(allocate(holiday, Long.MAX_VALUE).build());
    recorded(withdraw(holiday, Long.MAX_VALUE).build());
    recorded(allocate(holiday, Long.MAX_VALUE).build());

    assertEquals(Long.MAX_VALUE, envelope(holiday));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void concurrentWithdrawalsCannotOverdrawAnEnvelope() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    recorded(allocate(holiday, 100_00L).build());
    int attempts = 8;
    java.util.concurrent.ExecutorService pool =
        java.util.concurrent.Executors.newFixedThreadPool(attempts);
    java.util.concurrent.CountDownLatch go = new java.util.concurrent.CountDownLatch(1);
    try {
      List<java.util.concurrent.Future<Integer>> results = new java.util.ArrayList<>();
      for (int i = 0; i < attempts; i++) {
        results.add(
            pool.submit(
                () -> {
                  go.await();
                  return post(withdraw(holiday, 100_00L).build()).statusCode();
                }));
      }
      go.countDown();
      int created = 0;
      for (java.util.concurrent.Future<Integer> result : results) {
        int status = result.get(30, java.util.concurrent.TimeUnit.SECONDS);
        assertTrue(status == 201 || status == 409, "status " + status);
        if (status == 201) {
          created++;
        }
      }
      assertEquals(1, created, "the envelope held the amount once");
    } finally {
      pool.shutdownNow();
    }

    assertEquals(0, envelope(holiday));
    assertEquals(2, history("").size());
  }

  // --- Currency safety --------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void moneyIsNeverMovedBetweenCurrencies() throws Exception {
    Goal zloty = goal("Holiday", "PLN");
    Goal euro = goal("Rainy day", "EUR");
    recorded(allocate(zloty, 100_00L).build());

    refused(post(move(zloty, euro, 50_00L).build()), 400);

    assertEquals(100_00L, envelope(zloty));
    assertEquals(0, envelope(euro));
    assertEquals(1, history("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anEntryCarriesItsGoalsCurrency() throws Exception {
    Goal euro = goal("Rainy day", "EUR");

    assertEquals("EUR", recorded(allocate(euro, 10_00L).build()).getCurrency());
    assertEquals("EUR", recorded(withdraw(euro, 5_00L).build()).getCurrency());
    assertEquals(
        List.of("EUR"),
        PrudentTest.decode(
                PrudentTest.JSON,
                get(ALLOCATIONS + "/envelopes"),
                ListGoalEnvelopesResponse.newBuilder())
            .build()
            .getEnvelopesList()
            .stream()
            .map(GoalEnvelope::getCurrency)
            .toList());
  }

  // --- Validation -------------------------------------------------------------------------------

  @ParameterizedTest(name = "{0}")
  @ValueSource(longs = {0L, -1L, Long.MIN_VALUE})
  @TestSecurity(user = PrudentTest.ALICE)
  void anAmountThatIsNotPositiveIsRefusedForEveryKind(long amount) throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    Goal car = goal("Car", "PLN");

    refused(post(allocate(holiday, amount).build()), 400);
    refused(post(withdraw(holiday, amount).build()), 400);
    refused(post(move(holiday, car, amount).build()), 400);

    assertEquals(0, history("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aKindThatIsMissingOrUnknownIsRefused() throws Exception {
    Goal holiday = goal("Holiday", "PLN");

    refused(post(CreateGoalAllocationRequest.newBuilder().setTargetGoalId(holiday.getId()).setAmountMinor(1).build()), 400);
    refused(
        PrudentTest.request(PrudentTest.JSON)
            .body("{\"kind\":\"GOAL_ALLOCATION_KIND_REFUND\",\"targetGoalId\":\"" + holiday.getId()
                + "\",\"amountMinor\":\"1\"}")
            .when()
            .post(ALLOCATIONS)
            .andReturn(),
        400);
    assertEquals(0, history("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void eachKindNeedsExactlyTheGoalsItUses() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    Goal car = goal("Car", "PLN");
    recorded(allocate(holiday, 100_00L).build());

    // Missing a goal it needs.
    refused(post(CreateGoalAllocationRequest.newBuilder()
        .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE).setAmountMinor(1).build()), 400);
    refused(post(CreateGoalAllocationRequest.newBuilder()
        .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW).setAmountMinor(1).build()), 400);
    refused(post(allocate(holiday, 1).clearTargetGoalId().setSourceGoalId(holiday.getId()).build()), 400);
    refused(post(move(holiday, car, 1).clearTargetGoalId().build()), 400);
    refused(post(move(holiday, car, 1).clearSourceGoalId().build()), 400);
    // Carrying a goal it does not use.
    refused(post(allocate(holiday, 1).setSourceGoalId(car.getId()).build()), 400);
    refused(post(withdraw(holiday, 1).setTargetGoalId(car.getId()).build()), 400);

    assertEquals(1, history("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMoveToTheSameGoalIsRefused() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    recorded(allocate(holiday, 100_00L).build());

    refused(post(move(holiday, holiday, 10_00L).build()), 400);

    assertEquals(1, history("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMalformedGoalIdInTheBodyIsABadRequestAndAnUnknownOneIsNotFound() throws Exception {
    Goal holiday = goal("Holiday", "PLN");

    refused(post(allocate(holiday, 1).setTargetGoalId("not-a-uuid").build()), 400);
    refused(post(allocate(holiday, 1).setTargetGoalId(UUID.randomUUID().toString()).build()), 404);
    refused(post(move(holiday, holiday, 1).setTargetGoalId(UUID.randomUUID().toString()).build()), 404);
    assertEquals(0, history("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aNoteMayBeFiveHundredCharactersAndNoMore() throws Exception {
    Goal holiday = goal("Holiday", "PLN");

    assertEquals(500, recorded(allocate(holiday, 1).setNote("é".repeat(500)).build()).getNote().length());
    refused(post(allocate(holiday, 1).setNote("x".repeat(501)).build()), 400);
    assertEquals("", recorded(allocate(holiday, 1).setNote("   ").build()).getNote());
    assertEquals(2, history("").size());
  }

  // --- Goal states ------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void moneyGoesIntoAnActiveGoalOnly() throws Exception {
    Goal done = goal("Done", "PLN");
    Goal active = goal("Active", "PLN");
    recorded(allocate(active, 100_00L).build());
    recorded(allocate(done, 100_00L).build());
    assertEquals(200, transition(done, "complete").statusCode());

    refused(post(allocate(done, 1).build()), 409);
    refused(post(move(active, done, 1).build()), 409);

    assertEquals(100_00L, envelope(done));
    assertEquals(100_00L, envelope(active));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aCompletedGoalCanStillReleaseWhatIsLeftInIt() throws Exception {
    Goal done = goal("Done", "PLN");
    Goal active = goal("Active", "PLN");
    recorded(allocate(done, 100_00L).build());
    assertEquals(200, transition(done, "complete").statusCode());

    recorded(move(done, active, 40_00L).build());
    recorded(withdraw(done, 60_00L).build());

    assertEquals(0, envelope(done));
    assertEquals(40_00L, envelope(active));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anArchivedGoalIsReadOnlyUntilReactivated() throws Exception {
    Goal archived = goal("Old", "PLN");
    Goal active = goal("Active", "PLN");
    assertEquals(200, transition(archived, "archive").statusCode());

    refused(post(allocate(archived, 1).build()), 409);
    refused(post(move(active, archived, 1).build()), 409);
    refused(post(withdraw(archived, 1).build()), 409);

    assertEquals(200, transition(archived, "reactivate").statusCode());
    recorded(allocate(archived, 5_00L).build());
    assertEquals(5_00L, envelope(archived));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aGoalWithMoneySetAsideCannotBeArchivedUntilItIsReleased() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    recorded(allocate(holiday, 100_00L).build());

    refused(transition(holiday, "archive"), 409);
    assertEquals(
        "GOAL_STATUS_ACTIVE",
        PrudentTest.decode(PrudentTest.JSON, get(GOALS + "/" + holiday.getId()), Goal.newBuilder())
            .build()
            .getStatus()
            .name());

    recorded(withdraw(holiday, 100_00L).build());
    assertEquals(200, transition(holiday, "archive").statusCode());
    // A completed goal with money is held to the same rule on its way to the archive.
    assertEquals(200, transition(holiday, "reactivate").statusCode());
    recorded(allocate(holiday, 1L).build());
    assertEquals(200, transition(holiday, "complete").statusCode());
    refused(transition(holiday, "archive"), 409);
  }

  // --- History ----------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theHistoryIsNewestFirstAndCanBeNarrowedToOneGoal() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    Goal car = goal("Car", "PLN");
    Goal other = goal("Other", "PLN");
    GoalAllocation first = recorded(allocate(holiday, 100_00L).build());
    Thread.sleep(5);
    GoalAllocation second = recorded(move(holiday, car, 30_00L).build());
    Thread.sleep(5);
    GoalAllocation third = recorded(allocate(other, 1_00L).build());

    assertEquals(List.of(third, second, first), history(""));
    assertEquals(List.of(second, first), history("?goalId=" + holiday.getId()));
    assertEquals(List.of(second), history("?goalId=" + car.getId()));
    assertEquals(List.of(third), history("?goalId=" + other.getId()));
    refused(get(ALLOCATIONS + "?goalId=not-a-uuid"), 400);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theHistoryCannotBeEditedOrDeleted() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    GoalAllocation entry = recorded(allocate(holiday, 100_00L).build());
    String path = ALLOCATIONS + "/" + entry.getId();

    for (Response response :
        List.of(
            PrudentTest.request(PrudentTest.JSON).when().delete(path).andReturn(),
            PrudentTest.body(
                    PrudentTest.request(PrudentTest.JSON),
                    PrudentTest.JSON,
                    allocate(holiday, 1L).build())
                .when()
                .put(path)
                .andReturn(),
            PrudentTest.body(
                    PrudentTest.request(PrudentTest.JSON),
                    PrudentTest.JSON,
                    allocate(holiday, 1L).build())
                .when()
                .patch(path)
                .andReturn())) {
      assertTrue(
          response.statusCode() == 405 || response.statusCode() == 404,
          "status " + response.statusCode());
    }
    assertEquals(List.of(entry), history(""));
    assertEquals(100_00L, envelope(holiday));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMistakeIsCorrectedByAnotherEntryNotByRewritingTheFirst() throws Exception {
    Goal holiday = goal("Holiday", "PLN");
    GoalAllocation mistaken = recorded(allocate(holiday, 900_00L).build());
    GoalAllocation correction = recorded(withdraw(holiday, 800_00L).setNote("typo, meant 100").build());

    assertEquals(100_00L, envelope(holiday));
    assertEquals(List.of(correction, mistaken), history(""));
  }

  // --- Isolation and what an envelope does not touch --------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anotherUsersGoalAndHistoryAreNeitherVisibleNorUsable() throws Exception {
    UUID bobsGoal = PrudentTest.seedGoal(PrudentTest.BOB, "Bob's car", "PLN", 10_000_00L);
    UUID bobsEntry = PrudentTest.seedAllocation(PrudentTest.BOB, bobsGoal, "PLN", 50_00L);
    Goal mine = goal("Holiday", "PLN");
    recorded(allocate(mine, 10_00L).build());

    assertEquals(1, history("").size());
    assertEquals(0, history("?goalId=" + bobsGoal).size());
    refused(get(ALLOCATIONS + "/" + bobsEntry), 404);
    for (CreateGoalAllocationRequest.Builder attempt :
        List.of(
            CreateGoalAllocationRequest.newBuilder()
                .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE)
                .setTargetGoalId(bobsGoal.toString())
                .setAmountMinor(1),
            CreateGoalAllocationRequest.newBuilder()
                .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW)
                .setSourceGoalId(bobsGoal.toString())
                .setAmountMinor(1),
            CreateGoalAllocationRequest.newBuilder()
                .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE)
                .setSourceGoalId(bobsGoal.toString())
                .setTargetGoalId(mine.getId())
                .setAmountMinor(1),
            CreateGoalAllocationRequest.newBuilder()
                .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE)
                .setSourceGoalId(mine.getId())
                .setTargetGoalId(bobsGoal.toString())
                .setAmountMinor(1))) {
      refused(post(attempt.build()), 404);
    }
    assertEquals(1, history("").size());
    assertEquals(10_00L, envelope(mine));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theEnvelopesListEveryGoalInCreationOrderIncludingEmptyOnes() throws Exception {
    Goal first = goal("First", "PLN");
    Goal second = goal("Second", "EUR");
    Goal third = goal("Third", "PLN");
    recorded(allocate(third, 7_00L).build());
    assertEquals(200, transition(second, "archive").statusCode());

    ListGoalEnvelopesResponse envelopes =
        PrudentTest.decode(
                PrudentTest.JSON,
                get(ALLOCATIONS + "/envelopes"),
                ListGoalEnvelopesResponse.newBuilder())
            .build();

    assertEquals(
        List.of(first.getId(), second.getId(), third.getId()),
        envelopes.getEnvelopesList().stream().map(GoalEnvelope::getGoalId).toList());
    assertEquals(
        List.of(0L, 0L, 7_00L),
        envelopes.getEnvelopesList().stream().map(GoalEnvelope::getAmountMinor).toList());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anEnvelopeMovesNoMoneyInAnyAccountOrReport() throws Exception {
    UUID wallet = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    String accountBefore = get("/api/v1/accounts/" + wallet).asString();
    String analyticsBefore =
        get("/api/v1/analytics/spend-by-category?currency=PLN&year=2026").asString();
    Goal holiday = goal("Holiday", "PLN");
    Goal car = goal("Car", "PLN");

    recorded(allocate(holiday, 400_00L).build());
    recorded(move(holiday, car, 100_00L).build());
    recorded(withdraw(car, 50_00L).build());

    assertEquals(accountBefore, get("/api/v1/accounts/" + wallet).asString());
    assertEquals(
        analyticsBefore,
        get("/api/v1/analytics/spend-by-category?currency=PLN&year=2026").asString());
    assertEquals(
        0,
        PrudentTest.decode(
                PrudentTest.JSON,
                get("/api/v1/records"),
                prudent.proto.v1.ListRecordsResponse.newBuilder())
            .build()
            .getRecordsCount(),
        "an allocation is not a transaction");
  }

  @Test
  void aCallerWithoutAnIdentityIsRefused() {
    assertEquals(
        401, PrudentTest.request(PrudentTest.JSON).when().get(ALLOCATIONS).andReturn().statusCode());
    assertEquals(
        401,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .get(ALLOCATIONS + "/envelopes")
            .andReturn()
            .statusCode());
  }
}
