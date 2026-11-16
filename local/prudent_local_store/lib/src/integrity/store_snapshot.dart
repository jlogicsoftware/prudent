import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import '../../generated/prudent_local/v1/store.pb.dart';
import '../prudent_local_store.dart';

/// Every live record of every collection, read once, so the integrity checks see one consistent
/// state and do not each walk the store. Records in conflict are read as the store shows them (each
/// disputed field from its latest version), which is what the person sees too.
final class StoreSnapshot {
  final Map<String, Account> accounts;
  final Map<String, AccountCurrency> accountCurrencies;
  final Map<String, Category> categories;
  final Map<String, Record> records;
  final Map<String, Transfer> transfers;
  final Map<String, Budget> budgets;
  final Map<String, BudgetCarryOverReset> budgetResets;
  final Map<String, Goal> goals;
  final Map<String, GoalAllocation> goalAllocations;
  final Map<String, Plan> plans;
  final Map<String, OccurrenceState> occurrences;
  final Settings? settings;

  StoreSnapshot._({
    required this.accounts,
    required this.accountCurrencies,
    required this.categories,
    required this.records,
    required this.transfers,
    required this.budgets,
    required this.budgetResets,
    required this.goals,
    required this.goalAllocations,
    required this.plans,
    required this.occurrences,
    required this.settings,
  });

  /// Reads [store], or fails with the store's own error when a record cannot be read.
  static ZenResult<StoreSnapshot> read(PrudentLocalStore store) {
    try {
      final settings = _all(store.settings);
      return ZenResult.ok(
        StoreSnapshot._(
          accounts: _all(store.accounts),
          accountCurrencies: _all(store.accountCurrencies),
          categories: _all(store.categories),
          records: _all(store.records),
          transfers: _all(store.transfers),
          budgets: _all(store.budgets),
          budgetResets: _all(store.budgetResets),
          goals: _all(store.goals),
          goalAllocations: _all(store.goalAllocations),
          plans: _all(store.plans),
          occurrences: _all(store.occurrences),
          settings: settings.values.firstOrNull,
        ),
      );
    } on _Unreadable catch (e) {
      return ZenResult.err(e.error);
    }
  }

  /// Whether [accountId] holds [currency]: an account-currency record exists for the pair.
  bool holds(String accountId, String currency) =>
      accountCurrencies.values.any((c) => c.accountId == accountId && c.currency == currency);

  static Map<String, T> _all<T extends GeneratedMessage>(ZenCollection<T> collection) =>
      switch (collection.list()) {
        ZenSuccess(:final data) => {for (final value in data) value.getField(1) as String: value},
        ZenFailure(:final error) => throw _Unreadable(error),
      };
}

final class _Unreadable implements Exception {
  final ZenError error;
  const _Unreadable(this.error);
}
