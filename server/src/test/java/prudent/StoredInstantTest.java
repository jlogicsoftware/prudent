package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.google.protobuf.Message;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.YearMonth;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.proto.v1.BudgetCarryOverReset;
import prudent.proto.v1.CreateGoalAllocationRequest;
import prudent.proto.v1.CreateGoalRequest;
import prudent.proto.v1.Goal;
import prudent.proto.v1.GoalAllocation;
import prudent.proto.v1.GoalAllocationKind;
import prudent.proto.v1.ListBudgetCarryOverResetsResponse;
import prudent.proto.v1.ListGoalAllocationsResponse;
import prudent.proto.v1.ResetBudgetCarryOverRequest;

/**
 * A write is answered with the instant a later read gives, even when the clock reads finer than the
 * database keeps (ADR-139, jlogicsoftware/prudent#284). The answer to a write is built from memory,
 * so an uncut instant shows as a 1 ms difference between the two.
 */
@QuarkusTest
class StoredInstantTest {

  private static final String GOALS = "/api/v1/goals";
  private static final String ALLOCATIONS = "/api/v1/goal-allocations";
  private static final String RESETS = "/api/v1/budget-carry-over-resets";

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    FineStoredClock.install();
  }

  private static <B extends Message.Builder> B read(Response response, int status, B builder)
      throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, builder);
  }

  private static Response get(String path) {
    return PrudentTest.request(PrudentTest.JSON).when().get(path).andReturn();
  }

  private static Response post(String path, Message body) throws Exception {
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, body)
        .when()
        .post(path)
        .andReturn();
  }

  private static Response post(String path) {
    return PrudentTest.request(PrudentTest.JSON).when().post(path).andReturn();
  }

  private static Goal goal() throws Exception {
    return read(
            post(
                GOALS,
                CreateGoalRequest.newBuilder()
                    .setName("Holiday")
                    .setCurrency("PLN")
                    .setTargetAmountMinor(10_000_00L)
                    .build()),
            201,
            Goal.newBuilder())
        .build();
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anEnvelopeEntryIsAnsweredAsItIsReadBack() throws Exception {
    PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 1_000_00L, "PLN");
    Goal goal = goal();

    GoalAllocation answered =
        read(
                post(
                    ALLOCATIONS,
                    CreateGoalAllocationRequest.newBuilder()
                        .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE)
                        .setTargetGoalId(goal.getId())
                        .setAmountMinor(1_00L)
                        .build()),
                201,
                GoalAllocation.newBuilder())
            .build();

    assertEquals(FineStoredClock.EPOCH_MILLI, answered.getCreatedAtMs());
    assertEquals(
        answered,
        read(get(ALLOCATIONS + "/" + answered.getId()), 200, GoalAllocation.newBuilder()).build());
    assertEquals(
        answered,
        read(get(ALLOCATIONS), 200, ListGoalAllocationsResponse.newBuilder())
            .build()
            .getAllocations(0));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aGoalIsAnsweredAsItIsReadBack() throws Exception {
    Goal created = goal();

    assertEquals(FineStoredClock.EPOCH_MILLI, created.getCreatedAtMs());
    assertEquals(FineStoredClock.EPOCH_MILLI, created.getStatusChangedAtMs());
    assertEquals(
        created, read(get(GOALS + "/" + created.getId()), 200, Goal.newBuilder()).build());

    Goal completed =
        read(post(GOALS + "/" + created.getId() + "/complete"), 200, Goal.newBuilder()).build();

    assertEquals(FineStoredClock.EPOCH_MILLI, completed.getStatusChangedAtMs());
    assertEquals(
        completed, read(get(GOALS + "/" + created.getId()), 200, Goal.newBuilder()).build());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aCarryOverResetIsAnsweredAsItIsReadBack() throws Exception {
    UUID category = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");

    BudgetCarryOverReset answered =
        read(
                post(
                    RESETS,
                    ResetBudgetCarryOverRequest.newBuilder()
                        .setCategoryId(category.toString())
                        .setMonth(YearMonth.of(2026, 9).toString())
                        .setCurrency("PLN")
                        .build()),
                201,
                BudgetCarryOverReset.newBuilder())
            .build();

    assertEquals(FineStoredClock.EPOCH_MILLI, answered.getCreatedAtMs());
    assertEquals(answered, onlyReset());

    // The revocation is answered from the database, so the two always agree; what is held here is
    // that the stored instant is still in the millisecond the clock read.
    BudgetCarryOverReset revoked =
        read(
                post(RESETS + "/" + answered.getId() + "/revoke"),
                200,
                BudgetCarryOverReset.newBuilder())
            .build();

    assertEquals(FineStoredClock.EPOCH_MILLI, revoked.getRevokedAtMs());
    assertEquals(revoked, onlyReset());
  }

  private static BudgetCarryOverReset onlyReset() throws Exception {
    return read(get(RESETS), 200, ListBudgetCarryOverResetsResponse.newBuilder())
        .build()
        .getResets(0);
  }
}
