import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';
import 'repairs.dart';

/// Money in a currency its account does not hold.
///
/// The server refuses such a record, transfer or plan when it is written (`RecordWriter.java:92`,
/// `TransferResource.java`, phase-0 §0.3 row 5.18) and refuses to drop a currency while records or
/// plans use it (rows 5.6, 5.7). On two devices one can drop the currency while the other writes in
/// it, so the merge holds both; this check names each posting left in a currency its (still
/// existing) account no longer holds. A posting whose account is gone is the dangling-reference
/// check's, not this one's.
final class HeldCurrencyCheck implements IntegrityCheck {
  const HeldCurrencyCheck();

  @override
  String get name => 'held_currency';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    bool broken(String accountId, String currency) =>
        snapshot.accounts.containsKey(accountId) && !snapshot.holds(accountId, currency);

    for (final record in snapshot.records.values) {
      final p = record.posting;
      if (!broken(p.accountId, p.currency)) continue;
      yield IntegrityIssue(
        code: 'currency.record_not_held',
        collection: 'records',
        recordId: record.id,
        facts: {'accountId': p.accountId, 'currency': p.currency},
        actions: [
          Repairs.addCurrency(store, snapshot, p.accountId, p.currency),
          Repairs.deleteRecord(store, record.id),
        ],
      );
    }

    for (final transfer in snapshot.transfers.values) {
      for (final (side, p) in [
        ('source', transfer.source),
        ('destination', transfer.destination),
      ]) {
        if (!broken(p.accountId, p.currency)) continue;
        yield IntegrityIssue(
          code: 'currency.transfer_not_held',
          collection: 'transfers',
          recordId: transfer.id,
          key: '${transfer.id}:$side',
          facts: {'accountId': p.accountId, 'currency': p.currency, 'side': side},
          actions: [
            Repairs.addCurrency(store, snapshot, p.accountId, p.currency),
            Repairs.deleteTransfer(store, transfer.id),
          ],
        );
      }
    }

    for (final plan in snapshot.plans.values) {
      final p = plan.posting;
      if (!broken(p.accountId, p.currency)) continue;
      yield IntegrityIssue(
        code: 'currency.plan_not_held',
        collection: 'plans',
        recordId: plan.id,
        facts: {'accountId': p.accountId, 'currency': p.currency},
        actions: [
          Repairs.addCurrency(store, snapshot, p.accountId, p.currency),
          Repairs.deletePlan(store, plan.id),
        ],
      );
    }
  }
}
