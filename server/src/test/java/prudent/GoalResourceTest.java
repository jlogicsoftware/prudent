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
import prudent.proto.v1.CreateGoalRequest;
import prudent.proto.v1.Goal;
import prudent.proto.v1.GoalStatus;
import prudent.proto.v1.ListGoalsResponse;
import prudent.proto.v1.UpdateGoalRequest;
import zen.proto.v1.ZenError;

/**
 * Goal model and lifecycle (M4, jlogicsoftware/prudent#38, ADR-049): a goal has a name, a currency,
 * a positive target and an optional date; it is created active, can be completed, archived and
 * reactivated, and is never deleted; it is the caller's alone; and it moves no money.
 */
@QuarkusTest
class GoalResourceTest {

  private static final String GOALS = "/api/v1/goals";

  @BeforeEach
  void seed() {
    PrudentTest.reset();
  }

  // --- Helpers ----------------------------------------------------------------------------------

  private static CreateGoalRequest.Builder holiday() {
    return CreateGoalRequest.newBuilder()
        .setName("Holiday")
        .setCurrency("PLN")
        .setTargetAmountMinor(5_000_00L);
  }

  private static Response postCreate(String mode, CreateGoalRequest request) throws Exception {
    return PrudentTest.body(PrudentTest.request(mode), mode, request).when().post(GOALS).andReturn();
  }

  private static Goal create(String mode, CreateGoalRequest request) throws Exception {
    Response response = postCreate(mode, request);
    assertEquals(201, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, Goal.newBuilder()).build();
  }

  private static Goal create(CreateGoalRequest request) throws Exception {
    return create(PrudentTest.JSON, request);
  }

