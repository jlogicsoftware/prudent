/// The server side of the parity harness (ADR-107): each parity operation as the real Quarkus
/// server answers it, over HTTP with canonical proto3 JSON.
///
/// Plain JSON maps, not the generated Dart messages: those live in the server-connected app's
/// package (and move to `packages/prudent_ui` in unit 2), which this package must not depend on.
/// A misspelled field is not silent — the server's proto3 JSON reader refuses an unknown field —
/// and the response is read field by field, with proto3's defaults made explicit (an omitted
/// `int64` is `"0"`, an omitted plain `string` is `""`, an omitted `optional string` is absent).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:prudent_local_core/parity.dart';
import 'package:prudent_local_store/parity.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_transport/zen_transport.dart';

/// One signed-in user on the live server, shared by every scenario of a suite run.
///
/// **One sign-up per run, not one per scenario.** Registration is rate-limited by zen-ratelimit's
/// production auth limits (which `%dev` keeps, rightly), and a user per scenario trips them on the
/// second run within the window. Loosening the limit for the suite would be a gate bent for
/// convenience, so instead every scenario creates its own accounts and categories and binds them by
/// name: no step reads a row another scenario made. A later unit that adds a list operation must
/// keep that property — filter the answer to the scenario's own bound ids — or argue for a user per
/// scenario in its ADR (ADR-107).
final class ServerSession {
  ServerSession._(this.baseUrl, this._client);

  final String baseUrl;
  final ZenSessionClient _client;

  /// Registers a new user at [baseUrl] and waits for the starter data registration seeds, which
  /// races the response (ADR-017).
  static Future<ServerSession> register(String baseUrl) async {
    final client = createSessionClient();
    Future<bool> recover() async => false;
    final identity = SupabaseIdentityRepository(
      client: ZenClient(baseUrl: baseUrl, httpClient: client, recoverSession: recover),
    );
    final email = 'prudent-parity-${DateTime.now().microsecondsSinceEpoch}@example.com';
    final registered = await identity.registerWithEmail(email: email, password: 'parity-secret-1');
    if (!registered.isSuccess) {
      client.close();
      throw StateError('registering the parity user failed: ${registered.errorOrNull?.message}');
    }
    final session = ServerSession._(baseUrl, client);
    for (var attempt = 0; attempt < 40; attempt++) {
      final answer = await session._send('GET', ['categories']);
      final categories = (answer.body['categories'] as List<Object?>?) ?? const [];
      if (answer.status == 200 && categories.isNotEmpty) return session;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    client.close();
    throw StateError('registration never seeded the starter categories');
  }

  void close() => _client.close();

  /// `GET /api/v1/privacy/export` (ADR-071) as the proto3 JSON the server sent: the file a person
  /// saves and moves into Prudent Local (unit 10b, ADR-123).
  Future<Map<String, Object?>> privacyExport() async {
    final answer = await _send('GET', ['privacy', 'export']);
    if (answer.status != 200) {
      throw StateError('the privacy export answered ${answer.status}');
    }
    return answer.body;
  }

  /// One request under `/api/v1/`, path segments percent-encoded one by one (a currency of
  /// `" chf "` is a path segment with spaces in it, as the server receives it).
  Future<_Answer> _send(
    String method,
    List<String> segments, [
    Map<String, Object?>? body,
    Map<String, String>? query,
  ]) async {
    final base = Uri.parse(baseUrl);
    final uri = base.replace(
      pathSegments: [...base.pathSegments, 'api', 'v1', ...segments],
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Content-Type': ZenTransportFormat.json.contentType,
        'Accept': ZenTransportFormat.json.contentType,
        zenTransportHeaderName: ZenTransportFormat.json.value,
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await _client.send(request));
    final text = response.body;
    final decoded = text.isEmpty ? const <String, Object?>{} : jsonDecode(text);
    if (decoded is! Map<String, Object?>) {
      throw StateError('$method $uri answered ${response.statusCode} with a body that is not JSON');
    }
    return _Answer(method, uri, response.statusCode, decoded);
  }
}

/// Runs parity operations against the live server, as the [ServerSession]'s user.
final class ServerBackend extends ParityBackend {
  ServerBackend(this._session);

