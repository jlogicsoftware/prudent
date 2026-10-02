// The goal views' pure helpers (jlogicsoftware/prudent#67): the direction an envelope entry moved
// money in, which goals a move may go to, and how the server's guidance is worded.
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prudent/generated/prudent/v1/goal_allocations.pb.dart';
import 'package:prudent/generated/prudent/v1/goals.pb.dart';
import 'package:prudent/goal/goal_figures.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';

Goal _goal(
  String id, {
  String currency = 'PLN',
  GoalStatus status = GoalStatus.GOAL_STATUS_ACTIVE,
}) => Goal(id: id, name: id, currency: currency, targetAmountMinor: Int64(1000), status: status);

void main() {
  final t = lookupPrudentLocalizations(const Locale('en'));

  group('envelopeChange', () {
    test('an allocation is money in, a withdrawal money out', () {
      final allocate = GoalAllocation(
        kind: GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE,
        targetGoalId: 'a',
        amountMinor: Int64(500),
      );
      final withdraw = GoalAllocation(
        kind: GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW,
        sourceGoalId: 'a',
        amountMinor: Int64(200),
      );
      expect(envelopeChange(allocate, 'a'), Int64(500));
      expect(envelopeChange(withdraw, 'a'), Int64(-200));
    });

    test('a move is money out of its source and into its target', () {
      final move = GoalAllocation(
        kind: GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE,
        sourceGoalId: 'a',
        targetGoalId: 'b',
        amountMinor: Int64(300),
      );
      expect(envelopeChange(move, 'a'), Int64(-300));
      expect(envelopeChange(move, 'b'), Int64(300));
    });
  });

  test('a move goes only to another active goal in the same currency', () {
    final source = _goal('a');
    final goals = [
      source,
      _goal('same'),
      _goal('eur', currency: 'EUR'),
      _goal('done', status: GoalStatus.GOAL_STATUS_COMPLETED),
      _goal('old', status: GoalStatus.GOAL_STATUS_ARCHIVED),
    ];
    expect(moveTargets(goals, source).map((g) => g.id), ['same']);
  });

  test('goalsWithStatus keeps the server order', () {
    final goals = [_goal('1'), _goal('2', status: GoalStatus.GOAL_STATUS_ARCHIVED), _goal('3')];
    expect(goalsWithStatus(goals, GoalStatus.GOAL_STATUS_ACTIVE).map((g) => g.id), ['1', '3']);
    expect(goalsWithStatus(goals, GoalStatus.GOAL_STATUS_ARCHIVED).map((g) => g.id), ['2']);
  });

  group('goalGuidanceText', () {
    GoalProgress progress(GoalGuidance guidance, {int? monthly, int? months}) => GoalProgress(
      currency: 'PLN',
      guidance: guidance,
      monthlyContributionMinor: monthly == null ? null : Int64(monthly),
      monthsRemaining: months,
    );

    test('words a contribution with the months left, and "this month" for the last one', () {
      expect(
        goalGuidanceText(
          t,
          progress(GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION, monthly: 12345, months: 4),
        ),
        'Set aside 123.45 PLN a month · 4 months left',
      );
      expect(
        goalGuidanceText(
          t,
          progress(GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION, monthly: 100, months: 1),
        ),
        'Set aside 1.00 PLN a month · Due this month',
      );
    });

    test('words reached, no date and overdue, and says nothing for a goal not being saved for', () {
      expect(goalGuidanceText(t, progress(GoalGuidance.GOAL_GUIDANCE_REACHED)), 'Target reached');
      expect(
        goalGuidanceText(t, progress(GoalGuidance.GOAL_GUIDANCE_NO_TARGET_DATE)),
        'No target date',
      );
      expect(
        goalGuidanceText(t, progress(GoalGuidance.GOAL_GUIDANCE_OVERDUE)),
        'The target date has passed',
      );
      expect(goalGuidanceText(t, progress(GoalGuidance.GOAL_GUIDANCE_NOT_ACTIVE)), isNull);
    });
  });

  test('a date that is not one is shown as sent, not guessed', () async {
    await initializeDateFormatting('en');
    expect(formatGoalDate('2027-03-15', 'en'), 'Mar 15, 2027');
    expect(formatGoalDate('soon', 'en'), 'soon');
  });
}
