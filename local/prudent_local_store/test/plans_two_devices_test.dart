// Unit 6b's two-device cases (ADR-119): plans, occurrences and reminders on two real sessions — two
// encrypted stores, each with its own key and directory — synced through jZen's ZenFolderCloud.
//
// What is proven: two devices that confirm one occurrence offline write one record, never two; a
// skip on one device and a confirmation on the other end as a completed occurrence that the
// integrity runner lists and the person settles; a plan two devices edited differently has no
// occurrence in any list and no reminder, and cannot be confirmed, until it is settled — and says
// so; a reminder read on two devices keeps the first time without a question; a plan one device
// deleted while the other confirmed an occurrence leaves a record that reads as detached.
import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

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

  /// The world and one plan with a reminder due 2026-11-20, made on the laptop and synced.
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

  List<String> issueCodes(Device device) => [
    for (final issue in Device.ok(device.integrity().evaluate())) issue.code,
  ];

  test('two devices that confirm one occurrence offline write one record', () async {
    final s = await synced();
    final onLaptop = Device.ok(
      await laptop.confirm(s.occurrence, wire.ConfirmOccurrenceRequest(), asOf: noon),
    );
    final onPhone = Device.ok(
      await phone.confirm(s.occurrence, wire.ConfirmOccurrenceRequest(), asOf: noon),
    );
    expect(onLaptop.record.id, onPhone.record.id);
    await devices.sync();
    for (final device in devices.both) {
      expect(Device.ok(device.store.records.list()), hasLength(1));
      expect(Device.ok(device.store.records.conflicts()), isEmpty);
    }
    expect(
      Device.ok(await laptopLedger.accountBalances(s.world.account)).minor['PLN'],
      100000 - 150000,
    );
  });

  test(
    'two confirmations that differ are one record in conflict, left out of the balance',
    () async {
      final s = await synced();
      Device.ok(
        await laptop.confirm(
          s.occurrence,
          wire.ConfirmOccurrenceRequest(amountMinor: Int64(-100)),
          asOf: noon,
        ),
      );
      Device.ok(
        await phone.confirm(
          s.occurrence,
          wire.ConfirmOccurrenceRequest(amountMinor: Int64(-200)),
          asOf: noon,
        ),
      );
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.store.records.list()), hasLength(1));
        expect(Device.ok(device.store.records.conflicts()), hasLength(1));
        final balances = Device.ok(await Ledger(device.store).accountBalances(s.world.account));
        expect(balances.minor['PLN'], 100000, reason: 'a disputed amount counts in no balance');
        expect(balances.unsettled, hasLength(1));
      }
    },
  );

  test(
    'a skip on one device and a confirmation on the other end completed, and are listed',
    () async {
      final s = await synced();
      Device.ok(await laptop.skip(s.occurrence, asOf: noon));
      Device.ok(await phone.confirm(s.occurrence, wire.ConfirmOccurrenceRequest(), asOf: noon));
      await devices.sync();
      for (final device in devices.both) {
        final plans = PlanLedger(device.store);
        expect(
          Device.ok(await plans.occurrenceOf(s.plan.id, '2026-11-20', asOf: noon)).status,
          wire.OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED,
          reason: 'money moved, so the occurrence reads as paid',
        );
        expect(issueCodes(device), ['occurrence.skipped_and_paid']);
      }
      // The person takes the skip back; the other device sees the issue go.
      final issue = Device.ok(devices.laptop.integrity().evaluate()).single;
      Device.ok(await issue.actions.firstWhere((a) => a.code == 'clear_skip').run());
      await devices.sync();
      for (final device in devices.both) {
        expect(issueCodes(device), isEmpty);
      }
    },
  );

  test(
    'a plan two devices edited differently has no occurrence and no reminder until settled',
    () async {
      final s = await synced();
      Device.ok(
        await laptop.replacePlan(
          s.plan.id,
          updateOf(
            planRequest(s.world, amount: -100, reminder: wire.Reminder(enabled: true, leadDays: 7)),
          ),
        ),
      );
      Device.ok(
        await phone.replacePlan(
          s.plan.id,
          updateOf(
            planRequest(s.world, amount: -200, reminder: wire.Reminder(enabled: true, leadDays: 7)),
          ),
        ),
      );
      await devices.sync();
      for (final plans in [laptop, phone]) {
        final upcoming = Device.ok(await plans.upcoming(asOf: noon));
        expect(upcoming.value.occurrences, isEmpty, reason: 'the amount is in dispute');
        expect(upcoming.unsettled.keys, [s.plan.id]);
        final reminders = Device.ok(await plans.reminders(asOf: noon));
        expect(reminders.value.reminders, isEmpty);
        expect(reminders.unsettled.keys, [s.plan.id]);
        final overdue = Device.ok(await plans.overdue(asOf: DateTime.utc(2026, 12, 1)));
        expect(overdue.value.occurrences, isEmpty);
        expect(overdue.isSettled, isFalse);
        final refusal = await plans.skip(s.occurrence, asOf: noon);
        expect(refusal, isA<ZenFailure<Object?>>());
        expect(LedgerErrors.statusOf((refusal as ZenFailure).error), 409);
        expect(
          LedgerErrors.statusOf(
            (await plans.confirm(
              s.occurrence,
              wire.ConfirmOccurrenceRequest(),
              asOf: noon,
            ) as ZenFailure).error,
          ),
          409,
        );
      }
    },
  );

  test('a conflict about a plan\'s title leaves its occurrences settled', () async {
    final s = await synced();
    Device.ok(
      await laptop.replacePlan(
        s.plan.id,
        updateOf(
          planRequest(
            s.world,
            title: 'Rent A',
            reminder: wire.Reminder(enabled: true, leadDays: 7),
          ),
        ),
      ),
    );
    Device.ok(
      await phone.replacePlan(
        s.plan.id,
        updateOf(
          planRequest(
            s.world,
            title: 'Rent B',
            reminder: wire.Reminder(enabled: true, leadDays: 7),
          ),
        ),
      ),
    );
    await devices.sync();
    for (final plans in [laptop, phone]) {
      final upcoming = Device.ok(await plans.upcoming(asOf: noon));
      expect(upcoming.isSettled, isTrue);
      expect(upcoming.value.occurrences, hasLength(1));
    }
  });

  test('a reminder read on two devices keeps the first time, without a question', () async {
    final s = await synced();
    Device.ok(await laptop.markRead(s.occurrence, asOf: DateTime.utc(2026, 11, 16, 9)));
    Device.ok(await phone.markRead(s.occurrence, asOf: DateTime.utc(2026, 11, 16, 7)));
    await devices.sync();
    for (final device in devices.both) {
      expect(Device.ok(device.store.occurrences.conflicts()), isEmpty);
      expect(
        Device.ok(device.store.occurrences.get(s.occurrence)).reminderReadAtMs,
        Int64(DateTime.utc(2026, 11, 16, 7).millisecondsSinceEpoch),
      );
    }
  });

  test('a plan deleted on one device while the other confirmed leaves a detached record', () async {
    final s = await synced();
    Device.ok(await laptop.deletePlan(s.plan.id));
    Device.ok(await phone.confirm(s.occurrence, wire.ConfirmOccurrenceRequest(), asOf: noon));
    await devices.sync();
    for (final device in devices.both) {
      final ledger = Ledger(device.store);
      final records = Device.ok(await ledger.listRecords()).records;
      expect(records, hasLength(1));
      expect(
        records.single.hasPlanId(),
        isFalse,
        reason: 'its plan is gone, so it reads as detached',
      );
      expect(
        Device.ok(await PlanLedger(device.store).upcoming(asOf: noon)).value.occurrences,
        isEmpty,
      );
    }
  });
}
