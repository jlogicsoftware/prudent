import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_ui/money.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import '../l10n/generated/local_localizations.dart';

/// How each of Prudent's collections shows a conflict: a record the person recognises ("Record
/// Groceries, 2026-11-12") and each disputed field by its name and value, an amount formatted, an
/// account or category by its name rather than its id.
///
/// Every collection of the store is listed, so a conflict in one is never invisible; the ones the
/// screens do not edit yet (budgets, goals, plans) are shown with the store's plain field names
/// until their units add words.
List<ZenConflictSource> prudentConflictSources(
  PrudentLocalStore store,
  LocalLocalizations t,
) {
  String accountName(String id) => _value(store.accounts, id)?.name ?? id;
  String categoryName(String id) => _value(store.categories, id)?.title ?? id;
  String posting(Posting p) =>
      '${formatMinorUnits(p.amountMinor)} ${p.currency} (${accountName(p.accountId)})';

  return [
    ZenConflictSource<Account>(
      collection: store.accounts,
      title: (a) => t.conflictAccount(a.name),
      fieldLabel: (field) => switch (field) {
        2 => t.fieldName,
        4 => t.fieldActive,
        _ => null,
      },
    ),
    ZenConflictSource<AccountCurrency>(
      collection: store.accountCurrencies,
      title: (c) =>
          '${t.conflictAccountCurrency(c.currency)} — ${accountName(c.accountId)}',
      fieldLabel: (field) => field == 4 ? t.fieldOpening : null,
      fieldValue: (c, field) => field == 4
          ? '${formatMinorUnits(c.openingMinor)} ${c.currency}'
          : null,
    ),
    ZenConflictSource<Category>(
      collection: store.categories,
      title: (c) => t.conflictCategory(c.title),
      fieldLabel: (field) => switch (field) {
        2 => t.fieldName,
        6 => t.fieldArchived,
        _ => null,
      },
    ),
    ZenConflictSource<Record>(
      collection: store.records,
      title: (r) => t.conflictRecord('${r.title}, ${r.date}'),
      fieldLabel: (field) => switch (field) {
        2 => t.fieldTitle,
        3 => t.fieldAmount,
        4 => t.fieldDate,
        5 => t.fieldCategory,
        6 => t.fieldPayee,
        7 => t.fieldNote,
        _ => null,
      },
      fieldValue: (r, field) => switch (field) {
        3 when r.hasPosting() => posting(r.posting),
        5 when r.hasCategoryId() => categoryName(r.categoryId),
        _ => null,
      },
    ),
    ZenConflictSource<Transfer>(
      collection: store.transfers,
      title: (tr) => t.conflictTransfer('${tr.title}, ${tr.date}'),
      fieldLabel: (field) => switch (field) {
        2 => t.fieldTitle,
        3 => t.fieldDate,
        4 || 5 => t.fieldAccount,
        _ => null,
      },
      fieldValue: (tr, field) => switch (field) {
        4 when tr.hasSource() => posting(tr.source),
        5 when tr.hasDestination() => posting(tr.destination),
        _ => null,
      },
    ),
    ZenConflictSource<Settings>(
      collection: store.settings,
      title: (_) => t.conflictSettings,
      fieldLabel: (field) => switch (field) {
        2 => t.fieldMainCurrency,
        3 => t.fieldDefaultAccount,
        _ => null,
      },
      fieldValue: (s, field) => field == 3 && s.hasDefaultAccountId()
          ? accountName(s.defaultAccountId)
          : null,
    ),
    _plain<Budget>(store.budgets, t),
    _plain<BudgetCarryOverReset>(store.budgetResets, t),
    _plain<Goal>(store.goals, t),
    _plain<GoalAllocation>(store.goalAllocations, t),
    _plain<Plan>(store.plans, t),
    _plain<OccurrenceState>(store.occurrences, t),
  ];
}

ZenConflictSource<T> _plain<T extends GeneratedMessage>(
  ZenCollection<T> collection,
  LocalLocalizations t,
) => ZenConflictSource<T>(
  collection: collection,
  title: (_) => t.conflictOther(collection.name),
);

T? _value<T extends GeneratedMessage>(ZenCollection<T> collection, String id) =>
    collection.get(id).dataOrNull;
