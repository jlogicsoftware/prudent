import 'dart:math' as math;

import 'package:fixnum/fixnum.dart';
import 'package:meta/meta.dart' show internal;
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/budgets.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goal_allocations.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/settings.pb.dart' as wire;
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart' show ZenStorageError;

import '../../generated/prudent_local/v1/store.pb.dart';
import '../derived_ids.dart';
import '../integrity/checks/category_kind_check.dart';
import '../prudent_local_store.dart';
import '../wire_mapper.dart';
import 'envelopes.dart';
import 'ledger_errors.dart';
import 'ledger_view.dart';
import 'plan_ledger.dart';
import 'record_query.dart';

part 'ledger_budgets.dart';
part 'ledger_goals.dart';

/// Prudent Local's ledger (unit 5 of `docs/plans/PRUDENT-LOCAL-PLAN.md`, ADR-113): accounts,
/// categories, records, transfers, corrections and settings, with every rule the server enforces on
/// them (phase-0 §0.3 rows 5.1–5.53), over [PrudentLocalStore].
///
/// **The server is the specification.** Each operation is the server's resource method, check for
/// check and in the server's order, so the same request is refused with the same status for the same
/// first reason — the parity suite runs one scenario through both and compares every answer. It takes
/// the wire request messages the shared screens already build and answers the wire messages they
/// read, so the Local app's repository (unit 9) adapts it to `PrudentRepository` without a mapping of
/// its own.
///
/// **Where Local differs, on purpose** (ADR-102, ADR-113):
///
/// - a transfer is one immutable store record, listed as two legs;
/// - balances are derived on every read, and a figure never reads a value two devices disagree about
///   ([LedgerView]); a correction is refused while its account's figure is unsettled;
/// - the default account is one field of the settings record;
/// - several records are written as one only through jZen's `ZenStore.writeAll` (jZenDev/jZen#232):
///   an account with its currencies, an account deleted with its records — all or nothing;
/// - row-level security has no meaning: one person per store, whose encryption is the boundary
///   (phase-0 §0.3 X.1, X.2), so there is no "another user's account" to answer 404 for.
///
/// Every answer is a [ZenResult]: a rule's refusal is a [ZenError] shaped as the server's
/// ([LedgerErrors]); the store's own errors (a record in conflict, a storage failure) are returned as
/// they are.
final class Ledger {
  final PrudentLocalStore store;

  /// The wall clock, in epoch milliseconds, that labels what an audit entry records: when a reset,
  /// a revocation, a goal or an allocation was made (unit 6a). It decides no merge and no figure but
  /// the order of the histories, as `created_at` does on the server. Tests pass their own.
  final int Function() _clock;

  Ledger(this.store, {int Function()? clock}) : _clock = clock ?? _wallClock;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  // ── Accounts ────────────────────────────────────────────────────────────────────────────────

  /// Every account in name order (`TextRules.compareNames`, row 5.51), with what each one's
  /// balances leave out while two devices disagree (ADR-113).
  Future<ZenResult<Settled<wire.ListAccountsResponse>>> listAccounts() => _run(() async {
    final view = LedgerView.read(store);
    final accounts = view.accounts.values.toList()
      ..sort((a, b) => SearchRules.compareNames(a.name, a.id, b.name, b.id));
    return Settled(
      wire.ListAccountsResponse(accounts: [for (final a in accounts) _accountWire(view, a)]),
      _unsettled(view, accounts),
    );
  });

  /// One account, with what its balances leave out while two devices disagree (ADR-113).
  Future<ZenResult<Settled<wire.Account>>> getAccount(String id) => _run(() async {
    final view = LedgerView.read(store);
    final account = _requireAccount(view, id);
    return Settled(_accountWire(view, account), _unsettled(view, [account]));
  });

  /// The balances of account [id] and what they leave out while two devices disagree (ADR-113).
  Future<ZenResult<AccountBalances>> accountBalances(String id) => _run(() async {
    final view = LedgerView.read(store);
    return view.balancesOf(_requireAccount(view, id).id);
  });

  /// `AccountResource.create`: name, type, account number, then the currencies (rows 5.1–5.5, 5.9,
  /// 5.13), written with the account's currencies and the default setting as one.
  Future<ZenResult<Settled<wire.Account>>> createAccount(wire.CreateAccountRequest request) =>
      _run(() async {
        final view = LedgerView.read(store);
        final id = store.newId();
        final account = _account(
          view,
          id,
          name: request.name,
          type: request.type,
          isActive: request.isActive,
          includeInTotal: request.includeInTotal,
          includeInOverview: request.includeInOverview,
          eligibleForGoals: request.eligibleForGoals,
          accountNumber: request.accountNumber,
        );
        final openings = _openings(request.balances, inUse: const {}, planned: const {});
        final batch = StoreBatch(store)..putAccount(account);
        _putCurrencies(batch, view, id, openings);
        _applyDefault(batch, view, id, request.isDefault);
        await _write(store.writeAll(batch));
        return _settledAccount(id);
      });

