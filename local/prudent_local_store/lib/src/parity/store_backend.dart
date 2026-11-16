import 'dart:io';

import 'package:prudent_local_core/parity.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/budgets.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goal_allocations.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/settings.pb.dart' as wire;
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import '../imports/import_workflow.dart';
import '../ledger/ledger.dart';
import '../ledger/ledger_errors.dart';
import '../ledger/ledger_view.dart';
import '../ledger/record_query.dart';
import '../prudent_local_store.dart';
import 'import_parity.dart';

/// The local side of the parity suite (ADR-107, ADR-113): every parity operation answered by the
/// [Ledger] over a real encrypted [ZenStore] in a temporary directory, one fresh store per scenario.
///
/// It replaced unit 3's in-memory `LocalRulesBackend` under the same operation names, as ADR-107
/// planned: the scenarios and the engine did not change. Answers are wire messages written as proto3
/// JSON and read by the same [ParityReaders] the server's answers are, so the two sides observe
/// alike by construction.
///
/// Budgets, resets, goals and allocations (unit 6a) go through the ledger too; `budget.set` and
/// `reset.create` kept the names of unit 3's stand-ins, which they replaced.
///
/// **The clock is strictly increasing** ([_tick]): a history is ordered by creation time, and two
/// entries written within one millisecond would tie and fall back to their random ids, an order the
/// server's microsecond clock never shows. That is a property of the harness, not of the ledger.
final class StoreBackend extends ParityBackend {
  @override
  String get name => 'local';

