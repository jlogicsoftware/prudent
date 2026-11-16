import 'package:fixnum/fixnum.dart';

import '../../../generated/prudent_local/v1/store.pb.dart';
import '../../ledger/envelopes.dart';
import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';

/// A goal's envelope below zero (phase-0 §0.3 row 6.24, ADR-102 D6).
///
/// The server refuses an entry that would take an envelope below zero (`GoalAllocationResource`,
/// row 6.24). Entries are append-only with random ids, so two devices that each withdraw what the
/// envelope held, offline, both write — and the merged envelope is negative, which no device did.
/// The history is never edited: the repair is a compensating `ALLOCATE` of the deficit, a new entry
/// on top of the others, which the person chooses.
final class EnvelopeBelowZeroCheck implements IntegrityCheck {
  /// The wall clock the compensating entry is labelled with; it decides nothing.
  final int Function() now;

  const EnvelopeBelowZeroCheck({this.now = _wallClock});

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  @override
  String get name => 'envelope_below_zero';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    final envelopes = goalEnvelopes(snapshot.goalAllocations.values);
    for (final goal in snapshot.goals.values) {
      final amount = envelopes[goal.id] ?? 0;
      if (amount >= 0) continue;
      yield IntegrityIssue(
        code: 'goal.envelope_below_zero',
        collection: 'goals',
        recordId: goal.id,
        facts: {'goalId': goal.id, 'currency': goal.currency, 'deficitMinor': '${-amount}'},
        actions: [
          IntegrityAction.now(
            'allocate_deficit',
            () => store.addGoalAllocation(
              GoalAllocation(
                id: store.newId(),
                kind: AllocationKind.ALLOCATION_KIND_ALLOCATE,
                targetGoalId: goal.id,
                currency: goal.currency,
                amountMinor: Int64(-amount),
                createdAtMs: Int64(now()),
                createdBy: store.deviceId,
              ),
            ),
          ),
        ],
      );
    }
  }
}