  /// `AccountResource.replace`: a full replacement. A currency still used by a record, a transfer or
  /// a plan cannot be dropped (rows 5.6, 5.7); a dropped currency's opening record is deleted with
  /// the change, in one write.
  Future<ZenResult<Settled<wire.Account>>> updateAccount(
    String id,
    wire.UpdateAccountRequest request,
  ) => _run(() async {
    final view = LedgerView.read(store);
    final current = _requireAccount(view, id);
    final account = _account(
      view,
      current.id,
      name: request.name,
      type: request.type,
      isActive: request.isActive,
      includeInTotal: request.includeInTotal,
      includeInOverview: request.includeInOverview,
      eligibleForGoals: request.eligibleForGoals,
      accountNumber: request.accountNumber,
    );
    final openings = _openings(
      request.balances,
      inUse: _currenciesInUse(view, current.id),
      planned: {
        for (final p in view.planValues())
          if (p.posting.accountId == current.id) p.posting.currency,
      },
    );
    final batch = StoreBatch(store)..putAccount(account);
    _putCurrencies(batch, view, current.id, openings);
    for (final held in view.currenciesOf(current.id)) {
      if (!openings.containsKey(held.currency)) batch.deleteAccountCurrency(held.id);
    }
    _applyDefault(batch, view, current.id, request.isDefault);
    await _write(store.writeAll(batch));
    return _settledAccount(current.id);
  });

  /// `AccountResource.delete` (rows 5.10–5.12, 5.53). Without [deleteRecords] an account with any
  /// record, correction or transfer is refused (409). A plan refuses either way, checked before
  /// anything is deleted. With [deleteRecords], the account, its currencies, every record on it and
  /// every transfer touching it — both legs, which are one record here — and the default setting
  /// naming it go in **one** `writeAll` (ADR-081, jZenDev/jZen#232): all or nothing. An occurrence a
  /// deleted record confirmed reopens by itself, because completion is derived (ADR-102).
  ///
  /// A record touching the account that two devices disagree about is in the batch, so the store
  /// refuses the whole delete until it is settled — nothing is half-deleted around a conflict.
  Future<ZenResult<void>> deleteAccount(String id, {bool deleteRecords = false}) => _run(() async {
    final view = LedgerView.read(store);
    final account = _requireAccount(view, id);
    final records = <String>{
      for (final r in view.recordValues())
        if (r.posting.accountId == account.id) r.id,
    };
    final transfers = <String>{
      for (final t in view.transferValues())
        if (t.source.accountId == account.id || t.destination.accountId == account.id) t.id,
    };
    if (!deleteRecords && (records.isNotEmpty || transfers.isNotEmpty)) {
      throw const Refusal.conflict(
        '5.10',
        'This account still has records. Delete them first, or delete the account with them.',
      );
    }
    if (view.planValues().any((p) => p.posting.accountId == account.id)) {
      throw const Refusal.conflict(
        '5.11',
        'This account still has plans. Delete them or move them to another account first.',
      );
    }
    final batch = StoreBatch(store);
    for (final r in records) {
      batch.deleteRecord(r);
    }
    for (final t in transfers) {
      batch.deleteTransfer(t);
    }
    for (final c in view.currenciesOf(account.id)) {
      batch.deleteAccountCurrency(c.id);
    }
    for (final conflict in view.currencyConflicts.values) {
      // An account currency deleted on one device and edited on another is not listed by the
      // store; it still belongs to this account and goes (or blocks) with it.
      if (!view.accountCurrencies.containsKey(conflict.id) &&
          conflict.sides.any((s) => s.value?.accountId == account.id)) {
        batch.deleteAccountCurrency(conflict.id);
      }
    }
    _applyDefault(batch, view, account.id, false);
    batch.deleteAccount(account.id);
    await _write(store.writeAll(batch));
  });

  // ── Categories ──────────────────────────────────────────────────────────────────────────────

  /// Every category in name order (`TextRules.compareNames`, row 5.52).
  Future<ZenResult<wire.ListCategoriesResponse>> listCategories() => _run(() async {
    final view = LedgerView.read(store);
    final categories = view.categories.values.toList()
      ..sort((a, b) => SearchRules.compareNames(a.title, a.id, b.title, b.id));
    return wire.ListCategoriesResponse(
      categories: [for (final c in categories) WireMapper.categoryToWire(c)],
    );
  });

  Future<ZenResult<wire.Category>> getCategory(String id) => _run(() async {
    final view = LedgerView.read(store);
    return WireMapper.categoryToWire(_requireCategory(view, id));
  });

  /// `CategoryResource.create` (rows 5.38–5.40).
  Future<ZenResult<wire.Category>> createCategory(wire.CreateCategoryRequest request) =>
      _run(() async {
        final category = _category(
          store.newId(),
          title: request.title,
          iconKey: request.iconKey,
          description: request.description,
          colorArgb: request.colorArgb,
          kind: request.kind,
          archived: false,
        );
        return WireMapper.categoryToWire(await _write(store.putCategory(category)));
      });

  /// `CategoryResource.replace`: a full replacement; the archived state is kept.
  Future<ZenResult<wire.Category>> updateCategory(String id, wire.UpdateCategoryRequest request) =>
      _run(() async {
        final current = _requireCategory(LedgerView.read(store), id);
        final category = _category(
          current.id,
          title: request.title,
          iconKey: request.iconKey,
          description: request.description,
          colorArgb: request.colorArgb,
          kind: request.kind,
          archived: current.archived,
        );
        return WireMapper.categoryToWire(await _write(store.putCategory(category)));
      });

  /// `CategoryResource.archive`: refused (409) when it is already archived (row 5.41).
  Future<ZenResult<wire.Category>> archiveCategory(String id) => _run(() async {
    final current = _requireCategory(LedgerView.read(store), id);
    if (current.archived) {
      throw const Refusal.conflict('5.41', 'This category is already archived.');
    }
    final next = current.deepCopy()..archived = true;
    return WireMapper.categoryToWire(await _write(store.putCategory(next)));
  });

