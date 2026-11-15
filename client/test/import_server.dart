// A stand-in for the server's import-session routes (ADR-089 to ADR-092), for the review-flow tests.
// It follows the server's rules where the screens depend on them: the preview resets what the user
// decided about duplicates, counts are recomputed after every decision, a commit is refused unless it
// confirms exactly the accepted rows and every row has a category or a default, and a rejected row
// takes no decision. Everything in it is synthetic.
import 'dart:convert';

import 'package:http/http.dart' as http;

const _headers = {
  'X-Zen-Transport': 'json',
  // Without a charset the HTTP package encodes the body as Latin-1, and a Polish letter then fails to decode.
  'content-type': 'application/json; charset=utf-8',
};

const accepted = 'IMPORT_ROW_STATUS_ACCEPTED';
const duplicate = 'IMPORT_ROW_STATUS_DUPLICATE';
const rejected = 'IMPORT_ROW_STATUS_REJECTED';

Map<String, Object?> importRow(
  int number, {
  String status = accepted,
  int? amount,
  String? description,
  String? date = '2026-11-01',
  String? rejectionCode,
  String? duplicateCode,
  String? hintCode,
}) => {
  'sessionId': 's1',
  'rowNumber': number,
  'status': status,
  'rejectionCode': ?rejectionCode,
  'transactionDate': ?date,
  if (amount != null) 'amountMinor': '$amount',
  'description': ?description,
  'duplicateCode': ?duplicateCode,
  'hintCode': ?hintCode,
};

/// The routes, with the session's state in memory and a log of what was asked.
class ImportServer {
  ImportServer({
    required this.rows,
    this.accountId,
    this.categories = _categories,
    this.duplicatesByAccount,
  });

  /// Which rows are duplicates for each destination account (the server decides this per account,
  /// ImportDuplicateStage). Null keeps the rows that start as duplicates for every account.
  final Map<String, Set<int>>? duplicatesByAccount;

  List<Map<String, Object?>> rows;
  String? accountId;
  String state = 'IMPORT_SESSION_STATE_PARSED';
  Map<int, Object?>? _initialDuplicates;
  String? defaultExpense;
  String? defaultIncome;
  int? committedWritten;
  int? committedAlready;
  final List<Map<String, Object?>> categories;

  /// A response for the next call to a route (`POST /api/v1/import-sessions` and so on), consumed
  /// once. The body is the ZenError the real server sends.
  final Map<String, (int, Map<String, Object?>)> failNext = {};

  /// Calls (`POST /api/v1/...`) that never reach the server: the network drops the request.
  final dropBefore = <String>{};

  /// Calls the server completes but whose answer the network loses, so the client sees a failure
  /// for something that happened.
  final dropResponse = <String>{};

  final calls = <String>[];
  final bodies = <String, List<Map<String, Object?>>>{};

  List<Map<String, Object?>> bodiesOf(String call) => bodies[call] ?? const [];
  int count(String call) => calls.where((c) => c == call).length;

  static const _categories = <Map<String, Object?>>[
    {'id': 'food', 'title': 'Food', 'kind': 'CATEGORY_KIND_EXPENSE'},
    {'id': 'salary', 'title': 'Salary', 'kind': 'CATEGORY_KIND_INCOME'},
    {'id': 'misc', 'title': 'Misc', 'kind': 'CATEGORY_KIND_UNSPECIFIED'},
    {'id': 'old', 'title': 'Old shop', 'kind': 'CATEGORY_KIND_EXPENSE', 'archived': true},
  ];

  bool _writes(Map<String, Object?> r) =>
      r['status'] == accepted || (r['status'] == duplicate && r['includeDuplicate'] == true);

  Map<String, Object?> _counts() => {
    'acceptedRows': rows.where(_writes).length,
    'duplicateRows': rows.where((r) => r['status'] == duplicate && r['includeDuplicate'] != true).length,
    'rejectedRows': rows.where((r) => r['status'] == rejected).length,
  };