  private static Response put(String id, UpdateGoalRequest request) throws Exception {
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, request)
        .when()
        .put(GOALS + "/" + id)
        .andReturn();
  }

  private static Response get(String path) {
    return PrudentTest.request(PrudentTest.JSON).when().get(path).andReturn();
  }

  private static Response transition(String id, String action) {
    return PrudentTest.request(PrudentTest.JSON).when().post(GOALS + "/" + id + "/" + action).andReturn();
  }

  private static Goal moved(String id, String action) throws Exception {
    Response response = transition(id, action);
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, Goal.newBuilder()).build();
  }

  private static ZenError refused(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  private static List<Goal> listed(String query) throws Exception {
    Response response = get(GOALS + query);
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ListGoalsResponse.newBuilder())
        .build()
        .getGoalsList();
  }

  // --- Create and read, both transports ---------------------------------------------------------

  @ParameterizedTest(name = "{0}")
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void aGoalIsCreatedActiveAndReadBackIdentically(String mode) throws Exception {
    Goal created = create(mode, holiday().setTargetDate("2027-06-30").build());

    assertFalse(created.getId().isEmpty(), "the server mints the id");
    assertEquals("Holiday", created.getName());
    assertEquals("PLN", created.getCurrency());
    assertEquals(5_000_00L, created.getTargetAmountMinor());
    assertEquals("2027-06-30", created.getTargetDate());
    assertEquals(GoalStatus.GOAL_STATUS_ACTIVE, created.getStatus());
    assertTrue(created.getCreatedAtMs() > 0);
    assertEquals(
        created.getCreatedAtMs(),
        created.getStatusChangedAtMs(),
        "no transition yet, so the status was last changed when the goal was created");

    Response read = PrudentTest.request(mode).when().get(GOALS + "/" + created.getId()).andReturn();
    assertEquals(200, read.statusCode(), read.asString());
    assertEquals(created, PrudentTest.decode(mode, read, Goal.newBuilder()).build());

    Response all = PrudentTest.request(mode).when().get(GOALS).andReturn();
    assertEquals(
        List.of(created),
        PrudentTest.decode(mode, all, ListGoalsResponse.newBuilder()).build().getGoalsList());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theTargetDateIsOptional() throws Exception {
    Goal created = create(holiday().build());

    assertFalse(created.hasTargetDate());
    assertFalse(get(GOALS + "/" + created.getId()).asString().contains("targetDate"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aDateInThePastIsAccepted() throws Exception {
    // Whether a date is still reachable is progress guidance (#66), not a reason to refuse it.
    assertEquals("2020-01-01", create(holiday().setTargetDate("2020-01-01").build()).getTargetDate());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aLowerCaseCurrencyIsStoredUpperCaseAndTheNameIsTrimmed() throws Exception {
    Goal created = create(holiday().setCurrency(" eur ").setName("  Holiday  ").build());

    assertEquals("EUR", created.getCurrency());
    assertEquals("Holiday", created.getName());
  }

  // --- Validation -------------------------------------------------------------------------------

  @ParameterizedTest(name = "{0}")
  @ValueSource(strings = {"", "   "})
  @TestSecurity(user = PrudentTest.ALICE)
  void aBlankNameIsRefused(String name) throws Exception {
    refused(postCreate(PrudentTest.JSON, holiday().setName(name).build()), 400);
    assertEquals(0, listed("").size());
  }

  @ParameterizedTest(name = "{0}")
  @ValueSource(longs = {0L, -1L, Long.MIN_VALUE})
  @TestSecurity(user = PrudentTest.ALICE)
  void aTargetThatIsNotPositiveIsRefused(long target) throws Exception {
    refused(postCreate(PrudentTest.JSON, holiday().setTargetAmountMinor(target).build()), 400);
    assertEquals(0, listed("").size());
  }

  @ParameterizedTest(name = "{0}")
  @ValueSource(strings = {"", "ZZZ", "PL", "PLNN", "12$"})
  @TestSecurity(user = PrudentTest.ALICE)
  void aCurrencyThatIsNotIso4217IsRefused(String currency) throws Exception {
    refused(postCreate(PrudentTest.JSON, holiday().setCurrency(currency).build()), 400);
    assertEquals(0, listed("").size());
  }

  @ParameterizedTest(name = "{0}")
  @ValueSource(strings = {"", "2027-02-30", "2027-6-1", "01/06/2027", "tomorrow"})
  @TestSecurity(user = PrudentTest.ALICE)
  void aDateThatIsNotAnIsoDateIsRefused(String date) throws Exception {
    refused(postCreate(PrudentTest.JSON, holiday().setTargetDate(date).build()), 400);
    assertEquals(0, listed("").size());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aLargeTargetIsKeptExactly() throws Exception {
    assertEquals(Long.MAX_VALUE, create(holiday().setTargetAmountMinor(Long.MAX_VALUE).build())
        .getTargetAmountMinor());
  }

  // --- Edit -------------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void editingReplacesNameTargetAndDateButNeverTheCurrencyOrStatus() throws Exception {
    Goal goal = create(holiday().setTargetDate("2027-06-30").build());
    Goal completed = moved(goal.getId(), "complete");

    Response response =
        put(
            goal.getId(),
            UpdateGoalRequest.newBuilder()
                .setName("Big holiday")
                .setTargetAmountMinor(8_000_00L)
                .setTargetDate("2027-08-31")
                .build());
    assertEquals(200, response.statusCode(), response.asString());
    Goal edited = PrudentTest.decode(PrudentTest.JSON, response, Goal.newBuilder()).build();

    assertEquals("Big holiday", edited.getName());
    assertEquals(8_000_00L, edited.getTargetAmountMinor());
    assertEquals("2027-08-31", edited.getTargetDate());
    assertEquals("PLN", edited.getCurrency());
    assertEquals(GoalStatus.GOAL_STATUS_COMPLETED, edited.getStatus());
    assertEquals(
        completed.getStatusChangedAtMs(),
        edited.getStatusChangedAtMs(),
        "an edit is not a status change");
    assertEquals(goal.getCreatedAtMs(), edited.getCreatedAtMs());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anAbsentDateClearsIt() throws Exception {
    Goal goal = create(holiday().setTargetDate("2027-06-30").build());

    Response response =
        put(
            goal.getId(),
            UpdateGoalRequest.newBuilder().setName("Holiday").setTargetAmountMinor(100L).build());

    assertEquals(200, response.statusCode(), response.asString());
    assertFalse(
        PrudentTest.decode(PrudentTest.JSON, response, Goal.newBuilder()).build().hasTargetDate());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anEditHoldsTheSameRulesAsACreateAndChangesNothingWhenRefused() throws Exception {
    Goal goal = create(holiday().setTargetDate("2027-06-30").build());

    refused(put(goal.getId(), UpdateGoalRequest.newBuilder().setName(" ").setTargetAmountMinor(1).build()), 400);
    refused(put(goal.getId(), UpdateGoalRequest.newBuilder().setName("X").setTargetAmountMinor(0).build()), 400);
    refused(
        put(
            goal.getId(),
            UpdateGoalRequest.newBuilder()
                .setName("X")
                .setTargetAmountMinor(1)
                .setTargetDate("nonsense")
                .build()),
        400);

    assertEquals(List.of(goal), listed(""));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anArchivedGoalCannotBeEditedUntilItIsReactivated() throws Exception {
    Goal goal = create(holiday().build());
    moved(goal.getId(), "archive");
    UpdateGoalRequest edit =
        UpdateGoalRequest.newBuilder().setName("Renamed").setTargetAmountMinor(1_00L).build();

    refused(put(goal.getId(), edit), 409);
    assertEquals("Holiday", listed("").get(0).getName());

    moved(goal.getId(), "reactivate");
    assertEquals(200, put(goal.getId(), edit).statusCode());
  }

  // --- Lifecycle --------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void everyPermittedTransitionIsAppliedAndStampsTheTime() throws Exception {
    Goal goal = create(holiday().build());

    Goal completed = moved(goal.getId(), "complete");
    assertEquals(GoalStatus.GOAL_STATUS_COMPLETED, completed.getStatus());
    assertTrue(completed.getStatusChangedAtMs() >= goal.getStatusChangedAtMs());

    assertEquals(GoalStatus.GOAL_STATUS_ACTIVE, moved(goal.getId(), "reactivate").getStatus());
    assertEquals(GoalStatus.GOAL_STATUS_ARCHIVED, moved(goal.getId(), "archive").getStatus());
    assertEquals(GoalStatus.GOAL_STATUS_ACTIVE, moved(goal.getId(), "reactivate").getStatus());
    moved(goal.getId(), "complete");
    assertEquals(GoalStatus.GOAL_STATUS_ARCHIVED, moved(goal.getId(), "archive").getStatus());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aTransitionThatIsNotAChangeIsRefusedAndChangesNothing() throws Exception {
    Goal active = create(holiday().build());
    refused(transition(active.getId(), "reactivate"), 409);

    moved(active.getId(), "complete");
    refused(transition(active.getId(), "complete"), 409);

    Goal archived = moved(active.getId(), "archive");
    refused(transition(active.getId(), "archive"), 409);
    // A refused change must not move the timestamp either.
    assertEquals(archived, listed("").get(0));
    // Completing needs an active goal: an archived one is reactivated first.
    refused(transition(active.getId(), "complete"), 409);
    assertEquals(archived, listed("").get(0));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void nothingIsEverDeleted() throws Exception {
    Goal goal = create(holiday().build());
    moved(goal.getId(), "archive");

    Response delete = PrudentTest.request(PrudentTest.JSON).when().delete(GOALS + "/" + goal.getId()).andReturn();

    assertTrue(delete.statusCode() == 405 || delete.statusCode() == 404, "status " + delete.statusCode());
    assertEquals(1, listed("").size(), "an archived goal stays in the list");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theListFiltersByStatusAndKeepsCreationOrder() throws Exception {
    Goal first = create(holiday().setName("First").build());
    Goal second = create(holiday().setName("Second").build());
    Goal third = create(holiday().setName("Third").build());
    moved(second.getId(), "complete");
    moved(third.getId(), "archive");

    assertEquals(
        List.of("First", "Second", "Third"),
        listed("").stream().map(Goal::getName).toList());
    assertEquals(List.of(first.getId()), listed("?status=ACTIVE").stream().map(Goal::getId).toList());
    assertEquals(List.of(second.getId()), listed("?status=COMPLETED").stream().map(Goal::getId).toList());
    assertEquals(List.of(third.getId()), listed("?status=ARCHIVED").stream().map(Goal::getId).toList());
  }

  @ParameterizedTest(name = "{0}")
  @ValueSource(strings = {"active", "DONE", "GOAL_STATUS_ACTIVE"})
  @TestSecurity(user = PrudentTest.ALICE)
  void aStatusFilterThatIsNotAStatusIsRefused(String status) throws Exception {
    refused(get(GOALS + "?status=" + status), 400);
  }

  // --- Isolation, scoping and what a goal does not touch ----------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anotherUsersGoalIsNeitherVisibleNorChangeable() throws Exception {
    UUID bobs = PrudentTest.seedGoal(PrudentTest.BOB, "Bob's car", "PLN", 10_000_00L);
    Goal mine = create(holiday().build());

    assertEquals(List.of(mine), listed(""));
    refused(get(GOALS + "/" + bobs), 404);
    refused(put(bobs.toString(), UpdateGoalRequest.newBuilder().setName("Mine").setTargetAmountMinor(1).build()), 404);
    for (String action : new String[] {"complete", "archive", "reactivate"}) {
      refused(transition(bobs.toString(), action), 404);
    }
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMalformedIdIsNotFoundNotAServerError() throws Exception {
    refused(get(GOALS + "/not-a-uuid"), 404);
    refused(transition("not-a-uuid", "archive"), 404);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void goalsMoveNoMoney() throws Exception {
    UUID wallet = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    String before = get("/api/v1/accounts/" + wallet).asString();
    String analyticsBefore = get("/api/v1/analytics/spend-by-category?currency=PLN&year=2026").asString();

    Goal goal = create(holiday().build());
    moved(goal.getId(), "complete");
    moved(goal.getId(), "archive");

    assertEquals(before, get("/api/v1/accounts/" + wallet).asString());
    assertEquals(analyticsBefore, get("/api/v1/analytics/spend-by-category?currency=PLN&year=2026").asString());
    assertEquals(
        0,
        PrudentTest.decode(
                PrudentTest.JSON,
                get("/api/v1/records"),
                prudent.proto.v1.ListRecordsResponse.newBuilder())
            .build()
            .getRecordsCount(),
        "a goal is not a transaction");
  }

  @Test
  void aCallerWithoutAnIdentityIsRefused() {
    assertEquals(401, PrudentTest.request(PrudentTest.JSON).when().get(GOALS).andReturn().statusCode());
  }
}
