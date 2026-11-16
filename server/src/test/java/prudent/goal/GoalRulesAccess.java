package prudent.goal;

import java.time.LocalDate;

/**
 * Opens the package-private arithmetic of {@link GoalProgressCalculator} to the golden-vector
 * generator ({@link prudent.parity.GoldenVectorsTest}), so that Prudent Local's port of goal
 * progress (unit 6a of {@code docs/plans/PRUDENT-LOCAL-PLAN.md}, ADR-052) is held to the methods the
 * server runs, not to a copy of them. It adds no behaviour.
 */
public final class GoalRulesAccess {
  private GoalRulesAccess() {}

  /** {@link GoalProgressCalculator#percent}. */
  public static int percent(long allocated, long target) {
    return GoalProgressCalculator.percent(allocated, target);
  }

  /** {@link GoalProgressCalculator#monthsRemaining}. */
  public static int monthsRemaining(LocalDate asOf, LocalDate targetDate) {
    return GoalProgressCalculator.monthsRemaining(asOf, targetDate);
  }

  /** {@link GoalProgressCalculator#ceilDiv}. */
  public static long ceilDiv(long remaining, int months) {
    return GoalProgressCalculator.ceilDiv(remaining, months);
  }
}