  /// `CategoryResource.restore`: refused (409) when it is not archived (row 5.41).
  Future<ZenResult<wire.Category>> restoreCategory(String id) => _run(() async {
    final current = _requireCategory(LedgerView.read(store), id);
    if (!current.archived) {
      throw const Refusal.conflict('5.41', 'This category is not archived.');
    }
    // Cleared, not set to false: the store compares serialised fields, and an explicit default is a
    // different value from an absent one (jZenDev/jZen#245).
    final next = current.deepCopy()..clearArchived();
    return WireMapper.categoryToWire(await _write(store.putCategory(next)));
  });

  /// `CategoryResource.delete`: refused (409) while a record, plan, budget or carry-over reset
  /// names it (row 5.42); archiving is the way out.
  Future<ZenResult<void>> deleteCategory(String id) => _run(() async {
    final view = LedgerView.read(store);
    final category = _requireCategory(view, id);
    if (view.recordValues().any((r) => r.hasCategoryId() && r.categoryId == category.id)) {
      throw const Refusal.conflict('5.42', 'This category still has records.');
    }
    if (view.planValues().any((p) => p.categoryId == category.id)) {
      throw const Refusal.conflict('5.42', 'This category still has plans.');
    }
    // Budgets and resets as every device holds them (unit 6a), as records are read above.
    if (view.budgetValues().any((b) => b.categoryId == category.id)) {
      throw const Refusal.conflict('5.42', 'This category still has budgets.');
    }
    if (view.resetValues().any((r) => r.categoryId == category.id)) {
      throw const Refusal.conflict('5.42', 'This category has carry-over reset history.');
    }
    await _write(store.deleteCategory(category.id));
  });

  /// "Start fresh on this device" (row 5.43, `NewUserSetup`): the five starter categories, with ids
  /// derived from a fixed key, written as one — and only into a store with no category at all, as
  /// the server seeds only a user with none. Two devices that both start fresh write the same five
  /// records. "Join" never calls this. The settings record is not written: an absent one reads as
  /// the default main currency, and writing it here would be a choice nobody made.
  Future<ZenResult<void>> startFresh() => _run(() async {
    if (readOrThrow(store.categories.list()).isNotEmpty) return;
    final batch = StoreBatch(store);
    for (final (key, title, icon, color) in _starters) {
      batch.putCategory(
        Category(
          id: DerivedIds.starterCategory(key),
          title: title,
          iconKey: icon,
          colorArgb: color,
        ),
      );
    }
    await _write(store.writeAll(batch));
  });

  /// `NewUserSetup.STARTERS`, in the server's order and words.
  static const _starters = [
    ('food', 'Food', 'food', 0xFF4CAF50),
    ('restaurant', 'Restaurant', 'restaurant', 0xFFFF9800),
    ('leisure', 'Leisure', 'leisure', 0xFF9C27B0),
    ('health', 'Health', 'medicine', 0xFFF44336),
    ('work', 'Work', 'work', 0xFF2196F3),
  ];

  // ── Records ─────────────────────────────────────────────────────────────────────────────────

  /// `RecordResource.list` (rows 5.46–5.50): each transfer is expanded into its two leg records
  /// first, then every filter applies to each row exactly as the server applies it, in the server's
  /// order `date desc, id`, and the search last.
  Future<ZenResult<wire.ListRecordsResponse>> listRecords([
    RecordQuery query = const RecordQuery(),
  ]) => _run(() async {
    final dateFrom = _optionalDate(query.dateFrom);
    final dateTo = _optionalDate(query.dateTo);
    final accountId = _optionalId(query.accountId, 'accountId');
    final categoryId = _optionalId(query.categoryId, 'categoryId');
    final type = RecordTypes.parse(query.type);
    if ((query.amountMin ?? 0) < 0 || (query.amountMax ?? 0) < 0) {
      throw const Refusal.invalid('5.48', 'An amount bound must not be negative.');
    }
    final view = LedgerView.read(store);
    final rows = <(CivilDate, wire.Record)>[
      for (final r in view.records.values)
        (_storedDate('records', r.id, r.date), _recordWire(view, r)),
      for (final t in view.transfers.values)
        for (final leg in [
          WireMapper.transferToWire(t).fromRecord,
          WireMapper.transferToWire(t).toRecord,
        ])
          (_storedDate('transfers', t.id, t.date), leg),
    ];
    bool keep((CivilDate, wire.Record) row) {
      final (date, r) = row;
      if (dateFrom != null && date.compareTo(dateFrom) < 0) return false;
      if (dateTo != null && date.compareTo(dateTo) > 0) return false;
      if (accountId != null && r.accountId != accountId) return false;
      if (categoryId != null && !(r.hasCategoryId() && r.categoryId == categoryId)) return false;
      final amount = r.amountMinor.toInt();
      final leg = r.hasTransferId();
      final matchesType = switch (type) {
        null => true,
        RecordType.expense => amount < 0 && !leg && !r.isCorrection,
        RecordType.income => amount > 0 && !leg && !r.isCorrection,
        RecordType.transfer => leg,
        RecordType.correction => r.isCorrection,
      };
      if (!matchesType) return false;
      if (query.amountMin != null || query.amountMax != null) {
        // Postgres' abs(bigint) fails on the one value with no absolute value; so does this,
        // rather than compare a wrapped negative.
        final magnitude = amount == minMinorUnits ? negateExact(amount) : amount.abs();
        if (query.amountMin != null && magnitude < query.amountMin!) return false;
        if (query.amountMax != null && magnitude > query.amountMax!) return false;
      }
      return true;
    }

    final kept = rows.where(keep).toList()
      ..sort((a, b) {
        final byDate = b.$1.compareTo(a.$1);
        return byDate != 0 ? byDate : a.$2.id.compareTo(b.$2.id);
      });
    final term = SearchRules.searchTerm(query.search);
    return wire.ListRecordsResponse(
      records: [
        for (final (_, r) in kept)
          if (term == null ||
              SearchRules.matchesAny(term, [
                r.title,
                r.hasPayee() ? r.payee : null,
                r.hasNote() ? r.note : null,
              ]))
            r,
      ],
    );
  });

