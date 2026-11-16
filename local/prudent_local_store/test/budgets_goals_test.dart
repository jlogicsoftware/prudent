// Unit 6a on one device: what the parity suite cannot show, because the server has no equivalent.
//
// - Every write whose rule was checked first carries that rule into the write's own turn
//   (jZenDev/jZen#251): a write queued between the check and the write — on this device here, a
//   sync's receive in life — that breaks the rule makes the write refused, and nothing is written.
// - The histories are ordered by this device's clock, ties by id; the progress "today" is the
//   clock's UTC date (the parity suite pins `asOf`, finding F-07).
// - Who made a reset, a revocation or an entry is this device.
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/budgets.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goal_allocations.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import 'support/two_devices.dart';

void main() {
  late Directory directory;
  late ZenStore zen;
  late PrudentLocalStore store;
  late Ledger ledger;
  var clock = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prudent_budgets_goals');
    zen = Device.ok(await ZenStore.open(directory, deviceName: 'one', key: List.filled(32, 3)));
    store = PrudentLocalStore(zen);
    clock = DateTime.utc(2027, 1, 31, 23, 30).millisecondsSinceEpoch;
    ledger = Ledger(store, clock: () => clock);
  });
  tearDown(() async {
    await zen.close();
    await directory.delete(recursive: true);
  });

  int statusOf(ZenResult<Object?> result) => switch (result) {
    ZenFailure(:final error) => LedgerErrors.statusOf(error) ?? -1,
    ZenSuccess() => 200,
  };

  Future<String> category() async => Device.ok(
    await ledger.createCategory(wire.CreateCategoryRequest(title: 'Food', iconKey: 'food')),
  ).id;

  Future<String> eligibleAccount(int opening) async => Device.ok(
    await ledger.createAccount(
      wire.CreateAccountRequest(
        name: 'Wallet',
        type: wire.AccountType.ACCOUNT_TYPE_CASH,
        isActive: true,
        eligibleForGoals: true,
        balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(opening))],
      ),
    ),
  ).value.id;

  Future<String> goal() async => Device.ok(
    await ledger.createGoal(
      wire.CreateGoalRequest(name: 'Bike', currency: 'PLN', targetAmountMinor: Int64(5000)),
    ),
  ).id;

  Future<ZenResult<wire.GoalAllocation>> entry(
    wire.GoalAllocationKind kind,
    int amount, {
    String? source,
    String? target,
  }) => ledger.createGoalAllocation(
    wire.CreateGoalAllocationRequest(
      kind: kind,
      amountMinor: Int64(amount),
      sourceGoalId: source,
      targetGoalId: target,
    ),
  );

  const allocate = wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE;
  const withdraw = wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW;

  group('a rule checked before a write holds when the write runs (jZenDev/jZen#251)', () {
    test('a new budget slot, the category archived in between', () async {
      final food = await category();
      final archived = Device.ok(store.categories.get(food)).deepCopy()..archived = true;
      final between = store.putCategory(archived);
      final result = ledger.setBudget(food, '2026-11', 'PLN', 5000);
      Device.ok(await between);
      expect(statusOf(await result), 409);
      expect(Device.ok(store.budgets.list()), isEmpty);
    });

    test('a reset, another reset of the slot written in between', () async {
      final food = await category();
      final between = store.addBudgetReset(
        BudgetCarryOverReset(
          id: store.newId(),
          categoryId: food,
          month: '2026-11',
          currency: 'PLN',
          createdBy: store.deviceId,
          createdAtMs: Int64(1),
        ),
      );
      final result = ledger.resetBudgetCarryOver(
        wire.ResetBudgetCarryOverRequest(categoryId: food, month: '2026-11', currency: 'PLN'),
      );
      Device.ok(await between);
      expect(statusOf(await result), 409);
      expect(Device.ok(store.budgetResets.list()), hasLength(1));
    });

    test('a reset, the carry-over it records changed in between', () async {
      final food = await category();
      Device.ok(await ledger.setBudget(food, '2026-10', 'PLN', 5000));
      final between = store.putBudget(
        Budget(
          id: DerivedIds.budget(food, '2026-10', 'PLN'),
          categoryId: food,
          month: '2026-10',
          currency: 'PLN',
          amountMinor: Int64(6000),
        ),
      );
      final result = ledger.resetBudgetCarryOver(
        wire.ResetBudgetCarryOverRequest(categoryId: food, month: '2026-11', currency: 'PLN'),
      );
      Device.ok(await between);
      expect(statusOf(await result), 409);
      expect(Device.ok(store.budgetResets.list()), isEmpty);
    });

    test('a revocation, the reset revoked in between', () async {
      final food = await category();
      final reset = Device.ok(
        await ledger.resetBudgetCarryOver(
          wire.ResetBudgetCarryOverRequest(categoryId: food, month: '2026-11', currency: 'PLN'),
        ),
      );
      final between = store.revokeBudgetReset(reset.id, atMs: 5);
      final result = ledger.revokeBudgetReset(reset.id);
      Device.ok(await between);
      expect(result, completion(isA<ZenFailure<Object?>>()));
      expect(Device.ok(store.budgetResets.get(reset.id)).revocation.atMs, Int64(5));
    });

    test('a withdrawal, the envelope emptied in between', () async {
      await eligibleAccount(10000);
      final bike = await goal();
      Device.ok(await entry(allocate, 1000, target: bike));
      final between = store.addGoalAllocation(
        GoalAllocation(
          id: store.newId(),
          kind: AllocationKind.ALLOCATION_KIND_WITHDRAW,
          sourceGoalId: bike,
          currency: 'PLN',
          amountMinor: Int64(1000),
          createdAtMs: Int64(2),
          createdBy: store.deviceId,
        ),
      );
      final result = entry(withdraw, 1000, source: bike);
      Device.ok(await between);
      expect(statusOf(await result), 409);
      expect(Device.ok(store.goalAllocations.list()), hasLength(2));
    });

    test('an allocation, the free money taken in between', () async {
      await eligibleAccount(1000);
      final bike = await goal();
      final car = await goal();
      final between = entry(allocate, 1000, target: car);
      final result = entry(allocate, 1000, target: bike);
      Device.ok(await between);
      expect(statusOf(await result), 409);
      expect(Device.ok(store.goalAllocations.list()), hasLength(1));
    });

    test('an archive, money put into the goal in between', () async {
      await eligibleAccount(10000);
      final bike = await goal();
      final between = entry(allocate, 100, target: bike);
      final result = ledger.archiveGoal(bike);
      Device.ok(await between);
      expect(statusOf(await result), 409);
      expect(Device.ok(store.goals.get(bike)).status, GoalState.GOAL_STATE_ACTIVE);
    });

    test('an edit, the goal archived in between', () async {
      final bike = await goal();
      final between = ledger.archiveGoal(bike);
      final result = ledger.updateGoal(
        bike,
        wire.UpdateGoalRequest(name: 'Car', targetAmountMinor: Int64(1)),
      );
      Device.ok(await between);
      expect(statusOf(await result), 409);
      expect(Device.ok(store.goals.get(bike)).name, 'Bike');
    });

    test('a move of a goal renamed in between does not write the old name back', () async {
      final bike = await goal();
      final renamed = Device.ok(store.goals.get(bike)).deepCopy()..name = 'Racing bike';
      final between = store.putGoal(renamed);
      final result = ledger.completeGoal(bike);
      Device.ok(await between);
      expect(statusOf(await result), 409);
      final now = Device.ok(store.goals.get(bike));
      expect((now.name, now.status), ('Racing bike', GoalState.GOAL_STATE_ACTIVE));
    });

    test('a budget re-planned in between is neither overwritten nor deleted', () async {
      final food = await category();
      Device.ok(await ledger.setBudget(food, '2026-11', 'PLN', 5000));
      final slot = DerivedIds.budget(food, '2026-11', 'PLN');
      Budget planned(int amount) => Budget(
        id: slot,
        categoryId: food,
        month: '2026-11',
        currency: 'PLN',
        amountMinor: Int64(amount),
      );
      var between = store.putBudget(planned(7000));
      final replaced = ledger.setBudget(food, '2026-11', 'PLN', 6000);
      Device.ok(await between);
      expect(statusOf(await replaced), 409);
      between = store.putBudget(planned(8000));
      final deleted = ledger.deleteBudget(food, '2026-11', 'PLN');
      Device.ok(await between);
      expect(statusOf(await deleted), 409);
      expect(Device.ok(store.budgets.get(slot)).amountMinor, Int64(8000));
    });

    test('every store write of a budget, reset, goal or entry passes its expect on', () async {
      final food = await category();
      ZenError? no(Object? _) => const ZenValidationError('no');
      final budget = Budget(
        id: DerivedIds.budget(food, '2026-11', 'PLN'),
        categoryId: food,
        month: '2026-11',
        currency: 'PLN',
        amountMinor: Int64(1),
      );
      expect(await store.putBudget(budget, expect: no), isA<ZenFailure<Budget>>());
      final reset = BudgetCarryOverReset(
        id: store.newId(),
        categoryId: food,
        month: '2026-11',
        currency: 'PLN',
        createdAtMs: Int64(1),
      );
      expect(await store.addBudgetReset(reset, expect: no), isA<ZenFailure<Object?>>());
      Device.ok(await store.addBudgetReset(reset));
      expect(
        await store.revokeBudgetReset(reset.id, atMs: 2, expect: no),
        isA<ZenFailure<Object?>>(),
      );
      final g = Goal(
        id: store.newId(),
        name: 'Bike',
        currency: 'PLN',
        targetAmountMinor: Int64(1),
        status: GoalState.GOAL_STATE_ACTIVE,
      );
      expect(await store.putGoal(g, expect: no), isA<ZenFailure<Goal>>());
      final e = GoalAllocation(
        id: store.newId(),
        kind: AllocationKind.ALLOCATION_KIND_ALLOCATE,
        targetGoalId: g.id,
        currency: 'PLN',
        amountMinor: Int64(1),
      );
      expect(await store.addGoalAllocation(e, expect: no), isA<ZenFailure<Object?>>());
      expect(Device.ok(store.budgets.list()), isEmpty);
      expect(Device.ok(store.budgetResets.get(reset.id)).hasRevocation(), isFalse);
      expect(Device.ok(store.goals.list()), isEmpty);
      expect(Device.ok(store.goalAllocations.list()), isEmpty);
    });
  });

  group('clock and authorship', () {
    test('goals and entries made in one millisecond are ordered by id', () async {
      final ids = [for (var i = 0; i < 4; i++) await goal()];
      final listed = Device.ok(await ledger.listGoals()).goals.map((g) => g.id).toList();
      expect(listed, [...ids]..sort());
    });

    test('the envelope history is newest first by this device\'s clock', () async {
      await eligibleAccount(10000);
      final bike = await goal();
      final first = Device.ok(await entry(allocate, 1, target: bike));
      clock += 1;
      final second = Device.ok(await entry(allocate, 2, target: bike));
      final listed = Device.ok(await ledger.listGoalAllocations()).allocations;
      expect(listed.map((e) => e.id), [second.id, first.id]);
      expect(listed.map((e) => e.createdBy).toSet(), {store.deviceId});
    });

    test('progress defaults to the clock\'s UTC date, not the device\'s', () async {
      final bike = Device.ok(
        await ledger.createGoal(
          wire.CreateGoalRequest(
            name: 'Bike',
            currency: 'PLN',
            targetAmountMinor: Int64(3000),
            targetDate: '2027-03-01',
          ),
        ),
      );
      final progress = Device.ok(await ledger.goalProgress()).value;
      expect(progress.asOf, '2027-01-31');
      final one = progress.goals.single;
      expect(
        (one.goalId, one.monthsRemaining, one.monthlyContributionMinor),
        (bike.id, 3, Int64(1000)),
      );
    });

    test('a reset and its revocation name this device and the clock', () async {
      final food = await category();
      final reset = Device.ok(
        await ledger.resetBudgetCarryOver(
          wire.ResetBudgetCarryOverRequest(categoryId: food, month: '2026-11', currency: 'PLN'),
        ),
      );
      expect((reset.createdBy, reset.createdAtMs.toInt()), (store.deviceId, clock));
      clock += 7;
      final revoked = Device.ok(await ledger.revokeBudgetReset(reset.id));
      expect((revoked.revokedBy, revoked.revokedAtMs.toInt()), (store.deviceId, clock));
    });

    test(
      'a goal\'s status time is the clock at each move, its creation time never changes',
      () async {
        final bike = await goal();
        final created = clock;
        clock += 100;
        final done = Device.ok(await ledger.completeGoal(bike));
        expect((done.createdAtMs.toInt(), done.statusChangedAtMs.toInt()), (created, clock));
      },
    );
  });
}
