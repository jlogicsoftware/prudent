// PrudentRepository over a fake transport (Phase 3 requirement, docs/prudent-migration-plan.md).
//
// Three shapes, and the point of the suite is that they are DISTINGUISHABLE: a decode failure
// must not read as "the server said nothing" (CLAUDE.md "Nothing swallows a failure" —
// ZenResult.err carries a ZenError; a caller can never mistake it for an empty success).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/src/generated/prudent/v1/records.pb.dart';
import 'package:prudent/src/prudent_repository.dart';
import 'package:zen_transport/zen_transport.dart';

ZenClient _clientAnswering(http.Response Function(http.Request) respond) => ZenClient(
  baseUrl: 'https://example.test',
  format: ZenTransportFormat.json,
  httpClient: MockClient((request) async => respond(request)),
);

http.Response _jsonResponse(Map<String, dynamic> body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'X-Zen-Transport': 'json'},
);

void main() {
  group('PrudentRepository.listRecords', () {
    test('success decodes the real records', () async {
      final repository = PrudentRepository(
        client: _clientAnswering(
          (request) => _jsonResponse({
            'records': [
              {
                'id': 'r1',
                'title': 'Coffee',
                'amountMinor': '450',
                'currency': 'PLN',
                'date': '2026-08-17',
                'categoryId': 'c1',
                'accountId': 'a1',
              },
            ],
          }),
        ),
      );

      final result = await repository.listRecords();

      expect(result.isSuccess, isTrue);
      final records = result.fold((r) => r.records, (e) => throw e);
      expect(records, hasLength(1));
      expect(records.single.title, 'Coffee');
      expect(records.single.amountMinor.toInt(), 450);
    });

    test('a ZenError response surfaces as ZenResult.err, not an empty list', () async {
      final repository = PrudentRepository(
        client: _clientAnswering(
          (request) => _jsonResponse({
            'code': 'unauthorized',
            'message': 'no session',
          }, status: 401),
        ),
      );

      final result = await repository.listRecords();

      expect(result.isFailure, isTrue);
      result.fold(
        (r) => fail('expected a failure, got success with ${r.records.length} records'),
        (error) => expect(error.message, contains('no session')),
      );
    });

    test('a decode failure is distinguishable from an empty result', () async {
      final repository = PrudentRepository(
        client: _clientAnswering(
          (request) => http.Response(
            'not valid json at all {{{',
            200,
            headers: {'X-Zen-Transport': 'json'},
          ),
        ),
      );

      final result = await repository.listRecords();

      // A decode failure is a ZenResult.err — never a ZenResult.ok with an empty list, which
      // would be indistinguishable from "the user genuinely has no records".
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, isNotNull);
    });
  });

  group('PrudentRepository.createRecord', () {
    test('posts the typed request and decodes the created record', () async {
      String? capturedBody;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedBody = request.body;
          return _jsonResponse({
            'id': 'server-minted-id',
            'title': 'Lunch',
            'amountMinor': '1200',
            'currency': 'PLN',
            'date': '2026-08-17',
            'categoryId': 'c1',
            'accountId': 'a1',
          }, status: 201);
        }),
      );

      final result = await repository.createRecord(
        CreateRecordRequest(
          title: 'Lunch',
          date: '2026-08-17',
          categoryId: 'c1',
          accountId: 'a1',
          currency: 'PLN',
        ),
      );

      expect(capturedBody, contains('"title":"Lunch"'));
      final record = result.fold((r) => r, (e) => throw e);
      // Server-minted, not client-chosen — the create request above carried no id.
      expect(record.id, 'server-minted-id');
    });
  });
}
