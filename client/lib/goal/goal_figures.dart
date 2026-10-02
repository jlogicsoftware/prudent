import 'package:fixnum/fixnum.dart';
import 'package:intl/intl.dart';

import '../generated/prudent/v1/goal_allocations.pb.dart';
import '../generated/prudent/v1/goals.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';

/// An amount with its currency, the one way every goal figure is written, so an envelope amount
/// and an account balance can never be told apart by formatting alone — what sets them apart is
/// the envelope treatment, not the digits.
String formatGoalAmount(Int64 minor, String currency) => '${formatMinorUnits(minor)} $currency';

/// A goal's `YYYY-MM-DD` target date as a readable date; the raw text if it is somehow not one, so
/// a date is never shown blank or guessed.
String formatGoalDate(String wire, String locale) {
  final date = DateTime.tryParse(wire);
  return date == null ? wire : DateFormat.yMMMd(locale).format(date);
}

/// The goals in [status], in the server's creation order.
List<Goal> goalsWithStatus(List<Goal> goals, GoalStatus status) => [
  for (final goal in goals)
    if (goal.status == status) goal,
];

/// The line under a goal's figures that says what to do next. The server has already decided
/// which case applies (`GoalGuidance`, ADR-052) — this only words it, so the rule lives in one
/// place. Null for a goal that is not active: nothing is being saved towards it.
String? goalGuidanceText(PrudentLocalizations t, GoalProgress progress) {
  switch (progress.guidance) {
    case GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION:
      final contribution = t.goalGuidanceContribution(
        formatGoalAmount(progress.monthlyContributionMinor, progress.currency),
      );
      final months = progress.monthsRemaining;
      return '$contribution · ${months == 1 ? t.goalDueThisMonth : t.goalMonthsLeft(months)}';
    case GoalGuidance.GOAL_GUIDANCE_REACHED:
      return t.goalGuidanceReached;
    case GoalGuidance.GOAL_GUIDANCE_NO_TARGET_DATE:
      return t.goalGuidanceNoDate;
    case GoalGuidance.GOAL_GUIDANCE_OVERDUE:
      return t.goalGuidanceOverdue;
    default:
      return null;
  }
}

/// What one history entry did to [goalId]'s envelope: positive when money came in, negative when
/// it went out. The wire amount is always positive and the direction is the kind (ADR-050), so a
/// MOVE reads as an inflow on its target and an outflow on its source.
Int64 envelopeChange(GoalAllocation entry, String goalId) {
  final inflow = entry.hasTargetGoalId() && entry.targetGoalId == goalId;
  return inflow ? entry.amountMinor : -entry.amountMinor;
}

/// The active goals money can be moved to from [source]: same currency (a move never converts,
/// ADR-009) and not [source] itself. Only active goals take money in (goal_allocations.proto).
List<Goal> moveTargets(List<Goal> goals, Goal source) => [
  for (final goal in goals)
    if (goal.id != source.id &&
        goal.currency == source.currency &&
        goal.status == GoalStatus.GOAL_STATUS_ACTIVE)
      goal,
];
