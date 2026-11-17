import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:meta/meta.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/privacy.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import '../../generated/prudent_local/v1/store.pb.dart';
import '../derived_ids.dart';
import '../ledger/ledger_view.dart';
import '../prudent_local_store.dart';
import '../wire_mapper.dart';
import '../write_expect.dart';
import 'move_in_refusal.dart';

/// Moving a person's data from the server into an empty Prudent Local store, once, by the privacy
/// export file (unit 10b; ADR-103 decides it, ADR-123 records how it is built).
///
/// - **Into an empty store only.** A store that holds anything refuses it, and the write checks
///   again, inside the store's own turn, that nothing arrived meanwhile (a sync from another device).
/// - **All or nothing.** Every record is written by one `writeAll`; if any part is refused, nothing
///   is written. Every part carries an `expect` that its record is still absent (ADR-115).
/// - **Ids from the export, never random.** A row keeps the server's id, written as 32 lower-case
///   hex characters ([LocalIds.fromServerId]); a row whose collection derives its id from a natural
///   key gets that id (an opening amount, a budget, an occurrence state, a confirming record, an
///   imported record). The same export moved in on two devices therefore writes the same records, which
///   merge as one when the devices sync.
/// - **Openings rebuilt (finding F-03).** The export's account balances are current balances; the
///   opening of each account and currency is `exported balance − Σ exported records` there.
/// - **A transfer's two legs become one record** (ADR-102). A leg without its partner is refused.
/// - **Statement keys survive** (ADR-110): an imported record carries its key and the id derived from
///   it, so a statement imported before the move is recognised as already imported after it.
/// - **Refused whole unless every balance matches to the cent** after the import, computed by the
///   ledger's own [LedgerView.balancesOf] over exactly the records about to be written. That check
///   catches a dropped or mis-joined record. **It is the only figure checked at run time:** budgets,
///   carry-over, envelopes, free money, goal progress and occurrences are not in the export, so they
///   cannot be compared here; the parity suite proves them against the server instead (ADR-123).
///
/// **Dropped on purpose:** the profile (Prudent Local has no account), import sessions and their rows
/// (a session is device-only and short-lived, ADR-114), and every planned occurrence (Local reads
/// them from the plan's schedule, ADR-119; only a skip is stored).
final class MoveIn {
  MoveIn(this.store, {@visibleForTesting this.fault});

  final PrudentLocalStore store;

  /// A test's change to the planned records just before the balance check, so that the check can be
  /// shown to catch a dropped or mis-joined record. Null in the app.
  final MoveInFault? fault;

  /// The `DataExport.format_version` this build reads (`PrudentDataExporter.FORMAT_VERSION`).
  static const int formatVersion = 1;

  /// The statement-key version this build reads (`RowFingerprints`, ADR-091): `v1:` and 64 lower-case
  /// hex characters. A key of another version is refused, never guessed at (ADR-110).
  static final RegExp _fingerprint = RegExp(r'^v1:[0-9a-f]{64}$');

  /// The export in [bytes]: UTF-8, canonical proto3 JSON, as the server answers it and as both apps
  /// save it. A field this build does not know is refused rather than dropped.
  static wire.DataExport read(List<int> bytes) {
    try {
      final Object? json = jsonDecode(utf8.decode(bytes));
      return wire.DataExport()..mergeFromProto3Json(json, ignoreUnknownFields: false);
    } on FormatException {
      throw const MoveInRefusal(MoveInRule.unreadable);
    } on ArgumentError {
      throw const MoveInRefusal(MoveInRule.unreadable);
    }
  }

  /// Moves [export] in: refused whole with the reason, or written whole.
  Future<MoveInResult> run(wire.DataExport export) async {
    try {
      final failure = _anythingHeld(store);
      if (failure != null) throw failure;
      final plan = MoveInPlan.of(export, fault: fault);
      final batch = StoreBatch(store);
      plan._addTo(batch, (_) => _anythingHeld(store)?._asError());
      final written = await store.writeAll(batch);
      if (written case ZenFailure(:final error)) {
        throw _refusalOf(error) ??
            MoveInRefusal(
              error is ZenConflictError ? MoveInRule.changedMeanwhile : MoveInRule.storeFailed,
              const {},
              error,
            );
      }
      return MovedIn(plan.summary);
    } on MoveInRefusal catch (refusal) {
      return MoveInRefused(refusal);
    }
  }

