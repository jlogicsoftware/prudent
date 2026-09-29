// PrudentRepository over a fake transport (Phase 3 requirement, docs/prudent-migration-plan.md).
//
// Three shapes, and the point of the suite is that they are DISTINGUISHABLE: a decode failure
// must not read as "the server said nothing" (CLAUDE.md "Nothing swallows a failure" —
// ZenResult.err carries a ZenError; a caller can never mistake it for an empty success).
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/generated/prudent/v1/plans.pb.dart';
import 'package:prudent/generated/prudent/v1/records.pb.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/record/record_filter.dart';
import 'package:zen_transport/zen_transport.dart';

Uri _uriOf(http.Request request) => request.url;

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

    test('an omitted filter hits the bare path, exactly like today', () async {
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedUri = _uriOf(request);
          return _jsonResponse({'records': []});
        }),
      );

      await repository.listRecords();

      expect(capturedUri!.path, '/api/v1/records');
      expect(capturedUri!.query, isEmpty);
    });

    test('RecordFilter.empty hits the bare path, exactly like an omitted filter', () async {
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedUri = _uriOf(request);
          return _jsonResponse({'records': []});
        }),
      );

      await repository.listRecords(filter: RecordFilter.empty);

      expect(capturedUri!.path, '/api/v1/records');
      expect(capturedUri!.query, isEmpty);
    });

    test('a populated filter is sent as query parameters', () async {
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedUri = _uriOf(request);
          return _jsonResponse({'records': []});
        }),
      );

      await repository.listRecords(
        filter: RecordFilter(
          dateFrom: DateTime(2026, 8, 1),
          dateTo: DateTime(2026, 8, 31),
          accountId: 'a1',
          categoryId: 'c1',
          type: RecordFilterType.expense,
          amountMin: Int64(500),
          amountMax: Int64(10000),
          search: 'coffee',
        ),
      );

      expect(capturedUri!.path, '/api/v1/records');
      expect(capturedUri!.queryParameters['dateFrom'], '2026-08-01');
      expect(capturedUri!.queryParameters['dateTo'], '2026-08-31');
      expect(capturedUri!.queryParameters['accountId'], 'a1');
      expect(capturedUri!.queryParameters['categoryId'], 'c1');
      expect(capturedUri!.queryParameters['type'], 'expense');
      expect(capturedUri!.queryParameters['amountMin'], '500');
      expect(capturedUri!.queryParameters['amountMax'], '10000');
      expect(capturedUri!.queryParameters['search'], 'coffee');
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

  group('PrudentRepository.createTransfer', () {
    test('posts the typed request and decodes both legs', () async {
      String? capturedBody;
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedBody = request.body;
          capturedUri = _uriOf(request);
          return _jsonResponse({
            'id': 'transfer-1',
            'fromRecord': {
              'id': 'leg-from',
              'title': 'Transfer',
              'amountMinor': '-5000',
              'currency': 'PLN',
              'date': '2026-08-17',
              'accountId': 'a1',
              'transferId': 'transfer-1',
            },
            'toRecord': {
              'id': 'leg-to',
              'title': 'Transfer',
              'amountMinor': '5000',
              'currency': 'PLN',
              'date': '2026-08-17',
              'accountId': 'a2',
              'transferId': 'transfer-1',
            },
          }, status: 201);
        }),
      );

      final result = await repository.createTransfer(
        CreateTransferRequest(
          fromCurrency: 'PLN',
          toCurrency: 'PLN',
          date: '2026-08-17',
          fromAccountId: 'a1',
          toAccountId: 'a2',
        ),
      );

      expect(capturedUri!.path, '/api/v1/transfers');
      expect(capturedBody, contains('"fromAccountId":"a1"'));
      final transfer = result.fold((t) => t, (e) => throw e);
      expect(transfer.id, 'transfer-1');
      expect(transfer.fromRecord.amountMinor.toInt(), -5000);
      expect(transfer.toRecord.amountMinor.toInt(), 5000);
      expect(transfer.fromRecord.hasCategoryId(), isFalse);
    });

    test('a ZenError response surfaces as ZenResult.err', () async {
      final repository = PrudentRepository(
        client: _clientAnswering(
          (request) => _jsonResponse({
            'code': 'invalid',
            'message': 'A transfer needs two different accounts.',
          }, status: 400),
        ),
      );

      final result = await repository.createTransfer(
        CreateTransferRequest(
          fromCurrency: 'PLN',
          toCurrency: 'PLN',
          date: '2026-08-17',
          fromAccountId: 'a1',
          toAccountId: 'a1',
        ),
      );

      expect(result.isFailure, isTrue);
      result.fold(
        (t) => fail('expected a failure'),
        (error) => expect(error.message, contains('two different accounts')),
      );
    });
  });

  group('PrudentRepository.deleteTransfer', () {
    test('deletes by transfer id', () async {
      Uri? capturedUri;
      String? capturedMethod;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedUri = _uriOf(request);
          capturedMethod = request.method;
          return http.Response('', 204, headers: {'X-Zen-Transport': 'json'});
        }),
      );

      final result = await repository.deleteTransfer('transfer-1');

      expect(capturedMethod, 'DELETE');
      expect(capturedUri!.path, '/api/v1/transfers/transfer-1');
      expect(result.isSuccess, isTrue);
    });
  });

  group('PrudentRepository plans', () {
    test('createPlan posts the typed request and decodes the recurrence', () async {
      String? capturedBody;
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedBody = request.body;
          capturedUri = _uriOf(request);
          return _jsonResponse({
            'id': 'plan-1',
            'title': 'Rent',
            'amountMinor': '-250000',
            'currency': 'PLN',
            'accountId': 'a1',
            'categoryId': 'c1',
            'recurrence': {
              'frequency': 'RECURRENCE_FREQUENCY_MONTHLY',
              'interval': 1,
              'startDate': '2026-10-31',
              'timeZone': 'Europe/Warsaw',
              'occurrenceCount': 12,
            },
          }, status: 201);
        }),
      );

      final result = await repository.createPlan(
        CreatePlanRequest(
          title: 'Rent',
          amountMinor: Int64(-250000),
          currency: 'PLN',
          accountId: 'a1',
          categoryId: 'c1',
          recurrence: Recurrence(
            frequency: RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY,
            interval: 1,
            startDate: '2026-10-31',
            timeZone: 'Europe/Warsaw',
            occurrenceCount: 12,
          ),
        ),
      );

      expect(capturedUri!.path, '/api/v1/plans');
      expect(capturedBody, contains('"timeZone":"Europe/Warsaw"'));
      final plan = result.fold((p) => p, (e) => throw e);
      expect(plan.id, 'plan-1');
      expect(plan.amountMinor.toInt(), -250000);
      expect(plan.recurrence.frequency, RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY);
      expect(plan.recurrence.whichEnd(), Recurrence_End.occurrenceCount);
      expect(plan.recurrence.occurrenceCount, 12);
    });

    test('listPlans decodes the list, and deletePlan deletes by id', () async {
      final calls = <String>[];
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          calls.add('${request.method} ${_uriOf(request).path}');
          if (request.method == 'DELETE') {
            return http.Response('', 204, headers: {'X-Zen-Transport': 'json'});
          }
          return _jsonResponse({
            'plans': [
              {
                'id': 'plan-1',
                'title': 'Salary',
                'amountMinor': '800000',
                'currency': 'PLN',
                'accountId': 'a1',
                'categoryId': 'c1',
                'recurrence': {
                  'frequency': 'RECURRENCE_FREQUENCY_ONCE',
                  'interval': 1,
                  'startDate': '2026-10-10',
                  'timeZone': 'Europe/Warsaw',
                },
              },
            ],
          });
        }),
      );

      final listed = await repository.listPlans();
      final plans = listed.fold((r) => r.plans, (e) => throw e);
      expect(plans.single.recurrence.whichEnd(), Recurrence_End.notSet);

      final deleted = await repository.deletePlan('plan-1');
      expect(deleted.isSuccess, isTrue);
      expect(calls, ['GET /api/v1/plans', 'DELETE /api/v1/plans/plan-1']);
    });
  });

  group('PrudentRepository occurrences', () {
    Map<String, Object?> occurrence(String status) => {
      'id': 'occ-1',
      'planId': 'plan-1',
      'occurrenceDate': '2026-10-10',
      'status': status,
      'title': 'Rent',
      'amountMinor': '-250000',
      'currency': 'PLN',
      'accountId': 'a1',
      'categoryId': 'c1',
    };

    test('listUpcomingOccurrences sends days only when given, and decodes every state', () async {
      final uris = <Uri>[];
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          uris.add(_uriOf(request));
          return _jsonResponse({
            'occurrences': [
              occurrence('OCCURRENCE_STATUS_PLANNED'),
              occurrence('OCCURRENCE_STATUS_COMPLETED'),
              occurrence('OCCURRENCE_STATUS_SKIPPED'),
            ],
          });
        }),
      );

      final defaulted = await repository.listUpcomingOccurrences();
      final bounded = await repository.listUpcomingOccurrences(days: 60);

      expect(uris[0].path, '/api/v1/occurrences/upcoming');
      expect(uris[0].hasQuery, isFalse);
      expect(uris[1].queryParameters['days'], '60');
      final decoded = defaulted.fold((r) => r.occurrences, (e) => throw e);
      expect(decoded.map((o) => o.status), [
        OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
        OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED,
        OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED,
      ]);
      expect(decoded.first.amountMinor.toInt(), -250000);
      expect(decoded.first.occurrenceDate, '2026-10-10');
      expect(bounded.isSuccess, isTrue);
    });

    test('listOverdueOccurrences decodes the derived OVERDUE status', () async {
      Uri? uri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          uri = _uriOf(request);
          return _jsonResponse({
            'occurrences': [occurrence('OCCURRENCE_STATUS_OVERDUE')],
          });
        }),
      );

      final result = await repository.listOverdueOccurrences();

      expect(uri!.path, '/api/v1/occurrences/overdue');
      expect(
        result.fold((r) => r.occurrences.single.status, (e) => throw e),
        OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE,
      );
    });

    test('skip and restore POST to the occurrence and decode the updated state', () async {
      final calls = <String>[];
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          calls.add('${request.method} ${_uriOf(request).path}');
          return _jsonResponse(occurrence('OCCURRENCE_STATUS_SKIPPED'));
        }),
      );

      final skipped = await repository.skipOccurrence('occ-1');
      final restored = await repository.restoreOccurrence('occ-1');

      expect(calls, [
        'POST /api/v1/occurrences/occ-1/skip',
        'POST /api/v1/occurrences/occ-1/restore',
      ]);
      expect(
        skipped.fold((o) => o.status, (e) => throw e),
        OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED,
      );
      expect(restored.isSuccess, isTrue);
    });

    test('a refused transition surfaces the conflict rather than a decoded occurrence', () async {
      final repository = PrudentRepository(
        client: _clientAnswering(
          (request) => _jsonResponse({
            'code': 'conflict',
            'message': 'An occurrence that is COMPLETED cannot become SKIPPED.',
          }, status: 409),
        ),
      );

      final result = await repository.skipOccurrence('occ-1');

      expect(result.isFailure, isTrue);
    });
  });

  group('PrudentRepository.spendByCategory', () {
    test('sends currency and year as query parameters, and decodes the response', () async {
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedUri = _uriOf(request);
          return _jsonResponse({
            'currency': 'PLN',
            'items': [
              {'categoryId': 'c1', 'amountMinor': '3500'},
            ],
          });
        }),
      );

      final result = await repository.spendByCategory(currency: 'PLN', year: 2026, month: 8);

      expect(capturedUri!.path, '/api/v1/analytics/spend-by-category');
      expect(capturedUri!.queryParameters['currency'], 'PLN');
      expect(capturedUri!.queryParameters['year'], '2026');
      expect(capturedUri!.queryParameters['month'], '8');
      final response = result.fold((r) => r, (e) => throw e);
      expect(response.items.single.amountMinor.toInt(), 3500);
    });

    test('month is omitted from the query when null — the whole-year scope', () async {
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedUri = _uriOf(request);
          return _jsonResponse({'currency': 'PLN', 'items': []});
        }),
      );

      await repository.spendByCategory(currency: 'PLN', year: 2026);

      expect(capturedUri!.queryParameters.containsKey('month'), isFalse);
    });

    test('the empty case decodes as an empty list, not a failure', () async {
      final repository = PrudentRepository(
        client: _clientAnswering((request) => _jsonResponse({'currency': 'PLN', 'items': []})),
      );

      final result = await repository.spendByCategory(currency: 'PLN', year: 2026);

      expect(result.isSuccess, isTrue);
      expect(result.fold((r) => r.items, (e) => throw e), isEmpty);
    });
  });

  group('PrudentRepository.spendByPeriod', () {
    test('sends granularity and count as query parameters, and decodes the response', () async {
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedUri = _uriOf(request);
          return _jsonResponse({
            'currency': 'PLN',
            'granularity': 'GRANULARITY_MONTH',
            'periods': [
              {'period': '2026-08', 'amountMinor': '1000'},
            ],
          });
        }),
      );

      final result = await repository.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 12);

      expect(capturedUri!.queryParameters['granularity'], 'MONTH');
      expect(capturedUri!.queryParameters['count'], '12');
      final response = result.fold((r) => r, (e) => throw e);
      expect(response.periods.single.period, '2026-08');
    });
  });
}
