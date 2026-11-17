import 'package:zen_core/zen_core.dart';

import '../../../generated/prudent_local/v1/store.pb.dart';
import '../../derived_ids.dart';
import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';

/// An occurrence that one device skipped and another confirmed.
///
/// The server cannot reach this state: an occurrence is planned, skipped or completed, and only a
/// planned one can be confirmed (`OccurrenceState.successors`, row 6.37). Here "skipped" is a stored
/// state and "completed" is the confirming record, written on two devices that did not see each
/// other, so both can be true. Money moved, so the occurrence reads as completed (`PlanLedger`); the
/// skip is a decision about money that did move, and the person is asked to take it back — clear the
/// skip — or to delete the record, which reopens the occurrence as skipped.
final class OccurrenceSkippedAndPaidCheck implements IntegrityCheck {
  const OccurrenceSkippedAndPaidCheck();

  @override
  String get name => 'occurrence_skipped_and_paid';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    for (final state in snapshot.occurrences.values) {
      if (!state.skipped) continue;
      final confirming = DerivedIds.confirmation(state.id);
      if (!snapshot.records.containsKey(confirming)) continue;
      yield IntegrityIssue(
        code: 'occurrence.skipped_and_paid',
        collection: 'occurrences',
        recordId: state.id,
        facts: {'planId': state.planId, 'date': state.occurrenceDate, 'recordId': confirming},
        actions: [
          IntegrityAction.now('clear_skip', () => _clearSkip(store, state)),
          IntegrityAction.now('delete_record', () => store.deleteRecord(confirming)),
        ],
      );
    }
  }

  static Future<ZenResult<Object?>> _clearSkip(PrudentLocalStore store, OccurrenceState state) async {
    final next = state.deepCopy()..clearSkipped();
    return await store.putOccurrenceState(next);
  }
}