  /// Why the store does not count as empty, or null when it holds nothing at all: no record in any
  /// synced collection, no conflict, and no import session.
  static MoveInRefusal? _anythingHeld(PrudentLocalStore store) {
    final collections = <ZenCollection<GeneratedMessage>>[
      store.accounts,
      store.accountCurrencies,
      store.categories,
      store.records,
      store.transfers,
      store.budgets,
      store.budgetResets,
      store.goals,
      store.goalAllocations,
      store.plans,
      store.occurrences,
      store.settings,
      store.importSessions,
    ];
    for (final collection in collections) {
      final listed = collection.list();
      final conflicts = collection.conflicts();
      if (listed case ZenFailure(:final error)) {
        return MoveInRefusal(MoveInRule.storeFailed, const {}, error);
      }
      if (conflicts case ZenFailure(:final error)) {
        return MoveInRefusal(MoveInRule.storeFailed, const {}, error);
      }
      if (listed.dataOrNull!.isNotEmpty || conflicts.dataOrNull!.isNotEmpty) {
        return const MoveInRefusal(MoveInRule.storeNotEmpty);
      }
    }
    return null;
  }

  /// The refusal an `expect` of this move carried out of the store's turn, if it was one.
  static MoveInRefusal? _refusalOf(ZenError error) {
    final code = error.internalData?['moveIn'];
    if (code is! String) return null;
    for (final rule in MoveInRule.values) {
      if (rule.code == code) return MoveInRefusal(rule, const {}, error);
    }
    return null;
  }
}

extension on MoveInRefusal {
  /// This refusal as the error an `expect` answers, carrying the rule out of the store's turn.
  ZenError _asError() => ZenConflictError(
    'The store is no longer empty: ${rule.code}.',
    internalData: {'moveIn': rule.code},
  );
}

/// A test's change to the planned records and transfers, by id, before the balance check.
typedef MoveInFault = void Function(Map<String, Record> records, Map<String, Transfer> transfers);

/// What a move answered.
sealed class MoveInResult {
  const MoveInResult();
}

/// Everything was written; [summary] counts it.
final class MovedIn extends MoveInResult {
  const MovedIn(this.summary);
  final MoveInSummary summary;
}

/// Nothing was written, for [refusal]'s reason.
final class MoveInRefused extends MoveInResult {
  const MoveInRefused(this.refusal);
  final MoveInRefusal refusal;
}

/// What a move wrote, and what it left out on purpose.
@immutable
final class MoveInSummary {
  const MoveInSummary({
    required this.accounts,
    required this.categories,
    required this.records,
    required this.transfers,
    required this.plans,
    required this.skippedOccurrences,
    required this.budgets,
    required this.carryOverResets,
    required this.goals,
    required this.goalAllocations,
    required this.importKeys,
    required this.droppedImportSessions,
  });

  final int accounts;
  final int categories;

  /// Ordinary records, corrections and confirmations; a transfer counts once, in [transfers].
  final int records;
  final int transfers;
  final int plans;
  final int skippedOccurrences;
  final int budgets;
  final int carryOverResets;
  final int goals;
  final int goalAllocations;

  /// Records that keep their statement key, so the statement is recognised if imported again.
  final int importKeys;

  /// Import sessions in the export, which are not moved (ADR-114: a session is device-only).
  final int droppedImportSessions;
}

/// The store records a move will write, built from an export and checked, with nothing written yet.
/// [MoveInPlan.of] throws a [MoveInRefusal] for anything it cannot move exactly.
final class MoveInPlan {
  MoveInPlan._(this.summary);

  final MoveInSummary summary;

