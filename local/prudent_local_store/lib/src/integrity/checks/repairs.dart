import 'package:fixnum/fixnum.dart';
import 'package:zen_core/zen_core.dart';

import '../../../generated/prudent_local/v1/store.pb.dart';
import '../../derived_ids.dart';
import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../store_snapshot.dart';

/// The actions the store-model checks offer, each one ordinary write through [PrudentLocalStore]'s
/// rules — so a repair can be refused like any other write, and is then shown, never retried.
abstract final class Repairs {
  static IntegrityAction deleteRecord(PrudentLocalStore store, String id) =>
      IntegrityAction.now('delete_record', () => store.deleteRecord(id));

  static IntegrityAction deleteTransfer(PrudentLocalStore store, String id) =>
      IntegrityAction.now('delete_transfer', () => store.deleteTransfer(id));

  static IntegrityAction deletePlan(PrudentLocalStore store, String id) =>
      IntegrityAction.now('delete_plan', () => store.deletePlan(id));

  static IntegrityAction deleteBudget(PrudentLocalStore store, String id) =>
      IntegrityAction.now('delete_budget', () => store.deleteBudget(id));

  static IntegrityAction deleteAccountCurrency(PrudentLocalStore store, String id) =>
      IntegrityAction.now('delete_account_currency', () => store.deleteAccountCurrency(id));

  /// Re-creates a deleted account under its old id, with the name the person gives. The store keeps
  /// no content of a deleted record (a tombstone), so only the name can be asked for; the rest takes
  /// the defaults of a new account and can be edited afterwards.
  static IntegrityAction recreateAccount(PrudentLocalStore store, String id) =>
      IntegrityAction.withText(
        'recreate_account',
        (name) => store.putAccount(
          Account(
            id: id,
            name: name.trim(),
            active: true,
            includeInTotal: true,
            includeInOverview: true,
          ),
        ),
      );

  /// Re-creates a deleted category under its old id, with the title the person gives.
  static IntegrityAction recreateCategory(PrudentLocalStore store, String id) =>
      IntegrityAction.withText(
        'recreate_category',
        (title) => store.putCategory(Category(id: id, title: title.trim())),
      );

  /// Gives [currency] to [accountId] with an opening amount of zero, after its other currencies.
  static IntegrityAction addCurrency(
    PrudentLocalStore store,
    StoreSnapshot snapshot,
    String accountId,
    String currency,
  ) {
    final position = snapshot.accountCurrencies.values
        .where((c) => c.accountId == accountId)
        .length;
    return IntegrityAction.now(
      'add_currency',
      () => store.putAccountCurrency(
        AccountCurrency(
          id: DerivedIds.accountCurrency(accountId, currency),
          accountId: accountId,
          currency: currency,
          openingMinor: Int64.ZERO,
          position: position,
        ),
      ),
    );
  }

  /// Moves the record to one of [accountIds], keeping its currency and amount (one posting, so the
  /// three change together). Null when there is nowhere to move it.
  static IntegrityAction? moveRecordToAccount(
    PrudentLocalStore store,
    Record record,
    Iterable<String> accountIds,
  ) {
    final choices = accountIds.where((id) => id != record.posting.accountId).toList()..sort();
    if (choices.isEmpty) return null;
    return IntegrityAction.choose(
      'move_to_account',
      choices,
      (accountId) => _write(
        store.records.get(record.id),
        (current) => store.putRecord(
          current.deepCopy()..posting = (current.posting.deepCopy()..accountId = accountId),
        ),
      ),
    );
  }

  /// Files the record under one of [categoryIds]. Null when there is no other category.
  static IntegrityAction? moveRecordToCategory(
    PrudentLocalStore store,
    Record record,
    Iterable<String> categoryIds,
  ) {
    final choices = categoryIds.where((id) => id != record.categoryId).toList()..sort();
    if (choices.isEmpty) return null;
    return IntegrityAction.choose(
      'move_to_category',
      choices,
      (categoryId) => _write(
        store.records.get(record.id),
        (current) => store.putRecord(current.deepCopy()..categoryId = categoryId),
      ),
    );
  }

  static IntegrityAction? movePlanToAccount(
    PrudentLocalStore store,
    Plan plan,
    Iterable<String> accountIds,
  ) {
    final choices = accountIds.where((id) => id != plan.posting.accountId).toList()..sort();
    if (choices.isEmpty) return null;
    return IntegrityAction.choose(
      'move_to_account',
      choices,
      (accountId) => _write(
        store.plans.get(plan.id),
        (current) => store.putPlan(
          current.deepCopy()..posting = (current.posting.deepCopy()..accountId = accountId),
        ),
      ),
    );
  }

  static IntegrityAction? movePlanToCategory(
    PrudentLocalStore store,
    Plan plan,
    Iterable<String> categoryIds,
  ) {
    final choices = categoryIds.where((id) => id != plan.categoryId).toList()..sort();
    if (choices.isEmpty) return null;
    return IntegrityAction.choose(
      'move_to_category',
      choices,
      (categoryId) => _write(
        store.plans.get(plan.id),
        (current) => store.putPlan(current.deepCopy()..categoryId = categoryId),
      ),
    );
  }

  /// The ids of live, unarchived categories — where a record or plan may be filed.
  static Iterable<String> fileableCategories(StoreSnapshot snapshot) =>
      snapshot.categories.values.where((c) => !c.archived).map((c) => c.id);

  /// The ids of live, active accounts — where money may be moved.
  static Iterable<String> activeAccounts(StoreSnapshot snapshot) =>
      snapshot.accounts.values.where((a) => a.active).map((a) => a.id);

  /// Applies [write] to the record as it stands *when the person acts*, not as it stood when the
  /// issue was found, so an edit made in between is not undone.
  static Future<ZenResult<Object?>> _write<T>(
    ZenResult<T> current,
    Future<ZenResult<Object?>> Function(T current) write,
  ) => switch (current) {
    ZenSuccess(:final data) => write(data),
    ZenFailure(:final error) => Future.value(ZenResult.err(error)),
  };
}
