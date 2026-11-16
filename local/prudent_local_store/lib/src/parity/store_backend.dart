import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_core/parity.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/settings.pb.dart' as wire;
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import '../../generated/prudent_local/v1/store.pb.dart';
import '../derived_ids.dart';
import '../ledger/ledger.dart';
import '../ledger/ledger_errors.dart';
import '../ledger/record_query.dart';
import '../prudent_local_store.dart';

/// The local side of the parity suite (ADR-107, ADR-113): every parity operation answered by the
/// [Ledger] over a real encrypted [ZenStore] in a temporary directory, one fresh store per scenario.
///
/// It replaced unit 3's in-memory `LocalRulesBackend` under the same operation names, as ADR-107
/// planned: the scenarios and the engine did not change. Answers are wire messages written as proto3
/// JSON and read by the same [ParityReaders] the server's answers are, so the two sides observe
/// alike by construction.
///
/// **`budget.set` and `reset.create` are stand-ins until unit 6a** ports the budget and reset rules:
/// they enforce exactly what unit 3's backend did (the category exists, month, currency, a positive
/// amount; the note; one live reset per slot) and write the store record. Any rule of the server's
/// they lack shows as a difference, never as a pass, which is why every setup step of a scenario
/// states its outcome.
final class StoreBackend extends ParityBackend {
  @override
  String get name => 'local';

  Directory? _directory;
  ZenStore? _zen;
  late PrudentLocalStore _store;
  late Ledger _ledger;

  @override
  late final Map<String, ParityOp> ops = {
    'account.create': _guarded(_createAccount),
    'account.balances': _guarded(_balances),
    'account.get': _guarded(_getAccount),
    'account.update': _guarded(_updateAccount),
    'account.delete': _guarded(_deleteAccount),
    'account.list': _guarded(_listAccounts),
    'category.create': _guarded(_createCategory),
    'category.update': _guarded(_updateCategory),
    'category.archive': _guarded(_archiveCategory),
    'category.restore': _guarded(_restoreCategory),
    'category.delete': _guarded(_deleteCategory),
    'category.list': _guarded(_listCategories),
    'record.create': _guarded(_createRecord),
    'record.update': _guarded(_updateRecord),
    'record.delete': _guarded(_deleteRecord),
    'record.list': _guarded(_listRecords),
    'transfer.create': _guarded(_createTransfer),
    'transfer.delete': _guarded(_deleteTransfer),
    'correction.create': _guarded(_createCorrection),
    'correction.delete': _guarded(_deleteCorrection),
    'settings.update': _guarded(_updateSettings),
    'budget.set': _guarded(_setBudget),
    'reset.create': _guarded(_createReset),
  };

  @override
  Future<void> open(String scenarioName) async {
    final directory = await Directory.systemTemp.createTemp('prudent_parity_$scenarioName');
    _directory = directory;
    final zen = _ok(await ZenStore.open(directory, deviceName: 'parity', key: List.filled(32, 7)));
    _zen = zen;
    _store = PrudentLocalStore(zen);
    _ledger = Ledger(_store);
  }

  @override
  Future<void> close() async {
    await _zen?.close();
    await _directory?.delete(recursive: true);
    _zen = null;
    _directory = null;
  }

  // ── Accounts ────────────────────────────────────────────────────────────────────────────────

  Future<StepResult> _createAccount(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.CreateAccountRequest()..mergeFromProto3Json(input);
    final account = _ok(await _ledger.createAccount(request));
    final json = _json(account);
    return StepResult(
      ParityObservation.accepted({
        'name': ParityReaders.string(json, 'name'),
        'balances': _balanceMap(json),
        'accountNumber': ParityReaders.string(json, 'accountNumber'),
      }),
      createdId: account.id,
    );
  }

  Future<StepResult> _balances(Map<String, Object?> input, ParityBindings bindings) async {
    final account = _ok(await _ledger.getAccount(bindings.resolve(input['account'])));
    return StepResult(ParityObservation.accepted({'balances': _balanceMap(_json(account))}));
  }

  Future<StepResult> _getAccount(Map<String, Object?> input, ParityBindings bindings) async {
    final account = _ok(await _ledger.getAccount(bindings.idOrLiteral(input['account'])!));
    return StepResult(ParityObservation.accepted(ParityReaders.account(_json(account))));
  }