  /// A record, or one leg of a transfer, by its id.
  Future<ZenResult<wire.Record>> getRecord(String id) => _run(() async {
    final view = LedgerView.read(store);
    if (_legOf(view, id) case final leg?) return leg;
    return _recordWire(view, _requireRecord(view, id));
  });

  /// `RecordWriter.apply` for a record a plan's confirmation creates (unit 6b, `PlanLedger`): the
  /// same checks in the same order as a record typed in by hand, so what a plan allowed can still be
  /// refused here if the world moved, and a confirmation cannot slip past them. A new record, so an
  /// archived category is refused (409).
  static Record recordForConfirmation(
    LedgerView view,
    String id, {
    required String title,
    required int amountMinor,
    required String date,
    required String categoryId,
    required String accountId,
    required String currency,
    required String? payee,
    required String? note,
  }) => _applyRecord(
    view,
    null,
    id,
    title: title,
    amountMinor: amountMinor,
    date: date,
    categoryId: categoryId,
    accountId: accountId,
    currency: currency,
    payee: payee,
    note: note,
  );

  /// `RecordResource.create` through `RecordWriter.apply` (rows 5.15–5.20, 5.23).
  Future<ZenResult<wire.Record>> createRecord(wire.CreateRecordRequest request) => _run(() async {
    final view = LedgerView.read(store);
    final record = _applyRecord(
      view,
      null,
      store.newId(),
      title: request.title,
      amountMinor: request.amountMinor.toInt(),
      date: request.date,
      categoryId: request.categoryId,
      accountId: request.accountId,
      currency: request.currency,
      payee: request.hasPayee() ? request.payee : null,
      note: request.hasNote() ? request.note : null,
    );
    return WireMapper.recordToWire(await _write(store.putRecord(record)));
  });

  /// `RecordResource.replace`: a transfer leg (row 5.21) and a correction (row 5.22) are refused
  /// (409); the rest is `RecordWriter.apply` against the record as it stands.
  ///
  /// A record moved to another account loses its statement key, as on the server (ADR-091). Here
  /// its id is derived from that key and its old account, so it becomes a new record with a new id,
  /// written as one with the old one's delete; the answer carries the new id.
  Future<ZenResult<wire.Record>> updateRecord(String id, wire.UpdateRecordRequest request) =>
      _run(() async {
        final view = LedgerView.read(store);
        final current = _requireEditableRecord(view, id);
        var record = _applyRecord(
          view,
          current,
          current.id,
          title: request.title,
          amountMinor: request.amountMinor.toInt(),
          date: request.date,
          categoryId: request.categoryId,
          accountId: request.accountId,
          currency: request.currency,
          payee: request.hasPayee() ? request.payee : null,
          note: request.hasNote() ? request.note : null,
        );
        if (current.hasImportKey() && record.posting.accountId != current.posting.accountId) {
          record = (record.deepCopy()
            ..id = store.newId()
            ..clearImportKey());
          final batch = StoreBatch(store)
            ..deleteRecord(current.id)
            ..putRecord(record);
          await _write(store.writeAll(batch));
          return WireMapper.recordToWire(record);
        }
        return _recordWire(view, await _write(store.putRecord(record)));
      });

  /// `RecordResource.delete`: a hard delete (row 5.24). A confirmed occurrence reopens by itself,
  /// because completion is derived from the confirming record existing (row 5.26).
  Future<ZenResult<void>> deleteRecord(String id) => _run(() async {
    final view = LedgerView.read(store);
    final record = _requireEditableRecord(view, id);
    final batch = StoreBatch(store)..deleteRecord(record.id);
    // The server keeps an occurrence row for good, so the occurrence a deleted confirmation reopens
    // is still listed when the plan's schedule no longer produces its date. Here only a stored state
    // keeps such a date (unit 6b), so it is written in the same all-or-nothing batch.
    if (record.hasPlanLink() && record.planLink.occurrenceDate.isNotEmpty) {
      final link = record.planLink;
      final plan = view.plans[link.planId];
      final date = CivilDate.tryParse(link.occurrenceDate);
      if (plan != null &&
          date != null &&
          !view.occurrenceStates.containsKey(link.occurrenceId) &&
          PlanLedger.ruleOf(plan).occurrencesBetween(date, date).isEmpty) {
        batch.putOccurrenceState(
          OccurrenceState(
            id: link.occurrenceId,
            planId: link.planId,
            occurrenceDate: link.occurrenceDate,
          ),
        );
      }
    }
    await _write(store.writeAll(batch));
  });

  // ── Transfers ───────────────────────────────────────────────────────────────────────────────

