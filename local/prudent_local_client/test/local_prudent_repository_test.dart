// LocalPrudentRepository (plan unit 9): every shared screen's call answered from this device's store.
// The ledger's rules are unit 5's and proven there; what is proven here is the adapter — the filter
// reaches the ledger as the server's query, a delete answers the empty message the server's
// repository answers, the balances carry their caveat, and every part this build does not have yet
// answers the typed NotInThisBuildError rather than a faked value.
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/repository/local_data_export.dart';
import 'package:prudent_local_client/repository/local_prudent_repository.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/budgets.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/goal_allocations.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/privacy.pb.dart';
import 'package:prudent_ui/failure_code.dart';
import 'package:prudent_ui/record/record_filter.dart';
import 'package:zen_core/zen_core.dart';

import 'support/ledger_setup.dart';
import 'support/two_local_devices.dart';

void main() {
  late TwoLocalDevices devices;
  late LocalPrudentRepository repository;

  setUp(() async {
    devices = await TwoLocalDevices.create();
    repository = LocalPrudentRepository(
      ledger: () => devices.phone.ledger,
      imports: () => devices.phone.imports,
      plans: () => devices.phone.plans,
      analytics: () => devices.phone.analytics,
      export: LocalDataExport(now: () => DateTime.utc(2026, 11, 16, 9)),
    );
  });
  tearDown(() async => devices.dispose());

  test(
    'accounts carry what their balances leave out, from the same answer',
    () async {
      final books = await openBooks(devices.laptop.ledger);
      final bread = await addRecord(devices.laptop.ledger, books);
      await devices.sync();
      await editAmount(devices.laptop.ledger, books, bread.id, -1200);
      await editAmount(devices.phone.ledger, books, bread.id, -1500);
      await devices.sync();

      final answer = ok(await repository.listAccounts());
      expect(answer.accounts.single.balances.single.amountMinor, Int64(10000));
      expect(answer.unsettled, {
        books.account: [bread.id],
      });
      expect(answer.leftOutOf(books.account), 1);
    },
  );

  test('the record filter reaches the ledger as the server query', () async {
    final books = await openBooks(devices.phone.ledger);
    await addRecord(devices.phone.ledger, books, amount: -1000, title: 'Bread');
    await addRecord(devices.phone.ledger, books, amount: 5000, title: 'Salary');
    final expenses = ok(
      await repository.listRecords(
        filter: const RecordFilter(type: RecordFilterType.expense),
      ),
    );
    expect(expenses.records.map((r) => r.title), ['Bread']);
    final searched = ok(
      await repository.listRecords(
        filter: const RecordFilter(search: '  sal '),
      ),
    );
    expect(searched.records.map((r) => r.title), ['Salary']);
    final ranged = ok(
      await repository.listRecords(
        filter: RecordFilter(amountMin: Int64(2000)),
      ),
    );
    expect(ranged.records.map((r) => r.title), ['Salary']);
    final dated = ok(
      await repository.listRecords(
        filter: RecordFilter(
          dateFrom: DateTime(2026, 11, 3),
          dateTo: DateTime(2026, 12, 1),
        ),
      ),
    );
    expect(dated.records, isEmpty);
  });

  test(
    'a delete answers the empty message, as the server repository does',
    () async {
      final books = await openBooks(devices.phone.ledger);
      final bread = await addRecord(devices.phone.ledger, books);
      final deleted = ok(await repository.deleteRecord(bread.id));
      expect(deleted.id, isEmpty);
      expect(ok(await repository.listRecords()).records, isEmpty);
    },
  );

  test(
    'a refusal is the ledger\'s, read by failureCode like the server\'s',
    () async {
      final missing = await repository.deleteRecord('0' * 32);
      expect(missing, isA<ZenFailure<Object?>>());
      expect(failureCode((missing as ZenFailure).error), 'not_found');
    },
  );

  test(
    'analytics come from unit 7, and its figures carry what they leave out',
    () async {
      final books = await openBooks(devices.laptop.ledger);
      final bread = await addRecord(devices.laptop.ledger, books);
      await devices.sync();
      final settled = ok(
        await repository.spendByCategory(
          currency: 'PLN',
          year: 2026,
          month: 11,
        ),
      );
      expect(settled.leftOut, 0);
      expect(settled.value.items.single.amountMinor, Int64(1000));
      await editAmount(devices.laptop.ledger, books, bread.id, -1200);
      await editAmount(devices.phone.ledger, books, bread.id, -1500);
      await devices.sync();
      final disputed = ok(
        await repository.spendByCategory(
          currency: 'PLN',
          year: 2026,
          month: 11,
        ),
      );
      expect(disputed.leftOut, 1);
      expect(disputed.value.items, isEmpty);
      final period = ok(
        await repository.spendByPeriod(
          currency: 'PLN',
          granularity: 'YEAR',
          count: 1,
        ),
      );
      expect(period.leftOut, 1);
    },
  );

  test('there is no account to erase: the server form is refused, nothing is touched', () async {
    final books = await openBooks(devices.phone.ledger);
    final result = await repository.eraseAccount(
      EraseAccountRequest(confirmEmail: 'a@b.c'),
    );
    expect(result, isA<ZenFailure<Object?>>());
    expect(
      ok(await repository.listAccounts()).accounts.single.id,
      books.account,
    );
  });

  test('a statement is imported through unit 8b\'s workflow, never synced, and written once', () async {
    // The server's own synthetic fixture (ADR-088): its account number ends in 3.
    final statement = File(
      '../../server/src/test/resources/import/erste/statement-minimal.csv',
    ).readAsBytesSync();
    final account = ok(
      await repository.createAccount(
        wire.CreateAccountRequest(
          name: 'Bank',
          type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
          isActive: true,
          accountNumber: '00000000000000000000000003',
          balances: [
            wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(5000)),
          ],
        ),
      ),
    );
    final books = await openBooks(devices.phone.ledger, name: 'Cash');
    final session = ok(
      await repository.createImportSession(
        CreateImportSessionRequest(
          formatId: 'erste-pl-csv',
          content: statement,
          accountId: account.id,
        ),
      ),
    );
    final previewed = ok(
      await repository.previewImportSession(
        session.id,
        PreviewImportSessionRequest(),
      ),
    );
    expect(previewed.acceptedRows, greaterThan(0));
    ok(
      await repository.setImportDefaults(
        session.id,
        SetImportDefaultsRequest(
          defaultExpenseCategoryId: books.category,
          defaultIncomeCategoryId: books.category,
        ),
      ),
    );
    final committed = ok(
      await repository.commitImportSession(
        session.id,
        CommitImportSessionRequest(
          confirmedAcceptedRows: previewed.acceptedRows,
        ),
      ),
    );
    expect(committed.state, ImportSessionState.IMPORT_SESSION_STATE_COMMITTED);
    final listed = ok(
      await repository.listImportSessions(
        state: ImportSessionState.IMPORT_SESSION_STATE_COMMITTED,
      ),
    );
    expect(listed.sessions.map((s) => s.id), [session.id]);
    final records = ok(await repository.listRecords()).records;
    expect(
      records.where((r) => r.accountId == account.id),
      hasLength(previewed.acceptedRows),
    );

    // ADR-100 T12: the session stays on this device; the records reach the other.
    await devices.sync();
    expect(ok(await devices.laptop.imports.list()).sessions, isEmpty);
    expect(
      ok(await devices.laptop.ledger.listRecords()).records
          .where((r) => r.accountId == account.id),
      hasLength(previewed.acceptedRows),
    );
  });

  test('budgets and goals come from unit 6a, and their figures carry what they leave out', () async {
    final books = await openBooks(devices.laptop.ledger);
    final bread = await addRecord(devices.laptop.ledger, books);
    ok(
      await LocalPrudentRepository(
        ledger: () => devices.laptop.ledger,
        imports: () => devices.laptop.imports,
        plans: () => devices.laptop.plans,
        analytics: () => devices.laptop.analytics,
        export: const LocalDataExport(),
      ).setBudget(
        categoryId: books.category,
        month: '2026-11',
        currency: 'PLN',
        request: SetBudgetRequest(amountMinor: Int64(5000)),
      ),
    );
    await devices.sync();
    final settled = ok(
      await repository.getBudgetSummary(month: '2026-11', currency: 'PLN'),
    );
    expect(settled.leftOut, 0);
    expect(settled.value.items.single.actualMinor, Int64(1000));

    await editAmount(devices.laptop.ledger, books, bread.id, -1200);
    await editAmount(devices.phone.ledger, books, bread.id, -1500);
    await devices.sync();
    final disputed = ok(
      await repository.getBudgetSummary(month: '2026-11', currency: 'PLN'),
    );
    expect(disputed.leftOut, 1);
    expect(disputed.value.items.single.actualMinor, Int64.ZERO);

    final goal = ok(
      await repository.createGoal(
        CreateGoalRequest(
          name: 'Bike',
          currency: 'PLN',
          targetAmountMinor: Int64(20000),
        ),
      ),
    );
    expect(
      ok(await repository.listGoals(status: GoalStatus.GOAL_STATUS_ACTIVE))
          .goals
          .single
          .id,
      goal.id,
    );
    final free = ok(await repository.getFreeMoney());
    expect(
      free.leftOut,
      0,
      reason: 'Wallet is not marked eligible for goals, so nothing is read',
    );
    expect(ok(await repository.listGoalAllocations()).allocations, isEmpty);
    expect(
      ok(await repository.listGoalEnvelopes()).envelopes.single.goalId,
      goal.id,
    );
    // A refusal is the ledger's, read like the server's (an allocation with no kind is a 400).
    final refused = await repository.createGoalAllocation(
      CreateGoalAllocationRequest(),
    );
    expect(failureCode((refused as ZenFailure).error), 'invalid');
  });

  test('plans, occurrences and reminders come from unit 6b, as of the device clock', () async {
    final books = await openBooks(devices.phone.ledger);
    final dated = LocalPrudentRepository(
      ledger: () => devices.phone.ledger,
      imports: () => devices.phone.imports,
      plans: () => devices.phone.plans,
      analytics: () => devices.phone.analytics,
      export: const LocalDataExport(),
      now: () => DateTime.utc(2026, 11, 16, 9),
    );
    final plan = ok(
      await dated.createPlan(
        CreatePlanRequest(
          title: 'Rent',
          amountMinor: Int64(-2000),
          currency: 'PLN',
          accountId: books.account,
          categoryId: books.category,
          recurrence: Recurrence(
            frequency: RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY,
            interval: 1,
            startDate: '2026-11-20',
            timeZone: 'Europe/Warsaw',
          ),
        ),
      ),
    );
    expect(ok(await dated.listPlans()).plans.single.id, plan.id);
    final upcoming = ok(await dated.listUpcomingOccurrences(days: 30));
    expect(upcoming.occurrences.first.occurrenceDate, '2026-11-20');
    final confirmed = ok(
      await dated.confirmOccurrence(upcoming.occurrences.first.id),
    );
    expect(confirmed.record.amountMinor, Int64(-2000));
    expect(ok(await dated.listOverdueOccurrences()).occurrences, isEmpty);
    expect(ok(await dated.listReminders()).reminders, isEmpty);
    expect(ok(await dated.deletePlan(plan.id)).id, isEmpty);
  });
}