  Future<StepResult> _updateAccount(Map<String, Object?> input, ParityBindings bindings) async {
    final body = Map<String, Object?>.of(input)..remove('account');
    final request = wire.UpdateAccountRequest()..mergeFromProto3Json(body);
    final account = _ok(
      await _ledger.updateAccount(bindings.idOrLiteral(input['account'])!, request),
    );
    return StepResult(ParityObservation.accepted(ParityReaders.account(_json(account))));
  }

  Future<StepResult> _deleteAccount(Map<String, Object?> input, ParityBindings bindings) async {
    _ok(
      await _ledger.deleteAccount(
        bindings.idOrLiteral(input['account'])!,
        deleteRecords: (input['deleteRecords'] as bool?) ?? false,
      ),
    );
    return StepResult(ParityObservation.accepted());
  }

  Future<StepResult> _listAccounts(Map<String, Object?> input, ParityBindings bindings) async {
    final list = _ok(await _ledger.listAccounts());
    final rows = (_json(list)['accounts'] as List<Object?>?) ?? const [];
    return StepResult(
      ParityObservation.accepted({'accounts': ParityReaders.boundNames(rows, bindings)}),
    );
  }

  // ── Categories ──────────────────────────────────────────────────────────────────────────────

  Future<StepResult> _createCategory(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.CreateCategoryRequest()..mergeFromProto3Json(input);
    final category = _ok(await _ledger.createCategory(request));
    return StepResult(ParityObservation.accepted(), createdId: category.id);
  }

  Future<StepResult> _updateCategory(Map<String, Object?> input, ParityBindings bindings) async {
    final body = Map<String, Object?>.of(input)..remove('category');
    final request = wire.UpdateCategoryRequest()..mergeFromProto3Json(body);
    final category = _ok(
      await _ledger.updateCategory(bindings.idOrLiteral(input['category'])!, request),
    );
    return StepResult(ParityObservation.accepted(ParityReaders.category(_json(category))));
  }

  Future<StepResult> _archiveCategory(Map<String, Object?> input, ParityBindings bindings) async {
    final category = _ok(await _ledger.archiveCategory(bindings.idOrLiteral(input['category'])!));
    return StepResult(ParityObservation.accepted(ParityReaders.category(_json(category))));
  }

  Future<StepResult> _restoreCategory(Map<String, Object?> input, ParityBindings bindings) async {
    final category = _ok(await _ledger.restoreCategory(bindings.idOrLiteral(input['category'])!));
    return StepResult(ParityObservation.accepted(ParityReaders.category(_json(category))));
  }

  Future<StepResult> _deleteCategory(Map<String, Object?> input, ParityBindings bindings) async {
    _ok(await _ledger.deleteCategory(bindings.idOrLiteral(input['category'])!));
    return StepResult(ParityObservation.accepted());
  }

  Future<StepResult> _listCategories(Map<String, Object?> input, ParityBindings bindings) async {
    final list = _ok(await _ledger.listCategories());
    final rows = (_json(list)['categories'] as List<Object?>?) ?? const [];
    return StepResult(
      ParityObservation.accepted({'categories': ParityReaders.boundNames(rows, bindings)}),
    );
  }

  // ── Records ─────────────────────────────────────────────────────────────────────────────────

  /// The record request every record op builds from a scenario's input: `account` and `category`
  /// are references, the rest is the wire's JSON.
  static Map<String, Object?> recordBody(Map<String, Object?> input, ParityBindings bindings) => {
    'title': input['title'],
    'amountMinor': input['amountMinor'],
    'date': input['date'],
    'categoryId': bindings.idOrLiteral(input['category']),
    'accountId': bindings.idOrLiteral(input['account']),
    'currency': input['currency'],
    if (input.containsKey('payee')) 'payee': input['payee'],
    if (input.containsKey('note')) 'note': input['note'],
  };

  /// What a record step observes (unit 3's shape, kept).
  static Map<String, Object?> recordObservation(Map<String, Object?> json) => {
    'title': ParityReaders.string(json, 'title'),
    'amountMinor': ParityReaders.int64(json, 'amountMinor'),
    'currency': ParityReaders.string(json, 'currency'),
    'date': ParityReaders.string(json, 'date'),
    'payee': json['payee'] as String?,
    'note': json['note'] as String?,
  };

  Future<StepResult> _createRecord(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.CreateRecordRequest()
      ..mergeFromProto3Json(_present(recordBody(input, bindings)));
    final record = _ok(await _ledger.createRecord(request));
    return StepResult(
      ParityObservation.accepted(recordObservation(_json(record))),
      createdId: record.id,
    );
  }

