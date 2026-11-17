import 'package:meta/meta.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import '../../generated/prudent_local/v1/store.pb.dart';
import '../derived_ids.dart';
import '../prudent_local_store.dart';

/// A store read failed; carries the store's own error out of a read so the ledger answers it as it
/// is, never as "nothing there".
final class LedgerReadFailure implements Exception {
  final ZenError error;
  const LedgerReadFailure(this.error);

  @override
  String toString() => 'LedgerReadFailure(${error.runtimeType}: ${error.message})';
}

/// The value [result] holds, or a [LedgerReadFailure] carrying its error.
T readOrThrow<T>(ZenResult<T> result) => switch (result) {
  ZenSuccess(:final data) => data,
  ZenFailure(:final error) => throw LedgerReadFailure(error),
};

/// An account's balances as figures may be shown: per currency, the opening amount plus every
/// record and transfer leg that is **settled** — and the ids of what was left out because two
/// devices disagree about it.
@immutable
final class AccountBalances {
  /// The derived balance of each held currency, in minor units.
  final Map<String, int> minor;

  /// The records, transfers and account currencies this account's figures leave out, because the
  /// store holds a conflict about something the figure reads (ADR-113). Empty when every figure is
  /// settled. Sorted.
  final List<String> unsettled;

  const AccountBalances(this.minor, this.unsettled);
}

/// A wire answer that carries a derived figure, together with what that figure leaves out
/// (ADR-113). The wire `Account.balances` has no room to say "this leaves out a record two devices
/// disagree about", and a balance that silently drops money reads as settled; so every ledger read
/// that answers balances answers this, and the caller cannot reach [value] without passing the
/// place where [unsettled] sits. The Local app (unit 9) shows it beside the figure.
@immutable
final class Settled<T> {
  /// The wire answer, its figures computed from settled values only.
  final T value;

  /// By what each figure belongs to — an account's balances, a budget summary's category, free
  /// money's currency, a goal's progress (unit 6a, ADR-116) — the ids of what it leaves out, sorted;
  /// a figure with nothing left out is absent.
  final Map<String, List<String>> unsettled;

  const Settled(this.value, this.unsettled);

  /// Whether every figure in [value] is settled.
  bool get isSettled => unsettled.isEmpty;
}

/// The ledger's records read once, with what the store holds in conflict, so every figure of one
/// answer is computed from one state.
///
/// **A figure never reads a disputed value (ADR-113).** While a record is in conflict the store shows
/// one side of it (`ZenCollection.get` and `list` take each disputed field from its latest version —
/// a wall-clock choice that is right for showing a record and wrong for summing it). So a record,
/// transfer or opening amount whose conflict touches what a figure reads — the posting of a record,
/// the opening of an account currency, or the record's very existence (a delete against an edit) —
/// counts in **no** figure, on any device, until the person settles it; and every figure that left
/// something out says what ([AccountBalances.unsettled]). A conflict about something else (a note, a
/// title, a display position) leaves the money agreed, and it is counted.
///
/// Excluding is the only answer every device gives alike: both devices hold the same conflict and
/// leave out the same record, whereas "the side shown" would let the order of two clocks decide a
/// balance. The record list still lists the record as the store shows it — a person has to see what
/// they are settling.
final class LedgerView {
  final Map<String, Account> accounts;
  final Map<String, AccountCurrency> accountCurrencies;
  final Map<String, Category> categories;
  final Map<String, Record> records;
  final Map<String, Transfer> transfers;
  final Map<String, Plan> plans;
  final Map<String, Budget> budgets;
  final Map<String, BudgetCarryOverReset> budgetResets;
  final Map<String, Goal> goals;
  final Map<String, GoalAllocation> goalAllocations;
  final Settings? settings;

  /// The stored occurrence states (skipped, or a reminder read) by id; see `PlanLedger`.
  final Map<String, OccurrenceState> occurrenceStates;

  /// Every record in conflict, with each device's value (the deleting side omitted).
  final Map<String, ZenConflict<Record>> recordConflicts;
  final Map<String, ZenConflict<Transfer>> transferConflicts;
  final Map<String, ZenConflict<AccountCurrency>> currencyConflicts;
  final Map<String, ZenConflict<Account>> accountConflicts;
  final Map<String, ZenConflict<Budget>> budgetConflicts;
  final Map<String, ZenConflict<BudgetCarryOverReset>> resetConflicts;
  final Map<String, ZenConflict<Goal>> goalConflicts;

