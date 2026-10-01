// A budget's actual is net spending from ledger records (ADR-044), so a change to a record must
// make the next read of the summary ask the server again — a stale "actual" would be wrong
// without any error to show for it.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/generated/prudent/v1/records.pb.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/providers.dart';
import 'package:zen_transport/zen_transport.dart';

const _params = BudgetSummaryParams(month: '2026-10', currency: 'PLN');

void main() {
  late List<String> calls;
  late ProviderContainer container;

  setUp(() {
    calls = [];
    final client = ZenClient(
      baseUrl: 'https://example.test',
      format: ZenTransportFormat.json,
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        const headers = {'X-Zen-Transport': 'json'};
        if (request.method == 'DELETE') return http.Response('', 204, headers: headers);
        if (request.url.path == '/api/v1/budgets/summary') {
          return http.Response(
            jsonEncode({'month': '2026-10', 'currency': 'PLN'}),
            200,
            headers: headers,
          );
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/records') {
          return http.Response(jsonEncode({'records': []}), 200, headers: headers);
        }
        // createRecord / updateRecord answer the record.
        return http.Response(
          jsonEncode({'id': 'r1', 'title': 'Coffee', 'amountMinor': '-450', 'currency': 'PLN'}),
          200,
          headers: headers,
        );
      }),
    );
    container = ProviderContainer(
      overrides: [prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client))],
    );
    addTearDown(container.dispose);
  });

  int summaryReads() => calls.where((c) => c == 'GET /api/v1/budgets/summary').length;

  Future<void> readSummary() async {
    await container.read(budgetSummaryProvider(_params).future);
  }

  test('is fetched once and served from cache while it is being watched', () async {
    final subscription = container.listen(budgetSummaryProvider(_params), (_, _) {});
    addTearDown(subscription.close);

    await readSummary();
    await readSummary();

    expect(summaryReads(), 1);
  });

  test('is fetched again after a record is added, edited or removed', () async {
    final subscription = container.listen(budgetSummaryProvider(_params), (_, _) {});
    addTearDown(subscription.close);
    final records = container.read(recordsProvider.notifier);
    await readSummary();
    expect(summaryReads(), 1);

    await records.addRecord(CreateRecordRequest(title: 'Coffee'));
    await readSummary();
    expect(summaryReads(), 2);

    await records.editRecord('r1', UpdateRecordRequest(title: 'Coffee'));
    await readSummary();
    expect(summaryReads(), 3);

    await records.removeRecord('r1');
    await readSummary();
    expect(summaryReads(), 4);
  });
}
