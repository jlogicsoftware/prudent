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
import 'package:prudent/generated/prudent/v1/budgets.pb.dart';
import 'package:prudent/generated/prudent/v1/goal_allocations.pb.dart';
import 'package:prudent/generated/prudent/v1/goals.pb.dart';
import 'package:prudent/generated/prudent/v1/plans.pb.dart';
import 'package:prudent/generated/prudent/v1/records.pb.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/record/record_filter.dart';
import 'package:zen_transport/zen_transport.dart';

Uri _uriOf(http.Request request) => request.url;

ZenClient _clientAnswering(http.Response Function(http.Request) respond) =>
    ZenClient(
      baseUrl: 'https://example.test',
      format: ZenTransportFormat.json,
      httpClient: MockClient((request) async => respond(request)),
    );

http.Response _jsonResponse(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(
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

    test(
      'a ZenError response surfaces as ZenResult.err, not an empty list',
      () async {
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
          (r) => fail(
            'expected a failure, got success with ${r.records.length} records',
          ),
          (error) => expect(error.message, contains('no session')),
        );
      },
    );

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

    test(
      'RecordFilter.empty hits the bare path, exactly like an omitted filter',
      () async {
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
      },
    );

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
    test(
      'createPlan posts the typed request and decodes the recurrence',
      () async {
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
        expect(
          plan.recurrence.frequency,
          RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY,
        );
        expect(plan.recurrence.whichEnd(), Recurrence_End.occurrenceCount);
        expect(plan.recurrence.occurrenceCount, 12);
      },
    );

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

  group('PrudentRepository budgets', () {
    test(
      'setBudget puts the amount at the slot address and decodes the budget',
      () async {
        String? capturedBody;
        String? capturedMethod;
        Uri? capturedUri;
        final repository = PrudentRepository(
          client: _clientAnswering((request) {
            capturedBody = request.body;
            capturedMethod = request.method;
            capturedUri = _uriOf(request);
            return _jsonResponse({
              'categoryId': 'c1',
              'month': '2026-10',
              'currency': 'PLN',
              'amountMinor': '80000',
            }, status: 201);
          }),
        );

        final result = await repository.setBudget(
          categoryId: 'c1',
          month: '2026-10',
          currency: 'PLN',
          request: SetBudgetRequest(amountMinor: Int64(80000)),
        );

        expect(capturedMethod, 'PUT');
        expect(capturedUri!.path, '/api/v1/budgets/c1/2026-10/PLN');
        expect(capturedBody, contains('"amountMinor":"80000"'));
        final budget = result.fold((b) => b, (e) => throw e);
        expect(budget.categoryId, 'c1');
        expect(budget.month, '2026-10');
        expect(budget.currency, 'PLN');
        expect(budget.amountMinor.toInt(), 80000);
      },
    );

    test(
      'listBudgets sends only the filters given, and deleteBudget deletes the slot',
      () async {
        final calls = <String>[];
        final repository = PrudentRepository(
          client: _clientAnswering((request) {
            calls.add('${request.method} ${_uriOf(request)}');
            if (request.method == 'DELETE') {
              return http.Response(
                '',
                204,
                headers: {'X-Zen-Transport': 'json'},
              );
            }
            return _jsonResponse({
              'budgets': [
                {
                  'categoryId': 'c1',
                  'month': '2026-10',
                  'currency': 'PLN',
                  'amountMinor': '80000',
                },
              ],
            });
          }),
        );

        final all = await repository.listBudgets();
        expect(
          all.fold((r) => r.budgets, (e) => throw e).single.amountMinor.toInt(),
          80000,
        );
        await repository.listBudgets(month: '2026-10');
        await repository.listBudgets(month: '2026-10', categoryId: 'c1');
        final deleted = await repository.deleteBudget(
          categoryId: 'c1',
          month: '2026-10',
          currency: 'PLN',
        );

        expect(deleted.isSuccess, isTrue);
        expect(calls, [
          'GET https://example.test/api/v1/budgets',
          'GET https://example.test/api/v1/budgets?month=2026-10',
          'GET https://example.test/api/v1/budgets?month=2026-10&categoryId=c1',
          'DELETE https://example.test/api/v1/budgets/c1/2026-10/PLN',
        ]);
      },
    );
  });

  group('PrudentRepository goals', () {
    Map<String, Object?> goal({String status = 'GOAL_STATUS_ACTIVE'}) => {
      'id': 'g1',
      'name': 'Holiday',
      'currency': 'PLN',
      'targetAmountMinor': '500000',
      'targetDate': '2027-06-30',
      'status': status,
      'createdAtMs': '1790000000000',
      'statusChangedAtMs': '1790000000000',
    };

    test('createGoal posts the request and decodes the goal', () async {
      String? capturedBody;
      String? capturedMethod;
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedBody = request.body;
          capturedMethod = request.method;
          capturedUri = _uriOf(request);
          return _jsonResponse(goal(), status: 201);
        }),
      );

      final result = await repository.createGoal(
        CreateGoalRequest(
          name: 'Holiday',
          currency: 'PLN',
          targetAmountMinor: Int64(500000),
          targetDate: '2027-06-30',
        ),
      );

      expect(capturedMethod, 'POST');
      expect(capturedUri!.path, '/api/v1/goals');
      expect(capturedBody, contains('"targetAmountMinor":"500000"'));
      expect(capturedBody, contains('"targetDate":"2027-06-30"'));
      final created = result.fold((g) => g, (e) => throw e);
      expect(created.id, 'g1');
      expect(created.targetAmountMinor.toInt(), 500000);
      expect(created.hasTargetDate(), isTrue);
      expect(created.status, GoalStatus.GOAL_STATUS_ACTIVE);
    });

    test('a goal without a date decodes with no date', () async {
      final repository = PrudentRepository(
        client: _clientAnswering(
          (request) => _jsonResponse(goal()..remove('targetDate')),
        ),
      );

      final result = await repository.getGoal('g1');

      expect(result.fold((g) => g.hasTargetDate(), (e) => throw e), isFalse);
    });

    test('updateGoal puts to the goal address', () async {
      String? capturedMethod;
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedMethod = request.method;
          capturedUri = _uriOf(request);
          return _jsonResponse(goal());
        }),
      );

      final result = await repository.updateGoal(
        'g1',
        UpdateGoalRequest(name: 'Holiday', targetAmountMinor: Int64(500000)),
      );

      expect(result.isSuccess, isTrue);
      expect(capturedMethod, 'PUT');
      expect(capturedUri!.path, '/api/v1/goals/g1');
    });

    test('listGoals sends the status filter only when one is given', () async {
      final calls = <String>[];
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          calls.add('${request.method} ${_uriOf(request)}');
          return _jsonResponse({
            'goals': [goal()],
          });
        }),
      );

      final all = await repository.listGoals();
      expect(all.fold((r) => r.goals, (e) => throw e).single.name, 'Holiday');
      await repository.listGoals(status: GoalStatus.GOAL_STATUS_ACTIVE);
      await repository.listGoals(status: GoalStatus.GOAL_STATUS_COMPLETED);
      await repository.listGoals(status: GoalStatus.GOAL_STATUS_ARCHIVED);

      expect(calls, [
        'GET https://example.test/api/v1/goals',
        'GET https://example.test/api/v1/goals?status=ACTIVE',
        'GET https://example.test/api/v1/goals?status=COMPLETED',
        'GET https://example.test/api/v1/goals?status=ARCHIVED',
      ]);
    });

    test('listGoals refuses a status the server cannot filter by', () {
      final repository = PrudentRepository(
        client: _clientAnswering((request) => _jsonResponse({})),
      );

      expect(
        () => repository.listGoals(status: GoalStatus.GOAL_STATUS_UNSPECIFIED),
        throwsArgumentError,
      );
    });

    test('each lifecycle call posts to its own route', () async {
      final calls = <String>[];
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          calls.add('${request.method} ${_uriOf(request).path}');
          return _jsonResponse(goal(status: 'GOAL_STATUS_ARCHIVED'));
        }),
      );

      final archived = await repository.archiveGoal('g1');
      await repository.completeGoal('g1');
      await repository.reactivateGoal('g1');

      expect(
        archived.fold((g) => g.status, (e) => throw e),
        GoalStatus.GOAL_STATUS_ARCHIVED,
      );
      expect(calls, [
        'POST /api/v1/goals/g1/archive',
        'POST /api/v1/goals/g1/complete',
        'POST /api/v1/goals/g1/reactivate',
      ]);
    });

    test('a refused transition is an error the caller can render', () async {
      final repository = PrudentRepository(
        client: _clientAnswering(
          (request) => _jsonResponse({
            'code': 'conflict',
            'message': 'A goal that is ACTIVE cannot be made ACTIVE.',
          }, status: 409),
        ),
      );

      final result = await repository.reactivateGoal('g1');

      expect(result.isSuccess, isFalse);
    });
  });

  group('PrudentRepository goal envelopes', () {
    Map<String, Object?> entry({
      String kind = 'GOAL_ALLOCATION_KIND_ALLOCATE',
    }) => {
      'id': 'a1',
      'kind': kind,
      if (kind != 'GOAL_ALLOCATION_KIND_ALLOCATE') 'sourceGoalId': 'g1',
      if (kind != 'GOAL_ALLOCATION_KIND_WITHDRAW') 'targetGoalId': 'g2',
      'currency': 'PLN',
      'amountMinor': '25000',
      'note': 'First month',
      'createdAtMs': '1790000000000',
      'createdBy': 'u1',
    };

    test('createGoalAllocation posts the entry and decodes it', () async {
      String? capturedBody;
      String? capturedMethod;
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedBody = request.body;
          capturedMethod = request.method;
          capturedUri = _uriOf(request);
          return _jsonResponse(entry(), status: 201);
        }),
      );

      final result = await repository.createGoalAllocation(
        CreateGoalAllocationRequest(
          kind: GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE,
          targetGoalId: 'g2',
          amountMinor: Int64(25000),
          note: 'First month',
        ),
      );

      expect(capturedMethod, 'POST');
      expect(capturedUri!.path, '/api/v1/goal-allocations');
      expect(capturedBody, contains('"kind":"GOAL_ALLOCATION_KIND_ALLOCATE"'));
      expect(capturedBody, contains('"targetGoalId":"g2"'));
      expect(capturedBody, contains('"amountMinor":"25000"'));
      expect(capturedBody, isNot(contains('sourceGoalId')));
      final created = result.fold((r) => r, (e) => throw e);
      expect(created.id, 'a1');
      expect(created.kind, GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE);
      expect(created.hasSourceGoalId(), isFalse);
      expect(created.targetGoalId, 'g2');
      expect(created.amountMinor.toInt(), 25000);
      expect(created.createdBy, 'u1');
    });

    test('a move carries both goals', () async {
      String? capturedBody;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedBody = request.body;
          return _jsonResponse(
            entry(kind: 'GOAL_ALLOCATION_KIND_MOVE'),
            status: 201,
          );
        }),
      );

      final result = await repository.createGoalAllocation(
        CreateGoalAllocationRequest(
          kind: GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE,
          sourceGoalId: 'g1',
          targetGoalId: 'g2',
          amountMinor: Int64(25000),
        ),
      );

      expect(capturedBody, contains('"sourceGoalId":"g1"'));
      expect(capturedBody, contains('"targetGoalId":"g2"'));
      final moved = result.fold((r) => r, (e) => throw e);
      expect(moved.sourceGoalId, 'g1');
      expect(moved.targetGoalId, 'g2');
    });

    test('an overdrawn withdrawal is an error the caller can render', () async {
      final repository = PrudentRepository(
        client: _clientAnswering(
          (request) => _jsonResponse({
            'code': 'conflict',
            'message':
                "This goal's envelope holds less than the amount requested.",
          }, status: 409),
        ),
      );

      final result = await repository.createGoalAllocation(
        CreateGoalAllocationRequest(
          kind: GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW,
          sourceGoalId: 'g1',
          amountMinor: Int64(1),
        ),
      );

      expect(result.isSuccess, isFalse);
    });

    test(
      'listGoalAllocations sends the goal filter only when one is given',
      () async {
        final calls = <String>[];
        final repository = PrudentRepository(
          client: _clientAnswering((request) {
            calls.add('${request.method} ${_uriOf(request)}');
            return _jsonResponse({
              'allocations': [entry()],
            });
          }),
        );

        final all = await repository.listGoalAllocations();
        expect(all.fold((r) => r.allocations, (e) => throw e).single.id, 'a1');
        await repository.listGoalAllocations(goalId: 'g2');

        expect(calls, [
          'GET https://example.test/api/v1/goal-allocations',
          'GET https://example.test/api/v1/goal-allocations?goalId=g2',
        ]);
      },
    );

    test('getGoalAllocation reads one entry', () async {
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedUri = _uriOf(request);
          return _jsonResponse(entry());
        }),
      );

      final result = await repository.getGoalAllocation('a1');

      expect(capturedUri!.path, '/api/v1/goal-allocations/a1');
      expect(result.fold((r) => r.note, (e) => throw e), 'First month');
    });

    test('listGoalEnvelopes decodes one envelope per goal', () async {
      Uri? capturedUri;
      final repository = PrudentRepository(
        client: _clientAnswering((request) {
          capturedUri = _uriOf(request);
          return _jsonResponse({
            'envelopes': [
              {'goalId': 'g1', 'currency': 'PLN', 'amountMinor': '25000'},
              {'goalId': 'g2', 'currency': 'EUR', 'amountMinor': '0'},
            ],
          });
        }),
      );

      final result = await repository.listGoalEnvelopes();

      expect(capturedUri!.path, '/api/v1/goal-allocations/envelopes');
      final envelopes = result.fold((r) => r.envelopes, (e) => throw e);
      expect(envelopes.map((e) => e.goalId), ['g1', 'g2']);
      expect(envelopes.map((e) => e.currency), ['PLN', 'EUR']);
      expect(envelopes.map((e) => e.amountMinor.toInt()), [25000, 0]);
    });
  });

  group('PrudentRepository budget carry-over resets', () {
    Map<String, Object?> entry({bool revoked = false}) => {
      'id': 'r1',
      'categoryId': 'c1',
      'month': '2026-10',
      'currency': 'PLN',
      'discardedMinor': '-5000',
      'note': 'Fresh start',
      'createdBy': 'u1',
      'createdAtMs': '1790000000000',
      if (revoked) 'revokedBy': 'u1',
      if (revoked) 'revokedAtMs': '1790000100000',
    };

    test(
      'resetBudgetCarryOver posts the slot and decodes the audit entry',
      () async {
        String? capturedBody;
        String? capturedMethod;
        Uri? capturedUri;
        final repository = PrudentRepository(
          client: _clientAnswering((request) {
            capturedBody = request.body;
            capturedMethod = request.method;
            capturedUri = _uriOf(request);
            return _jsonResponse(entry(), status: 201);
          }),
        );

        final result = await repository.resetBudgetCarryOver(
          ResetBudgetCarryOverRequest(
            categoryId: 'c1',
            month: '2026-10',
            currency: 'PLN',
            note: 'Fresh start',
          ),
        );

        expect(capturedMethod, 'POST');
        expect(capturedUri!.path, '/api/v1/budget-carry-over-resets');
        expect(capturedBody, contains('"categoryId":"c1"'));
        expect(capturedBody, contains('"month":"2026-10"'));
        expect(capturedBody, contains('"note":"Fresh start"'));
        final reset = result.fold((r) => r, (e) => throw e);
        expect(reset.id, 'r1');
        expect(reset.discardedMinor.toInt(), -5000);
        expect(reset.createdBy, 'u1');
        expect(reset.createdAtMs.toInt(), 1790000000000);
        expect(reset.revokedBy, isEmpty);
      },
    );

    test(
      'the history sends only the filters given and decodes revoked entries',
      () async {
        final calls = <String>[];
        final repository = PrudentRepository(
          client: _clientAnswering((request) {
            calls.add('${request.method} ${_uriOf(request)}');
            return _jsonResponse({
              'resets': [entry(revoked: true)],
            });
          }),
        );

        final all = await repository.listBudgetCarryOverResets();
        await repository.listBudgetCarryOverResets(categoryId: 'c1');
        await repository.listBudgetCarryOverResets(
          categoryId: 'c1',
          currency: 'PLN',
        );

        final reset = all.fold((r) => r.resets, (e) => throw e).single;
        expect(reset.revokedBy, 'u1');
        expect(reset.revokedAtMs.toInt(), 1790000100000);
        expect(calls, [
          'GET https://example.test/api/v1/budget-carry-over-resets',
          'GET https://example.test/api/v1/budget-carry-over-resets?categoryId=c1',
          'GET https://example.test/api/v1/budget-carry-over-resets?categoryId=c1&currency=PLN',
        ]);
      },
    );

    test(
      'archiveCategory and restoreCategory post to the category and decode the flag',
      () async {
        final calls = <String>[];
        final repository = PrudentRepository(
          client: _clientAnswering((request) {
            calls.add('${request.method} ${_uriOf(request).path}');
            return _jsonResponse({
              'id': 'c1',
              'title': 'Food',
              'archived': request.url.path.endsWith('/archive'),
            });
          }),
        );

        final archived = await repository.archiveCategory('c1');
        final restored = await repository.restoreCategory('c1');

        expect(calls, [
          'POST /api/v1/categories/c1/archive',
          'POST /api/v1/categories/c1/restore',
        ]);
        expect(archived.fold((c) => c.archived, (e) => throw e), isTrue);
        expect(restored.fold((c) => c.archived, (e) => throw e), isFalse);
      },
    );

    test(
      'revokeBudgetCarryOverReset posts to the entry and decodes who revoked it',
      () async {
        String? capturedMethod;
        Uri? capturedUri;
        final repository = PrudentRepository(
          client: _clientAnswering((request) {
            capturedMethod = request.method;
            capturedUri = _uriOf(request);
            return _jsonResponse(entry(revoked: true));
          }),
        );

        final result = await repository.revokeBudgetCarryOverReset('r1');

        expect(capturedMethod, 'POST');
        expect(capturedUri!.path, '/api/v1/budget-carry-over-resets/r1/revoke');
        expect(result.fold((r) => r.revokedBy, (e) => throw e), 'u1');
      },
    );

    test(
      'a summary item decodes the reset month that bounds its carry-over',
      () async {
        final repository = PrudentRepository(
          client: _clientAnswering(
            (request) => _jsonResponse({
              'month': '2026-10',
              'currency': 'PLN',
              'items': [
                {
                  'categoryId': 'c1',
                  'planMinor': '80000',
                  'actualMinor': '0',
                  'carryOverMinor': '0',
                  'remainingMinor': '80000',
                  'carryOverResetMonth': '2026-10',
                },
              ],
            }),
          ),
        );

        final summary = (await repository.getBudgetSummary(
          month: '2026-10',
          currency: 'PLN',
        )).fold((r) => r, (e) => throw e);

        expect(summary.items.single.carryOverResetMonth, '2026-10');
      },
    );
  });

  group('PrudentRepository budget summary', () {
    test(
      'getBudgetSummary asks for one month in one currency and decodes every amount',
      () async {
        Uri? capturedUri;
        final repository = PrudentRepository(
          client: _clientAnswering((request) {
            capturedUri = _uriOf(request);
            return _jsonResponse({
              'month': '2026-10',
              'currency': 'PLN',
              'items': [
                {
                  'categoryId': 'c1',
                  'planMinor': '80000',
                  'actualMinor': '95000',
                  'carryOverMinor': '-5000',
                  'remainingMinor': '-20000',
                },
              ],
              'totalPlanMinor': '80000',
              'totalActualMinor': '95000',
              'totalCarryOverMinor': '-5000',
              'totalRemainingMinor': '-20000',
            });
          }),
        );

        final result = await repository.getBudgetSummary(
          month: '2026-10',
          currency: 'PLN',
        );

        expect(capturedUri!.path, '/api/v1/budgets/summary');
        expect(capturedUri!.queryParameters, {
          'month': '2026-10',
          'currency': 'PLN',
        });
        final summary = result.fold((r) => r, (e) => throw e);
        expect(summary.month, '2026-10');
        expect(summary.currency, 'PLN');
        final item = summary.items.single;
        expect(item.categoryId, 'c1');
        expect(item.planMinor.toInt(), 80000);
        expect(item.actualMinor.toInt(), 95000);
        expect(item.carryOverMinor.toInt(), -5000);
        expect(item.remainingMinor.toInt(), -20000);
        expect(summary.totalCarryOverMinor.toInt(), -5000);
        expect(summary.totalRemainingMinor.toInt(), -20000);
      },
    );
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

    test(
      'listUpcomingOccurrences sends days only when given, and decodes every state',
      () async {
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
      },
    );

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

    test(
      'skip and restore POST to the occurrence and decode the updated state',
      () async {
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
      },
    );

    test(
      'confirmOccurrence POSTs only what was overridden and decodes the record',
      () async {
        final bodies = <Map<String, Object?>>[];
        final calls = <String>[];
        final repository = PrudentRepository(
          client: _clientAnswering((request) {
            calls.add('${request.method} ${_uriOf(request).path}');
            bodies.add(jsonDecode(request.body) as Map<String, Object?>);
            return _jsonResponse({
              'occurrence': occurrence('OCCURRENCE_STATUS_COMPLETED'),
              'record': {
                'id': 'rec-1',
                'title': 'Rent',
                'amountMinor': '-250000',
                'currency': 'PLN',
                'date': '2026-10-12',
                'accountId': 'acc-1',
                'planId': 'plan-1',
                'planOccurrenceId': 'occ-1',
              },
            }, status: 201);
          }),
        );

        final asPlanned = await repository.confirmOccurrence('occ-1');
        final edited = await repository.confirmOccurrence(
          'occ-1',
          ConfirmOccurrenceRequest(
            date: '2026-10-12',
            amountMinor: Int64(-250000),
          ),
        );

        expect(calls, everyElement('POST /api/v1/occurrences/occ-1/confirm'));
        expect(
          bodies[0],
          isEmpty,
          reason: 'nothing overridden, so the plan supplies everything',
        );
        expect(bodies[1].keys, unorderedEquals(['date', 'amountMinor']));
        final confirmed = asPlanned.fold((r) => r, (e) => throw e);
        expect(
          confirmed.occurrence.status,
          OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED,
        );
        expect(confirmed.record.planId, 'plan-1');
        expect(confirmed.record.planOccurrenceId, 'occ-1');
        expect(edited.isSuccess, isTrue);
      },
    );

    test(
      'a refused transition surfaces the conflict rather than a decoded occurrence',
      () async {
        final repository = PrudentRepository(
          client: _clientAnswering(
            (request) => _jsonResponse({
              'code': 'conflict',
              'message':
                  'An occurrence that is COMPLETED cannot become SKIPPED.',
            }, status: 409),
          ),
        );

        final result = await repository.skipOccurrence('occ-1');

        expect(result.isFailure, isTrue);
      },
    );
  });

  group('PrudentRepository.spendByCategory', () {
    test(
      'sends currency and year as query parameters, and decodes the response',
      () async {
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

        final result = await repository.spendByCategory(
          currency: 'PLN',
          year: 2026,
          month: 8,
        );

        expect(capturedUri!.path, '/api/v1/analytics/spend-by-category');
        expect(capturedUri!.queryParameters['currency'], 'PLN');
        expect(capturedUri!.queryParameters['year'], '2026');
        expect(capturedUri!.queryParameters['month'], '8');
        final response = result.fold((r) => r, (e) => throw e);
        expect(response.items.single.amountMinor.toInt(), 3500);
      },
    );

    test(
      'month is omitted from the query when null — the whole-year scope',
      () async {
        Uri? capturedUri;
        final repository = PrudentRepository(
          client: _clientAnswering((request) {
            capturedUri = _uriOf(request);
            return _jsonResponse({'currency': 'PLN', 'items': []});
          }),
        );

        await repository.spendByCategory(currency: 'PLN', year: 2026);

        expect(capturedUri!.queryParameters.containsKey('month'), isFalse);
      },
    );

    test('the empty case decodes as an empty list, not a failure', () async {
      final repository = PrudentRepository(
        client: _clientAnswering(
          (request) => _jsonResponse({'currency': 'PLN', 'items': []}),
        ),
      );

      final result = await repository.spendByCategory(
        currency: 'PLN',
        year: 2026,
      );

      expect(result.isSuccess, isTrue);
      expect(result.fold((r) => r.items, (e) => throw e), isEmpty);
    });
  });

  group('PrudentRepository.spendByPeriod', () {
    test(
      'sends granularity and count as query parameters, and decodes the response',
      () async {
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

        final result = await repository.spendByPeriod(
          currency: 'PLN',
          granularity: 'MONTH',
          count: 12,
        );

        expect(capturedUri!.queryParameters['granularity'], 'MONTH');
        expect(capturedUri!.queryParameters['count'], '12');
        final response = result.fold((r) => r, (e) => throw e);
        expect(response.periods.single.period, '2026-08');
      },
    );
  });
}
