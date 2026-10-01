package prudent.goal;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import prudent.proto.v1.GoalGuidance;
import prudent.proto.v1.GoalProgress;
import prudent.proto.v1.ListGoalProgressResponse;

/**
 * Goal progress and contribution guidance with no framework around them (M4,
 * jlogicsoftware/prudent#66, ADR-052): the percentage rounds down, the contribution rounds up, and
 * which case a goal is in follows a fixed order.
 */
class GoalProgressCalculatorTest {

  private static final LocalDate TODAY = LocalDate.of(2026, 10, 15);

  private static GoalEntity goal(long target, LocalDate date, GoalState status) {
    GoalEntity goal = new GoalEntity();
    goal.id = UUID.randomUUID();
    goal.currency = "PLN";
    goal.targetAmountMinor = target;
    goal.targetDate = date;
    goal.status = status;
    return goal;
  }

  private static GoalProgress progress(long target, long allocated, LocalDate date) {
    return GoalProgressCalculator.progress(goal(target, date, GoalState.ACTIVE), allocated, TODAY);
  }

  // --- Allocated, remaining and the percentage ---------------------------------------------------

  @Test
  void anEmptyEnvelopeIsZeroPercentWithTheWholeTargetRemaining() {
    GoalProgress p = progress(1_000_00, 0, null);

    assertEquals(0, p.getAllocatedMinor());
    assertEquals(1_000_00, p.getTargetAmountMinor());
    assertEquals(1_000_00, p.getRemainingMinor());
    assertEquals(0, p.getProgressPercent());
  }

  @Test
  void remainingIsTheTargetLessTheEnvelope() {
    GoalProgress p = progress(1_000_00, 250_00, null);

    assertEquals(250_00, p.getAllocatedMinor());
    assertEquals(750_00, p.getRemainingMinor());
    assertEquals(25, p.getProgressPercent());
  }

  @Test
  void thePercentageRoundsDownSoOneHundredMeansReached() {
    // 99.9% is not reached: it must not be shown as 100.
    assertEquals(99, progress(1_000, 999, null).getProgressPercent());
    assertEquals(0, progress(1_000, 9, null).getProgressPercent());
    assertEquals(33, progress(3, 1, null).getProgressPercent());
    assertEquals(66, progress(3, 2, null).getProgressPercent());
    assertEquals(100, progress(1_000, 1_000, null).getProgressPercent());
  }

  @Test
  void anEnvelopeAboveTheTargetLeavesNothingRemainingAndStaysAtOneHundredPercent() {
    GoalProgress p = progress(1_000, 1_500, null);

    assertEquals(1_500, p.getAllocatedMinor());
    assertEquals(0, p.getRemainingMinor());
    assertEquals(100, p.getProgressPercent());
  }

  @Test
  void theArithmeticDoesNotOverflowNearTheTopOfTheRange() {
    long max = Long.MAX_VALUE;

    assertEquals(100, GoalProgressCalculator.percent(max, max));
    // max is odd, so max / 2 is a hair under half: 49, and one more is exactly 2^62, which is 50.
    assertEquals(49, GoalProgressCalculator.percent(max / 2, max));
    assertEquals(50, GoalProgressCalculator.percent(max / 2 + 1, max));
    assertEquals(99, GoalProgressCalculator.percent(max - 1, max));
    assertEquals(max / 2 + 1, GoalProgressCalculator.ceilDiv(max, 2));
    assertEquals(max, GoalProgressCalculator.ceilDiv(max, 1));
  }

  // --- Months remaining --------------------------------------------------------------------------

  @ParameterizedTest
  @CsvSource({
    // As-of, target, months: both months count.
    "2026-10-15, 2026-10-15, 1", // due today
    "2026-10-15, 2026-10-31, 1", // due later this month
    "2026-10-15, 2026-11-01, 2", // the day after the month turns is another month
    "2026-10-31, 2026-11-01, 2",
    "2026-10-01, 2026-12-15, 3",
    "2026-10-15, 2027-10-15, 13", // a year ahead is thirteen contribution months, both ends counted
    "2026-12-31, 2027-01-01, 2", // across a year boundary
    "2026-01-31, 2026-03-01, 3", // a short month is still one month
    "2026-10-15, 2036-10-15, 121",
  })
  void monthsAreCalendarMonthsFromTheAsOfMonthThroughTheTargetMonth(
      LocalDate asOf, LocalDate target, int months) {
    assertEquals(months, GoalProgressCalculator.monthsRemaining(asOf, target));
  }

  // --- The monthly contribution, rounded up -------------------------------------------------------

  @ParameterizedTest
  @CsvSource({
    // remaining, months, contribution
    "300, 3, 100", // divides exactly: no padding
    "301, 3, 101", // one over: rounds up
    "299, 3, 100",
    "1, 3, 1", // never rounds to zero while anything remains
    "2, 12, 1",
    "100, 1, 100",
    "7, 2, 4",
  })
  void theContributionRoundsUpSoPayingItEveryMonthReachesTheTarget(
      long remaining, int months, long contribution) {
    assertEquals(contribution, GoalProgressCalculator.ceilDiv(remaining, months));
    assertTrue(contribution * months >= remaining);
    // …and by less than a whole extra payment: it is the smallest amount that gets there.
    assertTrue((contribution - 1) * months < remaining);
  }

  @Test
  void aDatedActiveGoalGetsTheContributionAndTheMonthCountBehindIt() {
    // 1,000.00 target, 100.00 in the envelope, due in December: October, November and December.
    GoalProgress p = progress(1_000_00, 100_00, LocalDate.of(2026, 12, 20));

    assertEquals(GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION, p.getGuidance());
    assertEquals(3, p.getMonthsRemaining());
    assertEquals(300_00, p.getMonthlyContributionMinor());
  }

