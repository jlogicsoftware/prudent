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

    test('a dispute in the reset month itself does not block the reset: the carry-over into it '
        'cannot read it', () async {
      final l = await setUpLedger();
      Device.ok(await laptop.setBudget(l.category, '2026-10', 'PLN', 5000));
      final record = await spend(laptop, l, -1000, date: '2026-11-03');
      await devices.sync();
      wire.UpdateRecordRequest edit(int amount) => wire.UpdateRecordRequest(
        title: 'Bread',
        amountMinor: Int64(amount),
        date: '2026-11-03',
        categoryId: l.category,
        accountId: l.account,
        currency: 'PLN',
      );
      Device.ok(await laptop.updateRecord(record.id, edit(-2000)));
      Device.ok(await phone.updateRecord(record.id, edit(-3000)));
      await devices.sync();
      final reset = Device.ok(
        await laptop.resetBudgetCarryOver(
          wire.ResetBudgetCarryOverRequest(
            categoryId: l.category,
            month: '2026-11',
            currency: 'PLN',
          ),
        ),
      );
      expect(reset.discardedMinor, Int64(5000));
      // With November budgeted, a reset from December reads November's spending: refused.
      Device.ok(await laptop.setBudget(l.category, '2026-11', 'PLN', 5000));
      expect(
        statusOf(
          await laptop.resetBudgetCarryOver(
            wire.ResetBudgetCarryOverRequest(
              categoryId: l.category,
              month: '2026-12',
              currency: 'PLN',
            ),
          ),
        ),
        409,
      );
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
    test('a deficit repaired on both devices is one entry: the envelope ends at exactly zero', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      Device.ok(await entry(laptop, allocate, 1000, target: bike));
      await devices.sync();
      Device.ok(await entry(laptop, withdraw, 800, source: bike));
      Device.ok(await entry(phone, withdraw, 700, source: bike));
      await devices.sync();
      // Both people see the issue and both choose the repair, offline, before the other's arrives.
      for (final device in devices.both) {
        final issue = Device.ok(device.integrity().evaluate()).single;
        expect(issue.code, 'goal.envelope_below_zero');
        Device.ok(await issue.actions.single.run());
      }
      await devices.sync();
      for (final ledger in both()) {
        expect(
          Device.ok(await ledger.listGoalEnvelopes()).envelopes.single.amountMinor,
          Int64.ZERO,
        );
        expect(Device.ok(await ledger.listGoalAllocations()).allocations, hasLength(4));
      }
      for (final device in devices.both) {
        expect(Device.ok(device.store.goalAllocations.conflicts()), isEmpty);
        expect(Device.ok(device.integrity().evaluate()), isEmpty);
      }
    });

    test('money withdrawn from an archived goal on both devices is one entry', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      await devices.sync();
      Device.ok(await laptop.archiveGoal(bike));
      Device.ok(await entry(phone, allocate, 1200, target: bike));
      await devices.sync();
      for (final device in devices.both) {
        final issue = Device.ok(device.integrity().evaluate()).single;
        expect(issue.code, 'goal.archived_holds_money');
        Device.ok(await issue.actions.singleWhere((a) => a.code == 'withdraw_all').run());
      }
      await devices.sync();
      for (final ledger in both()) {
        expect(
          Device.ok(await ledger.listGoalEnvelopes()).envelopes.single.amountMinor,
          Int64.ZERO,
        );
      }
      for (final device in devices.both) {
        expect(Device.ok(device.store.goalAllocations.conflicts()), isEmpty);
        expect(Device.ok(device.integrity().evaluate()), isEmpty);
      }
    });

    /// An entry written to [device]'s store directly, as a merge can leave one: the ledger refuses a
    /// withdrawal from a negative envelope and an allocation into an archived goal.
    Future<void> raw(Device device, AllocationKind kind, String goalId, int amount) async {
      final entry = GoalAllocation(
        id: device.store.newId(),
        kind: kind,
        currency: 'PLN',
        amountMinor: Int64(amount),
        createdAtMs: Int64(tick()),
      );
      if (kind == AllocationKind.ALLOCATION_KIND_ALLOCATE) {
        entry.targetGoalId = goalId;
      } else {
        entry.sourceGoalId = goalId;
      }
      Device.ok(await device.store.addGoalAllocation(entry));
    }

    test('deficits repaired on two devices that read different entries: the overshoot is named and '
        'undone once', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      Device.ok(await entry(laptop, allocate, 1000, target: bike));
      await devices.sync();
      Device.ok(await entry(laptop, withdraw, 800, source: bike));
      Device.ok(await entry(phone, withdraw, 700, source: bike));
      await devices.sync();
      // The laptop takes 100 more before the phone has it: it reads -600, the phone -500.
      await raw(devices.laptop, AllocationKind.ALLOCATION_KIND_WITHDRAW, bike, 100);
      for (final device in devices.both) {
        Device.ok(await Device.ok(device.integrity().evaluate()).single.actions.single.run());
      }
      await devices.sync();
      // +600 and +500 on -600: 500 set aside by nobody — named, not left silent.
      for (final device in devices.both) {
        expect(
          Device.ok(await Ledger(device.store).listGoalEnvelopes()).envelopes.single.amountMinor,
          Int64(500),
        );
        final issues = Device.ok(device.integrity().evaluate());
        expect(issues.map((i) => (i.code, i.facts['overshootMinor'])), [
          ('goal.repairs_made_apart', '500'),
        ]);
        // Both people undo it, offline: one entry.
        Device.ok(await issues.single.actions.single.run());
      }
      await devices.sync();
      for (final device in devices.both) {
        expect(
          Device.ok(await Ledger(device.store).listGoalEnvelopes()).envelopes.single.amountMinor,
          Int64.ZERO,
        );
        expect(Device.ok(device.store.goalAllocations.conflicts()), isEmpty);
        expect(Device.ok(device.integrity().evaluate()), isEmpty);
      }
    });

    test('an archived goal emptied on two devices that read different entries: both issues clear '
        'with one repair', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      await devices.sync();
      Device.ok(await laptop.archiveGoal(bike));
      Device.ok(await entry(phone, allocate, 1200, target: bike));
      await devices.sync();
      // The phone has 50 more that the laptop has not received: it reads 1250, the laptop 1200.
      await raw(devices.phone, AllocationKind.ALLOCATION_KIND_ALLOCATE, bike, 50);
      for (final device in devices.both) {
        final issue = Device.ok(device.integrity().evaluate()).single;
        Device.ok(await issue.actions.singleWhere((a) => a.code == 'withdraw_all').run());
      }
      await devices.sync();
      // 1250 - 1200 - 1250 = -1200: below zero, and the two repairs made apart.
      final issues = Device.ok(devices.laptop.integrity().evaluate());
      expect(issues.map((i) => i.code).toSet(), {
        'goal.envelope_below_zero',
        'goal.repairs_made_apart',
      });
      final apart = issues.singleWhere((i) => i.code == 'goal.repairs_made_apart');
      expect(apart.facts['overshootMinor'], '1200');
      Device.ok(await apart.actions.single.run());
      await devices.sync();
      for (final device in devices.both) {
        expect(
          Device.ok(await Ledger(device.store).listGoalEnvelopes()).envelopes.single.amountMinor,
          Int64.ZERO,
        );
        expect(Device.ok(device.integrity().evaluate()), isEmpty);
      }
    });

    test('a group repaired again from the merged entries is settled, not listed again', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      await devices.sync();
      Device.ok(await laptop.archiveGoal(bike));
      Device.ok(await entry(phone, allocate, 1200, target: bike));
      await devices.sync();
      await raw(devices.phone, AllocationKind.ALLOCATION_KIND_ALLOCATE, bike, 50);
      for (final device in devices.both) {
        final issue = Device.ok(device.integrity().evaluate()).single;
        Device.ok(await issue.actions.singleWhere((a) => a.code == 'withdraw_all').run());
      }
      await devices.sync();
      // The person picks the deficit instead: computed from every entry, the group with them.
      final deficit = Device.ok(devices.phone.integrity().evaluate())
          .singleWhere((i) => i.code == 'goal.envelope_below_zero');
      Device.ok(await deficit.actions.single.run());
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.integrity().evaluate()), isEmpty);
      }
    });

    /// Three devices that hold an envelope of 1000 after a sync; each withdraws offline (800, 700,
    /// 600), they sync and all read -1100, and then their reads diverge: the laptop takes 100 more and
    /// the phone 50, neither synced. [body] runs on them; the stores are closed after it.
    Future<void> threeReadsApart(Future<void> Function(TwoDevices three, String bike) body) async {
      final three = await TwoDevices.create(withTablet: true);
      try {
        final ledgers = [for (final d in three.all) Ledger(d.store, clock: tick)];
        final first = ledgers.first;
        Device.ok(
          await first.createAccount(
            wire.CreateAccountRequest(
              name: 'Wallet',
              type: wire.AccountType.ACCOUNT_TYPE_CASH,
              isActive: true,
              eligibleForGoals: true,
              balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(100000))],
            ),
          ),
        );
        final bike = await goal(first);
        Device.ok(await entry(first, allocate, 1000, target: bike));
        await three.sync();
        for (final (ledger, amount) in [(ledgers[0], 800), (ledgers[1], 700), (ledgers[2], 600)]) {
          Device.ok(await entry(ledger, withdraw, amount, source: bike));
        }
        await three.sync();
        await raw(three.laptop, AllocationKind.ALLOCATION_KIND_WITHDRAW, bike, 100);
        await raw(three.phone, AllocationKind.ALLOCATION_KIND_WITHDRAW, bike, 50);
        await body(three, bike);
      } finally {
        await three.dispose();
      }
    }

    Future<int> envelopeOf(Device device) async =>
        Device.ok(await Ledger(device.store).listGoalEnvelopes()).envelopes.single.amountMinor
            .toInt();

    test(
      'three devices repairing from three different reads: one undo settles the overshoot',
      () => threeReadsApart((three, bike) async {
        // -1200, -1150 and -1100: three repairs, three ids, none of which saw another.
        for (final device in three.all) {
          Device.ok(await Device.ok(device.integrity().evaluate()).single.actions.single.run());
        }
        await three.sync();
        // Entries -1250, repairs +3450: 2200 set aside by nobody, named as one group of three.
        for (final device in three.all) {
          expect(await envelopeOf(device), 2200);
          final issues = Device.ok(device.integrity().evaluate());
          expect(issues.map((i) => (i.code, i.facts['overshootMinor'])), [
            ('goal.repairs_made_apart', '2200'),
          ]);
          // All three people undo it, offline: one entry.
          Device.ok(await issues.single.actions.single.run());
        }
        await three.sync();
        for (final device in three.all) {
          expect(await envelopeOf(device), 0);
          expect(Device.ok(device.store.goalAllocations.conflicts()), isEmpty);
          expect(Device.ok(device.integrity().evaluate()), isEmpty);
        }
      }),
    );

    // The overshoot depends on what each repair read, so on the order the devices synced and
    // repaired in; that it is named exactly, and undone by one entry, must not. Main's run
    // 44124134602 met the order where the phone's repair had seen the laptop's: 1100, not 2200.
    // Every order of the three repairs, each device online (syncing just before its repair and just
    // after it, so the next device to sync reads it) or offline.
    const names = ['laptop', 'phone', 'tablet'];
    for (final order in const [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ]) {
      for (var syncs = 0; syncs < 8; syncs++) {
        final online = [
          for (final i in order)
            if (syncs & (1 << i) != 0) names[i],
        ];
        test(
          'repairs in the order ${order.map((i) => names[i]).join(', ')}, '
          '${online.isEmpty ? 'none' : online.join(' and ')} online: '
          'the overshoot named is the envelope, and one undo settles it',
          () => threeReadsApart((three, bike) async {
            for (final i in order) {
              final device = three.all[i];
              if (syncs & (1 << i) != 0) await device.syncNow();
              final deficit = Device.ok(device.integrity().evaluate())
                  .where((issue) => issue.code == 'goal.envelope_below_zero');
              // A device that synced may find the others' repairs already balance what it reads.
              if (deficit.isEmpty) continue;
              Device.ok(await deficit.single.actions.single.run());
              if (syncs & (1 << i) != 0) await device.syncNow();
            }
            await three.sync();
            final envelope = await envelopeOf(three.laptop);
            // Each repair brought what its device read to zero, and every entry was read by the
            // repair of the device that wrote it, so together they can only overshoot.
            expect(envelope, greaterThanOrEqualTo(0));
            for (final device in three.all) {
              expect(await envelopeOf(device), envelope);
              final issues = Device.ok(device.integrity().evaluate());
              expect(
                issues.map((i) => (i.code, i.facts['overshootMinor'])),
                envelope == 0 ? isEmpty : [('goal.repairs_made_apart', '$envelope')],
              );
              // Everyone who sees it undoes it, offline.
              for (final issue in issues) {
                Device.ok(await issue.actions.single.run());
              }
            }
            await three.sync();
            for (final device in three.all) {
              expect(await envelopeOf(device), 0);
              expect(Device.ok(device.store.goalAllocations.conflicts()), isEmpty);
              expect(Device.ok(device.integrity().evaluate()), isEmpty);
            }
          }),
        );
      }
    }

    test('a goal reactivated on both devices merges, keeping the first moment', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      await devices.sync();
      Device.ok(await laptop.archiveGoal(bike));
      Device.ok(await entry(phone, allocate, 1200, target: bike));
      await devices.sync();
      for (final device in devices.both) {
        final issue = Device.ok(device.integrity().evaluate()).single;
        Device.ok(await issue.actions.singleWhere((a) => a.code == 'reactivate_goal').run());
      }
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.store.goals.conflicts()), isEmpty);
        expect(Device.ok(device.store.goals.get(bike)).status, GoalState.GOAL_STATE_ACTIVE);
        expect(Device.ok(device.integrity().evaluate()), isEmpty);
      }
    });

    test('a repair whose goal or entries changed after the issue was read is refused', () async {
      await setUpLedger();
      final bike = await goal(laptop);
      Device.ok(await entry(laptop, allocate, 1000, target: bike));
      await devices.sync();
      Device.ok(await entry(laptop, withdraw, 800, source: bike));
      Device.ok(await entry(phone, withdraw, 700, source: bike));
      await devices.sync();
      final store = devices.laptop.store;
      final deficit = Device.ok(devices.laptop.integrity().evaluate()).single;
      // An entry arrives (here: is written) between reading the issue and choosing the repair.
      Device.ok(await entry(laptop, allocate, 100, target: bike));
      expect(await deficit.actions.single.run(), isA<ZenFailure<Object?>>());
      expect(Device.ok(store.goalAllocations.list()), hasLength(4));

      Device.ok(await entry(laptop, allocate, 400, target: bike));
      Device.ok(await laptop.archiveGoal(bike));
      Device.ok(await entry(phone, allocate, 50, target: bike));
      await devices.sync();
      final archived = Device.ok(devices.laptop.integrity().evaluate()).single;
      expect(archived.code, 'goal.archived_holds_money');
      // The goal renamed in between: reactivating must not write the old name back.
      final renamed = Device.ok(store.goals.get(bike)).deepCopy()..name = 'Racing bike';
      Device.ok(await store.putGoal(renamed));
      expect(
        await archived.actions.singleWhere((a) => a.code == 'reactivate_goal').run(),
        isA<ZenFailure<Object?>>(),
      );
      expect(Device.ok(store.goals.get(bike)).name, 'Racing bike');
      expect(Device.ok(store.goals.get(bike)).status, GoalState.GOAL_STATE_ARCHIVED);
    });

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
