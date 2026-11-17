import '../../../generated/prudent_local/v1/store.pb.dart';
import '../../ledger/envelopes.dart';
import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';
import 'goal_repairs.dart';

/// Money in an archived goal (phase-0 §0.3 rows 6.16, 6.23; ADR-102 D6).
///
/// On the server an archived goal holds nothing: a goal holding money cannot be archived (row 6.16)
/// and an archived goal takes no money (row 6.23), so "archived" means "nothing is set aside here"
/// (ADR-050). Offline, one device archives an empty goal while another allocates into it — or
/// archives it while another still holds money there — and the merge leaves money in a goal nobody
/// can take it out of. The person reactivates the goal, or withdraws the money: a new `WITHDRAW`
/// entry, since the history is never edited.
final class ArchivedGoalMoneyCheck implements IntegrityCheck {
  /// The wall clock the repair is labelled with; it decides nothing.
  final int Function() now;

  const ArchivedGoalMoneyCheck({this.now = _wallClock});

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  @override
  String get name => 'archived_goal_money';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    final envelopes = goalEnvelopes(snapshot.goalAllocations.values);
    for (final goal in snapshot.goals.values) {
      final amount = envelopes[goal.id] ?? 0;
      if (goal.status != GoalState.GOAL_STATE_ARCHIVED || amount <= 0) continue;
      yield IntegrityIssue(
        code: 'goal.archived_holds_money',
        collection: 'goals',
        recordId: goal.id,
        facts: {'goalId': goal.id, 'currency': goal.currency, 'amountMinor': '$amount'},
        actions: [
          GoalRepairs.reactivate(store, goal, now),
          GoalRepairs.compensate(
            store,
            code: 'withdraw_all',
            goal: goal,
            kind: AllocationKind.ALLOCATION_KIND_WITHDRAW,
            amount: amount,
            read: GoalRepairs.entriesOf(snapshot.goalAllocations.values, goal.id),
          ),
        ],
      );
    }
  }
}
