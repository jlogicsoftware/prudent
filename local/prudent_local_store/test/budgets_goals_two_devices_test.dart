// Unit 6a's two-device cases: budgets, resets, goals and envelopes on two real sessions — two
// encrypted stores synced through jZen's ZenFolderCloud. Nothing is mocked.
//
// What is proven: a figure never reads a value two devices disagree about — a disputed record,
// budget, account flag or goal target counts in no budget summary, free money or progress, and the
// answer names it — and a rule that refuses a change reads every side of a conflict; envelope entries
// made offline on both devices are all kept; and what a merge breaks across records — an envelope
// below zero, money in a goal archived meanwhile, two live resets for one slot — is listed on both
// devices and settled by one action, never by editing the history.
import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/budgets.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goal_allocations.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

import 'support/two_devices.dart';

void main() {
  late TwoDevices devices;
  late Ledger laptop;
  late Ledger phone;
  var clock = 1000;
  int tick() => clock += 10;

  setUp(() async {
    devices = await TwoDevices.create();
    laptop = Ledger(devices.laptop.store, clock: tick);
    phone = Ledger(devices.phone.store, clock: tick);
  });
  tearDown(() async => devices.dispose());

  List<Ledger> both() => [laptop, phone];

  int statusOf(ZenResult<Object?> result) => switch (result) {
    ZenFailure(:final error) => LedgerErrors.statusOf(error) ?? -1,
    ZenSuccess() => 200,
  };

  /// An eligible PLN account holding 100.00 and an expense category, made on the laptop and synced.
  Future<({String account, String category})> setUpLedger() async {
    final account = Device.ok(
      await laptop.createAccount(
        wire.CreateAccountRequest(
          name: 'Wallet',
          type: wire.AccountType.ACCOUNT_TYPE_CASH,
          isActive: true,
          eligibleForGoals: true,
          balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(10000))],
        ),
      ),
    ).value;
    final category = Device.ok(
      await laptop.createCategory(
        wire.CreateCategoryRequest(
          title: 'Food',
          iconKey: 'food',
          kind: wire.CategoryKind.CATEGORY_KIND_EXPENSE,
        ),
      ),
    );
    await devices.sync();
    return (account: account.id, category: category.id);
  }

  Future<wire.Record> spend(
    Ledger on,
    ({String account, String category}) l,
    int amount, {
    String date = '2026-11-02',
  }) async => Device.ok(
    await on.createRecord(
      wire.CreateRecordRequest(
        title: 'Bread',
        amountMinor: Int64(amount),
        date: date,
        categoryId: l.category,
        accountId: l.account,
        currency: 'PLN',
      ),
    ),
  );

  Future<String> goal(Ledger on, {int target = 5000}) async => Device.ok(
    await on.createGoal(
      wire.CreateGoalRequest(name: 'Bike', currency: 'PLN', targetAmountMinor: Int64(target)),
    ),
  ).id;

  Future<ZenResult<wire.GoalAllocation>> entry(
    Ledger on,
    wire.GoalAllocationKind kind,
    int amount, {
    String? source,
    String? target,
  }) => on.createGoalAllocation(
    wire.CreateGoalAllocationRequest(
      kind: kind,
      amountMinor: Int64(amount),
      sourceGoalId: source,
      targetGoalId: target,
    ),
  );

  const allocate = wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE;
  const withdraw = wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW;

  group('budget figures', () {
    test('a disputed amount counts in no budget figure on either device, and is named', () async {
      final l = await setUpLedger();
      Device.ok(await laptop.setBudget(l.category, '2026-11', 'PLN', 5000));
      final record = await spend(laptop, l, -1000);
      await devices.sync();
      Device.ok(
        await laptop.updateRecord(
          record.id,
          wire.UpdateRecordRequest(
            title: 'Bread',
            amountMinor: Int64(-1500),
            date: '2026-11-02',
            categoryId: l.category,
            accountId: l.account,
            currency: 'PLN',
          ),
        ),
      );
      Device.ok(
        await phone.updateRecord(
          record.id,
          wire.UpdateRecordRequest(
            title: 'Bread',
            amountMinor: Int64(-2500),
            date: '2026-11-02',
            categoryId: l.category,
            accountId: l.account,
            currency: 'PLN',
          ),
        ),
      );
      await devices.sync();
      for (final ledger in both()) {
        final summary = Device.ok(await ledger.budgetSummary('2026-11', 'PLN'));
        expect(summary.value.items.single.actualMinor, Int64.ZERO);
        expect(summary.value.items.single.remainingMinor, Int64(5000));
        expect(summary.unsettled, {
          l.category: [record.id],
        });
        // The carry-over into the next month leaves it out too, and says so.
        Device.ok(await ledger.setBudget(l.category, '2026-12', 'PLN', 5000));
        final next = Device.ok(await ledger.budgetSummary('2026-12', 'PLN'));
        expect(next.value.items.single.carryOverMinor, Int64(5000));
        expect(next.unsettled[l.category], [record.id]);
      }
    });

    test('a record moved to another month on one device and deleted on the other', () async {
      final l = await setUpLedger();
      Device.ok(await laptop.setBudget(l.category, '2026-11', 'PLN', 5000));
      Device.ok(await laptop.setBudget(l.category, '2026-12', 'PLN', 5000));
      final record = await spend(laptop, l, -1000);
      await devices.sync();
      Device.ok(
        await laptop.updateRecord(
          record.id,
          wire.UpdateRecordRequest(
            title: 'Bread',
            amountMinor: Int64(-1000),
            date: '2026-12-01',
            categoryId: l.category,
            accountId: l.account,
            currency: 'PLN',
          ),
        ),
      );
      Device.ok(await phone.deleteRecord(record.id));
      await devices.sync();
      for (final ledger in both()) {
        // Neither side counts it in November any more: that month is settled without it.
        final november = Device.ok(await ledger.budgetSummary('2026-11', 'PLN'));
        expect(november.value.items.single.actualMinor, Int64.ZERO);
        expect(november.isSettled, isTrue);
        // December is where one side has it and the other has nothing: left out, and named.
        final december = Device.ok(await ledger.budgetSummary('2026-12', 'PLN'));
        expect(december.value.items.single.actualMinor, Int64.ZERO);
        expect(december.unsettled[l.category], [record.id]);
      }
    });

    test('two plans for one slot: the slot counts in no figure until settled', () async {
      final l = await setUpLedger();
      Device.ok(await laptop.setBudget(l.category, '2026-11', 'PLN', 5000));
      await devices.sync();
      Device.ok(await laptop.setBudget(l.category, '2026-11', 'PLN', 6000));
      Device.ok(await phone.setBudget(l.category, '2026-11', 'PLN', 7000));
      await devices.sync();
      final slot = DerivedIds.budget(l.category, '2026-11', 'PLN');
      for (final ledger in both()) {
        final summary = Device.ok(await ledger.budgetSummary('2026-11', 'PLN'));
        expect(summary.value.items, isEmpty);
        expect(summary.unsettled, {
          l.category: [slot],
        });
        // And the slot refuses a write until the person settles it (the store's own refusal).
        expect(await ledger.setBudget(l.category, '2026-11', 'PLN', 1), isA<ZenFailure<Object?>>());
      }
    });

    test('a reset is refused while the carry-over it would record leaves something out', () async {
      final l = await setUpLedger();
      Device.ok(await laptop.setBudget(l.category, '2026-10', 'PLN', 5000));
      await devices.sync();
      Device.ok(await laptop.setBudget(l.category, '2026-10', 'PLN', 6000));
      Device.ok(await phone.setBudget(l.category, '2026-10', 'PLN', 7000));
      await devices.sync();
      final result = await laptop.resetBudgetCarryOver(
        wire.ResetBudgetCarryOverRequest(categoryId: l.category, month: '2026-11', currency: 'PLN'),
      );
      expect(statusOf(result), 409);
      expect(Device.ok(devices.laptop.store.budgetResets.list()), isEmpty);
    });

    test('a category is still used by a budget only the other side of a conflict holds', () async {
      final l = await setUpLedger();
      Device.ok(await laptop.setBudget(l.category, '2026-11', 'PLN', 5000));
      await devices.sync();
      Device.ok(await laptop.deleteBudget(l.category, '2026-11', 'PLN'));
      Device.ok(await phone.setBudget(l.category, '2026-11', 'PLN', 6000));
      await devices.sync();
      for (final ledger in both()) {
        expect(statusOf(await ledger.deleteCategory(l.category)), 409);
      }
    });

    test('two resets of one slot made offline: one issue on both devices, revoke one', () async {
      final l = await setUpLedger();
      final request = wire.ResetBudgetCarryOverRequest(
        categoryId: l.category,
        month: '2026-11',
        currency: 'PLN',
      );
      final first = Device.ok(await laptop.resetBudgetCarryOver(request));
      final second = Device.ok(await phone.resetBudgetCarryOver(request));
      await devices.sync();
      for (final device in devices.both) {
        final issues = Device.ok(device.integrity().evaluate());
        expect(issues.map((i) => i.code), ['budget.reset_slot_twice']);
      }
      // Both resets are live: the slot refuses a third on either device.
      expect(statusOf(await phone.resetBudgetCarryOver(request)), 409);
      final issue = Device.ok(devices.phone.integrity().evaluate()).single;
      Device.ok(await issue.actions.single.run(second.id));
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.integrity().evaluate()), isEmpty);
      }
      final history = Device.ok(await laptop.listBudgetResets());
      expect(
        {for (final r in history.resets) r.id: r.revokedAtMs != Int64.ZERO},
        {first.id: false, second.id: true},
      );
    });
  });

  group('goals and envelopes', () {
    test(
      'entries made offline on both devices are all kept, and the envelope is their sum',
      () async {
        await setUpLedger();
        final bike = await goal(laptop);
        await devices.sync();
        Device.ok(await entry(laptop, allocate, 1000, target: bike));
        Device.ok(await entry(phone, allocate, 2000, target: bike));
        await devices.sync();
        for (final ledger in both()) {
          final envelopes = Device.ok(await ledger.listGoalEnvelopes()).envelopes;
          expect(envelopes.single.amountMinor, Int64(3000));
          expect(Device.ok(await ledger.listGoalAllocations()).allocations, hasLength(2));
        }
      },
    );

    test('two withdrawals offline take the envelope below zero: allocate the deficit', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      Device.ok(await entry(laptop, allocate, 1000, target: bike));
      await devices.sync();
      Device.ok(await entry(laptop, withdraw, 800, source: bike));
      Device.ok(await entry(phone, withdraw, 700, source: bike));
      await devices.sync();
      for (final device in devices.both) {
        final issues = Device.ok(device.integrity().evaluate());
        expect(issues.map((i) => (i.code, i.facts['deficitMinor'])), [
          ('goal.envelope_below_zero', '500'),
        ]);
      }
      final issue = Device.ok(devices.phone.integrity().evaluate()).single;
      Device.ok(await issue.actions.single.run());
      await devices.sync();
      for (final ledger in both()) {
        expect(
          Device.ok(await ledger.listGoalEnvelopes()).envelopes.single.amountMinor,
          Int64.ZERO,
        );
        // The history only grew: four entries, none edited.
        expect(Device.ok(await ledger.listGoalAllocations()).allocations, hasLength(4));
      }
      for (final device in devices.both) {
        expect(Device.ok(device.integrity().evaluate()), isEmpty);
      }
    });

    test('money put into a goal archived meanwhile: reactivate it, or withdraw it', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      final car = await goal(laptop);
      await devices.sync();
      Device.ok(await laptop.archiveGoal(bike));
      Device.ok(await laptop.archiveGoal(car));
      Device.ok(await entry(phone, allocate, 1200, target: bike));
      Device.ok(await entry(phone, allocate, 300, target: car));
      await devices.sync();
      for (final device in devices.both) {
        final issues = Device.ok(device.integrity().evaluate());
        expect(issues.map((i) => i.code), [
          'goal.archived_holds_money',
          'goal.archived_holds_money',
        ]);
      }
      final issues = Device.ok(devices.laptop.integrity().evaluate());
      IntegrityAction action(String goalId, String code) => issues
          .singleWhere((i) => i.recordId == goalId)
          .actions
          .singleWhere((a) => a.code == code);
      Device.ok(await action(bike, 'reactivate_goal').run());
      Device.ok(await action(car, 'withdraw_all').run());
      await devices.sync();
      for (final ledger in both()) {
        expect(Device.ok(await ledger.getGoal(bike)).status, wire.GoalStatus.GOAL_STATUS_ACTIVE);
        final envelopes = {
          for (final e in Device.ok(await ledger.listGoalEnvelopes()).envelopes)
            e.goalId: e.amountMinor.toInt(),
        };
        expect(envelopes, {bike: 1200, car: 0});
      }
      for (final device in devices.both) {
        expect(Device.ok(device.integrity().evaluate()), isEmpty);
      }
    });

    test('completed on one device and archived on the other: no money moves in or out', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      Device.ok(await entry(laptop, allocate, 1000, target: bike));
      Device.ok(await entry(laptop, withdraw, 1000, source: bike));
      await devices.sync();
      Device.ok(await laptop.completeGoal(bike));
      Device.ok(await phone.archiveGoal(bike));
      await devices.sync();
      for (final ledger in both()) {
        // One side is archived: money neither goes in (not active) nor comes out (archived).
        expect(statusOf(await entry(ledger, allocate, 1, target: bike)), 409);
        // And its progress is nobody's agreed figure.
        final progress = Device.ok(await ledger.goalProgress(asOf: '2026-11-15'));
        expect(progress.value.goals, isEmpty);
        expect(progress.unsettled, {
          bike: [bike],
        });
      }
    });

    test('two targets for one goal: its progress is left out on both devices, and named', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      final car = await goal(laptop, target: 9000);
      await devices.sync();
      Device.ok(
        await laptop.updateGoal(
          bike,
          wire.UpdateGoalRequest(name: 'Bike', targetAmountMinor: Int64(6000)),
        ),
      );
      Device.ok(
        await phone.updateGoal(
          bike,
          wire.UpdateGoalRequest(name: 'Bike', targetAmountMinor: Int64(7000)),
        ),
      );
      await devices.sync();
      for (final ledger in both()) {
        final progress = Device.ok(await ledger.goalProgress(asOf: '2026-11-15'));
        expect(progress.value.goals.map((g) => g.goalId), [car]);
        expect(progress.unsettled, {
          bike: [bike],
        });
      }
    });

    test('an eligibility two devices disagree about counts in no free money, and blocks an '
        'allocation in that currency', () async {
      final l = await setUpLedger();
      final bike = await goal(laptop);
      await devices.sync();
      wire.UpdateAccountRequest edit({required bool eligible}) => wire.UpdateAccountRequest(
        name: 'Wallet',
        type: wire.AccountType.ACCOUNT_TYPE_CASH,
        isActive: true,
        eligibleForGoals: eligible,
        balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(10000))],
      );
      // The laptop turns eligibility off; the phone turns it off and on again, offline: two
      // different last values of one field.
      Device.ok(await laptop.updateAccount(l.account, edit(eligible: false)));
      Device.ok(await phone.updateAccount(l.account, edit(eligible: false)));
      Device.ok(await phone.updateAccount(l.account, edit(eligible: true)));
      await devices.sync();
      for (final device in devices.both) {
        final conflict = Device.ok(device.store.accounts.conflictFor(l.account));
        expect(conflict?.fields, {Account().info_.byName['eligibleForGoals']!.tagNumber});
      }
      for (final ledger in both()) {
        final money = Device.ok(await ledger.freeMoney());
        expect(money.unsettled, {
          'PLN': [l.account],
        });
        expect(money.value.currencies.single.eligibleMinor, Int64.ZERO);
        expect(statusOf(await entry(ledger, allocate, 1, target: bike)), 409);
      }
    });

    test('a disputed spend on an eligible account leaves free money unsettled', () async {
      final l = await setUpLedger();
      final bike = await goal(laptop);
      final record = await spend(laptop, l, -1000);
      await devices.sync();
      wire.UpdateRecordRequest edit(int amount) => wire.UpdateRecordRequest(
        title: 'Bread',
        amountMinor: Int64(amount),
        date: '2026-11-02',
        categoryId: l.category,
        accountId: l.account,
        currency: 'PLN',
      );
      Device.ok(await laptop.updateRecord(record.id, edit(-2000)));
      Device.ok(await phone.updateRecord(record.id, edit(-3000)));
      await devices.sync();
      for (final ledger in both()) {
        final money = Device.ok(await ledger.freeMoney());
        expect(money.unsettled, {
          'PLN': [record.id],
        });
        expect(money.value.currencies.single.eligibleMinor, Int64(10000));
        expect(statusOf(await entry(ledger, allocate, 1, target: bike)), 409);
      }
    });
  });
}