  @Test
  void aGoalDueThisMonthNeedsTheWholeRemainderNow() {
    GoalProgress p = progress(1_000_00, 400_00, LocalDate.of(2026, 10, 31));

    assertEquals(GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION, p.getGuidance());
    assertEquals(1, p.getMonthsRemaining());
    assertEquals(600_00, p.getMonthlyContributionMinor());
  }

  @Test
  void aGoalDueTodayIsNotOverdue() {
    GoalProgress p = progress(1_000_00, 0, TODAY);

    assertEquals(GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION, p.getGuidance());
    assertEquals(1_000_00, p.getMonthlyContributionMinor());
  }

  @Test
  void anUnevenSplitRoundsUpAndOvershootsByLessThanAMonthsWorth() {
    // 1,000.01 over three months: 333.34 each, 1,000.02 in all.
    GoalProgress p = progress(1_000_01, 0, LocalDate.of(2026, 12, 1));

    assertEquals(3, p.getMonthsRemaining());
    assertEquals(333_34, p.getMonthlyContributionMinor());
    long overshoot = p.getMonthlyContributionMinor() * 3 - p.getRemainingMinor();
    assertTrue(overshoot >= 0 && overshoot < 3, "overshoot " + overshoot);
  }

  // --- Which case a goal is in -------------------------------------------------------------------

  @Test
  void aGoalWithoutADateHasNoContributionAndSaysWhy() {
    GoalProgress p = progress(1_000_00, 100_00, null);

    assertEquals(GoalGuidance.GOAL_GUIDANCE_NO_TARGET_DATE, p.getGuidance());
    assertFalse(p.hasMonthlyContributionMinor());
    assertFalse(p.hasMonthsRemaining());
    // The figures that need no date are still there.
    assertEquals(900_00, p.getRemainingMinor());
    assertEquals(10, p.getProgressPercent());
  }

  @Test
  void aGoalPastItsDateIsOverdueNotGivenAContribution() {
    GoalProgress p = progress(1_000_00, 100_00, TODAY.minusDays(1));

    assertEquals(GoalGuidance.GOAL_GUIDANCE_OVERDUE, p.getGuidance());
    assertFalse(p.hasMonthlyContributionMinor());
    assertFalse(p.hasMonthsRemaining());
    assertEquals(900_00, p.getRemainingMinor());
  }

  @Test
  void aDatePastEarlierInTheSameMonthIsStillOverdue() {
    // The date test is by day, so the month count never has to be zero or negative.
    assertEquals(
        GoalGuidance.GOAL_GUIDANCE_OVERDUE,
        progress(1_000_00, 0, LocalDate.of(2026, 10, 1)).getGuidance());
  }

  @Test
  void aReachedGoalHasNothingLeftToSuggestEvenIfItsDatePassed() {
    assertEquals(
        GoalGuidance.GOAL_GUIDANCE_REACHED,
        progress(1_000_00, 1_000_00, LocalDate.of(2026, 12, 1)).getGuidance());
    assertEquals(
        GoalGuidance.GOAL_GUIDANCE_REACHED,
        progress(1_000_00, 2_000_00, TODAY.minusYears(1)).getGuidance());
    assertEquals(
        GoalGuidance.GOAL_GUIDANCE_REACHED, progress(1_000_00, 1_000_00, null).getGuidance());
  }

  @Test
  void aGoalThatIsNotActiveGetsFiguresButNoGuidance() {
    for (GoalState status : List.of(GoalState.COMPLETED, GoalState.ARCHIVED)) {
      GoalProgress p =
          GoalProgressCalculator.progress(
              goal(1_000_00, LocalDate.of(2026, 12, 1), status), 100_00, TODAY);

      assertEquals(GoalGuidance.GOAL_GUIDANCE_NOT_ACTIVE, p.getGuidance(), status.toString());
      assertFalse(p.hasMonthlyContributionMinor());
      assertEquals(900_00, p.getRemainingMinor());
      assertEquals(10, p.getProgressPercent());
    }
  }

  @Test
  void notActiveTakesPrecedenceOverReached() {
    GoalProgress p =
        GoalProgressCalculator.progress(goal(1_000, null, GoalState.COMPLETED), 1_000, TODAY);

    assertEquals(GoalGuidance.GOAL_GUIDANCE_NOT_ACTIVE, p.getGuidance());
  }

  // --- The list ----------------------------------------------------------------------------------

  @Test
  void eachGoalIsMeasuredAgainstItsOwnEnvelopeInTheGoalsOrderAndAGoalWithNoneIsZero() {
    GoalEntity first = goal(1_000, null, GoalState.ACTIVE);
    GoalEntity second = goal(2_000, null, GoalState.ACTIVE);

    ListGoalProgressResponse response =
        GoalProgressCalculator.calculate(
            List.of(first, second), Map.of(second.id, 500L, UUID.randomUUID(), 99L), TODAY);

    assertEquals("2026-10-15", response.getAsOf());
    assertEquals(2, response.getGoalsCount());
    assertEquals(first.id.toString(), response.getGoals(0).getGoalId());
    assertEquals(0, response.getGoals(0).getAllocatedMinor());
    assertEquals(second.id.toString(), response.getGoals(1).getGoalId());
    assertEquals(500, response.getGoals(1).getAllocatedMinor());
    assertEquals(25, response.getGoals(1).getProgressPercent());
  }

  @Test
  void noGoalsIsAnEmptyListNotAnError() {
    ListGoalProgressResponse response = GoalProgressCalculator.calculate(List.of(), Map.of(), TODAY);

    assertEquals(0, response.getGoalsCount());
    assertEquals("2026-10-15", response.getAsOf());
  }
}