  /// Every plan in conflict, with each device's value (the deleting side omitted).
  final Map<String, ZenConflict<Plan>> planConflicts;

  LedgerView._({
    required this.accounts,
    required this.accountCurrencies,
    required this.categories,
    required this.records,
    required this.transfers,
    required this.plans,
    required this.budgets,
    required this.budgetResets,
    required this.goals,
    required this.goalAllocations,
    required this.settings,
    required this.occurrenceStates,
    required this.recordConflicts,
    required this.transferConflicts,
    required this.currencyConflicts,
    required this.accountConflicts,
    required this.budgetConflicts,
    required this.resetConflicts,
    required this.goalConflicts,
    required this.planConflicts,
  });

  /// Reads the ledger's collections of [store]; throws [LedgerReadFailure] with the store's error.
  factory LedgerView.read(PrudentLocalStore store) {
    Map<String, T> all<T extends GeneratedMessage>(ZenCollection<T> c) => {
      for (final v in readOrThrow(c.list())) v.getField(1) as String: v,
    };
    Map<String, ZenConflict<T>> disputed<T extends GeneratedMessage>(ZenCollection<T> c) => {
      for (final conflict in readOrThrow(c.conflicts())) conflict.id: conflict,
    };
    return LedgerView._(
      accounts: all(store.accounts),
      accountCurrencies: all(store.accountCurrencies),
      categories: all(store.categories),
      records: all(store.records),
      transfers: all(store.transfers),
      plans: all(store.plans),
      budgets: all(store.budgets),
      budgetResets: all(store.budgetResets),
      goals: all(store.goals),
      goalAllocations: all(store.goalAllocations),
      settings: readOrThrow(store.settings.list()).firstOrNull,
      occurrenceStates: all(store.occurrences),
      recordConflicts: disputed(store.records),
      transferConflicts: disputed(store.transfers),
      currencyConflicts: disputed(store.accountCurrencies),
      accountConflicts: disputed(store.accounts),
      budgetConflicts: disputed(store.budgets),
      resetConflicts: disputed(store.budgetResets),
      goalConflicts: disputed(store.goals),
      planConflicts: disputed(store.plans),
    );
  }

  static final int _postingTag = Record().info_.byName['posting']!.tagNumber;
  static final int _openingTag = AccountCurrency().info_.byName['openingMinor']!.tagNumber;

  /// Every value of a record any device holds: the one shown and each side of its conflict. Rules
  /// that refuse a change while something still uses a thing ("a category with records") read
  /// these, so a record one device moved elsewhere still holds the thing on the other side.
  Iterable<Record> recordValues() sync* {
    yield* records.values;
    for (final conflict in recordConflicts.values) {
      for (final side in conflict.sides) {
        if (side.value case final value?) yield value;
      }
    }
  }

  /// [recordValues] for transfers (which are written once, so a conflict is not expected, but a
  /// store that held one would not be read past).
  Iterable<Transfer> transferValues() sync* {
    yield* transfers.values;
    for (final conflict in transferConflicts.values) {
      for (final side in conflict.sides) {
        if (side.value case final value?) yield value;
      }
    }
  }

  /// [recordValues] for budgets: a budget one device deleted and another re-planned still names its
  /// category on the other side, so "this category still has budgets" reads it (unit 6a).
  Iterable<Budget> budgetValues() => _values(budgets, budgetConflicts);

  /// [recordValues] for carry-over resets (unit 6a).
  Iterable<BudgetCarryOverReset> resetValues() => _values(budgetResets, resetConflicts);

  /// Every value of goal [id] any device holds: the one shown and each side of its conflict. A rule
  /// about a goal's state (money goes into an active goal only) holds only when it holds on every
  /// side, because which side the person keeps is theirs to say (unit 6a).
  List<Goal> goalSides(String id) => [
    ?goals[id],
    for (final side in goalConflicts[id]?.sides ?? const <ZenConflictSide<Goal>>[]) ?side.value,
  ];

  /// Whether a plan with [id] exists on any device's side: shown, or one side of a conflict.
  bool planExists(String id) => plans.containsKey(id) || planConflicts.containsKey(id);

  /// [recordValues] for plans (unit 6b): the "still used by" rules read every side of a conflict.
  Iterable<Plan> planValues() => _values(plans, planConflicts);

  static Iterable<T> _values<T>(Map<String, T> shown, Map<String, ZenConflict<T>> conflicts) sync* {
    yield* shown.values;
    for (final conflict in conflicts.values) {
      for (final side in conflict.sides) {
        if (side.value case final value?) yield value;
      }
    }
  }

