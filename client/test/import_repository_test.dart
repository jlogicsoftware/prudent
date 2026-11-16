// The statement-import routes of PrudentRepository (jlogicsoftware/prudent#74), against the generated
// messages: each method calls the route the server defines (ADR-089 to ADR-092) with the body the
// route reads, and every import message survives the wire in both transport modes, as
// wire_round_trip_test.dart does for the older messages.
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent_ui/generated/prudent/v1/imports.pb.dart';
import 'package:prudent_ui/imports/import_failure.dart';
import 'package:prudent_ui/imports/import_providers.dart';
import 'package:prudent_ui/prudent_repository.dart';
import 'package:prudent/server_prudent_repository.dart';
import 'package:prudent_ui/providers.dart';
import 'package:protobuf/protobuf.dart';
import 'package:zen_transport/zen_transport.dart';

class _Call {
  _Call(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final String body;
}

PrudentRepository _repository(List<_Call> calls, Map<String, Object?> answer, {int status = 200}) =>
    ServerPrudentRepository(
      client: ZenClient(
        baseUrl: 'https://example.test',
        format: ZenTransportFormat.json,
        httpClient: MockClient((request) async {
          calls.add(_Call(request.method, request.url.path, request.url.queryParameters, request.body));
          return http.Response(
            jsonEncode(answer),
            status,
            headers: {'X-Zen-Transport': 'json', 'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

T roundTrip<T extends GeneratedMessage>(T m, ZenTransportFormat f, T Function() create) =>
    ZenProtoCodec.decode(ZenProtoCodec.encode(m, f), f, create);

void main() {
  group('a response that cannot be decoded', () {
    // The transport's own message ends with the decoder's text, and a JSON decoder quotes the part of
    // the body it choked on: for a session that is lines of a bank statement. A screen's load-error
    // view logs the error it is given, so the error must reach it without that text.
    const secret = 'TEST SECRET DESCRIPTION';

    ProviderContainer container(String body) {
      final client = ZenClient(
        baseUrl: 'https://example.test',
        format: ZenTransportFormat.json,
        httpClient: MockClient(
          (request) async => http.Response(
            body,
            200,
            headers: {'X-Zen-Transport': 'json', 'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final c = ProviderContainer(
        overrides: [prudentRepositoryProvider.overrideWithValue(ServerPrudentRepository(client: client))],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the transport message does quote the body (why this matters)', () async {
      final repository = ServerPrudentRepository(
        client: ZenClient(
          baseUrl: 'https://example.test',
          format: ZenTransportFormat.json,
          httpClient: MockClient(
            (request) async => http.Response(
              '{"id": "s1", "rows": [{"description": "$secret"',
              200,
              headers: {'X-Zen-Transport': 'json'},
            ),
          ),
        ),
      );
      final raw = (await repository.getImportSession('s1')).fold((_) => '', (e) => e.toString());
      expect(raw, contains(secret));
    });

    test('a session list that fails to decode carries no statement text', () async {
      final c = container('{"sessions": [{"id": "s1", "description": "$secret"');
      await expectLater(c.read(openImportSessionsProvider.future), throwsA(anything));
      final error = c.read(openImportSessionsProvider).error!;
      expect('$error $error', isNot(contains(secret)));
      expect(ImportFailure.from(error).kind, ImportFailureKind.unexpected);
    });

    test('a review that fails to decode carries no statement text', () async {
      final c = container('{"id": "s1", "rows": [{"description": "$secret"');
      await expectLater(c.read(importReviewProvider('s1').future), throwsA(anything));
      final error = c.read(importReviewProvider('s1')).error!;
      expect('$error', isNot(contains(secret)));
      expect(ImportFailure.from(error).kind, ImportFailureKind.unexpected);
    });

    test('an upload whose answer fails to decode carries no statement text', () async {
      final c = container('{"id": "s1", "rows": [{"description": "$secret"');
      await expectLater(
        c.read(importStarterProvider).start(bytes: Uint8List.fromList([1]), accountId: 'acc'),
        throwsA(anything),
      );
      try {
        await c.read(importStarterProvider).start(bytes: Uint8List.fromList([1]), accountId: 'acc');
      } catch (error) {
        expect('$error', isNot(contains(secret)));
      }
    });
  });

  const session = {'id': 's1', 'state': 'IMPORT_SESSION_STATE_PREVIEWED', 'currency': 'PLN'};

  group('PrudentRepository import sessions', () {
    test('createImportSession posts the format, the bytes and the account', () async {
      final calls = <_Call>[];
      final result = await _repository(calls, session, status: 201).createImportSession(
        CreateImportSessionRequest(formatId: 'erste-pl-csv', content: utf8.encode('x'), accountId: 'acc'),
      );

      expect(calls.single.method, 'POST');
      expect(calls.single.path, '/api/v1/import-sessions');
      final body = jsonDecode(calls.single.body) as Map;
      expect(body['formatId'], 'erste-pl-csv');
      expect(body['accountId'], 'acc');
      expect(base64Decode(body['content'] as String), utf8.encode('x'));
      expect(result.fold((s) => s.id, (e) => throw e), 's1');
    });

    test('listImportSessions can narrow by state', () async {
      final calls = <_Call>[];
      final repository = _repository(calls, {'sessions': [session]});

      final all = await repository.listImportSessions();
      final previewed = await repository.listImportSessions(
        state: ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED,
      );

      expect(calls[0].path, '/api/v1/import-sessions');
      expect(calls[0].query, isEmpty);
      expect(calls[1].query, {'state': 'PREVIEWED'});
      expect(all.fold((r) => r.sessions.length, (e) => throw e), 1);
      expect(previewed.isSuccess, isTrue);
    });

    test('a state a list cannot be filtered by is refused before any request', () {
      final calls = <_Call>[];
      expect(
        () => _repository(calls, session).listImportSessions(
          state: ImportSessionState.IMPORT_SESSION_STATE_UNSPECIFIED,
        ),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('getImportSession, preview, defaults, commit and discard use the session routes', () async {
      final calls = <_Call>[];
      final repository = _repository(calls, session);

      await repository.getImportSession('s1');
      await repository.previewImportSession('s1', PreviewImportSessionRequest(accountId: 'acc'));
      await repository.setImportDefaults(
        's1',
        SetImportDefaultsRequest(defaultExpenseCategoryId: 'food', defaultIncomeCategoryId: ''),
      );
      await repository.commitImportSession('s1', CommitImportSessionRequest(confirmedAcceptedRows: 3));
      await repository.discardImportSession('s1');

      expect([for (final c in calls) '${c.method} ${c.path}'], [
        'GET /api/v1/import-sessions/s1',
        'POST /api/v1/import-sessions/s1/preview',
        'POST /api/v1/import-sessions/s1/defaults',
        'POST /api/v1/import-sessions/s1/commit',
        'POST /api/v1/import-sessions/s1/discard',
      ]);
      expect(jsonDecode(calls[1].body), {'accountId': 'acc'});
      // An empty string is "clear it" and must reach the wire, not be dropped as a default value.
      expect(jsonDecode(calls[2].body), {'defaultExpenseCategoryId': 'food', 'defaultIncomeCategoryId': ''});
      expect(jsonDecode(calls[3].body), {'confirmedAcceptedRows': 3});
    });

    test('updateImportRow is a POST to the row, carrying only the fields set', () async {
      final calls = <_Call>[];
      final result = await _repository(calls, {
        'row': {'rowNumber': 4, 'status': 'IMPORT_ROW_STATUS_DUPLICATE', 'includeDuplicate': true},
        'acceptedRows': 4,
        'duplicateRows': 0,
        'rejectedRows': 2,
      }).updateImportRow('s1', 4, UpdateImportRowRequest(includeDuplicate: true));

      expect(calls.single.method, 'POST');
      expect(calls.single.path, '/api/v1/import-sessions/s1/rows/4');
      expect(jsonDecode(calls.single.body), {'includeDuplicate': true});
      final answer = result.fold((a) => a, (e) => throw e);
      expect(answer.row.includeDuplicate, isTrue);
      expect([answer.acceptedRows, answer.duplicateRows, answer.rejectedRows], [4, 0, 2]);
    });

    test('a refusal arrives as an error, never as an empty session', () async {
      final result = await _repository([], {'code': 'conflict', 'message': 'expired'}, status: 409)
          .commitImportSession('s1', CommitImportSessionRequest(confirmedAcceptedRows: 1));

      expect(result.isSuccess, isFalse);
      expect(result.errorOrNull, isA<ZenTransportError>());
    });
  });

  for (final format in ZenTransportFormat.values) {
    group('${format.value} wire format, imports', () {
      test('an ImportRow keeps its optional fields, absent or present', () {
        final accepted = ImportRow(
          sessionId: 's1',
          rowNumber: 3,
          status: ImportRowStatus.IMPORT_ROW_STATUS_DUPLICATE,
          transactionDate: '2026-11-03',
          amountMinor: Int64(-1250),
          description: 'TEST CARD PAYMENT',
          duplicateCode: 'duplicate.already_imported',
          categoryId: 'food',
          note: 'weekly shop',
          includeDuplicate: true,
          hintCode: 'transfer.own_account',
        );
        final decoded = roundTrip(accepted, format, ImportRow.new);
        expect(decoded, accepted);
        expect(decoded.amountMinor, Int64(-1250));

        final rejected = roundTrip(
          ImportRow(
            rowNumber: 5,
            status: ImportRowStatus.IMPORT_ROW_STATUS_REJECTED,
            rejectionCode: 'description.unknown_shape',
          ),
          format,
          ImportRow.new,
        );
        // A rejected row has no amount, no date and no text; it must not decode with any.
        expect(rejected.hasAmountMinor(), isFalse);
        expect(rejected.hasTransactionDate(), isFalse);
        expect(rejected.hasDescription(), isFalse);
        expect(rejected.hasCategoryId(), isFalse);
        expect(rejected.rejectionCode, 'description.unknown_shape');
      });

      test('an ImportSession keeps its counts, defaults and committed result', () {
        final original = ImportSession(
          id: 's1',
          formatId: 'erste-pl-csv',
          state: ImportSessionState.IMPORT_SESSION_STATE_COMMITTED,
          accountId: 'acc',
          currency: 'PLN',
          expiresAtMs: Int64(1790086400000),
          acceptedRows: 3,
          duplicateRows: 1,
          rejectedRows: 2,
          committedWritten: 2,
          committedAlreadyImported: 1,
          defaultExpenseCategoryId: 'food',
          defaultIncomeCategoryId: 'salary',
          rows: [ImportRow(rowNumber: 1, status: ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED)],
        );
        final decoded = roundTrip(original, format, ImportSession.new);
        expect(decoded, original);
        // Zero is a real committed result, not an absent one.
        final none = roundTrip(
          ImportSession(committedWritten: 0, committedAlreadyImported: 0),
          format,
          ImportSession.new,
        );
        expect(none.hasCommittedWritten(), isTrue);
        expect(none.committedWritten, 0);
      });

      test('the requests and the row answer survive', () {
        expect(
          roundTrip(
            CreateImportSessionRequest(formatId: 'erste-pl-csv', content: [0, 255, 10, 13], accountId: 'a'),
            format,
            CreateImportSessionRequest.new,
          ).content,
          [0, 255, 10, 13],
        );
        final update = roundTrip(
          UpdateImportRowRequest(categoryId: '', note: '', includeDuplicate: false),
          format,
          UpdateImportRowRequest.new,
        );
        // Present-but-empty and present-but-false are decisions ("clear", "leave out"), not absence.
        expect(update.hasCategoryId(), isTrue);
        expect(update.hasNote(), isTrue);
        expect(update.hasIncludeDuplicate(), isTrue);
        expect(
          roundTrip(UpdateImportRowRequest(note: 'n'), format, UpdateImportRowRequest.new).hasCategoryId(),
          isFalse,
        );
        final answer = roundTrip(
          UpdateImportRowResponse(
            row: ImportRow(rowNumber: 2),
            acceptedRows: 4,
            duplicateRows: 0,
            rejectedRows: 1,
          ),
          format,
          UpdateImportRowResponse.new,
        );
        expect([answer.row.rowNumber, answer.acceptedRows, answer.rejectedRows], [2, 4, 1]);
        expect(
          roundTrip(
            SetImportDefaultsRequest(defaultExpenseCategoryId: 'x'),
            format,
            SetImportDefaultsRequest.new,
          ).hasDefaultIncomeCategoryId(),
          isFalse,
        );
        expect(
          roundTrip(
            CommitImportSessionRequest(confirmedAcceptedRows: 7),
            format,
            CommitImportSessionRequest.new,
          ).confirmedAcceptedRows,
          7,
        );
        expect(
          roundTrip(
            ListImportSessionsResponse(sessions: [ImportSession(id: 'a'), ImportSession(id: 'b')]),
            format,
            ListImportSessionsResponse.new,
          ).sessions.map((s) => s.id),
          ['a', 'b'],
        );
      });
    });
  }
}
