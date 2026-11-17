import 'package:fixnum/fixnum.dart';
import 'package:zen_core/zen_core.dart';

import '../../../generated/prudent_local/v1/store.pb.dart';
import '../../derived_ids.dart';
import '../../prudent_local_store.dart';
import '../../write_expect.dart';
import '../integrity_issue.dart';

/// The repairs of the envelope checks (ADR-116, ADR-120). Each writes through [PrudentLocalStore]'s
/// rules **and** carries a precondition the store runs inside the write's turn (jZenDev/jZen#251):
/// the state the issue was read from must still be the state it is applied to.
///
/// **A compensating entry is the same record on every device** (ADR-120). Both people may see one
/// issue and both choose its repair before either device has the other's; with a random id each
/// would write an entry, and a deficit of 500 made good twice ends 500 *above* zero — money set
/// aside that nobody put there. So its id is derived from the goal, the repair and the exact entries
/// it compensates ([DerivedIds.goalRepair]), and every other field is a function of those entries:
/// the amount, a time just after the latest of them, and no author (who chose it is a device, and
/// two devices' names would conflict). Two devices that read the same entries write the same bytes,
/// which merge as one record. Devices that read *different* entries write two records; each lists
/// what it compensated (`compensates`), so `RepairsMadeApartCheck` finds the pair and undoes the
/// overshoot.
///
/// **The repairs bypass the ledger's state rules on purpose.** A withdrawal from an archived goal,
/// or an allocation above free money, is refused to a person (ADR-050, ADR-051); a repair restores an
/// invariant a merge broke, so it writes through the store's structural rules only. Routing it through
/// `Ledger.createGoalAllocation` would refuse exactly the repairs that are needed.
abstract final class GoalRepairs {
  /// The entries that put money into or took it out of [goalId], from [entries].
  static List<GoalAllocation> entriesOf(Iterable<GoalAllocation> entries, String goalId) => [
    for (final e in entries)
      if ((e.hasSourceGoalId() && e.sourceGoalId == goalId) ||
          (e.hasTargetGoalId() && e.targetGoalId == goalId))
        e,
  ];

  /// What [entry] adds to [goalId]'s envelope: its amount when it targets the goal, minus it when it
  /// takes from it, nothing otherwise.
  static int signedFor(GoalAllocation entry, String goalId) {
    var out = 0;
    if (entry.hasTargetGoalId() && entry.targetGoalId == goalId) out += entry.amountMinor.toInt();
    if (entry.hasSourceGoalId() && entry.sourceGoalId == goalId) out -= entry.amountMinor.toInt();
    return out;
  }

  /// An entry of [kind] and [amount] for [goal] that compensates exactly [read] — the goal's entries
  /// the issue was computed from — written once, and only while the goal's entries are still those.
  static IntegrityAction compensate(
    PrudentLocalStore store, {
    required String code,
    required Goal goal,
    required AllocationKind kind,
    required int amount,
    required List<GoalAllocation> read,
  }) {
    final ids = {for (final e in read) e.id};
    final latest = read.map((e) => e.createdAtMs).reduce((a, b) => a > b ? a : b);
    final entry = GoalAllocation(
      id: DerivedIds.goalRepair(goal.id, code, ids),
      kind: kind,
      currency: goal.currency,
      amountMinor: Int64(amount),
      createdAtMs: latest + 1,
      compensates: ids.toList()..sort(),
    );
    if (kind == AllocationKind.ALLOCATION_KIND_ALLOCATE) {
      entry.targetGoalId = goal.id;
    } else {
      entry.sourceGoalId = goal.id;
    }
    return IntegrityAction.now(
      code,
      () => store.addGoalAllocation(
        entry,
        expect: (current) {
          if (current != null) return const ZenValidationError('This repair is already written.');
          return switch (store.goalAllocations.list()) {
            ZenFailure(:final error) => error,
            ZenSuccess(:final data) =>
              _sameIds(entriesOf(data, goal.id), ids)
                  ? null
                  : const ZenConflictError(
                      "The goal's envelope changed since this was shown; look at it again.",
                    ),
          };
        },
      ),
    );
  }

  /// Makes [goal] active again — only if it is still exactly the archived goal the issue was read
  /// from, so an edit another device made in between is never written back over.
  static IntegrityAction reactivate(
    PrudentLocalStore store,
    Goal goal,
    int Function() now,
  ) => IntegrityAction.now(
    'reactivate_goal',
    () => store.putGoal(
      goal.deepCopy()
        ..status = GoalState.GOAL_STATE_ACTIVE
        ..statusChangedAtMs = Int64(now()),
      // A goal is never deleted (ADR-049), so `gone` cannot happen; it answers as `changed` does.
      expect: WriteExpects.asRead(goal, gone: _goalChanged, changed: _goalChanged),
    ),
  );

  static ZenError _goalChanged() =>
      const ZenConflictError('This goal changed since this was shown; look at it again.');

  static bool _sameIds(List<GoalAllocation> entries, Set<String> ids) =>
      entries.length == ids.length && entries.every((e) => ids.contains(e.id));
}