  final ServerSession _session;

  @override
  String get name => 'server';

  @override
  late final Map<String, ParityOp> ops = {
    'account.create': _createAccount,
    'account.balances': _balances,
    'category.create': _createCategory,
    'record.create': _createRecord,
    // Unit 6a: budgets, resets, goals, allocations. The same request helpers as above.
    'budget.set': _setBudget,
    'budget.get': _getBudget,
    'budget.delete': _deleteBudget,
    'budget.list': _listBudgets,
    'budget.summary': _budgetSummary,
    'reset.create': _createReset,
    'reset.revoke': _revokeReset,
    'reset.list': _listResets,
    'goal.create': _createGoal,
    'goal.get': _getGoal,
    'goal.update': _updateGoal,
    'goal.complete': (i, b) => _transition(i, b, 'complete'),
    'goal.archive': (i, b) => _transition(i, b, 'archive'),
    'goal.reactivate': (i, b) => _transition(i, b, 'reactivate'),
    'goal.list': _listGoals,
    'goal.progress': _goalProgress,
    'allocation.create': _createAllocation,
    'allocation.get': _getAllocation,
    'allocation.list': _listAllocations,
    'envelope.list': _listEnvelopes,
    'freemoney.get': _freeMoney,
    // Unit 5, the ledger (ADR-113). Request bodies are built by the local backend's own helpers
    // (StoreBackend.recordBody and its siblings), so both sides send the same request.
    'account.get': _getAccount,
    'account.update': _updateAccount,
    'account.delete': _deleteAccount,
    'account.list': _listAccounts,
    'category.update': _updateCategory,
    'category.archive': _archiveCategory,
    'category.restore': _restoreCategory,
    'category.delete': _deleteCategory,
    'category.list': _listCategories,
    'record.update': _updateRecord,
    'record.delete': _deleteRecord,
    'record.list': _listRecords,
    'transfer.create': _createTransfer,
    'transfer.delete': _deleteTransfer,
    'correction.create': _createCorrection,
    'correction.delete': _deleteCorrection,
    'settings.update': _updateSettings,
    // Unit 6b, plans (ADR-119). The server reads its own clock; a scenario names dates relative to
    // today (ParityClock) so that both sides agree on what today is.
    'plan.create': _createPlan,
    'plan.update': _updatePlan,
    'plan.delete': _deletePlan,
    'plan.list': _listPlans,
    'occurrence.find': _findOccurrence,
    'occurrence.upcoming': _upcoming,
    'occurrence.overdue': _overdue,
    'occurrence.skip': _skip,
    'occurrence.restore': _restore,
    'occurrence.confirm': _confirm,
    'reminder.list': _listReminders,
    'reminder.read': _readReminder,
    'reminder.unread': _unreadReminder,
    'reminder.readAll': _readAllReminders,
    // Unit 8b, statement import (ADR-114): bodies and observations are ImportParity's, shared.
    'import.create': _createImport,
    'import.preview': _previewImport,
    'import.defaults': _importDefaults,
    'import.row': _importRow,
    'import.commit': _commitImport,
    'import.discard': _discardImport,
    // Unit 7, analytics (ADR-118): a plain GET with the scenario's values as query parameters.
    'analytics.spendByCategory': _spendByCategory,
    'analytics.spendByPeriod': _spendByPeriod,
  };

  /// Nothing to set up: the session is the suite's, and a scenario's rows are its own (see
  /// [ServerSession]).
  @override
  Future<void> open(String scenarioName) async {}

  @override
  Future<void> close() async {}

  Future<_Answer> _send(
    String method,
    List<String> segments, [
    Map<String, Object?>? body,
    Map<String, String>? query,
  ]) => _session._send(method, segments, body, query);