  /// `TransferResource.create` (rows 5.27–5.30, 5.32): one immutable store record, answered as the
  /// wire's two legs.
  Future<ZenResult<wire.Transfer>> createTransfer(wire.CreateTransferRequest request) =>
      _run(() async {
        if (request.fromAmountMinor <= 0) {
          throw const Refusal.invalid('5.27', 'A transfer needs a positive source amount.');
        }
        if (request.toAmountMinor <= 0) {
          throw const Refusal.invalid('5.27', 'A transfer needs a positive destination amount.');
        }
        final view = LedgerView.read(store);
        final from = _accountInBody(view, request.fromAccountId, rule: '5.28');
        final to = _accountInBody(view, request.toAccountId, rule: '5.28');
        if (from.id == to.id) {
          throw const Refusal.invalid('5.28', 'A transfer needs two different accounts.');
        }
        final fromCurrency = Currencies.parse(request.fromCurrency);
        _requireHeld(view, from, fromCurrency, rule: '5.29');
        final toCurrency = Currencies.parse(request.toCurrency);
        _requireHeld(view, to, toCurrency, rule: '5.29');
        final date = _date(request.date, rule: '5.32');
        final title = javaIsBlank(request.title) ? 'Transfer' : javaTrim(request.title);
        final transfer = Transfer(
          id: store.newId(),
          title: title,
          date: date.toString(),
          source: Posting(
            accountId: from.id,
            currency: fromCurrency,
            amountMinor: request.fromAmountMinor,
          ),
          destination: Posting(
            accountId: to.id,
            currency: toCurrency,
            amountMinor: request.toAmountMinor,
          ),
        );
        return WireMapper.transferToWire(await _write(store.addTransfer(transfer)));
      });

  /// `TransferResource.delete`: both legs go, because they are one record (row 5.31).
  Future<ZenResult<void>> deleteTransfer(String id) => _run(() async {
    if (!LocalIds.isValid(id)) throw const Refusal.notFound('5.31', 'No such transfer.');
    final view = LedgerView.read(store);
    if (!view.transfers.containsKey(id)) throw const Refusal.notFound('5.31', 'No such transfer.');
    await _write(store.deleteTransfer(id));
  });

  // ── Corrections ─────────────────────────────────────────────────────────────────────────────

  /// `CorrectionResource.create` (rows 5.33–5.37): the delta from the current derived balance,
  /// marked as a correction, with the balance it was asked for and the one it saw (D7) and the other
  /// corrections of this account and currency it saw (ADR-113).
  ///
  /// Refused (409) while that balance leaves out something two devices disagree about: a delta from
  /// a figure that is not settled would be money computed from a guess.
  Future<ZenResult<wire.Record>> createCorrection(wire.CreateCorrectionRequest request) =>
      _run(() async {
        final view = LedgerView.read(store);
        final account = _accountInBody(view, request.accountId, rule: '5.35');
        final currency = Currencies.parse(request.currency);
        _requireHeld(view, account, currency, rule: '5.35');
        final date = _date(request.date, rule: '5.33');
        if (view.unsettledIn(account.id, currency).isNotEmpty) {
          throw const Refusal.conflict(
            '5.33',
            'This balance has changes from two devices waiting to be settled; settle them first.',
          );
        }
        final current = view.balancesOf(account.id).minor[currency]!;
        final target = request.balanceMinor.toInt();
        final delta = subtractExact(target, current);
        if (delta == 0) {
          throw const Refusal.invalid('5.34', 'The account already balances there.');
        }
        final title = request.hasTitle() && !javaIsBlank(request.title)
            ? javaTrim(request.title)
            : 'Balance correction';
        final record = Record(
          id: store.newId(),
          title: title,
          posting: Posting(accountId: account.id, currency: currency, amountMinor: Int64(delta)),
          date: date.toString(),
          correction: CorrectionIntent(
            targetMinor: Int64(target),
            seenMinor: Int64(current),
            seenCorrections: [
              for (final r in view.records.values)
                if (r.hasCorrection() &&
                    r.posting.accountId == account.id &&
                    r.posting.currency == currency)
                  r.id,
            ]..sort(),
          ),
        );
        // Presence-exact (jZenDev/jZen#245): a zero target or seen balance is left unset.
        if (target == 0) record.correction.clearTargetMinor();
        if (current == 0) record.correction.clearSeenMinor();
        if (TextRules.optionalTrimmed(request.hasNote() ? request.note : null) case final note?) {
          record.note = note;
        }
        return WireMapper.recordToWire(await _write(store.putRecord(record)));
      });

  /// `CorrectionResource.delete`: 404 unless [id] is a correction.
  Future<ZenResult<void>> deleteCorrection(String id) => _run(() async {
    if (!LocalIds.isValid(id)) throw const Refusal.notFound('5.37', 'No such correction.');
    final record = LedgerView.read(store).records[id];
    if (record == null || !record.hasCorrection()) {
      throw const Refusal.notFound('5.37', 'No such correction.');
    }
    await _write(store.deleteRecord(id));
  });

  // ── Settings ────────────────────────────────────────────────────────────────────────────────

  /// The default main currency (`SettingsEntity.DEFAULT_MAIN_CURRENCY`).
  static const defaultMainCurrency = 'PLN';

  /// `SettingsResource.get`: an absent settings record reads as the default (row 5.44).
  Future<ZenResult<wire.Settings>> getSettings() => _run(() async {
    final settings = LedgerView.read(store).settings;
    return wire.Settings(
      mainCurrency: settings != null && settings.hasMainCurrency()
          ? settings.mainCurrency
          : defaultMainCurrency,
    );
  });