  final List<Account> accounts = [];
  final List<AccountCurrency> accountCurrencies = [];
  final List<Category> categories = [];
  final List<Record> records = [];
  final List<Transfer> transfers = [];
  final List<Plan> plans = [];
  final List<OccurrenceState> occurrences = [];
  final List<Budget> budgets = [];
  final List<BudgetCarryOverReset> resets = [];
  final List<Goal> goals = [];
  final List<GoalAllocation> allocations = [];
  late final Settings settings;

  /// Builds and checks the plan for [export].
  static MoveInPlan of(wire.DataExport export, {@visibleForTesting MoveInFault? fault}) {
    try {
      return _Planner(export, fault).plan();
    } on MoneyOverflow {
      // A sum the server could not have produced: its own arithmetic is the same exact 64-bit one.
      throw const MoveInRefusal(MoveInRule.invalidValue, {'collection': 'balances'});
    }
  }

  /// Every record as one batch. [first] is an extra precondition on the first operation, run in
  /// the store's turn before anything of the batch is applied: the move uses it to find the store
  /// still empty.
  void _addTo(StoreBatch batch, ZenError? Function(Object? current) first) {
    var firstDone = false;
    WriteExpect<T> absent<T extends GeneratedMessage>() {
      final asNew = WriteExpects.asRead<T>(null, changed: _changed);
      if (firstDone) return asNew;
      firstDone = true;
      return (current) => first(current) ?? asNew(current);
    }

    batch.putSettings(settings, expect: absent());
    for (final v in accounts) {
      batch.putAccount(v, expect: absent());
    }
    for (final v in accountCurrencies) {
      batch.putAccountCurrency(v, expect: absent());
    }
    for (final v in categories) {
      batch.putCategory(v, expect: absent());
    }
    for (final v in records) {
      batch.putRecord(v, expect: absent());
    }
    for (final v in transfers) {
      batch.addTransfer(v, expect: absent());
    }
    for (final v in plans) {
      batch.putPlan(v, expect: absent());
    }
    for (final v in occurrences) {
      batch.putOccurrenceState(v, expect: absent());
    }
    for (final v in budgets) {
      batch.putBudget(v, expect: absent());
    }
    for (final v in resets) {
      batch.addMovedBudgetReset(v, expect: absent());
    }
    for (final v in goals) {
      batch.putGoal(v, expect: absent());
    }
    for (final v in allocations) {
      batch.addGoalAllocation(v, expect: absent());
    }
  }

  static ZenError _changed() => const ZenConflictError(
    'The store changed while the move was being written.',
    internalData: {'moveIn': 'move_in.changed_meanwhile'},
  );
}

/// One pass over an export. Ids are turned into Local ids first; everything after works in them.
final class _Planner {
  _Planner(this.export, this.fault);

  final wire.DataExport export;
  final MoveInFault? fault;