  Directory? _directory;
  ZenStore? _zen;
  late PrudentLocalStore _store;
  late Ledger _ledger;
  late ImportWorkflow _imports;

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
    'budget.get': _guarded(_getBudget),
    'budget.delete': _guarded(_deleteBudget),
    'budget.list': _guarded(_listBudgets),
    'budget.summary': _guarded(_budgetSummary),
    'reset.create': _guarded(_createReset),
    // Unit 8b, statement import (ADR-114).
    'import.create': _guarded(_createImport),
    'import.preview': _guarded(_previewImport),
    'import.defaults': _guarded(_importDefaults),
    'import.row': _guarded(_importRow),
    'import.commit': _guarded(_commitImport),
    'import.discard': _guarded(_discardImport),
    'reset.revoke': _guarded(_revokeReset),
    'reset.list': _guarded(_listResets),
    'goal.create': _guarded(_createGoal),
    'goal.get': _guarded(_getGoal),
    'goal.update': _guarded(_updateGoal),
    'goal.complete': _guarded((i, b) => _transition(i, b, _ledger.completeGoal)),
    'goal.archive': _guarded((i, b) => _transition(i, b, _ledger.archiveGoal)),
    'goal.reactivate': _guarded((i, b) => _transition(i, b, _ledger.reactivateGoal)),
    'goal.list': _guarded(_listGoals),
    'goal.progress': _guarded(_goalProgress),
    'allocation.create': _guarded(_createAllocation),
    'allocation.get': _guarded(_getAllocation),
    'allocation.list': _guarded(_listAllocations),
    'envelope.list': _guarded(_listEnvelopes),
    'freemoney.get': _guarded(_freeMoney),
  };

  int _lastTick = 0;

  int _tick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastTick = now > _lastTick ? now : _lastTick + 1;
    return _lastTick;
  }

  @override
  Future<void> open(String scenarioName) async {
    final directory = await Directory.systemTemp.createTemp('prudent_parity_$scenarioName');
    _directory = directory;
    final zen = _ok(await ZenStore.open(directory, deviceName: 'parity', key: List.filled(32, 7)));
    _zen = zen;
    _store = PrudentLocalStore(zen);
    _ledger = Ledger(_store, clock: _tick);
    // The wall clock, as the server's: its importer measures dates from today in UTC.
    _imports = ImportWorkflow(ledger: _store, nowMs: () => DateTime.now().millisecondsSinceEpoch);
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
    final account = _settled(_ok(await _ledger.createAccount(request)));
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
    final account = _settled(_ok(await _ledger.getAccount(bindings.resolve(input['account']))));
    return StepResult(ParityObservation.accepted({'balances': _balanceMap(_json(account))}));
  }

  Future<StepResult> _getAccount(Map<String, Object?> input, ParityBindings bindings) async {
    final account = _settled(
      _ok(await _ledger.getAccount(bindings.idOrLiteral(input['account'])!)),
    );
    return StepResult(ParityObservation.accepted(ParityReaders.account(_json(account))));
  }

  Future<StepResult> _updateAccount(Map<String, Object?> input, ParityBindings bindings) async {
    final body = Map<String, Object?>.of(input)..remove('account');
    final request = wire.UpdateAccountRequest()..mergeFromProto3Json(body);
    final account = _settled(
      _ok(await _ledger.updateAccount(bindings.idOrLiteral(input['account'])!, request)),
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
    final list = _settled(_ok(await _ledger.listAccounts()));
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

  // ── Budgets and resets (unit 6a) ───────────────────────────────────────────────────────────

  Future<StepResult> _setBudget(Map<String, Object?> input, ParityBindings bindings) async {
    final written = _ok(
      await _ledger.setBudget(
        bindings.idOrLiteral(input['category'])!,
        input['month']! as String,
        input['currency']! as String,
        int.parse(input['amountMinor']! as String),
      ),
    );
    return StepResult(
      ParityObservation.accepted({
        ...ParityReaders.budget(_json(written.budget), bindings),
        'created': written.created,
      }),
    );
  }

  Future<StepResult> _getBudget(Map<String, Object?> input, ParityBindings bindings) async {
    final budget = _ok(
      await _ledger.getBudget(
        bindings.idOrLiteral(input['category'])!,
        input['month']! as String,
        input['currency']! as String,
      ),
    );
    return StepResult(ParityObservation.accepted(ParityReaders.budget(_json(budget), bindings)));
  }

  Future<StepResult> _deleteBudget(Map<String, Object?> input, ParityBindings bindings) async {
    _ok(
      await _ledger.deleteBudget(
        bindings.idOrLiteral(input['category'])!,
        input['month']! as String,
        input['currency']! as String,
      ),
    );
    return StepResult(ParityObservation.accepted());
  }

  Future<StepResult> _listBudgets(Map<String, Object?> input, ParityBindings bindings) async {
    final list = _ok(
      await _ledger.listBudgets(
        month: input['month'] as String?,
        categoryId: bindings.idOrLiteral(input['category']),
      ),
    );
    final rows = (_json(list)['budgets'] as List<Object?>?) ?? const [];
    return StepResult(
      ParityObservation.accepted({
        'budgets': ParityReaders.boundRows(
          rows,
          bindings,
          'categoryId',
          (row) => ParityReaders.budget(row, bindings),
        ),
      }),
    );
  }

  Future<StepResult> _budgetSummary(Map<String, Object?> input, ParityBindings bindings) async {
    final summary = _settled(
      _ok(await _ledger.budgetSummary(input['month']! as String, input['currency']! as String)),
    );
    return StepResult(
      ParityObservation.accepted(ParityReaders.budgetSummary(_json(summary), bindings)),
    );
  }

  /// The reset request a scenario's input names: the category is a reference.
  static Map<String, Object?> resetBody(Map<String, Object?> input, ParityBindings bindings) => {
    'categoryId': bindings.idOrLiteral(input['category']),
    'month': input['month'],
    'currency': input['currency'],
    'note': input['note'],
  };

  Future<StepResult> _createReset(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.ResetBudgetCarryOverRequest()
      ..mergeFromProto3Json(_present(resetBody(input, bindings)));
    final reset = _ok(await _ledger.resetBudgetCarryOver(request));
    return StepResult(
      ParityObservation.accepted(ParityReaders.reset(_json(reset), bindings)),
      createdId: reset.id,
    );
  }

  Future<StepResult> _revokeReset(Map<String, Object?> input, ParityBindings bindings) async {
    final reset = _ok(await _ledger.revokeBudgetReset(bindings.idOrLiteral(input['reset'])!));
    return StepResult(ParityObservation.accepted(ParityReaders.reset(_json(reset), bindings)));
  }

  Future<StepResult> _listResets(Map<String, Object?> input, ParityBindings bindings) async {
    final list = _ok(
      await _ledger.listBudgetResets(
        categoryId: bindings.idOrLiteral(input['category']),
        currency: input['currency'] as String?,
      ),
    );
    final rows = (_json(list)['resets'] as List<Object?>?) ?? const [];
    return StepResult(
      ParityObservation.accepted({'resets': ParityReaders.boundNames(rows, bindings)}),
    );
  }

  // ── Goals and allocations (unit 6a) ─────────────────────────────────────────────────────────

  /// The goal request a scenario's input names (create and update take the same fields; update
  /// ignores the currency, which the server's update request does not have).
  static Map<String, Object?> goalBody(Map<String, Object?> input, {required bool create}) => {
    'name': input['name'],
    if (create) 'currency': input['currency'],
    'targetAmountMinor': input['targetAmountMinor'],
    if (input.containsKey('targetDate')) 'targetDate': input['targetDate'],
  };

  Future<StepResult> _createGoal(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.CreateGoalRequest()
      ..mergeFromProto3Json(_present(goalBody(input, create: true)));
    final goal = _ok(await _ledger.createGoal(request));
    return StepResult(
      ParityObservation.accepted(ParityReaders.goal(_json(goal))),
      createdId: goal.id,
    );
  }

  Future<StepResult> _getGoal(Map<String, Object?> input, ParityBindings bindings) async {
    final goal = _ok(await _ledger.getGoal(bindings.idOrLiteral(input['goal'])!));
    return StepResult(ParityObservation.accepted(ParityReaders.goal(_json(goal))));
  }

  Future<StepResult> _updateGoal(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.UpdateGoalRequest()
      ..mergeFromProto3Json(_present(goalBody(input, create: false)));
    final goal = _ok(await _ledger.updateGoal(bindings.idOrLiteral(input['goal'])!, request));
    return StepResult(ParityObservation.accepted(ParityReaders.goal(_json(goal))));
  }

  Future<StepResult> _transition(
    Map<String, Object?> input,
    ParityBindings bindings,
    Future<ZenResult<wire.Goal>> Function(String id) move,
  ) async {
    final goal = _ok(await move(bindings.idOrLiteral(input['goal'])!));
    return StepResult(ParityObservation.accepted(ParityReaders.goal(_json(goal))));
  }

  Future<StepResult> _listGoals(Map<String, Object?> input, ParityBindings bindings) async {
    final list = _ok(await _ledger.listGoals(status: input['status'] as String?));
    final rows = (_json(list)['goals'] as List<Object?>?) ?? const [];
    return StepResult(
      ParityObservation.accepted({'goals': ParityReaders.boundNames(rows, bindings)}),
    );
  }

  Future<StepResult> _goalProgress(Map<String, Object?> input, ParityBindings bindings) async {
    final progress = _json(
      _settled(_ok(await _ledger.goalProgress(asOf: input['asOf'] as String?))),
    );
    return StepResult(
      ParityObservation.accepted({
        'asOf': ParityReaders.string(progress, 'asOf'),
        'goals': ParityReaders.boundRows(
          (progress['goals'] as List<Object?>?) ?? const [],
          bindings,
          'goalId',
          (row) => ParityReaders.goalProgress(row, bindings),
        ),
      }),
    );
  }

  /// The envelope-entry request a scenario's input names: goals are references.
  static Map<String, Object?> allocationBody(Map<String, Object?> input, ParityBindings bindings) =>
      {
        'kind': input['kind'],
        if (input.containsKey('source')) 'sourceGoalId': bindings.idOrLiteral(input['source']),
        if (input.containsKey('target')) 'targetGoalId': bindings.idOrLiteral(input['target']),
        'amountMinor': input['amountMinor'],
        if (input.containsKey('note')) 'note': input['note'],
      };

  Future<StepResult> _createAllocation(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.CreateGoalAllocationRequest()
      ..mergeFromProto3Json(_present(allocationBody(input, bindings)));
    final entry = _ok(await _ledger.createGoalAllocation(request));
    return StepResult(
      ParityObservation.accepted(ParityReaders.allocation(_json(entry), bindings)),
      createdId: entry.id,
    );
  }

  Future<StepResult> _getAllocation(Map<String, Object?> input, ParityBindings bindings) async {
    final entry = _ok(await _ledger.getGoalAllocation(bindings.idOrLiteral(input['allocation'])!));
    return StepResult(ParityObservation.accepted(ParityReaders.allocation(_json(entry), bindings)));
  }

  Future<StepResult> _listAllocations(Map<String, Object?> input, ParityBindings bindings) async {
    final list = _ok(
      await _ledger.listGoalAllocations(goalId: bindings.idOrLiteral(input['goal'])),
    );
    final rows = (_json(list)['allocations'] as List<Object?>?) ?? const [];
    return StepResult(
      ParityObservation.accepted({'allocations': ParityReaders.boundNames(rows, bindings)}),
    );
  }

  Future<StepResult> _listEnvelopes(Map<String, Object?> input, ParityBindings bindings) async {
    final list = _json(_ok(await _ledger.listGoalEnvelopes()));
    return StepResult(
      ParityObservation.accepted({
        'envelopes': ParityReaders.boundRows(
          (list['envelopes'] as List<Object?>?) ?? const [],
          bindings,
          'goalId',
          (row) => ParityReaders.envelope(row, bindings),
        ),
      }),
    );
  }

  Future<StepResult> _freeMoney(Map<String, Object?> input, ParityBindings bindings) async {
    final money = _json(_settled(_ok(await _ledger.freeMoney())));
    return StepResult(
      ParityObservation.accepted(
        ParityReaders.freeMoney(money, input['currency']! as String, bindings),
      ),
    );
  }

  // ── Statement import (unit 8b) ──────────────────────────────────────────────────────────────

  Future<StepResult> _createImport(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.CreateImportSessionRequest()
      ..mergeFromProto3Json(ImportParity.createBody(input, bindings));
    final session = _ok(await _imports.create(request));
    return StepResult(
      ParityObservation.accepted(ImportParity.sessionObservation(_json(session), bindings)),
      createdId: session.id,
    );
  }

  Future<StepResult> _previewImport(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.PreviewImportSessionRequest()
      ..mergeFromProto3Json(ImportParity.previewBody(input, bindings));
    return _session(
      await _imports.preview(ImportParity.session(input, bindings), request),
      bindings,
    );
  }

  Future<StepResult> _importDefaults(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.SetImportDefaultsRequest()
      ..mergeFromProto3Json(ImportParity.defaultsBody(input, bindings));
    return _session(
      await _imports.setDefaults(ImportParity.session(input, bindings), request),
      bindings,
    );
  }

  Future<StepResult> _importRow(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.UpdateImportRowRequest()
      ..mergeFromProto3Json(ImportParity.rowBody(input, bindings));
    final answer = _ok(
      await _imports.updateRow(
        ImportParity.session(input, bindings),
        ImportParity.rowNumber(input),
        request,
      ),
    );
    return StepResult(
      ParityObservation.accepted(ImportParity.rowDecisionObservation(_json(answer))),
    );
  }

  Future<StepResult> _commitImport(Map<String, Object?> input, ParityBindings bindings) async {
    final request = wire.CommitImportSessionRequest()
      ..mergeFromProto3Json(ImportParity.commitBody(input));
    return _session(
      await _imports.commit(ImportParity.session(input, bindings), request),
      bindings,
    );
  }

  Future<StepResult> _discardImport(Map<String, Object?> input, ParityBindings bindings) async =>
      _session(await _imports.discard(ImportParity.session(input, bindings)), bindings);

  StepResult _session(ZenResult<wire.ImportSession> answer, ParityBindings bindings) => StepResult(
    ParityObservation.accepted(ImportParity.sessionObservation(_json(_ok(answer)), bindings)),
  );

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

  /// One store, one device: nothing can be in conflict, so a figure that leaves something out is a
  /// bug, never a value to compare.
  static T _settled<T>(Settled<T> answer) {
    if (!answer.isSettled) throw StateError('a parity figure left out ${answer.unsettled}');
    return answer.value;
  }

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