  /// `SettingsResource.replace`: blank resets to the default; otherwise an ISO-4217 code, never
  /// checked against the accounts (rows 5.44, 5.45). The default account is kept.
  Future<ZenResult<wire.Settings>> updateSettings(wire.UpdateSettingsRequest request) =>
      _run(() async {
        final requested = request.mainCurrency;
        final main = javaIsBlank(requested) ? defaultMainCurrency : Currencies.parse(requested);
        final current = LedgerView.read(store).settings;
        final next = (current?.deepCopy() ?? Settings(id: DerivedIds.settings))
          ..mainCurrency = main;
        final written = await _write(store.putSettings(next));
        return wire.Settings(mainCurrency: written.mainCurrency);
      });

  // ── Account rules ───────────────────────────────────────────────────────────────────────────

  /// `applyScalars` then `applyAccountNumber`: the store record, every default left unset.
  Account _account(
    LedgerView view,
    String id, {
    required String name,
    required wire.AccountType type,
    required bool isActive,
    required bool includeInTotal,
    required bool includeInOverview,
    required bool eligibleForGoals,
    required String accountNumber,
  }) {
    final trimmed = TextRules.requiredTrimmed(name, rule: '5.1');
    final kind = type == wire.AccountType.ACCOUNT_TYPE_UNSPECIFIED
        ? null
        : AccountKind.valueOf(type.value);
    if (kind == null) {
      throw const Refusal.invalid('5.2', 'An account needs a type.');
    }
    final number = AccountNumbers.normalize(accountNumber);
    if (number != null &&
        view.accounts.values.any((a) => a.id != id && a.accountNumber == number)) {
      throw const Refusal.conflict(
        '5.9',
        'Another of your accounts already has this account number.',
      );
    }
    final account = Account(id: id, kind: kind);
    if (trimmed.isNotEmpty) account.name = trimmed;
    if (isActive) account.active = true;
    if (includeInTotal) account.includeInTotal = true;
    if (includeInOverview) account.includeInOverview = true;
    if (eligibleForGoals) account.eligibleForGoals = true;
    if (number != null) account.accountNumber = number;
    return account;
  }

  /// `applyBalances`: the currencies in their declared order with their opening amounts (rows
  /// 5.3–5.7). [inUse] and [planned] are the currencies that must stay.
  static Map<String, int> _openings(
    List<wire.CurrencyBalance> requested, {
    required Set<String> inUse,
    required Set<String> planned,
  }) {
    if (requested.isEmpty) {
      throw const Refusal.invalid('5.3', 'An account must hold at least one currency.');
    }
    final openings = <String, int>{};
    for (final balance in requested) {
      final currency = Currencies.parse(balance.currency);
      if (openings.containsKey(currency)) {
        throw const Refusal.invalid('5.4', 'A currency appears more than once in this account.');
      }
      openings[currency] = balance.amountMinor.toInt();
    }
    if (inUse.any((c) => !openings.containsKey(c))) {
      throw const Refusal.conflict(
        '5.6',
        'A currency this account still has records in is dropped.',
      );
    }
    if (planned.any((c) => !openings.containsKey(c))) {
      throw const Refusal.conflict('5.7', 'A currency this account still has plans in is dropped.');
    }
    return openings;
  }

  /// The currencies some record or transfer of [accountId] is in, on any device's side.
  static Set<String> _currenciesInUse(LedgerView view, String accountId) => {
    for (final r in view.recordValues())
      if (r.posting.accountId == accountId) r.posting.currency,
    for (final t in view.transferValues()) ...[
      if (t.source.accountId == accountId) t.source.currency,
      if (t.destination.accountId == accountId) t.destination.currency,
    ],
  };

  /// One account-currency record per currency, its position the declared order (row 5.5).
  void _putCurrencies(
    StoreBatch batch,
    LedgerView view,
    String accountId,
    Map<String, int> openings,
  ) {
    var position = 0;
    for (final MapEntry(key: currency, value: opening) in openings.entries) {
      final record = AccountCurrency(
        id: DerivedIds.accountCurrency(accountId, currency),
        accountId: accountId,
        currency: currency,
      );
      if (opening != 0) record.openingMinor = Int64(opening);
      if (position != 0) record.position = position;
      batch.putAccountCurrency(record);
      position++;
    }
  }

  /// `enforceSingleDefault`, as one field (row 5.8): a default account names itself in the settings;
  /// clearing the flag of the account that is the default clears the setting. Nothing is written
  /// when nothing changes.
  void _applyDefault(StoreBatch batch, LedgerView view, String accountId, bool isDefault) {
    final current = view.settings;
    final isNow =
        current != null && current.hasDefaultAccountId() && current.defaultAccountId == accountId;
    if (isDefault == isNow) return;
    final next = current?.deepCopy() ?? Settings(id: DerivedIds.settings);
    if (isDefault) {
      next.defaultAccountId = accountId;
    } else {
      next.clearDefaultAccountId();
    }
    batch.putSettings(next);
  }

  /// The account [id] as written, read back with its figures and what they leave out.
  Settled<wire.Account> _settledAccount(String id) {
    final view = LedgerView.read(store);
    final account = readOrThrow(store.accounts.get(id));
    return Settled(_accountWire(view, account), _unsettled(view, [account]));
  }

