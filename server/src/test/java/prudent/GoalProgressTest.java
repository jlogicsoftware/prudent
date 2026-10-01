package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.proto.v1.CreateGoalAllocationRequest;
import prudent.proto.v1.CreateGoalRequest;
import prudent.proto.v1.Goal;
import prudent.proto.v1.GoalAllocationKind;
import prudent.proto.v1.GoalGuidance;
import prudent.proto.v1.GoalProgress;
import prudent.proto.v1.ListGoalProgressResponse;
import zen.proto.v1.ZenError;

/**
 * Goal progress and contribution guidance over HTTP (M4, jlogicsoftware/prudent#66, ADR-052): the
 * figures follow the real envelope history, the day is the caller's to state, and nothing is
 * stored. The rounding and the case order are {@code prudent.goal.GoalProgressCalculatorTest}.
 */
@QuarkusTest
class GoalProgressTest {

  private static final String GOALS = "/api/v1/goals";
  private static final String ALLOCATIONS = "/api/v1/goal-allocations";
  private static final String PROGRESS = GOALS + "/progress";

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    // Money to allocate from; every test that writes an entry through the API needs it (ADR-051).
    PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 100_000_00L, "PLN", "EUR");
  }

  // --- Helpers ----------------------------------------------------------------------------------

  private static Goal goal(String name, String currency, long target, String date)
      throws Exception {
    CreateGoalRequest.Builder request =
        CreateGoalRequest.newBuilder().setName(name).setCurrency(currency).setTargetAmountMinor(target);
    if (date != null) {
      request.setTargetDate(date);
    }
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, request.build())
            .when()
            .post(GOALS)
            .andReturn();
    assertEquals(201, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, Goal.newBuilder()).build();
  }

  private static void entry(
      GoalAllocationKind kind, Goal source, Goal target, long amount) throws Exception {
    CreateGoalAllocationRequest.Builder request =
        CreateGoalAllocationRequest.newBuilder().setKind(kind).setAmountMinor(amount);
    if (source != null) {
      request.setSourceGoalId(source.getId());
    }
    if (target != null) {
      request.setTargetGoalId(target.getId());
    }
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, request.build())
            .when()
            .post(ALLOCATIONS)
            .andReturn();
    assertEquals(201, response.statusCode(), response.asString());
  }

  private static void allocate(Goal target, long amount) throws Exception {
    entry(GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE, null, target, amount);
  }

  private static ListGoalProgressResponse progress(String mode, String asOf) throws Exception {
    var request = PrudentTest.request(mode);
    if (asOf != null) {
      request = request.queryParam("asOf", asOf);
    }
    Response response = request.when().get(PROGRESS).andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, ListGoalProgressResponse.newBuilder()).build();
  }

  private static GoalProgress of(ListGoalProgressResponse response, Goal goal) {
    return response.getGoalsList().stream()
        .filter(p -> p.getGoalId().equals(goal.getId()))
        .findFirst()
        .orElseThrow(() -> new AssertionError("no progress for " + goal.getName()));
  }

  private static void post(String path) {
    Response response = PrudentTest.request(PrudentTest.JSON).when().post(path).andReturn();
    assertEquals(200, response.statusCode(), response.asString());
  }

  // --- The figures ------------------------------------------------------------------------------

  @ParameterizedTest(name = "{0}")
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void aDatedGoalReportsAllocatedRemainingPercentAndTheMonthlyContribution(String mode)
      throws Exception {
    Goal car = goal("Car", "PLN", 1_000_00L, "2026-12-20");
    allocate(car, 100_00L);

    ListGoalProgressResponse response = progress(mode, "2026-10-01");

    assertEquals("2026-10-01", response.getAsOf());
    GoalProgress p = of(response, car);
    assertEquals("PLN", p.getCurrency());
    assertEquals(100_00L, p.getAllocatedMinor());
    assertEquals(1_000_00L, p.getTargetAmountMinor());
    assertEquals(900_00L, p.getRemainingMinor());
    assertEquals(10, p.getProgressPercent());
    assertEquals(GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION, p.getGuidance());
    // October, November and December.
    assertEquals(3, p.getMonthsRemaining());
    assertEquals(300_00L, p.getMonthlyContributionMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theContributionRoundsUpOverTheWire() throws Exception {
    Goal trip = goal("Trip", "PLN", 1_000_01L, "2026-12-01");

    GoalProgress p = of(progress(PrudentTest.JSON, "2026-10-15"), trip);

    assertEquals(333_34L, p.getMonthlyContributionMinor());
    assertEquals(0, p.getProgressPercent());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theFiguresFollowTheRealHistoryThroughAllocateWithdrawAndMove() throws Exception {
    Goal a = goal("A", "PLN", 1_000_00L, null);
    Goal b = goal("B", "PLN", 1_000_00L, null);
    allocate(a, 600_00L);
    entry(GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW, a, null, 100_00L);
    entry(GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE, a, b, 200_00L);

    ListGoalProgressResponse response = progress(PrudentTest.JSON, "2026-10-01");

    assertEquals(300_00L, of(response, a).getAllocatedMinor());
    assertEquals(30, of(response, a).getProgressPercent());
    assertEquals(200_00L, of(response, b).getAllocatedMinor());
    assertEquals(800_00L, of(response, b).getRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void goalsAreListedOldestFirstEachInItsOwnCurrencyWithNoTotal() throws Exception {
    Goal pln = goal("Zloty", "PLN", 1_000_00L, null);
    Goal eur = goal("Euro", "EUR", 500_00L, null);
    allocate(eur, 50_00L);

    ListGoalProgressResponse response = progress(PrudentTest.JSON, "2026-10-01");

    assertEquals(2, response.getGoalsCount());
    assertEquals(pln.getId(), response.getGoals(0).getGoalId());
    assertEquals("PLN", response.getGoals(0).getCurrency());
    assertEquals(eur.getId(), response.getGoals(1).getGoalId());
    assertEquals("EUR", response.getGoals(1).getCurrency());
    assertEquals(10, response.getGoals(1).getProgressPercent());
  }

  // --- Guidance cases ---------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void everyCaseOfGuidanceIsReachableThroughTheApi() throws Exception {
    Goal dated = goal("Dated", "PLN", 600_00L, "2026-12-31");
    Goal open = goal("Open", "PLN", 600_00L, null);
    Goal late = goal("Late", "PLN", 600_00L, "2026-09-30");
    Goal done = goal("Done", "PLN", 100_00L, "2026-12-31");
    allocate(done, 100_00L);
    Goal retired = goal("Retired", "PLN", 600_00L, "2026-12-31");
    post(GOALS + "/" + retired.getId() + "/complete");

    ListGoalProgressResponse response = progress(PrudentTest.JSON, "2026-10-01");

    assertEquals(GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION, of(response, dated).getGuidance());
    assertEquals(200_00L, of(response, dated).getMonthlyContributionMinor());
    assertEquals(GoalGuidance.GOAL_GUIDANCE_NO_TARGET_DATE, of(response, open).getGuidance());
    assertEquals(GoalGuidance.GOAL_GUIDANCE_OVERDUE, of(response, late).getGuidance());
    assertEquals(GoalGuidance.GOAL_GUIDANCE_REACHED, of(response, done).getGuidance());
    assertEquals(100, of(response, done).getProgressPercent());
    assertEquals(GoalGuidance.GOAL_GUIDANCE_NOT_ACTIVE, of(response, retired).getGuidance());
    // Only the contribution case carries the two derived fields.
    for (Goal g : new Goal[] {open, late, done, retired}) {
      assertFalse(of(response, g).hasMonthlyContributionMinor(), g.getName());
      assertFalse(of(response, g).hasMonthsRemaining(), g.getName());
    }
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theSameGoalChangesCaseWithTheDayItIsAskedAbout() throws Exception {
    Goal car = goal("Car", "PLN", 1_000_00L, "2026-12-15");

    assertEquals(
        333_34L,
        of(progress(PrudentTest.JSON, "2026-10-01"), car).getMonthlyContributionMinor());
    assertEquals(
        1_000_00L,
        of(progress(PrudentTest.JSON, "2026-12-15"), car).getMonthlyContributionMinor());
    assertEquals(
        GoalGuidance.GOAL_GUIDANCE_OVERDUE,
        of(progress(PrudentTest.JSON, "2026-12-16"), car).getGuidance());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anArchivedGoalIsStillListedWithItsFigures() throws Exception {
    Goal old = goal("Old", "PLN", 1_000_00L, "2026-12-31");
    post(GOALS + "/" + old.getId() + "/archive");

    GoalProgress p = of(progress(PrudentTest.JSON, "2026-10-01"), old);

    assertEquals(GoalGuidance.GOAL_GUIDANCE_NOT_ACTIVE, p.getGuidance());
    assertEquals(1_000_00L, p.getRemainingMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void editingTheDateOrTargetChangesTheGuidanceBecauseNothingIsStored() throws Exception {
    Goal car = goal("Car", "PLN", 1_000_00L, "2026-12-15");
    assertEquals(
        GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION,
        of(progress(PrudentTest.JSON, "2026-10-01"), car).getGuidance());

    Response moved =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                prudent.proto.v1.UpdateGoalRequest.newBuilder()
                    .setName("Car")
                    .setTargetAmountMinor(2_000_00L)
                    .build())
            .when()
            .put(GOALS + "/" + car.getId())
            .andReturn();
    assertEquals(200, moved.statusCode(), moved.asString());

    GoalProgress p = of(progress(PrudentTest.JSON, "2026-10-01"), car);
    assertEquals(GoalGuidance.GOAL_GUIDANCE_NO_TARGET_DATE, p.getGuidance());
    assertEquals(2_000_00L, p.getRemainingMinor());
  }

  // --- The day ----------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void omittingTheDayUsesTheServersUtcDate() throws Exception {
    // Read either side of the call: the server may cross UTC midnight in between, and either date
    // is then a correct answer.
    LocalDate before = LocalDate.now(ZoneOffset.UTC);
    ListGoalProgressResponse response = progress(PrudentTest.JSON, null);
    LocalDate after = LocalDate.now(ZoneOffset.UTC);

    assertTrue(
        response.getAsOf().equals(before.toString()) || response.getAsOf().equals(after.toString()),
        response.getAsOf());
  }

  @ParameterizedTest
  @ValueSource(strings = {"tomorrow", "2026-13-01", "2026-02-30", "01/10/2026", "2026-10"})
  @TestSecurity(user = PrudentTest.ALICE)
  void aDayThatIsNotAnIsoDateIsRefusedNotGuessed(String asOf) throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON).queryParam("asOf", asOf).when().get(PROGRESS).andReturn();

    assertEquals(400, response.statusCode(), response.asString());
    ZenError error = PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
    assertTrue(error.getMessage().contains(asOf), error.getMessage());
  }

  // --- Ownership and the rest of the surface ----------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anotherUsersGoalsAndEnvelopesAreNotShown() throws Exception {
    UUID bobsGoal = PrudentTest.seedGoal(PrudentTest.BOB, "Bob's car", "PLN", 10_000_00L);
    PrudentTest.seedAllocation(PrudentTest.BOB, bobsGoal, "PLN", 100_00L);
    Goal mine = goal("Mine", "PLN", 1_000_00L, null);

    ListGoalProgressResponse response = progress(PrudentTest.JSON, "2026-10-01");

    assertEquals(1, response.getGoalsCount());
    assertEquals(mine.getId(), response.getGoals(0).getGoalId());
    assertEquals(0, response.getGoals(0).getAllocatedMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void noGoalsIsAnEmptyListNotAnError() throws Exception {
    ListGoalProgressResponse response = progress(PrudentTest.JSON, "2026-10-01");

    assertEquals(0, response.getGoalsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theProgressRouteDoesNotShadowAGoalCalledByItsId() throws Exception {
    Goal car = goal("Car", "PLN", 1_000_00L, null);

    Response response =
        PrudentTest.request(PrudentTest.JSON).when().get(GOALS + "/" + car.getId()).andReturn();

    assertEquals(200, response.statusCode(), response.asString());
    assertEquals(
        car, PrudentTest.decode(PrudentTest.JSON, response, Goal.newBuilder()).build());
  }

  @Test
  void aCallerWithoutAnIdentityIsRefused() {
    assertEquals(
        401, PrudentTest.request(PrudentTest.JSON).when().get(PROGRESS).andReturn().statusCode());
  }
}
