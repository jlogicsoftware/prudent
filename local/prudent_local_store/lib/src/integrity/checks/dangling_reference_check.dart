import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';
import 'repairs.dart';

/// A record that names an account or a category no longer in the store.
///
/// On the server a foreign key refuses the delete while anything points at the row (phase-0 §0.3
/// rows 5.10, 5.11, 5.42; `init.sql:110,113`, `plans.sql:24–25`, `budgets.sql:21`,
/// `carry_over_resets.sql:25`). On two devices nothing can: one deletes a category while the other
/// files a record under it, each write valid where it was made, and the merge holds both. So the
/// store keeps both and this check names every reference left dangling, with what can be done:
/// delete the referring record, move it, or re-create what was deleted under its old id.
///
/// Not checked here, because a missing target is a meaning rather than a break: a record's plan link
/// to a deleted plan reads as detached (ADR-102), and an occurrence state of a deleted plan is never
/// read. A goal is never deleted, so an allocation cannot dangle.
final class DanglingReferenceCheck implements IntegrityCheck {
  const DanglingReferenceCheck();

  @override
  String get name => 'dangling_references';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    final accounts = Repairs.activeAccounts(snapshot);
    final categories = Repairs.fileableCategories(snapshot);
    bool hasAccount(String id) => snapshot.accounts.containsKey(id);
    bool hasCategory(String id) => snapshot.categories.containsKey(id);

    for (final record in snapshot.records.values) {
      final accountId = record.posting.accountId;
      if (!hasAccount(accountId)) {
        yield IntegrityIssue(
          code: 'reference.record_account_missing',
          collection: 'records',
          recordId: record.id,
          facts: {'accountId': accountId},
          actions: [
            Repairs.deleteRecord(store, record.id),
            // A correction is never edited, and an imported record's id is derived from its account.
            if (!record.hasCorrection() && !record.hasImportKey())
              ?Repairs.moveRecordToAccount(store, record, accounts),
            Repairs.recreateAccount(store, accountId),
          ],
        );
      }
      if (record.hasCategoryId() && !hasCategory(record.categoryId)) {
        yield IntegrityIssue(
          code: 'reference.record_category_missing',
          collection: 'records',
          recordId: record.id,
          facts: {'categoryId': record.categoryId},
          actions: [
            Repairs.deleteRecord(store, record.id),
            ?Repairs.moveRecordToCategory(store, record, categories),
            Repairs.recreateCategory(store, record.categoryId),
          ],
        );
      }
    }

    for (final transfer in snapshot.transfers.values) {
      for (final (side, posting) in [
        ('source', transfer.source),
        ('destination', transfer.destination),
      ]) {
        if (hasAccount(posting.accountId)) continue;
        yield IntegrityIssue(
          code: 'reference.transfer_account_missing',
          collection: 'transfers',
          recordId: transfer.id,
          key: '${transfer.id}:$side',
          facts: {'accountId': posting.accountId, 'side': side},
          // A transfer is never edited (ADR-102), so it cannot be moved.
          actions: [
            Repairs.deleteTransfer(store, transfer.id),
            Repairs.recreateAccount(store, posting.accountId),
          ],
        );
      }
    }

    for (final currency in snapshot.accountCurrencies.values) {
      if (hasAccount(currency.accountId)) continue;
      yield IntegrityIssue(
        code: 'reference.currency_account_missing',
        collection: 'account_currencies',
        recordId: currency.id,
        facts: {'accountId': currency.accountId, 'currency': currency.currency},
        actions: [
          Repairs.deleteAccountCurrency(store, currency.id),
          Repairs.recreateAccount(store, currency.accountId),
        ],
      );
    }

    for (final plan in snapshot.plans.values) {
      if (!hasAccount(plan.posting.accountId)) {
        yield IntegrityIssue(
          code: 'reference.plan_account_missing',
          collection: 'plans',
          recordId: plan.id,
          facts: {'accountId': plan.posting.accountId},
          actions: [
            Repairs.deletePlan(store, plan.id),
            ?Repairs.movePlanToAccount(store, plan, accounts),
            Repairs.recreateAccount(store, plan.posting.accountId),
          ],
        );
      }
      if (!hasCategory(plan.categoryId)) {
        yield IntegrityIssue(
          code: 'reference.plan_category_missing',
          collection: 'plans',
          recordId: plan.id,
          facts: {'categoryId': plan.categoryId},
          actions: [
            Repairs.deletePlan(store, plan.id),
            ?Repairs.movePlanToCategory(store, plan, categories),
            Repairs.recreateCategory(store, plan.categoryId),
          ],
        );
      }
    }

    for (final budget in snapshot.budgets.values) {
      if (hasCategory(budget.categoryId)) continue;
      yield IntegrityIssue(
        code: 'reference.budget_category_missing',
        collection: 'budgets',
        recordId: budget.id,
        facts: {
          'categoryId': budget.categoryId,
          'month': budget.month,
          'currency': budget.currency,
        },
        // A budget's category is part of its id, so it cannot be moved: delete it, or bring the
        // category back.
        actions: [
          Repairs.deleteBudget(store, budget.id),
          Repairs.recreateCategory(store, budget.categoryId),
        ],
      );
    }

    for (final reset in snapshot.budgetResets.values) {
      if (hasCategory(reset.categoryId)) continue;
      yield IntegrityIssue(
        code: 'reference.reset_category_missing',
        collection: 'budget_resets',
        recordId: reset.id,
        facts: {'categoryId': reset.categoryId, 'month': reset.month, 'currency': reset.currency},
        // A reset is an audit entry, never deleted or edited (ADR-046): the only repair is to bring
        // its category back.
        actions: [Repairs.recreateCategory(store, reset.categoryId)],
      );
    }
  }
}