  MoveInPlan plan() {
    if (export.formatVersion != MoveIn.formatVersion) {
      throw MoveInRefusal(MoveInRule.formatVersion, {'version': '${export.formatVersion}'});
    }

    // ── Accounts ──────────────────────────────────────────────────────────────────────────────
    final accounts = <String, Account>{};
    final currencies = <String, AccountCurrency>{};
    final exported = <(String, String), int>{}; // (account, currency) → exported current balance
    final wireAccounts = <String, wire.Account>{};
    String? defaultAccount;
    var defaults = 0;
    for (final value in export.accounts) {
      final id = _id(value.id, 'accounts');
      _unique(wireAccounts.keys, id, 'accounts');
      wireAccounts[id] = value;
      if (value.isDefault) {
        defaults++;
        defaultAccount = id;
      }
      for (final balance in value.balances) {
        _canonical(() => DerivedIds.accountCurrency(id, balance.currency), 'accounts', id);
        exported[(id, balance.currency)] = balance.amountMinor.toInt();
      }
    }
    if (defaults > 1) throw MoveInRefusal(MoveInRule.twoDefaults, {'count': '$defaults'});

    // ── Categories ────────────────────────────────────────────────────────────────────────────
    final categories = <String, Category>{};
    for (final value in export.categories) {
      final id = _id(value.id, 'categories');
      _unique(categories.keys, id, 'categories');
      categories[id] = WireMapper.categoryFromWire(value.deepCopy()..id = id);
    }

    // ── Plans and their occurrences ───────────────────────────────────────────────────────────
    final plans = <String, Plan>{};
    for (final value in export.plans) {
      final id = _id(value.id, 'plans');
      _unique(plans.keys, id, 'plans');
      final account = _ref(value.accountId, 'plans', id, 'accounts', wireAccounts.keys);
      final category = _ref(value.categoryId, 'plans', id, 'categories', categories.keys);
      _held(exported, account, value.currency, 'plans', id);
      if (value.hasRecurrence() && !PlanZones.isValid(value.recurrence.timeZone)) {
        throw MoveInRefusal(MoveInRule.planZone, {'plan': id});
      }
      plans[id] = WireMapper.planFromWire(
        value.deepCopy()
          ..id = id
          ..accountId = account
          ..categoryId = category,
      );
    }
    // Server occurrence id → (plan, date, status), every one of them, so a confirmation can be
    // remapped and a skip stored.
    final occurrences = <String, (String, String, wire.OccurrenceStatus)>{};
    final occurrenceSlots = <String>{};
    for (final value in export.occurrences) {
      final id = _id(value.id, 'occurrences');
      _unique(occurrences.keys, id, 'occurrences');
      final plan = _ref(value.planId, 'occurrences', id, 'plans', plans.keys);
      final slot = _canonical(
        () => DerivedIds.occurrence(plan, value.occurrenceDate),
        'occurrences',
        id,
      );
      _unique(occurrenceSlots, slot, 'occurrences');
      occurrenceSlots.add(slot);
      occurrences[id] = (plan, value.occurrenceDate, value.status);
    }

    // ── Records: transfers joined, everything else one by one ─────────────────────────────────
    final keys = <String, wire.ExportImportKey>{};
    for (final key in export.recordImportKeys) {
      final record = _id(key.recordId, 'record_import_keys');
      _unique(keys.keys, record, 'record_import_keys');
      keys[record] = key;
    }
    final legs = <String, List<wire.Record>>{};
    final plain = <String, wire.Record>{};
    final seenRecordIds = <String>{};
    final postings = <(String, String), int>{}; // Σ exported records per (account, currency)
    for (final value in export.records) {
      final id = _id(value.id, 'records');
      _unique(seenRecordIds, id, 'records');
      seenRecordIds.add(id);
      final account = _ref(value.accountId, 'records', id, 'accounts', wireAccounts.keys);
      _held(exported, account, value.currency, 'records', id);
      final key = (account, value.currency);
      postings[key] = addExact(postings[key] ?? 0, value.amountMinor.toInt());
      if (value.hasTransferId()) {
        (legs[_id(value.transferId, 'records')] ??= []).add(
          value.deepCopy()
            ..id = id
            ..accountId = account,
        );
      } else {
        plain[id] = value;
      }
    }
    for (final record in keys.keys) {
      if (!seenRecordIds.contains(record)) {
        throw MoveInRefusal(MoveInRule.unknownReference, {
          'collection': 'record_import_keys',
          'id': record,
          'missing': 'records',
          'missingId': record,
        });
      }
      if (!plain.containsKey(record)) throw MoveInRefusal(MoveInRule.importKey, {'record': record});
    }

    // Openings: exported balance − Σ exported records, per account and currency (F-03).
    final openings = <String, Map<String, int>>{};
    for (final MapEntry(key: (account, currency), value: balance) in exported.entries) {
      (openings[account] ??= {})[currency] = subtractExact(
        balance,
        postings[(account, currency)] ?? 0,
      );
    }
    for (final MapEntry(key: id, value: value) in wireAccounts.entries) {
      final AccountParts parts;
      try {
        parts = WireMapper.accountFromWire(
          value.deepCopy()..id = id,
          openingMinor: openings[id] ?? const {},
        );
      } on ArgumentError {
        throw MoveInRefusal(MoveInRule.invalidValue, {'collection': 'accounts', 'id': id});
      }
      accounts[id] = parts.account;
      for (final c in parts.currencies) {
        currencies[c.id] = c;
      }
    }

    final transfers = <String, Transfer>{};
    for (final MapEntry(key: id, value: pair) in legs.entries) {
      final from = pair.where((r) => r.amountMinor < 0).toList();
      final to = pair.where((r) => r.amountMinor > 0).toList();
      if (pair.length != 2 || from.length != 1 || to.length != 1) {
        throw MoveInRefusal(MoveInRule.transferBroken, {'transfer': id, 'legs': '${pair.length}'});
      }
      try {
        transfers[id] = WireMapper.transferFromWire(
          wire.Transfer(
            id: id,
            fromRecord: from.single..transferId = id,
            toRecord: to.single..transferId = id,
          ),
        );
      } on ArgumentError {
        throw MoveInRefusal(MoveInRule.transferBroken, {'transfer': id, 'legs': '2'});
      }
    }

    final records = <String, Record>{};
    final confirmed = <String>{}; // server occurrence ids a record confirms
    final corrections = <String>[];
    for (final MapEntry(key: id, value: value) in plain.entries) {
      final account = _id(value.accountId, 'records');
      final copy = value.deepCopy()
        ..id = id
        ..accountId = account;
      if (value.hasCategoryId()) {
        copy.categoryId = _ref(value.categoryId, 'records', id, 'categories', categories.keys);
      }
      PlanLink? link;
      if (value.hasPlanId() || value.hasPlanOccurrenceId()) {
        final plan = _ref(value.planId, 'records', id, 'plans', plans.keys);
        final occurrence = _ref(
          value.planOccurrenceId,
          'records',
          id,
          'occurrences',
          occurrences.keys,
        );
        final (occurrencePlan, date, status) = occurrences[occurrence]!;
        if (occurrencePlan != plan ||
            status != wire.OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED ||
            !confirmed.add(occurrence)) {
          throw MoveInRefusal(MoveInRule.occurrenceUnpaired, {'occurrence': occurrence});
        }
        link = PlanLink(
          planId: plan,
          occurrenceId: DerivedIds.occurrence(plan, date),
          occurrenceDate: date,
        );
        copy
          ..planId = plan
          ..planOccurrenceId = link.occurrenceId;
      }
      final key = keys[id];
      ImportKey? importKey;
      if (key != null) {
        if (link != null || value.isCorrection || !MoveIn._fingerprint.hasMatch(key.fingerprint) ||
            key.occurrence < 1) {
          throw MoveInRefusal(MoveInRule.importKey, {'record': id});
        }
        importKey = ImportKey(fingerprint: key.fingerprint, occurrence: key.occurrence);
      }
      final Record record;
      try {
        record = WireMapper.recordFromWire(
          copy,
          correction: value.isCorrection ? CorrectionIntent() : null,
          importKey: importKey,
        );
      } on ArgumentError {
        throw MoveInRefusal(MoveInRule.invalidValue, {'collection': 'records', 'id': id});
      }
      if (link != null) {
        record
          ..planLink = link
          ..id = DerivedIds.confirmation(link.occurrenceId);
      } else if (importKey != null) {
        record.id = DerivedIds.imported(account, importKey.fingerprint, importKey.occurrence);
      }
      if (records.containsKey(record.id)) {
        throw MoveInRefusal(MoveInRule.duplicateId, {'collection': 'records', 'id': id});
      }
      records[record.id] = record;
      if (value.isCorrection) corrections.add(record.id);
    }
    for (final MapEntry(key: id, value: (_, _, status)) in occurrences.entries) {
      if (status == wire.OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED && !confirmed.contains(id)) {
        throw MoveInRefusal(MoveInRule.occurrenceUnpaired, {'occurrence': id});
      }
    }
    _fillCorrections(records, transfers, currencies, corrections);

    // ── Budgets, resets, goals, allocations, settings ─────────────────────────────────────────
    final budgets = <String, Budget>{};
    for (final value in export.budgets) {
      final category = _ref(value.categoryId, 'budgets', value.categoryId, 'categories',
          categories.keys);
      final budget = _canonical(
        () => WireMapper.budgetFromWire(value.deepCopy()..categoryId = category),
        'budgets',
        category,
      );
      _unique(budgets.keys, budget.id, 'budgets');
      budgets[budget.id] = budget;
    }
    final resets = <String, BudgetCarryOverReset>{};
    for (final value in export.carryOverResets) {
      final id = _id(value.id, 'carry_over_resets');
      _unique(resets.keys, id, 'carry_over_resets');
      final category = _ref(value.categoryId, 'carry_over_resets', id, 'categories',
          categories.keys);
      resets[id] = _canonical(
        () => WireMapper.resetFromWire(
          value.deepCopy()
            ..id = id
            ..categoryId = category,
        ),
        'carry_over_resets',
        id,
      );
    }
    final goals = <String, Goal>{};
    for (final value in export.goals) {
      final id = _id(value.id, 'goals');
      _unique(goals.keys, id, 'goals');
      goals[id] = WireMapper.goalFromWire(value.deepCopy()..id = id);
    }
    final allocations = <String, GoalAllocation>{};
    for (final value in export.goalAllocations) {
      final id = _id(value.id, 'goal_allocations');
      _unique(allocations.keys, id, 'goal_allocations');
      final copy = value.deepCopy()..id = id;
      if (value.hasSourceGoalId()) {
        copy.sourceGoalId = _ref(value.sourceGoalId, 'goal_allocations', id, 'goals', goals.keys);
      }
      if (value.hasTargetGoalId()) {
        copy.targetGoalId = _ref(value.targetGoalId, 'goal_allocations', id, 'goals', goals.keys);
      }
      allocations[id] = WireMapper.allocationFromWire(copy);
    }
    final settings = WireMapper.settingsFromWire(
      export.settings,
      defaultAccountId: defaultAccount,
    );

    // ── The balance check (ADR-103) ───────────────────────────────────────────────────────────
    fault?.call(records, transfers);
    final view = LedgerView.planned(
      accounts: accounts,
      accountCurrencies: currencies,
      records: records,
      transfers: transfers,
    );
    for (final account in accounts.keys) {
      final derived = view.balancesOf(account).minor;
      for (final MapEntry(key: (owner, currency), value: expected) in exported.entries) {
        if (owner != account) continue;
        final actual = derived[currency];
        if (actual != expected) {
          throw MoveInRefusal(MoveInRule.balanceMismatch, {
            'account': account,
            'currency': currency,
            'expected': '$expected',
            'actual': '${actual ?? 'none'}',
          });
        }
      }
    }

    final skipped = [
      for (final (plan, date, status) in occurrences.values)
        if (status == wire.OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED)
          OccurrenceState(
            id: DerivedIds.occurrence(plan, date),
            planId: plan,
            occurrenceDate: date,
            skipped: true,
          ),
    ];

    final out = MoveInPlan._(
      MoveInSummary(
        accounts: accounts.length,
        categories: categories.length,
        records: records.length,
        transfers: transfers.length,
        plans: plans.length,
        skippedOccurrences: skipped.length,
        budgets: budgets.length,
        carryOverResets: resets.length,
        goals: goals.length,
        goalAllocations: allocations.length,
        importKeys: keys.length,
        droppedImportSessions: export.importSessions.length,
      ),
    );
    // Sorted by id, so the batch is the same on every device and in every run.
    List<T> sorted<T extends GeneratedMessage>(Iterable<T> values) =>
        values.toList()..sort((a, b) => (a.getField(1) as String).compareTo(b.getField(1) as String));
    out.accounts.addAll(sorted(accounts.values));
    out.accountCurrencies.addAll(sorted(currencies.values));
    out.categories.addAll(sorted(categories.values));
    out.records.addAll(sorted(records.values));
    out.transfers.addAll(sorted(transfers.values));
    out.plans.addAll(sorted(plans.values));
    out.occurrences.addAll(sorted(skipped));
    out.budgets.addAll(sorted(budgets.values));
    out.resets.addAll(sorted(resets.values));
    out.goals.addAll(sorted(goals.values));
    out.allocations.addAll(sorted(allocations.values));
    out.settings = settings;
    return out;
  }

