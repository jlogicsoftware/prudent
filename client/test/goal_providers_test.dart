// Free money is eligible account balances less the envelopes (ADR-051), and progress is a sum over
// the envelope history (ADR-052) — both calculated by the server on each read. So anything that
// moves a balance, changes which accounts are eligible, or writes a history entry must make the
// next read ask again; a stale figure would be wrong with no error to show for it.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/generated/prudent/v1/goal_allocations.pb.dart';
import 'package:prudent/generated/prudent/v1/records.pb.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/providers.dart';
import 'package:zen_transport/zen_transport.dart';

void main() {
  late List<String> calls;
  String? progressAsOf;
  late ProviderContainer container;

  setUp(() {
    calls = [];
    final client = ZenClient(
      baseUrl: 'https://example.test',
      format: ZenTransportFormat.json,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        calls.add('${request.method} $path');
        if (path == '/api/v1/goals/progress') progressAsOf = request.url.queryParameters['asOf'];
        const headers = {'X-Zen-Transport': 'json'};
        http.Response json(Object body) => http.Response(jsonEncode(body), 200, headers: headers);
        if (request.method == 'GET') {
          return switch (path) {
            '/api/v1/goal-allocations/free-money' => json({'currencies': []}),
            '/api/v1/goals/progress' => json({'goals': []}),
            '/api/v1/goals' => json({'goals': []}),
            '/api/v1/accounts' => json({'accounts': []}),
            _ => json({'records': []}),
          };
        }
        if (path == '/api/v1/goal-allocations') {
          return json({'id': 'e1', 'kind': 'GOAL_ALLOCATION_KIND_ALLOCATE', 'amountMinor': '100'});
        }
        if (path == '/api/v1/accounts') return json({'id': 'a1', 'name': 'Bank'});
        return json({'id': 'r1', 'title': 'Coffee', 'amountMinor': '-450', 'currency': 'PLN'});
      }),
    );
    container = ProviderContainer(
      overrides: [
        prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client)),
        goalProgressAsOfProvider.overrideWithValue('2026-10-02'),
      ],
    );
    addTearDown(container.dispose);
  });

  int reads(String path) => calls.where((c) => c == 'GET $path').length;

  test('free money is asked for again after a record or an account changes', () async {
    final subscription = container.listen(goalFreeMoneyProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(goalFreeMoneyProvider.future);
    expect(reads('/api/v1/goal-allocations/free-money'), 1);

    await container.read(recordsProvider.notifier).addRecord(CreateRecordRequest(title: 'Coffee'));
    await container.read(goalFreeMoneyProvider.future);
    expect(reads('/api/v1/goal-allocations/free-money'), 2);

    await container.read(accountsProvider.future);
    await container.read(accountsProvider.notifier).addAccount(CreateAccountRequest(name: 'Bank'));
    await container.read(goalFreeMoneyProvider.future);
    expect(reads('/api/v1/goal-allocations/free-money'), 3);
  });

  test('progress and free money are asked for again after an allocation', () async {
    final progress = container.listen(goalProgressProvider, (_, _) {});
    final free = container.listen(goalFreeMoneyProvider, (_, _) {});
    addTearDown(progress.close);
    addTearDown(free.close);
    await container.read(goalProgressProvider.future);
    await container.read(goalFreeMoneyProvider.future);

    await container.read(goalsProvider.future);
    await container
        .read(goalsProvider.notifier)
        .recordAllocation(
          CreateGoalAllocationRequest(
            kind: GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE,
            targetGoalId: 'g1',
          ),
        );
    await container.read(goalProgressProvider.future);
    await container.read(goalFreeMoneyProvider.future);

    expect(reads('/api/v1/goals/progress'), 2);
    expect(reads('/api/v1/goal-allocations/free-money'), 2);
  });

  test('progress is asked for with the client\'s own date', () async {
    await container.read(goalProgressProvider.future);
    expect(progressAsOf, '2026-10-02');
  });
}
