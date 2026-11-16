import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';

/// Two live carry-over resets for one category, month and currency.
///
/// The server allows one unrevoked reset per slot (a unique partial index, `carry_over_resets.sql:50`,
/// phase-0 §0.3 row 6.9). A reset is an audit entry with a random id (ADR-046), so two devices that
/// each reset the same slot write two records; the person revokes all but one. Revoking is the only
/// change a reset takes, so nothing is deleted.
final class LiveResetSlotCheck implements IntegrityCheck {
  /// The wall clock the revocation is labelled with; it decides nothing.
  final int Function() now;

  const LiveResetSlotCheck({this.now = _wallClock});

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  @override
  String get name => 'live_reset_slot';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    final bySlot = <(String, String, String), List<String>>{};
    for (final reset in snapshot.budgetResets.values) {
      if (reset.hasRevocation()) continue;
      bySlot.putIfAbsent((reset.categoryId, reset.month, reset.currency), () => []).add(reset.id);
    }
    for (final MapEntry(key: (categoryId, month, currency), value: ids) in bySlot.entries) {
      if (ids.length < 2) continue;
      ids.sort();
      yield IntegrityIssue(
        code: 'budget.reset_slot_twice',
        collection: 'budget_resets',
        recordId: ids.first,
        key: ids.join('+'),
        facts: {'categoryId': categoryId, 'month': month, 'currency': currency},
        actions: [
          IntegrityAction.choose(
            'revoke_reset',
            ids,
            (id) => store.revokeBudgetReset(id, atMs: now()),
          ),
        ],
      );
    }
  }
}