  static Map<String, List<String>> _unsettled(LedgerView view, Iterable<Account> accounts) => {
    for (final a in accounts)
      if (view.balancesOf(a.id).unsettled case final ids when ids.isNotEmpty) a.id: ids,
  };

  wire.Account _accountWire(LedgerView view, Account account) => WireMapper.accountToWire(
    account,
    currencies: view.currenciesOf(account.id),
    settings: view.settings,
    balanceMinor: view.balancesOf(account.id).minor,
  );

  /// `AccountResource.require`: 404 for an id that is not one (`Ids.parse`) or names nothing.
  static Account _requireAccount(LedgerView view, String id) {
    final account = LocalIds.isValid(id) ? view.accounts[id] : null;
    if (account == null) throw const Refusal.notFound('5.1', 'No such account.');
    return account;
  }

  /// An account named in a request body (`Ids.parseInBody` + `findOwned`): 400, not 404, for a
  /// blank, malformed or unknown id.
  static Account _accountInBody(LedgerView view, String id, {required String rule}) {
    if (javaIsBlank(id)) throw Refusal.invalid(rule, 'A record needs an account.');
    final account = LocalIds.isValid(id) ? view.accounts[id] : null;
    if (account == null) throw Refusal.invalid(rule, 'No such account.');
    return account;
  }

  static void _requireHeld(
    LedgerView view,
    Account account,
    String currency, {
    required String rule,
  }) {
    if (!view.holds(account.id, currency)) {
      throw Refusal.invalid(rule, 'The account does not hold this currency.');
    }
  }

  // ── Category rules ──────────────────────────────────────────────────────────────────────────

  /// `CategoryResource.apply`: title, icon, kind (rows 5.38–5.40). Every default is left unset.
  static Category _category(
    String id, {
    required String title,
    required String iconKey,
    required String description,
    required int colorArgb,
    required wire.CategoryKind kind,
    required bool archived,
  }) {
    final trimmed = TextRules.requiredTrimmed(title, rule: '5.38');
    if (!_iconKeys.contains(iconKey)) {
      throw const Refusal.invalid('5.39', 'Unknown icon key.');
    }
    final direction = CategoryDirection.valueOf(kind.value);
    if (direction == null) throw const Refusal.invalid('5.40', 'Unknown category kind.');
    final category = Category(id: id, iconKey: iconKey);
    if (trimmed.isNotEmpty) category.title = trimmed;
    if (description.isNotEmpty) category.description = description;
    if (colorArgb != 0) category.colorArgb = colorArgb;
    if (archived) category.archived = true;
    if (direction != CategoryDirection.CATEGORY_DIRECTION_UNSPECIFIED) category.kind = direction;
    return category;
  }

  /// `IconKeys.PERMITTED`.
  static const _iconKeys = {'work', 'leisure', 'food', 'restaurant', 'medicine'};

  static Category _requireCategory(LedgerView view, String id) {
    final category = LocalIds.isValid(id) ? view.categories[id] : null;
    if (category == null) throw const Refusal.notFound('5.38', 'No such category.');
    return category;
  }

  // ── Record rules ────────────────────────────────────────────────────────────────────────────

  /// The record an import commit writes for one statement row (unit 8b, ADR-114): exactly what
  /// `LedgerImportCommitter.write` asks of `RecordWriter.apply` — the same checks, in the same
  /// order, as a record typed by hand — plus the row's [key], which also derives the record's id
  /// (`DerivedIds.imported`), so two devices that commit one statement write one record per row.
  /// Throws the [Refusal] the ledger refuses the row with; the commit names the row, never the text.
  @internal
  static Record importedRecord(
    LedgerView view, {
    required String accountId,
    required String currency,
    required RowKey key,
    required String title,
    required int amountMinor,
    required String date,
    required String categoryId,
    required String? payee,
    required String? note,
  }) {
    final record = _applyRecord(
      view,
      null,
      DerivedIds.imported(accountId, key.fingerprint, key.occurrence),
      title: title,
      amountMinor: amountMinor,
      date: date,
      categoryId: categoryId,
      accountId: accountId,
      currency: currency,
      payee: payee,
      note: note,
    );
    return record..importKey = ImportKey(fingerprint: key.fingerprint, occurrence: key.occurrence);
  }

  /// `RecordWriter.apply`, check for check and in its order: title, amount, account, category, the
  /// category's archived state and kind (when the category or the direction changes), currency, the
  /// account holding it, date. [current] is the record being replaced, or null for a new one; its
  /// plan link and import key are kept (they are immutable).
  static Record _applyRecord(
    LedgerView view,
    Record? current,
    String id, {
    required String title,
    required int amountMinor,
    required String date,
    required String categoryId,
    required String accountId,
    required String currency,
    required String? payee,
    required String? note,
  }) {
    final trimmed = TextRules.requiredTrimmed(title, rule: '5.15');
    if (amountMinor == 0) {
      throw const Refusal.invalid('5.16', 'A record needs a nonzero amount.');
    }
    final account = _accountInBody(view, accountId, rule: '5.17');
    if (javaIsBlank(categoryId)) throw const Refusal.invalid('5.17', 'A record needs a category.');
    final category = LocalIds.isValid(categoryId) ? view.categories[categoryId] : null;
    if (category == null) throw const Refusal.invalid('5.17', 'No such category.');
    final sameCategory =
        current != null && current.hasCategoryId() && current.categoryId == category.id;
    if (!sameCategory && category.archived) {
      throw const Refusal.conflict('5.20', 'This category is archived.');
    }
    final sameDirection =
        current != null && signum(current.posting.amountMinor.toInt()) == signum(amountMinor);
    if ((!sameCategory || !sameDirection) &&
        !CategoryKindCheck.canFile(category.kind, amountMinor)) {
      throw const Refusal.invalid('5.19', 'This category is for the other direction.');
    }
    final normalized = Currencies.parse(currency);
    _requireHeld(view, account, normalized, rule: '5.18');
    final parsed = _date(date, rule: '5.23');
    final record = Record(
      id: id,
      posting: Posting(
        accountId: account.id,
        currency: normalized,
        amountMinor: Int64(amountMinor),
      ),
      date: parsed.toString(),
      categoryId: category.id,
    );
    if (trimmed.isNotEmpty) record.title = trimmed;
    if (TextRules.optionalTrimmed(payee) case final value?) record.payee = value;
    if (TextRules.optionalTrimmed(note) case final value?) record.note = value;
    if (current != null && current.hasPlanLink()) record.planLink = current.planLink;
    if (current != null && current.hasImportKey()) record.importKey = current.importKey;
    return record;
  }

