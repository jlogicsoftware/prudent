import '../../../generated/prudent_local/v1/store.pb.dart';
import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';
import 'repairs.dart';

/// A record whose sign its category's kind refuses.
///
/// The server refuses an income under an expense-only category and an expense under an income-only
/// one when the record is written (`CategoryEntity.canFile`, phase-0 §0.3 row 5.19). On two devices
/// one can change the category's kind while the other files a record of the other sign under it.
/// The person lets the category take both directions or files the record elsewhere.
final class CategoryKindCheck implements IntegrityCheck {
  const CategoryKindCheck();

  @override
  String get name => 'category_kind';

  /// `CategoryEntity.canFile`, value for value: an expense-only category refuses a positive amount,
  /// an income-only one a negative amount; zero and an unspecified kind are always accepted.
  static bool canFile(CategoryDirection kind, int amountMinor) =>
      !(kind == CategoryDirection.CATEGORY_DIRECTION_EXPENSE && amountMinor > 0 ||
          kind == CategoryDirection.CATEGORY_DIRECTION_INCOME && amountMinor < 0);

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    for (final record in snapshot.records.values) {
      if (!record.hasCategoryId()) continue;
      final category = snapshot.categories[record.categoryId];
      if (category == null) continue; // the dangling-reference check's
      final amount = record.posting.amountMinor.toInt();
      if (canFile(category.kind, amount)) continue;
      final fits = snapshot.categories.values
          .where((c) => !c.archived && canFile(c.kind, amount))
          .map((c) => c.id);
      yield IntegrityIssue(
        code: 'category.kind_refuses_sign',
        collection: 'records',
        recordId: record.id,
        facts: {'categoryId': category.id, 'kind': category.kind.name},
        actions: [
          IntegrityAction.now(
            'category_takes_both',
            () => store.putCategory(
              category.deepCopy()..kind = CategoryDirection.CATEGORY_DIRECTION_UNSPECIFIED,
            ),
          ),
          ?Repairs.moveRecordToCategory(store, record, fits),
        ],
      );
    }
  }
}
