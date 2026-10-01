package prudent.goal;

import java.math.BigInteger;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import prudent.proto.v1.GoalGuidance;
import prudent.proto.v1.GoalProgress;
import prudent.proto.v1.ListGoalProgressResponse;

/**
 * How far each goal is and what to set aside monthly to reach it (M4, jlogicsoftware/prudent#66,
 * ADR-052).
 *
 * <p>Pure arithmetic over values the caller has already fetched — a goal, what its envelope
 * holds and the day it is being asked about — so the rules can be tested without a database or a
 * clock. Everything is integer arithmetic on minor units, so a figure is exactly reproducible;
 * the two roundings are the ones {@code goals.proto} documents on {@code GoalProgress}:
 *
 * <ul>
 *   <li>the percentage is rounded <strong>down</strong>, so 100 means reached and never
 *       "99.6% shown as 100";
 *   <li>the monthly contribution is rounded <strong>up</strong>, so paying it every month for
 *       the months that remain always reaches the target (the last payment may be smaller).
 * </ul>
 */
final class GoalProgressCalculator {

  private GoalProgressCalculator() {}

  /** One {@link GoalProgress} per goal, in the order given, each against its own envelope. */
  static ListGoalProgressResponse calculate(
      List<GoalEntity> goals, Map<UUID, Long> envelopes, LocalDate asOf) {
    ListGoalProgressResponse.Builder response =
        ListGoalProgressResponse.newBuilder().setAsOf(asOf.toString());
    for (GoalEntity goal : goals) {
      response.addGoals(progress(goal, envelopes.getOrDefault(goal.id, 0L), asOf));
    }
    return response.build();
  }

  /**
   * @param allocated what the goal's envelope holds, never negative
   * @param asOf the civil day "today" is for the month count and the overdue test
   */
  static GoalProgress progress(GoalEntity goal, long allocated, LocalDate asOf) {
    long target = goal.targetAmountMinor;
    long remaining = Math.max(0L, target - allocated);
    GoalProgress.Builder builder =
        GoalProgress.newBuilder()
            .setGoalId(goal.id.toString())
            .setCurrency(goal.currency)
            .setAllocatedMinor(allocated)
            .setTargetAmountMinor(target)
            .setRemainingMinor(remaining)
            .setProgressPercent(percent(allocated, target));

    // The first case that applies, in the order goals.proto documents.
    if (goal.status != GoalState.ACTIVE) {
      return builder.setGuidance(GoalGuidance.GOAL_GUIDANCE_NOT_ACTIVE).build();
    }
    if (remaining == 0) {
      return builder.setGuidance(GoalGuidance.GOAL_GUIDANCE_REACHED).build();
    }
    if (goal.targetDate == null) {
      return builder.setGuidance(GoalGuidance.GOAL_GUIDANCE_NO_TARGET_DATE).build();
    }
    if (goal.targetDate.isBefore(asOf)) {
      return builder.setGuidance(GoalGuidance.GOAL_GUIDANCE_OVERDUE).build();
    }
    int months = monthsRemaining(asOf, goal.targetDate);
    return builder
        .setGuidance(GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION)
        .setMonthsRemaining(months)
        .setMonthlyContributionMinor(ceilDiv(remaining, months))
        .build();
  }

  /**
   * Whole percent of the target held, rounded down and capped at 100. {@code allocated * 100} is
   * done in {@link BigInteger} because an envelope near the top of the amount range would
   * overflow a long.
   */
  static int percent(long allocated, long target) {
    BigInteger scaled = BigInteger.valueOf(allocated).multiply(BigInteger.valueOf(100));
    BigInteger percent = scaled.divide(BigInteger.valueOf(target));
    return percent.min(BigInteger.valueOf(100)).intValueExact();
  }

  /**
   * Calendar months from {@code asOf}'s month through {@code targetDate}'s month, both inclusive,
   * so the month a goal is due in is a month to contribute in and a goal due this month has one.
   * Counted in months rather than 30-day periods so a contribution does not move because a month
   * is short. The target date must not be before {@code asOf}.
   */
  static int monthsRemaining(LocalDate asOf, LocalDate targetDate) {
    long between = YearMonth.from(asOf).until(YearMonth.from(targetDate), ChronoUnit.MONTHS);
    return Math.toIntExact(between) + 1;
  }

  /** Rounds up, so {@code ceilDiv(remaining, months) * months >= remaining}. Both are positive. */
  static long ceilDiv(long remaining, int months) {
    // Not (remaining + months - 1) / months: that overflows for a remainder near the top of the range.
    return remaining / months + (remaining % months == 0 ? 0 : 1);
  }
}