  Map<String, Object?> session({bool withRows = true}) => {
    'id': 's1',
    'formatId': 'erste-pl-csv',
    'state': state,
    if (accountId != null) 'accountId': accountId,
    'currency': 'PLN',
    'createdAtMs': '1790000000000',
    'expiresAtMs': '1790086400000',
    ..._counts(),
    if (withRows && (state == 'IMPORT_SESSION_STATE_PARSED' || state == 'IMPORT_SESSION_STATE_PREVIEWED'))
      'rows': rows,
    if (committedWritten != null) 'committedWritten': committedWritten,
    if (committedAlready != null) 'committedAlreadyImported': committedAlready,
    if (defaultExpense != null) 'defaultExpenseCategoryId': defaultExpense,
    if (defaultIncome != null) 'defaultIncomeCategoryId': defaultIncome,
  };

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: _headers);

  http.Response error(int status, String code, String message) =>
      _json({'code': code, 'message': message}, status);

  Future<http.Response> handle(http.Request request) async {
    final call = '${request.method} ${request.url.path}';
    if (dropBefore.remove(call)) {
      calls.add('$call (dropped)');
      throw http.ClientException('connection lost');
    }
    final response = await _handle(request);
    if (dropResponse.remove(call)) throw http.ClientException('connection lost');
    return response;
  }

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    final call = '${request.method} $path';
    calls.add(call);
    final body =
        request.body.isEmpty
            ? <String, Object?>{}
            : (jsonDecode(request.body) as Map).cast<String, Object?>();
    (bodies[call] ??= []).add(body);

    final failure = failNext.remove(call);
    if (failure != null) return _json(failure.$2, failure.$1);

    if (request.method == 'GET') {
      if (path == '/api/v1/categories') return _json({'categories': categories});
      if (path == '/api/v1/import-sessions') {
        return _json({'sessions': [session(withRows: false)]});
      }
      if (path == '/api/v1/import-sessions/s1') return _json(session());
    }

    if (request.method == 'POST') {
      if (path == '/api/v1/import-sessions') {
        accountId = body['accountId'] as String?;
        state = 'IMPORT_SESSION_STATE_PARSED';
        return _json(session(), 201);
      }
      if (path == '/api/v1/import-sessions/s1/preview') {
        if (body['accountId'] != null) accountId = body['accountId'] as String;
        state = 'IMPORT_SESSION_STATE_PREVIEWED';
        // As the real preview: every duplicate goes back to accepted, then the rows are classified
        // again for the destination, so what the user chose about a duplicate is gone.
        final known = _initialDuplicates ??= {
          for (final r in rows)
            if (r['status'] == duplicate) r['rowNumber'] as int: r['duplicateCode'],
        };
        for (final r in rows) {
          r.remove('includeDuplicate');
          if (r['status'] == duplicate) {
            r['status'] = accepted;
            r.remove('duplicateCode');
          }
        }
        final byAccount = duplicatesByAccount;
        for (final r in rows) {
          final number = r['rowNumber'] as int;
          final isDuplicate =
              byAccount == null ? known.containsKey(number) : (byAccount[accountId]?.contains(number) ?? false);
          if (r['status'] == accepted && isDuplicate) {
            r['status'] = duplicate;
            r['duplicateCode'] = known[number] ?? 'duplicate.already_imported';
          }
        }
        return _json(session());
      }
      final rowRoute = RegExp(r'^/api/v1/import-sessions/s1/rows/(\d+)$').firstMatch(path);
      if (rowRoute != null) {
        final n = int.parse(rowRoute.group(1)!);
        final row = rows.firstWhere((r) => r['rowNumber'] == n);
        if (row['status'] == rejected) {
          return error(409, 'conflict', 'Row $n was rejected and cannot be changed.');
        }
        if (body.containsKey('categoryId')) {
          final id = body['categoryId'] as String;
          if (id.isEmpty) {
            row.remove('categoryId');
          } else {
            row['categoryId'] = id;
          }
        }
        if (body.containsKey('note')) {
          final note = body['note'] as String;
          if (note.isEmpty) {
            row.remove('note');
          } else {
            row['note'] = note;
          }
        }
        if (body.containsKey('includeDuplicate')) {
          row['includeDuplicate'] = body['includeDuplicate'];
        }
        return _json({'row': row, ..._counts()});
      }
      if (path == '/api/v1/import-sessions/s1/defaults') {
        if (body.containsKey('defaultExpenseCategoryId')) {
          final id = body['defaultExpenseCategoryId'] as String;
          defaultExpense = id.isEmpty ? null : id;
        }
        if (body.containsKey('defaultIncomeCategoryId')) {
          final id = body['defaultIncomeCategoryId'] as String;
          defaultIncome = id.isEmpty ? null : id;
        }
        return _json(session(withRows: false));
      }
      if (path == '/api/v1/import-sessions/s1/commit') {
        final confirmed = body['confirmedAcceptedRows'] ?? 0;
        if (state == 'IMPORT_SESSION_STATE_COMMITTED') {
          // A repeat of a commit that went through answers with the same result, writing nothing.
          return confirmed == committedWritten
              ? _json(session(withRows: false))
              : error(409, 'conflict', 'Already committed with a different count.');
        }
        final writing = rows.where(_writes).toList();
        if (confirmed != writing.length) {
          return error(409, 'conflict', 'The confirmed row count does not match.');
        }
        final missing = writing.where((r) {
          if (r['categoryId'] != null) return false;
          final expense = int.parse(r['amountMinor'] as String) < 0;
          return (expense ? defaultExpense : defaultIncome) == null;
        });
        if (missing.isNotEmpty) {
          return error(409, 'conflict', '${missing.length} row(s) have no category yet.');
        }
        state = 'IMPORT_SESSION_STATE_COMMITTED';
        committedWritten = writing.length;
        committedAlready = 0;
        return _json(session(withRows: false));
      }
      if (path == '/api/v1/import-sessions/s1/discard') {
        state = 'IMPORT_SESSION_STATE_DISCARDED';
        return _json(session(withRows: false));
      }
    }
    return http.Response('unexpected $call', 500);
  }
}