  Future<StepResult> _createAccount(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['accounts'], input);
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'name': _string(body, 'name'),
          'balances': _balanceMap(body),
          'accountNumber': _string(body, 'accountNumber'),
        }),
        createdId: _string(body, 'id'),
      ),
    );
  }

  Future<StepResult> _balances(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['accounts', bindings.resolve(input['account'])]);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted({'balances': _balanceMap(body)})),
    );
  }

  Future<StepResult> _createCategory(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['categories'], input);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(), createdId: _string(body, 'id')),
    );
  }

  Future<StepResult> _createRecord(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['records'], StoreBackend.recordBody(input, bindings));
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(StoreBackend.recordObservation(body)),
        createdId: _string(body, 'id'),
      ),
    );
  }

  // ── Unit 5: the ledger ──────────────────────────────────────────────────────────────────────

  /// A path segment for an id: a bound name's id, or a literal the scenario sends on purpose.
  static String _id(Map<String, Object?> input, String key, ParityBindings bindings) =>
      bindings.idOrLiteral(input[key])!;

  Future<StepResult> _getAccount(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['accounts', _id(input, 'account', bindings)]);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.account(body))),
    );
  }

  Future<StepResult> _updateAccount(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('PUT', [
      'accounts',
      _id(input, 'account', bindings),
    ], Map<String, Object?>.of(input)..remove('account'));
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.account(body))),
    );
  }

  Future<StepResult> _deleteAccount(Map<String, Object?> input, ParityBindings bindings) async {
    final flag = input['deleteRecords'] as bool?;
    final answer = await _send(
      'DELETE',
      ['accounts', _id(input, 'account', bindings)],
      null,
      flag == null ? null : {'deleteRecords': '$flag'},
    );
    return answer.observe((_) => StepResult(ParityObservation.accepted()));
  }

  Future<StepResult> _listAccounts(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['accounts']);
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'accounts': ParityReaders.boundNames(
            (body['accounts'] as List<Object?>?) ?? const [],
            bindings,
          ),
        }),
      ),
    );
  }

  Future<StepResult> _updateCategory(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('PUT', [
      'categories',
      _id(input, 'category', bindings),
    ], Map<String, Object?>.of(input)..remove('category'));
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.category(body))),
    );
  }

  Future<StepResult> _archiveCategory(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['categories', _id(input, 'category', bindings), 'archive']);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.category(body))),
    );
  }

  Future<StepResult> _restoreCategory(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['categories', _id(input, 'category', bindings), 'restore']);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.category(body))),
    );
  }

  Future<StepResult> _deleteCategory(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('DELETE', ['categories', _id(input, 'category', bindings)]);
    return answer.observe((_) => StepResult(ParityObservation.accepted()));
  }

  Future<StepResult> _listCategories(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['categories']);
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'categories': ParityReaders.boundNames(
            (body['categories'] as List<Object?>?) ?? const [],
            bindings,
          ),
        }),
      ),
    );
  }

  Future<StepResult> _updateRecord(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('PUT', [
      'records',
      _id(input, 'record', bindings),
    ], StoreBackend.recordBody(input, bindings));
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(StoreBackend.recordObservation(body))),
    );
  }

  Future<StepResult> _deleteRecord(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('DELETE', ['records', _id(input, 'record', bindings)]);
    return answer.observe((_) => StepResult(ParityObservation.accepted()));
  }

  /// `GET /api/v1/records` with the scenario's filters as query parameters, under the server's names.
  Future<StepResult> _listRecords(Map<String, Object?> input, ParityBindings bindings) async {
    final query = <String, String>{
      for (final key in const ['dateFrom', 'dateTo', 'type', 'amountMin', 'amountMax', 'search'])
        if (input[key] case final String value) key: value,
      'accountId': ?bindings.idOrLiteral(input['account']),
      'categoryId': ?bindings.idOrLiteral(input['category']),
    };
    final answer = await _send('GET', ['records'], null, query);
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(
          ParityReaders.recordList((body['records'] as List<Object?>?) ?? const [], bindings),
        ),
      ),
    );
  }

  Future<StepResult> _spendByCategory(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['analytics', 'spend-by-category'], null, _query(input));
    return answer.observe(
      (body) =>
          StepResult(ParityObservation.accepted(ParityReaders.spendByCategory(body, bindings))),
    );
  }

  Future<StepResult> _spendByPeriod(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['analytics', 'spend-by-period'], null, _query(input));
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.spendByPeriod(body))),
    );
  }

  /// The scenario's analytics input as query parameters; an absent key is an absent parameter.
  static Map<String, String> _query(Map<String, Object?> input) => {
    for (final MapEntry(:key, :value) in input.entries)
      if (value != null) key: '$value',
  };

  Future<StepResult> _createTransfer(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['transfers'], StoreBackend.transferBody(input, bindings));
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(ParityReaders.transfer(body, bindings)),
        createdId: _string(body, 'id'),
      ),
    );
  }

  Future<StepResult> _deleteTransfer(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('DELETE', ['transfers', _id(input, 'transfer', bindings)]);
    return answer.observe((_) => StepResult(ParityObservation.accepted()));
  }

  Future<StepResult> _createCorrection(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', [
      'corrections',
    ], StoreBackend.correctionBody(input, bindings));
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(ParityReaders.record(body, bindings)),
        createdId: _string(body, 'id'),
      ),
    );
  }

  Future<StepResult> _deleteCorrection(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('DELETE', ['corrections', _id(input, 'correction', bindings)]);
    return answer.observe((_) => StepResult(ParityObservation.accepted()));
  }

  /// The settings are the suite's one user's, shared by every scenario: a scenario sets them before
  /// it reads them, and this step observes what a read answers after the write.
  Future<StepResult> _updateSettings(Map<String, Object?> input, ParityBindings bindings) async {
    final written = await _send('PUT', ['settings'], input);
    if (written.status != 200) return written.observe((_) => throw StateError('unreachable'));
    final answer = await _send('GET', ['settings']);
    return answer.observe(
      (body) =>
          StepResult(ParityObservation.accepted({'mainCurrency': _string(body, 'mainCurrency')})),
    );
  }

  // ── Statement import (unit 8b) ──────────────────────────────────────────────────────────────

  static const _imports = 'import-sessions';

  Future<StepResult> _createImport(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', [_imports], ImportParity.createBody(input, bindings));
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(ImportParity.sessionObservation(body, bindings)),
        createdId: _string(body, 'id'),
      ),
    );
  }

  Future<StepResult> _previewImport(Map<String, Object?> input, ParityBindings bindings) =>
      _sessionStep(input, bindings, 'preview', ImportParity.previewBody(input, bindings));

  Future<StepResult> _importDefaults(Map<String, Object?> input, ParityBindings bindings) =>
      _sessionStep(input, bindings, 'defaults', ImportParity.defaultsBody(input, bindings));

  Future<StepResult> _commitImport(Map<String, Object?> input, ParityBindings bindings) =>
      _sessionStep(input, bindings, 'commit', ImportParity.commitBody(input));

  Future<StepResult> _discardImport(Map<String, Object?> input, ParityBindings bindings) =>
      _sessionStep(input, bindings, 'discard', const {});

  Future<StepResult> _importRow(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', [
      _imports,
      ImportParity.session(input, bindings),
      'rows',
      '${ImportParity.rowNumber(input)}',
    ], ImportParity.rowBody(input, bindings));
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ImportParity.rowDecisionObservation(body))),
    );
  }

  Future<StepResult> _sessionStep(
    Map<String, Object?> input,
    ParityBindings bindings,
    String phase,
    Map<String, Object?> body,
  ) async {
    final answer = await _send('POST', [
      _imports,
      ImportParity.session(input, bindings),
      phase,
    ], body);
    return answer.observe(
      (json) =>
          StepResult(ParityObservation.accepted(ImportParity.sessionObservation(json, bindings))),
    );
  }

  // ── Unit 6a: budgets, resets, goals, allocations ───────────────────────────────────────────

  /// The budget slot's path: the category (a bound name, or a literal sent on purpose), the month
  /// and the currency exactly as the scenario spells them.
  static List<String> _slot(Map<String, Object?> input, ParityBindings bindings) => [
    'budgets',
    _id(input, 'category', bindings),
    input['month']! as String,
    input['currency']! as String,
  ];

  Future<StepResult> _setBudget(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('PUT', _slot(input, bindings), {
      'amountMinor': input['amountMinor'],
    });
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          ...ParityReaders.budget(body, bindings),
          'created': answer.status == 201,
        }),
      ),
    );
  }

  Future<StepResult> _getBudget(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', _slot(input, bindings));
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.budget(body, bindings))),
    );
  }

  Future<StepResult> _deleteBudget(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('DELETE', _slot(input, bindings));
    return answer.observe((_) => StepResult(ParityObservation.accepted()));
  }

  Future<StepResult> _listBudgets(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send(
      'GET',
      ['budgets'],
      null,
      {
        if (input['month'] case final String month) 'month': month,
        'categoryId': ?bindings.idOrLiteral(input['category']),
      },
    );
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'budgets': ParityReaders.boundRows(
            (body['budgets'] as List<Object?>?) ?? const [],
            bindings,
            'categoryId',
            (row) => ParityReaders.budget(row, bindings),
          ),
        }),
      ),
    );
  }

  Future<StepResult> _budgetSummary(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send(
      'GET',
      ['budgets', 'summary'],
      null,
      {'month': input['month']! as String, 'currency': input['currency']! as String},
    );
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.budgetSummary(body, bindings))),
    );
  }

  Future<StepResult> _createReset(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', [
      'budget-carry-over-resets',
    ], _present(StoreBackend.resetBody(input, bindings)));
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(ParityReaders.reset(body, bindings)),
        createdId: _string(body, 'id'),
      ),
    );
  }

  Future<StepResult> _revokeReset(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', [
      'budget-carry-over-resets',
      _id(input, 'reset', bindings),
      'revoke',
    ]);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.reset(body, bindings))),
    );
  }

  Future<StepResult> _listResets(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send(
      'GET',
      ['budget-carry-over-resets'],
      null,
      {
        'categoryId': ?bindings.idOrLiteral(input['category']),
        if (input['currency'] case final String currency) 'currency': currency,
      },
    );
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'resets': ParityReaders.boundNames(
            (body['resets'] as List<Object?>?) ?? const [],
            bindings,
          ),
        }),
      ),
    );
  }

  Future<StepResult> _createGoal(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', [
      'goals',
    ], _present(StoreBackend.goalBody(input, create: true)));
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(ParityReaders.goal(body)),
        createdId: _string(body, 'id'),
      ),
    );
  }

  Future<StepResult> _getGoal(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['goals', _id(input, 'goal', bindings)]);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.goal(body))),
    );
  }

  Future<StepResult> _updateGoal(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('PUT', [
      'goals',
      _id(input, 'goal', bindings),
    ], _present(StoreBackend.goalBody(input, create: false)));
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.goal(body))),
    );
  }

  Future<StepResult> _transition(
    Map<String, Object?> input,
    ParityBindings bindings,
    String move,
  ) async {
    final answer = await _send('POST', ['goals', _id(input, 'goal', bindings), move]);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.goal(body))),
    );
  }

  Future<StepResult> _listGoals(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send(
      'GET',
      ['goals'],
      null,
      {if (input['status'] case final String status) 'status': status},
    );
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'goals': ParityReaders.boundNames(
            (body['goals'] as List<Object?>?) ?? const [],
            bindings,
          ),
        }),
      ),
    );
  }

  Future<StepResult> _goalProgress(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send(
      'GET',
      ['goals', 'progress'],
      null,
      {if (input['asOf'] case final String asOf) 'asOf': asOf},
    );
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'asOf': _string(body, 'asOf'),
          'goals': ParityReaders.boundRows(
            (body['goals'] as List<Object?>?) ?? const [],
            bindings,
            'goalId',
            (row) => ParityReaders.goalProgress(row, bindings),
          ),
        }),
      ),
    );
  }

  Future<StepResult> _createAllocation(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', [
      'goal-allocations',
    ], _present(StoreBackend.allocationBody(input, bindings)));
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(ParityReaders.allocation(body, bindings)),
        createdId: _string(body, 'id'),
      ),
    );
  }

  Future<StepResult> _getAllocation(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['goal-allocations', _id(input, 'allocation', bindings)]);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.allocation(body, bindings))),
    );
  }

  Future<StepResult> _listAllocations(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send(
      'GET',
      ['goal-allocations'],
      null,
      {'goalId': ?bindings.idOrLiteral(input['goal'])},
    );
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'allocations': ParityReaders.boundNames(
            (body['allocations'] as List<Object?>?) ?? const [],
            bindings,
          ),
        }),
      ),
    );
  }

  Future<StepResult> _listEnvelopes(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['goal-allocations', 'envelopes']);
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'envelopes': ParityReaders.boundRows(
            (body['envelopes'] as List<Object?>?) ?? const [],
            bindings,
            'goalId',
            (row) => ParityReaders.envelope(row, bindings),
          ),
        }),
      ),
    );
  }

  Future<StepResult> _freeMoney(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['goal-allocations', 'free-money']);
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(
          ParityReaders.freeMoney(body, input['currency']! as String, bindings),
        ),
      ),
    );
  }

  /// [body] without its null values, as the local backend sends it.
  static Map<String, Object?> _present(Map<String, Object?> body) => {
    for (final MapEntry(:key, :value) in body.entries) key: ?value,
  };

  // ── Unit 6b: plans, occurrences, reminders ──────────────────────────────────────────────────

  Future<StepResult> _createPlan(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['plans'], StoreBackend.planBody(input, bindings));
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(ParityReaders.plan(body, bindings)),
        createdId: _string(body, 'id'),
      ),
    );
  }

  Future<StepResult> _updatePlan(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('PUT', [
      'plans',
      _id(input, 'plan', bindings),
    ], StoreBackend.planBody(input, bindings));
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.plan(body, bindings))),
    );
  }

  Future<StepResult> _deletePlan(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('DELETE', ['plans', _id(input, 'plan', bindings)]);
    return answer.observe((_) => StepResult(ParityObservation.accepted()));
  }

  Future<StepResult> _listPlans(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['plans']);
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'plans': ParityReaders.planList((body['plans'] as List<Object?>?) ?? const [], bindings),
        }),
      ),
    );
  }

  /// The occurrence of a plan on a date, found the way a client finds one: in the two views, which
  /// also make the server generate the window. Nothing in either is the plan's: 404.
  Future<StepResult> _findOccurrence(Map<String, Object?> input, ParityBindings bindings) async {
    final plan = _id(input, 'plan', bindings);
    final date = input['date']! as String;
    for (final (segments, query) in [
      (['occurrences', 'upcoming'], {'days': '366'}),
      (['occurrences', 'overdue'], <String, String>{}),
    ]) {
      final answer = await _send('GET', segments, null, query);
      final found = answer.observe((body) {
        for (final row
            in ((body['occurrences'] as List<Object?>?) ?? const []).cast<Map<String, Object?>>()) {
          if (row['planId'] == plan && row['occurrenceDate'] == date) {
            return StepResult(
              ParityObservation.accepted(ParityReaders.occurrence(row, bindings)),
              createdId: _string(row, 'id'),
            );
          }
        }
        return const StepResult({}, createdId: null);
      });
      if (found.observation['outcome'] == 'refused' || found.createdId != null) return found;
    }
    return StepResult(ParityObservation.refused(404));
  }

  Future<StepResult> _upcoming(Map<String, Object?> input, ParityBindings bindings) async {
    final days = input['days'];
    final answer = await _send(
      'GET',
      ['occurrences', 'upcoming'],
      null,
      days == null ? null : {'days': '$days'},
    );
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(
          ParityReaders.occurrenceList(
            (body['occurrences'] as List<Object?>?) ?? const [],
            bindings,
          ),
        ),
      ),
    );
  }

  Future<StepResult> _overdue(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['occurrences', 'overdue']);
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(
          ParityReaders.occurrenceList(
            (body['occurrences'] as List<Object?>?) ?? const [],
            bindings,
          ),
        ),
      ),
    );
  }

  Future<StepResult> _skip(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['occurrences', _id(input, 'occurrence', bindings), 'skip']);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.occurrence(body, bindings))),
    );
  }

  Future<StepResult> _restore(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', [
      'occurrences',
      _id(input, 'occurrence', bindings),
      'restore',
    ]);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.occurrence(body, bindings))),
    );
  }

  Future<StepResult> _confirm(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', [
      'occurrences',
      _id(input, 'occurrence', bindings),
      'confirm',
    ], StoreBackend.confirmBody(input, bindings));
    return answer.observe((body) {
      final record = body['record']! as Map<String, Object?>;
      return StepResult(
        ParityObservation.accepted({
          'occurrence': ParityReaders.occurrence(
            body['occurrence']! as Map<String, Object?>,
            bindings,
          ),
          'record': ParityReaders.record(record, bindings),
        }),
        createdId: _string(record, 'id'),
      );
    });
  }

  Future<StepResult> _listReminders(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('GET', ['reminders']);
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(
          ParityReaders.occurrenceList(
            (body['reminders'] as List<Object?>?) ?? const [],
            bindings,
            nested: true,
          ),
        ),
      ),
    );
  }

  Future<StepResult> _readReminder(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['reminders', _id(input, 'occurrence', bindings), 'read']);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.reminder(body, bindings))),
    );
  }

  Future<StepResult> _unreadReminder(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['reminders', _id(input, 'occurrence', bindings), 'unread']);
    return answer.observe(
      (body) => StepResult(ParityObservation.accepted(ParityReaders.reminder(body, bindings))),
    );
  }

  Future<StepResult> _readAllReminders(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send('POST', ['reminders', 'read-all']);
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted(
          ParityReaders.occurrenceList(
            (body['reminders'] as List<Object?>?) ?? const [],
            bindings,
            nested: true,
          ),
        ),
      ),
    );
  }

  static Map<String, String> _balanceMap(Map<String, Object?> account) {
    final balances = (account['balances'] as List<Object?>?) ?? const [];
    final entries = [
      for (final balance in balances.cast<Map<String, Object?>>())
        MapEntry(_string(balance, 'currency'), _int64(balance, 'amountMinor')),
    ]..sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }

  /// A plain proto3 `string`: omitted from JSON when empty.
  static String _string(Map<String, Object?> body, String key) => (body[key] as String?) ?? '';

  /// A proto3 `int64`: a decimal string in JSON, omitted when zero.
  static String _int64(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value == null) return '0';
    if (value is String) return int.parse(value).toString();
    throw StateError('$key is not an int64 in proto3 JSON: $value');
  }
}

final class _Answer {
  _Answer(this.method, this.uri, this.status, this.body);

  final String method;
  final Uri uri;
  final int status;
  final Map<String, Object?> body;

  /// A 2xx is read by [read]; a 4xx is the refusal compared with the local one; anything else
  /// (a 5xx, a redirect) is a server failure, which ends the scenario rather than being compared.
  StepResult observe(StepResult Function(Map<String, Object?> body) read) {
    if (status >= 200 && status < 300) return read(body);
    if (status >= 400 && status < 500) return StepResult(ParityObservation.refused(status));
    throw StateError('$method $uri answered $status: ${body['code']} ${body['message']}');
  }
}