  /// A correction's intent (ADR-102 D7), which the export does not carry: the balance it saw is
  /// the opening plus everything on its account and currency that comes before it in date order (ties
  /// by id), the balance it asked for that plus its delta, and the corrections it saw every earlier
  /// one there. The server's order of creation is not in the export, so date order stands in for it.
  /// The figures never read these fields; what matters is that every correction names every other
  /// one on its balance as seen or seeing, so no `correction.made_apart` issue appears for a history
  /// one device made in order.
  static void _fillCorrections(
    Map<String, Record> records,
    Map<String, Transfer> transfers,
    Map<String, AccountCurrency> currencies,
    List<String> corrections,
  ) {
    if (corrections.isEmpty) return;
    // Every posting as (date, id, account, currency, amount).
    final entries = <(String, String, String, String, int)>[
      for (final r in records.values)
        (r.date, r.id, r.posting.accountId, r.posting.currency, r.posting.amountMinor.toInt()),
      for (final t in transfers.values) ...[
        (t.date, t.id, t.source.accountId, t.source.currency, -t.source.amountMinor.toInt()),
        (
          t.date,
          t.id,
          t.destination.accountId,
          t.destination.currency,
          t.destination.amountMinor.toInt(),
        ),
      ],
    ]..sort((a, b) {
      final byDate = a.$1.compareTo(b.$1);
      return byDate != 0 ? byDate : a.$2.compareTo(b.$2);
    });
    final running = <(String, String), int>{
      for (final c in currencies.values) (c.accountId, c.currency): c.openingMinor.toInt(),
    };
    final seen = <(String, String), List<String>>{};
    final isCorrection = corrections.toSet();
    for (final (_, id, account, currency, amount) in entries) {
      final key = (account, currency);
      final before = running[key] ?? 0;
      if (isCorrection.contains(id)) {
        final record = records[id]!;
        final intent = CorrectionIntent();
        final target = addExact(before, amount);
        if (target != 0) intent.targetMinor = Int64(target);
        if (before != 0) intent.seenMinor = Int64(before);
        intent.seenCorrections.addAll(seen[key] ?? const []);
        record.correction = intent;
        (seen[key] ??= []).add(id);
      }
      running[key] = addExact(before, amount);
    }
  }