  /// The record [id] that `RecordResource.replace` and `.delete` may touch: 404 when there is none,
  /// 409 for a transfer leg (row 5.21) or a correction (row 5.22).
  static Record _requireEditableRecord(LedgerView view, String id) {
    if (_legOf(view, id) != null) {
      throw const Refusal.conflict(
        '5.21',
        'This record is part of a transfer; delete the transfer.',
      );
    }
    final record = _requireRecord(view, id);
    if (record.hasCorrection()) {
      throw const Refusal.conflict(
        '5.22',
        'This record is a balance correction; delete it instead.',
      );
    }
    return record;
  }

  static Record _requireRecord(LedgerView view, String id) {
    final record = LocalIds.isValid(id) ? view.records[id] : null;
    if (record == null) throw const Refusal.notFound('5.15', 'No such record.');
    return record;
  }

  /// A record as the wire carries it. A record whose plan was deleted reads as **detached**, as the
  /// server's `detachFromPlan` leaves it (row 6.34): nothing is written when a plan is deleted, so
  /// the link stays in the store and the answer is what shows it gone (ADR-102, unit 6b).
  static wire.Record _recordWire(LedgerView view, Record record) {
    final out = WireMapper.recordToWire(record);
    if (record.hasPlanLink() && !view.planExists(record.planLink.planId)) {
      out
        ..clearPlanId()
        ..clearPlanOccurrenceId();
    }
    return out;
  }

  /// The leg [id] of some transfer, or null.
  static wire.Record? _legOf(LedgerView view, String id) {
    if (!LocalIds.isValid(id)) return null;
    for (final t in view.transfers.values) {
      if (DerivedIds.transferLeg(t.id, source: true) == id) {
        return WireMapper.transferToWire(t).fromRecord;
      }
      if (DerivedIds.transferLeg(t.id, source: false) == id) {
        return WireMapper.transferToWire(t).toRecord;
      }
    }
    return null;
  }

  // ── Shared ──────────────────────────────────────────────────────────────────────────────────

  /// A date the person entered (`RecordWriter.parseDate` and its copies): strict `YYYY-MM-DD`, else
  /// a 400 under [rule].
  static CivilDate _date(String text, {required String rule}) {
    final date = CivilDate.tryParse(text);
    if (date == null) throw Refusal.invalid(rule, 'Not an ISO-8601 date. Expected YYYY-MM-DD.');
    return date;
  }

  /// The date a stored record holds. Every write path parses it, so one that does not parse was not
  /// written by this ledger: that is a storage failure, answered as the store's kind of error and
  /// naming the record, never a 400 that tells every caller they asked for something wrong.
  static CivilDate _storedDate(String collection, String id, String date) =>
      CivilDate.tryParse(date) ??
      (throw LedgerReadFailure(ZenStorageError('$collection/$id holds a date that is not one.')));

  /// A list filter's date: blank is no filter, anything else must parse (row 5.46).
  static CivilDate? _optionalDate(String? text) {
    if (text == null || javaIsBlank(text)) return null;
    return _date(text, rule: '5.46');
  }

  /// A list filter's id: blank is no filter, a malformed id is a 400 (row 5.46), and a well-formed
  /// one that names nothing simply matches no row.
  static String? _optionalId(String? text, String name) {
    if (text == null || javaIsBlank(text)) return null;
    if (!LocalIds.isValid(text)) throw Refusal.invalid('5.46', 'Not a valid $name.');
    return text;
  }

  /// The value of a store write, or a [LedgerReadFailure] with the store's own error.
  static Future<T> _write<T>(Future<ZenResult<T>> write) async => readOrThrow(await write);

  /// Runs one operation: a rule's [Refusal] becomes the server-shaped error, the store's errors are
  /// returned as they are, and a figure that leaves the 64-bit range is an error, never a value.
  static Future<ZenResult<T>> _run<T>(Future<T> Function() body) async {
    try {
      return ZenResult.ok(await body());
    } on Refusal catch (refusal) {
      return ZenResult.err(LedgerErrors.of(refusal));
    } on LedgerReadFailure catch (failure) {
      return ZenResult.err(failure.error);
    } on MoneyOverflow catch (overflow) {
      return ZenResult.err(ZenUnknownError('A figure left the range of minor units ($overflow).'));
    }
  }
}