  /// Whether a conflict on a record touches any of [tags] or the record's existence: then a figure
  /// that reads one of those fields would read a value two devices disagree about (ADR-113).
  static bool disputes<T>(ZenConflict<T>? conflict, Set<int> tags) =>
      conflict != null && (conflict.isDeleteConflict || conflict.fields.any(tags.contains));

  /// The account currencies of [accountId], in display order (position, then code).
  List<AccountCurrency> currenciesOf(String accountId) =>
      accountCurrencies.values.where((c) => c.accountId == accountId).toList()..sort((a, b) {
        final byPosition = a.position.compareTo(b.position);
        return byPosition != 0 ? byPosition : a.currency.compareTo(b.currency);
      });

  /// Whether [accountId] holds [currency] as the store shows it.
  bool holds(String accountId, String currency) =>
      accountCurrencies.containsKey(DerivedIds.accountCurrency(accountId, currency));

  /// Whether the conflict on a record touches what a balance reads: its posting, or its existence.
  static bool _disputesMoney<T>(ZenConflict<T> conflict, int tag) =>
      conflict.isDeleteConflict || conflict.fields.contains(tag);

  /// The balances of [accountId] from settled figures only (see the class comment).
  AccountBalances balancesOf(String accountId) {
    final unsettled = <String>{};
    final minor = <String, int>{};
    for (final c in currenciesOf(accountId)) {
      final conflict = currencyConflicts[c.id];
      if (conflict != null && _disputesMoney(conflict, _openingTag)) {
        unsettled.add(c.id);
        minor[c.currency] = 0;
      } else {
        minor[c.currency] = c.openingMinor.toInt();
      }
    }
    void add(String currency, int amount) {
      // A posting in a currency the account does not hold is not part of its balance, as on the
      // server (`AccountMapper` iterates the held currencies); the integrity check names it.
      final current = minor[currency];
      if (current != null) minor[currency] = addExact(current, amount);
    }

    for (final record in records.values) {
      final conflict = recordConflicts[record.id];
      if (conflict != null && _disputesMoney(conflict, _postingTag)) continue;
      if (record.posting.accountId == accountId) {
        add(record.posting.currency, record.posting.amountMinor.toInt());
      }
    }
    for (final conflict in recordConflicts.values) {
      if (!_disputesMoney(conflict, _postingTag)) continue;
      final touches =
          records[conflict.id]?.posting.accountId == accountId ||
          conflict.sides.any((s) => s.value?.posting.accountId == accountId);
      if (touches) unsettled.add(conflict.id);
    }
    for (final transfer in transfers.values) {
      if (transferConflicts.containsKey(transfer.id)) continue;
      if (transfer.source.accountId == accountId) {
        add(transfer.source.currency, negateExact(transfer.source.amountMinor.toInt()));
      }
      if (transfer.destination.accountId == accountId) {
        add(transfer.destination.currency, transfer.destination.amountMinor.toInt());
      }
    }
    for (final conflict in transferConflicts.values) {
      final touches = conflict.sides.any(
        (s) =>
            s.value?.source.accountId == accountId || s.value?.destination.accountId == accountId,
      );
      if (touches) unsettled.add(conflict.id);
    }
    return AccountBalances(Map.unmodifiable(minor), List.unmodifiable(unsettled.toList()..sort()));
  }

  /// What [accountId]'s balance in [currency] leaves out (see [balancesOf]).
  List<String> unsettledIn(String accountId, String currency) {
    final out = <String>{};
    final opening = currencyConflicts[DerivedIds.accountCurrency(accountId, currency)];
    if (opening != null && _disputesMoney(opening, _openingTag)) out.add(opening.id);
    for (final conflict in recordConflicts.values) {
      if (!_disputesMoney(conflict, _postingTag)) continue;
      bool on(Record? r) =>
          r != null && r.posting.accountId == accountId && r.posting.currency == currency;
      if (on(records[conflict.id]) || conflict.sides.any((s) => on(s.value))) {
        out.add(conflict.id);
      }
    }
    for (final conflict in transferConflicts.values) {
      bool on(Posting p) => p.accountId == accountId && p.currency == currency;
      if (conflict.sides.any(
        (s) => s.value != null && (on(s.value!.source) || on(s.value!.destination)),
      )) {
        out.add(conflict.id);
      }
    }
    return out.toList()..sort();
  }
}
