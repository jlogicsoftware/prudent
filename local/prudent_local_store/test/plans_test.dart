// Unit 6b's rules on one device (phase-0 §0.3 rows 6.29–6.45, 6.51–6.53, ADR-119): plans,
// occurrences and reminders with the day pinned by `asOf`. The same rules run against the live
// server through the parity scenarios (plans, occurrence_windows, occurrences, day_boundary,
// reminders); these tests pin what the scenarios cannot see — the records written and not written,
// presence-exactness, the exact instant a day turns over in a plan's zone, the order of ties.
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import 'support/plan_fixtures.dart';
import 'support/two_devices.dart';

void main() {
  late Directory directory;
  late ZenStore zen;
  late PrudentLocalStore store;
  late Ledger ledger;
  late PlanLedger plans;
  late ({String account, String category}) world;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prudent_plans_test');
    zen = Device.ok(await ZenStore.open(directory, deviceName: 'one', key: List.filled(32, 5)));
    store = PrudentLocalStore(zen);
    ledger = Ledger(store);
    plans = PlanLedger(store);
    world = await planWorld(ledger);
  });
  tearDown(() async {
    await zen.close();
    await directory.delete(recursive: true);
  });

  (int, String) refused<T>(ZenResult<T> result) => switch (result) {
    ZenSuccess(:final data) => fail('expected a refusal, got $data'),
    ZenFailure(:final error) => (
      LedgerErrors.statusOf(error) ?? fail('not a ledger refusal: ${error.message}'),
      error.internalData!['rule'] as String,
    ),
  };

  Future<wire.Plan> create(wire.CreatePlanRequest request) async =>
      Device.ok(await plans.createPlan(request));

  /// The occurrence of [plan] on [date] as the views list it.
  Future<wire.PlanOccurrence> occurrence(String plan, String date, {DateTime? asOf}) async =>
      Device.ok(await plans.occurrenceOf(plan, date, asOf: asOf ?? noon));

  Future<List<wire.PlanOccurrence>> upcoming({int? days, DateTime? asOf}) async =>
      Device.ok(await plans.upcoming(days: days, asOf: asOf ?? noon)).value.occurrences;

  Future<List<wire.PlanOccurrence>> overdue({DateTime? asOf}) async =>
      Device.ok(await plans.overdue(asOf: asOf ?? noon)).value.occurrences;

  int stored(String collection) => switch (collection) {
    'states' => Device.ok(store.occurrences.list()).length,
    'records' => Device.ok(store.records.list()).length,
    _ => fail(collection),
  };

  group('a plan (rows 6.29–6.33)', () {
    test('is refused by the record rules, each in its status', () async {
      Future<(int, String)> attempt(wire.CreatePlanRequest r) async =>
          refused(await plans.createPlan(r));
      final base = planRequest(world);
      expect(await attempt(planRequest(world, title: '  ')), (400, '6.29'));
      expect(await attempt(planRequest(world, amount: 0)), (400, '6.29'));
      expect(await attempt(planRequest(world, currency: 'USD')), (400, '6.29'));
      expect((await attempt(planRequest(world, currency: 'XX'))).$1, 400);
      expect(await attempt(base.deepCopy()..accountId = 'nope'), (400, '6.29'));
      expect(await attempt(base.deepCopy()..categoryId = ''), (400, '6.29'));
      expect(await attempt(planRequest(world, amount: 5000)), (400, '6.29'));
      expect(await attempt(base.deepCopy()..clearRecurrence()), (400, '6.30'));
      expect(stored('states'), 0);
      expect(Device.ok(store.plans.list()), isEmpty);
    });

    test('keeps a lead time of 0 and answers a reminder at its default', () async {
      final withZero = await create(
        planRequest(world, reminder: wire.Reminder(enabled: true, leadDays: 0)),
      );
      expect(withZero.reminder.enabled, isTrue);
      expect(withZero.reminder.leadDays, 0);
      final plain = await create(planRequest(world));
      expect(plain.reminder.enabled, isFalse);
      expect(plain.reminder.leadDays, 1);
      // Presence-exact (jZenDev/jZen#245): a reminder that is off at its default lead is no
      // reminder in the store at all, and lead 0 is present while 1 is absent.
      expect(Device.ok(store.plans.get(plain.id)).hasReminder(), isFalse);
      final storedZero = Device.ok(store.plans.get(withZero.id)).reminder;
      expect(storedZero.hasLeadDays(), isTrue);
      expect(storedZero.leadDays, 0);
      final offAtThree = await create(
        planRequest(world, reminder: wire.Reminder(enabled: false, leadDays: 3)),
      );
      expect(
        offAtThree.reminder.leadDays,
        3,
        reason: 'a lead time is kept while the reminder is off',
      );
      final seven = await create(
        planRequest(world, reminder: wire.Reminder(enabled: true, leadDays: 7)),
      );
      expect(Device.ok(store.plans.get(seven.id)).reminder.hasLeadDays(), isTrue);
      final one = await create(
        planRequest(world, reminder: wire.Reminder(enabled: true, leadDays: 1)),
      );
      expect(Device.ok(store.plans.get(one.id)).reminder.hasLeadDays(), isFalse);
    });

    test('refuses a lead time outside {0, 1, 2, 3, 7} and rounds nothing (F-08)', () async {
      for (final lead in [4, 5, 6, 8, 14, 365, 366]) {
        expect(
          refused(
            await plans.createPlan(
              planRequest(world, reminder: wire.Reminder(enabled: true, leadDays: lead)),
            ),
          ),
          (400, '6.32'),
          reason: '$lead',
        );
      }
    });

    test('is replaced whole: an absent reminder resets it and a payee clears', () async {
      final request = planRequest(world, reminder: wire.Reminder(enabled: true, leadDays: 3))
        ..payee = 'Landlord';
      final plan = await create(request);
      final replaced = Device.ok(
        await plans.replacePlan(plan.id, updateOf(planRequest(world, title: 'Rent 2'))),
      );
      expect(replaced.title, 'Rent 2');
      expect(replaced.hasPayee(), isFalse);
      expect(replaced.reminder.enabled, isFalse);
      expect(replaced.reminder.leadDays, 1);
    });

    test('is listed by start date and then id, and an unknown id is 404', () async {
      final late = await create(
        planRequest(
          world,
          title: 'Late',
          recurrence_: recurrence(start: '2026-12-01'),
        ),
      );
      final early = await create(
        planRequest(
          world,
          title: 'Early',
          recurrence_: recurrence(start: '2026-11-01'),
        ),
      );
      final listed = Device.ok(await plans.listPlans()).plans.map((p) => p.id).toList();
      expect(listed, [early.id, late.id]);
      expect(refused(await plans.getPlan('nope')), (404, '6.33'));
      expect(refused(await plans.replacePlan('f' * 32, updateOf(planRequest(world)))), (
        404,
        '6.33',
      ));
      expect(refused(await plans.deletePlan('f' * 32)), (404, '6.33'));
    });

    test('holds its account\'s currency, its account and its category in place', () async {
      await create(planRequest(world));
      expect(refused(await ledger.deleteAccount(world.account)).$1, 409);
      expect(refused(await ledger.deleteCategory(world.category)).$1, 409);
    });
  });

  group('the day in a plan\'s own zone (rows 6.38, 6.42, 6.45)', () {
    test('turns over at the zone\'s midnight, to the millisecond', () async {
      // 23:00 UTC on 2026-11-19 is midnight in Warsaw (UTC+1 in November): the 20th begins.
      final plan = await create(
        planRequest(
          world,
          recurrence_: recurrence(start: '2026-11-19', zone: 'Europe/Warsaw'),
        ),
      );
      final before = DateTime.utc(2026, 11, 19, 22, 59, 59, 999);
      final after = DateTime.utc(2026, 11, 19, 23);
      expect(
        (await occurrence(plan.id, '2026-11-19', asOf: before)).status,
        wire.OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
      );
      expect(
        (await occurrence(plan.id, '2026-11-19', asOf: after)).status,
        wire.OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE,
      );
      expect(await overdue(asOf: before), isEmpty);
      expect((await overdue(asOf: after)).map((o) => o.planId), [plan.id]);
    });

    test('is reckoned per plan, not once for the device', () async {
      final warsaw = await create(
        planRequest(
          world,
          recurrence_: recurrence(start: '2026-11-19', zone: 'Europe/Warsaw'),
        ),
      );
      final honolulu = await create(
        planRequest(
          world,
          recurrence_: recurrence(start: '2026-11-19', zone: 'Pacific/Honolulu'),
        ),
      );
      final instant = DateTime.utc(
        2026,
        11,
        20,
        3,
      ); // the 20th in Warsaw, still the 19th in Honolulu
      expect((await overdue(asOf: instant)).map((o) => o.planId), [warsaw.id]);
      expect((await upcoming(asOf: instant)).map((o) => o.planId), [honolulu.id]);
    });

    test('a reminder falls due the day its lead begins, in the plan\'s zone', () async {
      final plan = await create(
        planRequest(
          world,
          recurrence_: recurrence(start: '2026-11-22', zone: 'Pacific/Kiritimati'),
          reminder: wire.Reminder(enabled: true, leadDays: 2),
        ),
      );
      // Kiritimati is UTC+14: 10:00 UTC on the 19th is already the 20th there, two days before the 22nd.
      final due = Device.ok(await plans.reminders(asOf: DateTime.utc(2026, 11, 19, 10))).value;
      expect(due.reminders.map((r) => r.occurrence.planId), [plan.id]);
      expect(due.reminders.single.remindOn, '2026-11-20');
      final notYet = Device.ok(await plans.reminders(asOf: DateTime.utc(2026, 11, 19, 9, 59)))
          .value;
      expect(notYet.reminders, isEmpty);
    });
  });

  group('occurrences (rows 6.35–6.41)', () {
    test('are derived, never stored, until a person decides something', () async {
      final plan = await create(
        planRequest(
          world,
          recurrence_: recurrence(
            frequency: wire.RecurrenceFrequency.RECURRENCE_FREQUENCY_DAILY,
            interval: 1,
            start: '2026-11-10',
          ),
        ),
      );
      expect((await upcoming(days: 5)).length, 6);
      expect((await overdue()).length, 6);
      expect(stored('states'), 0, reason: 'listing generates nothing');
      final one = await occurrence(plan.id, '2026-11-18');
      Device.ok(await plans.skip(one.id, asOf: noon));
      expect(stored('states'), 1);
      Device.ok(await plans.restore(one.id, asOf: noon));
      expect(stored('states'), 0, reason: 'a state that is the default is not stored');
    });

    test('move planned → skipped → planned, and refuse everything else', () async {
      final plan = await create(planRequest(world));
      final o = await occurrence(plan.id, '2026-11-20');
      expect(refused(await plans.restore(o.id, asOf: noon)), (409, '6.37'));
      expect(
        Device.ok(await plans.skip(o.id, asOf: noon)).status,
        wire.OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED,
      );
      expect(refused(await plans.skip(o.id, asOf: noon)), (409, '6.37'));
      expect(refused(await plans.confirm(o.id, wire.ConfirmOccurrenceRequest(), asOf: noon)), (
        409,
        '6.37',
      ));
      expect(
        Device.ok(await plans.restore(o.id, asOf: noon)).status,
        wire.OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
      );
      expect(refused(await plans.skip('nope', asOf: noon)), (404, '6.35'));
    });

    test('are completed by exactly one record, and deleting it reopens the occurrence', () async {
      final plan = await create(planRequest(world, title: 'Rent'));
      final o = await occurrence(plan.id, '2026-11-20');
      final first = Device.ok(
        await plans.confirm(o.id, wire.ConfirmOccurrenceRequest(), asOf: noon),
      );
      expect(first.occurrence.status, wire.OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED);
      expect(first.record.planId, plan.id);
      expect(first.record.planOccurrenceId, o.id);
      expect(first.record.title, 'Rent');
      expect(first.record.amountMinor, Int64(-150000));
      // A second confirmation is refused and writes nothing.
      expect(refused(await plans.confirm(o.id, wire.ConfirmOccurrenceRequest(), asOf: noon)), (
        409,
        '6.37',
      ));
      expect(stored('records'), 1);
      expect(refused(await plans.skip(o.id, asOf: noon)), (409, '6.37'));
      expect(refused(await plans.restore(o.id, asOf: noon)), (409, '6.37'));
      // The record carries the id derived from the occurrence and its date, so two devices write one.
      final record = Device.ok(store.records.get(first.record.id));
      expect(record.id, DerivedIds.confirmation(o.id));
      expect(record.planLink.occurrenceDate, '2026-11-20');
      // The balance moved by the record, and moves back when it is deleted.
      Future<int> balance() async =>
          Device.ok(await ledger.accountBalances(world.account)).minor['PLN']!;
      expect(await balance(), 100000 - 150000);
      Device.ok(await ledger.deleteRecord(first.record.id));
      expect(await balance(), 100000);
      expect(
        (await occurrence(plan.id, '2026-11-20')).status,
        wire.OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
      );
      Device.ok(await plans.confirm(o.id, wire.ConfirmOccurrenceRequest(), asOf: noon));
      expect(await balance(), 100000 - 150000);
    });

    test(
      'are confirmed with overrides validated as a record, and a refusal writes nothing',
      () async {
        final plan = await create(planRequest(world));
        final o = await occurrence(plan.id, '2026-11-20');
        Future<(int, String)> attempt(wire.ConfirmOccurrenceRequest r) async =>
            refused(await plans.confirm(o.id, r, asOf: noon));
        expect((await attempt(wire.ConfirmOccurrenceRequest(amountMinor: Int64(0)))).$1, 400);
        expect((await attempt(wire.ConfirmOccurrenceRequest(date: 'tomorrow'))).$1, 400);
        expect((await attempt(wire.ConfirmOccurrenceRequest(accountId: 'nope'))).$1, 400);
        expect((await attempt(wire.ConfirmOccurrenceRequest(categoryId: ''))).$1, 400);
        expect(
          (await attempt(wire.ConfirmOccurrenceRequest(amountMinor: Int64(500)))).$1,
          400,
          reason: 'income in an expense category',
        );
        expect(stored('records'), 0);
        expect(
          Device.ok(await plans.occurrenceOf(plan.id, '2026-11-20', asOf: noon)).status,
          wire.OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
        );
        final ok = Device.ok(
          await plans.confirm(
            o.id,
            wire.ConfirmOccurrenceRequest(date: '2026-11-18', amountMinor: Int64(-99)),
            asOf: noon,
          ),
        );
        expect(ok.record.date, '2026-11-18');
        expect(ok.record.amountMinor, Int64(-99));
      },
    );

    test('are listed after the plan\'s schedule changed when a person decided them', () async {
      final plan = await create(
        planRequest(
          world,
          recurrence_: recurrence(
            frequency: wire.RecurrenceFrequency.RECURRENCE_FREQUENCY_DAILY,
            interval: 1,
            start: '2026-11-16',
            count: 10,
          ),
        ),
      );
      final skipped = await occurrence(plan.id, '2026-11-17');
      final paid = await occurrence(plan.id, '2026-11-18');
      Device.ok(await plans.skip(skipped.id, asOf: noon));
      Device.ok(await plans.confirm(paid.id, wire.ConfirmOccurrenceRequest(), asOf: noon));
      // A new schedule that produces none of those dates: planned ones go, decided ones stay.
      Device.ok(
        await plans.replacePlan(
          plan.id,
          updateOf(planRequest(world, recurrence_: recurrence(start: '2026-12-01'))),
        ),
      );
      final listed = (await upcoming(days: 30)).map((o) => (o.occurrenceDate, o.status)).toList();
      expect(listed.where((e) => e.$1.compareTo('2026-11-16') >= 0).toList(), [
        ('2026-11-17', wire.OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED),
        ('2026-11-18', wire.OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED),
        ('2026-12-01', wire.OccurrenceStatus.OCCURRENCE_STATUS_PLANNED),
      ]);
      expect(await overdue(), isEmpty);
    });

    test(
      'stay listed, planned, when the record that confirmed one is deleted after a new schedule',
      () async {
        final plan = await create(planRequest(world));
        final o = await occurrence(plan.id, '2026-11-20');
        final paid = Device.ok(
          await plans.confirm(o.id, wire.ConfirmOccurrenceRequest(), asOf: noon),
        );
        Device.ok(
          await plans.replacePlan(
            plan.id,
            updateOf(planRequest(world, recurrence_: recurrence(start: '2026-12-01'))),
          ),
        );
        Device.ok(await ledger.deleteRecord(paid.record.id));
        // The server keeps the occurrence row: reopened, still there, though the schedule moved on.
        expect((await upcoming(days: 30)).map((x) => (x.occurrenceDate, x.status)).toList(), [
          ('2026-11-20', wire.OccurrenceStatus.OCCURRENCE_STATUS_PLANNED),
          ('2026-12-01', wire.OccurrenceStatus.OCCURRENCE_STATUS_PLANNED),
        ]);
        expect(stored('records'), 0);
      },
    );

    test('are deleted with the plan, whose records stay and read as detached', () async {
      final plan = await create(planRequest(world));
      final o = await occurrence(plan.id, '2026-11-20');
      final confirmed = Device.ok(
        await plans.confirm(o.id, wire.ConfirmOccurrenceRequest(), asOf: noon),
      );
      final other = await create(planRequest(world, recurrence_: recurrence(start: '2026-11-25')));
      Device.ok(await plans.skip((await occurrence(other.id, '2026-11-25')).id, asOf: noon));
      Device.ok(await plans.deletePlan(plan.id));
      Device.ok(await plans.deletePlan(other.id));
      // The plan and every state of it went in one write; the record is still in the ledger and
      // still moves the balance, and it now reads as an ordinary one.
      expect(stored('states'), 0);
      expect(stored('records'), 1);
      expect(Device.ok(await ledger.accountBalances(world.account)).minor['PLN'], 100000 - 150000);
      final record = Device.ok(await ledger.getRecord(confirmed.record.id));
      expect(record.hasPlanId(), isFalse);
      expect(record.hasPlanOccurrenceId(), isFalse);
      expect(refused(await plans.skip(o.id, asOf: noon)), (404, '6.35'));
      expect(await upcoming(days: 30), isEmpty);
      // An ordinary record: editable and deletable like any other.
      Device.ok(await ledger.deleteRecord(confirmed.record.id));
      expect(stored('records'), 0);
    });

    test('refuse days outside 1–366 and tie-break by Java\'s signed UUID order (F-11)', () async {
      for (final days in [0, 367, -3]) {
        expect(refused(await plans.upcoming(days: days, asOf: noon)), (
          400,
          '6.51',
        ), reason: '$days');
      }
      for (var i = 0; i < 8; i++) {
        await create(planRequest(world, title: 'Same day $i'));
      }
      final ids = (await upcoming(days: 30)).map((o) => o.id).toList();
      expect(ids.length, 8);
      expect(ids, [...ids]..sort(LocalIds.compareAsJavaUuid));
    });
  });

  group('reminders (rows 6.42, 6.43, 6.52)', () {
    test('are read keeping the first time, unread, ended by skip and confirm', () async {
      final plan = await create(
        planRequest(world, reminder: wire.Reminder(enabled: true, leadDays: 7)),
      );
      final o = await occurrence(plan.id, '2026-11-20');
      final t1 = DateTime.utc(2026, 11, 16, 9);
      final t2 = DateTime.utc(2026, 11, 16, 18);
      Device.ok(await plans.markRead(o.id, asOf: t1));
      Device.ok(await plans.markRead(o.id, asOf: t2));
      expect(
        Device.ok(store.occurrences.get(o.id)).reminderReadAtMs,
        Int64(t1.millisecondsSinceEpoch),
      );
      expect(Device.ok(await plans.reminders(asOf: noon)).value.reminders.single.read, isTrue);
      Device.ok(await plans.markUnread(o.id, asOf: noon));
      expect(stored('states'), 0);
      expect(Device.ok(await plans.reminders(asOf: noon)).value.reminders.single.read, isFalse);
      Device.ok(await plans.skip(o.id, asOf: noon));
      expect(Device.ok(await plans.reminders(asOf: noon)).value.reminders, isEmpty);
      expect(refused(await plans.markRead(o.id, asOf: noon)), (409, '6.43'));
      Device.ok(await plans.restore(o.id, asOf: noon));
      Device.ok(await plans.confirm(o.id, wire.ConfirmOccurrenceRequest(), asOf: noon));
      expect(Device.ok(await plans.reminders(asOf: noon)).value.reminders, isEmpty);
    });

    test('read-all marks every current reminder in one write and keeps earlier times', () async {
      final a = await create(
        planRequest(world, reminder: wire.Reminder(enabled: true, leadDays: 7)),
      );
      await create(
        planRequest(
          world,
          recurrence_: recurrence(start: '2026-11-17'),
          reminder: wire.Reminder(enabled: true, leadDays: 0),
        ),
      );
      final early = DateTime.utc(2026, 11, 16, 8);
      Device.ok(await plans.markRead((await occurrence(a.id, '2026-11-20')).id, asOf: early));
      final all = Device.ok(await plans.markAllRead(asOf: noon)).value;
      expect(all.reminders.map((r) => r.read), [true]);
      expect(stored('states'), 1, reason: 'the second is ahead of its lead and has no reminder');
    });

    test(
      'a plan with the reminder off has none, and the read state survives switching it back on',
      () async {
        final request = planRequest(world, reminder: wire.Reminder(enabled: true, leadDays: 7));
        final plan = await create(request);
        final o = await occurrence(plan.id, '2026-11-20');
        Device.ok(await plans.markRead(o.id, asOf: noon));
        Device.ok(await plans.replacePlan(plan.id, updateOf(planRequest(world))));
        expect(Device.ok(await plans.reminders(asOf: noon)).value.reminders, isEmpty);
        Device.ok(await plans.replacePlan(plan.id, updateOf(request)));
        expect(Device.ok(await plans.reminders(asOf: noon)).value.reminders.single.read, isTrue);
      },
    );
  });
}