  // ── Checks ────────────────────────────────────────────────────────────────────────────────

  static String _id(String serverId, String collection) {
    try {
      return LocalIds.fromServerId(serverId);
    } on Refusal {
      throw MoveInRefusal(MoveInRule.malformedId, {'collection': collection});
    }
  }

  static void _unique(Iterable<String> held, String id, String collection) {
    if (held.contains(id)) {
      throw MoveInRefusal(MoveInRule.duplicateId, {'collection': collection, 'id': id});
    }
  }

  /// The Local id of [serverId], which must be one of [known] in [missing].
  static String _ref(
    String serverId,
    String collection,
    String id,
    String missing,
    Iterable<String> known,
  ) {
    final local = _id(serverId, collection);
    if (!known.contains(local)) {
      throw MoveInRefusal(MoveInRule.unknownReference, {
        'collection': collection,
        'id': id,
        'missing': missing,
        'missingId': local,
      });
    }
    return local;
  }

  static void _held(
    Map<(String, String), int> exported,
    String account,
    String currency,
    String collection,
    String id,
  ) {
    if (!exported.containsKey((account, currency))) {
      throw MoveInRefusal(MoveInRule.currencyNotHeld, {
        'collection': collection,
        'id': id,
        'account': account,
        'currency': currency,
      });
    }
  }

  static T _canonical<T>(T Function() derive, String collection, String id) {
    try {
      return derive();
    } on ArgumentError {
      throw MoveInRefusal(MoveInRule.invalidValue, {'collection': collection, 'id': id});
    }
  }
}
