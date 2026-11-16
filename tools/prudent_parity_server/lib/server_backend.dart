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
    'budget.set': _setBudget,
    'reset.create': _createReset,
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

  Future<StepResult> _setBudget(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send(
      'PUT',
      [
        'budgets',
        bindings.resolve(input['category']),
        input['month']! as String,
        input['currency']! as String,
      ],
      {'amountMinor': input['amountMinor']},
    );
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'month': _string(body, 'month'),
          'currency': _string(body, 'currency'),
          'amountMinor': _int64(body, 'amountMinor'),
        }),
      ),
    );
  }

  Future<StepResult> _createReset(Map<String, Object?> input, ParityBindings bindings) async {
    final answer = await _send(
      'POST',
      ['budget-carry-over-resets'],
      {
        'categoryId': bindings.resolve(input['category']),
        'month': input['month'],
        'currency': input['currency'],
        'note': input['note'],
      },
    );
    return answer.observe(
      (body) => StepResult(
        ParityObservation.accepted({
          'month': _string(body, 'month'),
          'currency': _string(body, 'currency'),
          'note': _string(body, 'note'),
        }),
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