  Future<StepResult> _updateRecord(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.UpdateRecordRequest()
      ..mergeFromProto3Json(_present(recordBody(input, bindings)));
    final record = _ok(await _ledger.updateRecord(bindings.idOrLiteral(input['record'])!, request));
    return StepResult(ParityObservation.accepted(recordObservation(_json(record))));
  }

  Future<StepResult> _deleteRecord(Map<String, Object?> input, ParityBindings bindings) async {
    _ok(await _ledger.deleteRecord(bindings.idOrLiteral(input['record'])!));
    return StepResult(ParityObservation.accepted());
  }

  Future<StepResult> _listRecords(Map<String, Object?> input, ParityBindings bindings) async {
    int? bound(String key) => switch (input[key]) {
      null => null,
      final String text => int.parse(text),
      final other => throw FormatException('"$key" is a string of minor units, not $other.'),
    };
    final list = _ok(
      await _ledger.listRecords(
        RecordQuery(
          dateFrom: input['dateFrom'] as String?,
          dateTo: input['dateTo'] as String?,
          accountId: bindings.idOrLiteral(input['account']),
          categoryId: bindings.idOrLiteral(input['category']),
          type: input['type'] as String?,
          amountMin: bound('amountMin'),
          amountMax: bound('amountMax'),
          search: input['search'] as String?,
        ),
      ),
    );
    final rows = (_json(list)['records'] as List<Object?>?) ?? const [];
    return StepResult(ParityObservation.accepted(ParityReaders.recordList(rows, bindings)));
  }

  // ── Transfers and corrections ───────────────────────────────────────────────────────────────

  /// The transfer request a scenario's input names: accounts are references.
  static Map<String, Object?> transferBody(Map<String, Object?> input, ParityBindings bindings) => {
    'title': input['title'],
    'fromAmountMinor': input['fromAmountMinor'],
    'fromCurrency': input['fromCurrency'],
    'date': input['date'],
    'fromAccountId': bindings.idOrLiteral(input['fromAccount']),
    'toAccountId': bindings.idOrLiteral(input['toAccount']),
    'toAmountMinor': input['toAmountMinor'],
    'toCurrency': input['toCurrency'],
  };

  Future<StepResult> _createTransfer(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.CreateTransferRequest()
      ..mergeFromProto3Json(_present(transferBody(input, bindings)));
    final transfer = _ok(await _ledger.createTransfer(request));
    return StepResult(
      ParityObservation.accepted(ParityReaders.transfer(_json(transfer), bindings)),
      createdId: transfer.id,
    );
  }

  Future<StepResult> _deleteTransfer(Map<String, Object?> input, ParityBindings bindings) async {
    _ok(await _ledger.deleteTransfer(bindings.idOrLiteral(input['transfer'])!));
    return StepResult(ParityObservation.accepted());
  }

  /// The correction request a scenario's input names: the account is a reference.
  static Map<String, Object?> correctionBody(Map<String, Object?> input, ParityBindings bindings) =>
      {
        'accountId': bindings.idOrLiteral(input['account']),
        'currency': input['currency'],
        'balanceMinor': input['balanceMinor'],
        'date': input['date'],
        if (input.containsKey('title')) 'title': input['title'],
        if (input.containsKey('note')) 'note': input['note'],
      };

  Future<StepResult> _createCorrection(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.CreateCorrectionRequest()
      ..mergeFromProto3Json(_present(correctionBody(input, bindings)));
    final record = _ok(await _ledger.createCorrection(request));
    return StepResult(
      ParityObservation.accepted(ParityReaders.record(_json(record), bindings)),
      createdId: record.id,
    );
  }

  Future<StepResult> _deleteCorrection(Map<String, Object?> input, ParityBindings bindings) async {
    _ok(await _ledger.deleteCorrection(bindings.idOrLiteral(input['correction'])!));
    return StepResult(ParityObservation.accepted());
  }

  // ── Settings ────────────────────────────────────────────────────────────────────────────────

  Future<StepResult> _updateSettings(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.UpdateSettingsRequest()..mergeFromProto3Json(input);
    _ok(await _ledger.updateSettings(request));
    final settings = _ok(await _ledger.getSettings());
    return StepResult(
      ParityObservation.accepted({
        'mainCurrency': ParityReaders.string(_json(settings), 'mainCurrency'),
      }),
    );
  }

  // ── Budgets and resets: unit 3's stand-ins until unit 6a ────────────────────────────────────

