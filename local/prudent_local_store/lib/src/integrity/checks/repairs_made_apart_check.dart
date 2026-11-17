import '../../../generated/prudent_local/v1/store.pb.dart';
import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';
import 'goal_repairs.dart';

/// Envelope repairs made apart, which together overshoot zero (ADR-120).
///
/// A repair entry's id derives from the entries it was computed from, so two devices that read the
/// same entries write one repair. Two devices that read *different* entries — one had a withdrawal
/// the other had not received — each write a repair that brings *their* envelope to zero, and the
/// merged envelope ends beyond it: above zero after two `allocate_deficit`s, money set aside by
/// nobody, which no other check notices, since a positive envelope is a legitimate state.
///
/// Each repair lists what it compensated (`GoalAllocation.compensates`). Two repairs of one goal and
/// one kind neither of which lists the other were made without seeing each other. Together with the
/// entries they read, their combined effect should have been to bring the envelope to zero once; the
/// difference is the overshoot, undone by **one** compensating entry — never a delete, the history is
/// append-only. That entry lists every repair of the group, so it is aware of them, and its id derives
/// from what it read, so two devices that apply it write it once. Any later repair that lists the whole
/// group (a deficit repaired again from the merged entries) settles it the same way.
final class RepairsMadeApartCheck implements IntegrityCheck {
  const RepairsMadeApartCheck();

  @override
  String get name => 'repairs_made_apart';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    final byGoal = <String, List<GoalAllocation>>{};
    for (final entry in snapshot.goalAllocations.values) {
      if (entry.compensates.isEmpty) continue;
      final goalId = entry.hasTargetGoalId() ? entry.targetGoalId : entry.sourceGoalId;
      byGoal.putIfAbsent(goalId, () => []).add(entry);
    }
    for (final MapEntry(key: goalId, value: repairs) in byGoal.entries) {
      final goal = snapshot.goals[goalId];
      if (goal == null) continue;
      for (final kind in AllocationKind.values) {
        final ofKind = repairs.where((r) => r.kind == kind).toList();
        final apart = {
          for (final a in ofKind)
            for (final b in ofKind)
              if (a.id != b.id && !a.compensates.contains(b.id) && !b.compensates.contains(a.id)) a,
        };
        if (apart.length < 2) continue;
        final apartIds = {for (final r in apart) r.id};
        // A repair made afterwards that saw every one of them — an `undo_overshoot`, or a deficit
        // repaired again — was computed from their sum, and settled them.
        if (repairs.any((r) => apartIds.every(r.compensates.contains))) continue;
        // What the repairs together read, without themselves: the entries they meant to balance.
        final readIds = {
          for (final r in apart)
            for (final id in r.compensates)
              if (!apartIds.contains(id)) id,
        };
        var read = 0;
        for (final id in readIds) {
          if (snapshot.goalAllocations[id] case final entry?) {
            read += GoalRepairs.signedFor(entry, goalId);
          }
        }
        var repaired = 0;
        for (final r in apart) {
          repaired += GoalRepairs.signedFor(r, goalId);
        }
        // Brought to zero once, the read entries plus the repairs would sum to zero.
        final overshoot = read + repaired;
        if (overshoot == 0) continue;
        final ids = apartIds.toList()..sort();
        yield IntegrityIssue(
          code: 'goal.repairs_made_apart',
          collection: 'goal_allocations',
          recordId: ids.first,
          key: ids.join('+'),
          facts: {
            'goalId': goalId,
            'currency': goal.currency,
            'overshootMinor': '${overshoot.abs()}',
          },
          actions: [
            GoalRepairs.compensate(
              store,
              code: 'undo_overshoot',
              goal: goal,
              kind: overshoot > 0
                  ? AllocationKind.ALLOCATION_KIND_WITHDRAW
                  : AllocationKind.ALLOCATION_KIND_ALLOCATE,
              amount: overshoot.abs(),
              read: GoalRepairs.entriesOf(snapshot.goalAllocations.values, goalId),
            ),
          ],
        );
      }
    }
  }
}
