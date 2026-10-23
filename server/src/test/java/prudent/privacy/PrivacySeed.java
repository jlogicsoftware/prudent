package prudent.privacy;

import io.quarkus.narayana.jta.QuarkusTransaction;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.UUID;
import prudent.PrudentTest;
import prudent.budget.BudgetCarryResetEntity;
import prudent.category.CategoryEntity;
import prudent.goal.GoalEntity;
import prudent.goal.GoalState;

/**
 * Gives one user a row in <strong>every</strong> table Prudent keeps per user, including the
 * lifecycle states a screen hides — an archived category and goal, a revoked carry-over reset —
 * because an export or an erasure exercised only on the ordinary rows would never meet the rows
 * most likely to be forgotten.
 *
 * <p>Seeded straight into the database rather than through the API, for the reason {@link
 * PrudentTest} gives: the suites using this are asserting the privacy routes, not the resources.
 */
final class PrivacySeed {

  private PrivacySeed() {}

  /** The ids of what was seeded, for the assertions that name a particular row. */
  record Seeded(
      UUID account,
      UUID category,
      UUID archivedCategory,
      UUID record,
      UUID plan,
      UUID occurrence,
      UUID goal,
      UUID archivedGoal,
      UUID allocation,
      UUID liveReset,
      UUID revokedReset) {}

  static Seeded everythingFor(String userId) {
    UUID user = UUID.fromString(userId);
    UUID account = PrudentTest.seedAccount(userId, "Checking of " + userId, "PLN", "EUR");
    UUID category = PrudentTest.seedCategory(userId, "Food of " + userId);
    UUID archivedCategory = PrudentTest.seedCategory(userId, "Old of " + userId);
    QuarkusTransaction.requiringNew()
        .run(
            () ->
                CategoryEntity.<CategoryEntity>findById(archivedCategory).archivedAt =
                    Instant.now());
    PrudentTest.seedSettings(userId, "EUR");
    UUID record = PrudentTest.seedRecord(userId, account, category, -12_34L, "PLN");
    UUID plan = PrudentTest.seedPlan(userId, account, category, -50_00L, "PLN");
    UUID occurrence = PrudentTest.seedOccurrence(userId, plan, LocalDate.of(2026, 9, 1));
    PrudentTest.seedBudget(userId, category, YearMonth.of(2026, 9), "PLN", 500_00L);
    UUID goal = PrudentTest.seedGoal(userId, "Holiday of " + userId, "PLN", 5_000_00L);
    UUID archivedGoal = PrudentTest.seedGoal(userId, "Old goal of " + userId, "PLN", 100_00L);
    QuarkusTransaction.requiringNew()
        .run(() -> GoalEntity.<GoalEntity>findById(archivedGoal).status = GoalState.ARCHIVED);
    UUID allocation = PrudentTest.seedAllocation(userId, goal, "PLN", 100_00L);
    UUID liveReset =
        PrudentTest.seedCarryReset(userId, category, YearMonth.of(2026, 9), "PLN", 100_00L);
    UUID revokedReset =
        PrudentTest.seedCarryReset(userId, category, YearMonth.of(2026, 10), "PLN", 50_00L);
    QuarkusTransaction.requiringNew()
        .run(() -> BudgetCarryResetEntity.revoke(user, revokedReset, Instant.now()));
    return new Seeded(
        account,
        category,
        archivedCategory,
        record,
        plan,
        occurrence,
        goal,
        archivedGoal,
        allocation,
        liveReset,
        revokedReset);
  }
}