  /// The order of `BudgetResource.set`: category, month, currency, then a positive amount.
  Future<StepResult> _setBudget(Map<String, Object?> input, ParityBindings bindings) async {
    final category = _category(input, bindings);
    final month = CivilMonth.parse(input['month'] as String?);
    final currency = Currencies.parse(input['currency'] as String?);
    final amount = int.parse(input['amountMinor']! as String);
    if (amount <= 0) {
      throw const Refusal.invalid('6', 'A budget needs a positive amount.');
    }
    final budget = Budget(
      id: DerivedIds.budget(category, month.toString(), currency),
      categoryId: category,
      month: month.toString(),
      currency: currency,
      amountMinor: Int64(amount),
    );
    _ok(await _store.putBudget(budget));
    return StepResult(
      ParityObservation.accepted({
        'month': month.toString(),
        'currency': currency,
        'amountMinor': ParityObservation.figure(amount),
      }),
    );
  }

  /// The order of `BudgetCarryOverResetResource.reset`: category, month, currency, note, then one
  /// live reset per slot. The discarded carry-over is unit 6a's calculation.
  Future<StepResult> _createReset(Map<String, Object?> input, ParityBindings bindings) async {
    final category = _category(input, bindings);
    final month = CivilMonth.parse(input['month'] as String?);
    final currency = Currencies.parse(input['currency'] as String?);
    final note = TextRules.strippedNote((input['note'] as String?) ?? '');
    final live = _ok(_store.budgetResets.list()).any(
      (r) =>
          !r.hasRevocation() &&
          r.categoryId == category &&
          r.month == month.toString() &&
          r.currency == currency,
    );
    if (live) throw const Refusal.conflict('6', 'This slot already has a live reset.');
    final reset = BudgetCarryOverReset(
      id: _store.newId(),
      categoryId: category,
      month: month.toString(),
      currency: currency,
      createdBy: _store.deviceId,
      createdAtMs: Int64(1),
    );
    if (note.isNotEmpty) reset.note = note;
    _ok(await _store.addBudgetReset(reset));
    return StepResult(
      ParityObservation.accepted({'month': month.toString(), 'currency': currency, 'note': note}),
      createdId: reset.id,
    );
  }

  String _category(Map<String, Object?> input, ParityBindings bindings) {
    final id = bindings.resolve(input['category']);
    if (!_ok(_store.categories.get(id)).hasId()) {
      throw StateError('no step created category ${input['category']}');
    }
    return id;
  }

  // ── Plumbing ────────────────────────────────────────────────────────────────────────────────

  /// A refusal — the ledger's, or a rule's thrown here — becomes the refused observation. Any other
  /// failure is a bug in a rule, a store or a scenario and propagates, so the engine fails the step.
  ParityOp _guarded(Future<StepResult> Function(Map<String, Object?>, ParityBindings) op) =>
      (input, bindings) async {
        try {
          return await op(input, bindings);
        } on Refusal catch (refusal) {
          return StepResult(ParityObservation.refused(refusal.status));
        } on _Refused catch (refused) {
          return StepResult(ParityObservation.refused(refused.status));
        }
      };

  /// The value of [result]; a ledger refusal is thrown as [_Refused], anything else as a failure.
  static T _ok<T>(ZenResult<T> result) => switch (result) {
    ZenSuccess(:final data) => data,
    ZenFailure(:final error) => switch (LedgerErrors.statusOf(error)) {
      final int status => throw _Refused(status),
      null => throw StateError('the store failed: ${error.runtimeType}: ${error.message}'),
    },
  };

  static Map<String, Object?> _json(GeneratedMessage message) =>
      message.toProto3Json() as Map<String, Object?>;

  /// [body] without its null values: proto3 JSON reads `null` as "unset" for some fields and refuses
  /// it for others, and an absent key is what the server's request would have had.
  static Map<String, Object?> _present(Map<String, Object?> body) => {
    for (final MapEntry(:key, :value) in body.entries) key: ?value,
  };

  static Map<String, String> _balanceMap(Map<String, Object?> account) {
    final entries = [
      for (final b
          in ((account['balances'] as List<Object?>?) ?? const []).cast<Map<String, Object?>>())
        MapEntry(ParityReaders.string(b, 'currency'), ParityReaders.int64(b, 'amountMinor')),
    ]..sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }
}

final class _Refused implements Exception {
  final int status;
  const _Refused(this.status);
}
