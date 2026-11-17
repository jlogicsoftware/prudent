// Unit 6b's writes are held to what they were decided against, inside the store's write turn
// (jZenDev/jZen#251, ADR-115, ADR-122), on two real stores.
//
// The interleaving that matters is a sync's receive queued *before* a write and run *after* the
// rules were checked: the operation reads the plan, decides, and its write waits behind the receive.
// These tests queue the receive themselves, with exactly the payload the other device's store hands
// its transport (the way `write_precondition_test` does for the ledger), call the operation without
// awaiting it, and then look at the refusal and at what both devices hold afterwards.
import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import 'support/plan_fixtures.dart';
import 'support/two_devices.dart';

void main() {
  late TwoDevices devices;
  late Ledger laptopLedger;
  late PlanLedger laptop;
  late PlanLedger phone;
  setUp(() async {
    devices = await TwoDevices.create();
    laptopLedger = Ledger(devices.laptop.store);
    laptop = PlanLedger(devices.laptop.store);
    phone = PlanLedger(devices.phone.store);
  });
  tearDown(() async => devices.dispose());

  Future<ZenResult<ZenSyncReport>> queuePhoneChanges(List<String> names) =>
      devices.laptop.zen.receive([
        for (final name in names)
          ZenIncomingRecord(name, devices.phone.zen.outgoing(name)!.payload, null),
      ]);

  void expectRefused<T>(ZenResult<T> result, {required int status, String? rule}) {
    final error = result.errorOrNull;
    expect(error, isNotNull, reason: 'the write went through');
    expect(LedgerErrors.statusOf(error!), status, reason: error.message);
    if (rule != null) expect(error.internalData?['rule'], rule);
  }

  void expectNoConflicts() {
    for (final device in devices.both) {
      expect(device.zen.conflictCount, 0, reason: 'conflicts on ${device.name}');
    }
  }

  /// The world and one plan (reminder on, lead 7) due 2026-11-20, made on the laptop and synced.
  Future<({({String account, String category}) world, wire.Plan plan, String occurrence})>
  synced() async {
    final world = await planWorld(laptopLedger);
    final plan = Device.ok(
      await laptop.createPlan(
        planRequest(world, reminder: wire.Reminder(enabled: true, leadDays: 7)),
      ),
    );
    await devices.sync();
    final occurrence = Device.ok(await laptop.occurrenceOf(plan.id, '2026-11-20', asOf: noon));
    return (world: world, plan: plan, occurrence: occurrence.id);
  }

  wire.UpdatePlanRequest edit(({String account, String category}) world, {String title = 'Rent'}) =>
      updateOf(
        planRequest(world, title: title, reminder: wire.Reminder(enabled: true, leadDays: 7)),
      );

  group('a plan write never brings back a plan a sync just deleted', () {
    test('replace: 404, the plan stays deleted on both devices', () async {
      final s = await synced();
      Device.ok(await phone.deletePlan(s.plan.id));
      final received = queuePhoneChanges(['plans:${s.plan.id}']);
      final write = laptop.replacePlan(s.plan.id, edit(s.world, title: 'Rent 2'));
      expectRefused(await write, status: 404, rule: '6.33');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(device.store.plans.get(s.plan.id).errorOrNull, isA<ZenNotFoundError>());
      }
      expectNoConflicts();
    });

    test('skip: 404, no state is written for a plan that is gone', () async {
      final s = await synced();
      Device.ok(await phone.deletePlan(s.plan.id));
      final received = queuePhoneChanges(['plans:${s.plan.id}']);
      final write = laptop.skip(s.occurrence, asOf: noon);
      expectRefused(await write, status: 404);
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.store.occurrences.list()), isEmpty);
      }
      expectNoConflicts();
    });

    test('confirm: 404, no record is written for a plan that is gone', () async {
      final s = await synced();
      Device.ok(await phone.deletePlan(s.plan.id));
      final received = queuePhoneChanges(['plans:${s.plan.id}']);
      final write = laptop.confirm(s.occurrence, wire.ConfirmOccurrenceRequest(), asOf: noon);
      expectRefused(await write, status: 404);
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.store.records.list()), isEmpty);
      }
      expectNoConflicts();
    });
  });

  group('a plan write never goes over an edit a sync merged in meanwhile', () {
    test('replace: 409 under X.7, and the other device\'s title survives on both', () async {
      final s = await synced();
      Device.ok(await phone.replacePlan(s.plan.id, edit(s.world, title: 'Phone title')));
      final received = queuePhoneChanges(['plans:${s.plan.id}']);
      final write = laptop.replacePlan(s.plan.id, edit(s.world, title: 'Laptop title'));
      expectRefused(await write, status: 409, rule: 'X.7');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.store.plans.get(s.plan.id)).title, 'Phone title');
      }
      expectNoConflicts();
    });

    test('delete: 409 under X.7, and the plan with its edit survives on both', () async {
      final s = await synced();
      Device.ok(await phone.replacePlan(s.plan.id, edit(s.world, title: 'Phone title')));
      final received = queuePhoneChanges(['plans:${s.plan.id}']);
      final write = laptop.deletePlan(s.plan.id);
      expectRefused(await write, status: 409, rule: 'X.7');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.store.plans.get(s.plan.id)).title, 'Phone title');
      }
      expectNoConflicts();
    });

    test('skip: 409, when the other device skipped the occurrence first', () async {
      final s = await synced();
      Device.ok(await phone.skip(s.occurrence, asOf: noon));
      final received = queuePhoneChanges(['occurrences:${s.occurrence}']);
      final write = laptop.skip(s.occurrence, asOf: noon);
      expectRefused(await write, status: 409);
      await received;
      await devices.sync();
      expectNoConflicts();
    });

    test('mark read: 409, when the other device read it first, and its time survives', () async {
      final s = await synced();
      final first = DateTime.utc(2026, 11, 16, 7);
      Device.ok(await phone.markRead(s.occurrence, asOf: first));
      final received = queuePhoneChanges(['occurrences:${s.occurrence}']);
      final write = laptop.markRead(s.occurrence, asOf: DateTime.utc(2026, 11, 16, 9));
      expectRefused(await write, status: 409);
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(
          Device.ok(device.store.occurrences.get(s.occurrence)).reminderReadAtMs,
          Int64(first.millisecondsSinceEpoch),
        );
      }
      expectNoConflicts();
    });

    test(
      'confirm: 409 when the other device confirmed it first, and its record survives',
      () async {
        final s = await synced();
        final theirs = Device.ok(
          await phone.confirm(
            s.occurrence,
            wire.ConfirmOccurrenceRequest(amountMinor: Int64(-200)),
            asOf: noon,
          ),
        );
        final received = queuePhoneChanges(['records:${theirs.record.id}']);
        final write = laptop.confirm(
          s.occurrence,
          wire.ConfirmOccurrenceRequest(amountMinor: Int64(-100)),
          asOf: noon,
        );
        expectRefused(await write, status: 409, rule: '6.37');
        await received;
        await devices.sync();
        for (final device in devices.both) {
          final record = Device.ok(device.store.records.get(theirs.record.id));
          expect(record.posting.amountMinor, Int64(-200));
        }
        expectNoConflicts();
      },
    );
  });

  group('a change to an occurrence\'s state a sync landed meanwhile refuses the write (X.7)', () {
    /// The occurrence's reminder read on the laptop and synced, so both devices hold its state.
    Future<({({String account, String category}) world, wire.Plan plan, String occurrence})>
    withState() async {
      final s = await synced();
      Device.ok(await laptop.markRead(s.occurrence, asOf: DateTime.utc(2026, 11, 16, 7)));
      await devices.sync();
      return s;
    }

    test('delete plan, after the peer skipped the occurrence it had read', () async {
      final s = await withState();
      Device.ok(await phone.skip(s.occurrence, asOf: noon));
      final received = queuePhoneChanges(['occurrences:${s.occurrence}']);
      final write = laptop.deletePlan(s.plan.id);
      expectRefused(await write, status: 409, rule: 'X.7');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(device.store.plans.get(s.plan.id).isSuccess, isTrue, reason: device.name);
      }
      expectNoConflicts();
    });

    test('replace plan dropping a state, after the peer skipped that occurrence', () async {
      final s = await withState();
      Device.ok(await phone.skip(s.occurrence, asOf: noon));
      final received = queuePhoneChanges(['occurrences:${s.occurrence}']);
      // A schedule that no longer produces 2026-11-20 would drop its planned, read state.
      final write = laptop.replacePlan(
        s.plan.id,
        updateOf(
          planRequest(
            s.world,
            recurrence_: recurrence(start: '2026-12-01'),
            reminder: wire.Reminder(enabled: true, leadDays: 7),
          ),
        ),
      );
      expectRefused(await write, status: 409, rule: 'X.7');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.store.occurrences.get(s.occurrence)).skipped, isTrue);
        expect(Device.ok(device.store.plans.get(s.plan.id)).schedule.startDate, '2026-11-20');
      }
      expectNoConflicts();
    });

    test(
      'confirm, after the peer marked the reminder unread (the state it read is gone)',
      () async {
        final s = await withState();
        Device.ok(await phone.markUnread(s.occurrence, asOf: noon));
        final received = queuePhoneChanges(['occurrences:${s.occurrence}']);
        final write = laptop.confirm(s.occurrence, wire.ConfirmOccurrenceRequest(), asOf: noon);
        expectRefused(await write, status: 409, rule: 'X.7');
        await received;
        await devices.sync();
        for (final device in devices.both) {
          expect(Device.ok(device.store.records.list()), isEmpty, reason: device.name);
        }
        expectNoConflicts();
      },
    );

    test('mark unread, after the peer skipped the occurrence', () async {
      final s = await withState();
      Device.ok(await phone.skip(s.occurrence, asOf: noon));
      final received = queuePhoneChanges(['occurrences:${s.occurrence}']);
      final write = laptop.markUnread(s.occurrence, asOf: noon);
      expectRefused(await write, status: 409, rule: 'X.7');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.store.occurrences.get(s.occurrence)).skipped, isTrue);
      }
      expectNoConflicts();
    });

    // Unlike the others, this refusal does not come from the state's expect: the skipped state the
    // laptop read has vanished, and jZen answers a delete of an absent record itself, before any
    // precondition runs; `_write(missing:)` maps that to the same 409. The expect on this delete would
    // differ only for a skipped state that was *edited* meanwhile, which no operation does (a skipped
    // occurrence has no reminder to read, and a restore deletes the state). Removing it leaves this
    // test green, and that is why it is listed as such in ADR-122.
    test('restore, after the peer restored it first (the skipped state it read is gone)', () async {
      final s = await synced();
      Device.ok(await laptop.skip(s.occurrence, asOf: noon));
      await devices.sync();
      Device.ok(await phone.restore(s.occurrence, asOf: noon));
      final received = queuePhoneChanges(['occurrences:${s.occurrence}']);
      final write = laptop.restore(s.occurrence, asOf: noon);
      expectRefused(await write, status: 409, rule: 'X.7');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(device.store.occurrences.get(s.occurrence).errorOrNull, isA<ZenNotFoundError>());
      }
      expectNoConflicts();
    });

    test('read all, after the peer read one of them (a state it read as absent exists)', () async {
      final s = await synced();
      Device.ok(await phone.markRead(s.occurrence, asOf: DateTime.utc(2026, 11, 16, 7)));
      final received = queuePhoneChanges(['occurrences:${s.occurrence}']);
      final write = laptop.markAllRead(asOf: noon);
      expectRefused(await write, status: 409, rule: 'X.7');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(
          Device.ok(device.store.occurrences.get(s.occurrence)).reminderReadAtMs,
          Int64(DateTime.utc(2026, 11, 16, 7).millisecondsSinceEpoch),
        );
      }
      expectNoConflicts();
    });
  });

  // `createPlan`'s expect (absent) has no test, on purpose: it is unreachable. A new plan's id is
  // minted from 128 random bits on this device a moment before the write, so no other device can
  // hold a record under it, and no sync can deliver one in between. The expect is there so that
  // every write of this class carries one, not because a case can be built.

  test('a skip on one device and a schedule change on the other leave no conflict', () async {
    final s = await synced();
    Device.ok(await laptop.skip(s.occurrence, asOf: noon));
    Device.ok(await phone.replacePlan(s.plan.id, edit(s.world, title: 'Phone title')));
    await devices.sync();
    for (final device in devices.both) {
      expect(Device.ok(device.store.plans.get(s.plan.id)).title, 'Phone title');
      expect(Device.ok(device.store.occurrences.get(s.occurrence)).skipped, isTrue);
    }
    expectNoConflicts();
  });

  test('a confirmation is one write: the record and the plan it was decided against', () async {
    final s = await synced();
    Device.ok(await phone.replacePlan(s.plan.id, edit(s.world, title: 'Phone title')));
    final received = queuePhoneChanges(['plans:${s.plan.id}']);
    final write = laptop.confirm(s.occurrence, wire.ConfirmOccurrenceRequest(), asOf: noon);
    expectRefused(await write, status: 409, rule: 'X.7');
    await received;
    for (final device in devices.both) {
      expect(Device.ok(device.store.records.list()), isEmpty, reason: device.name);
    }
  });
}
