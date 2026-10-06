// Local-device notifications for planned-transaction reminders (M5, jlogicsoftware/prudent#69,
// ADR-056): which notifications are worked out, what their text says and does not say, when the
// permission prompt may appear, and that a pass is idempotent. The device itself is a fake behind
// LocalNotificationGateway, so no test reaches a plugin; the plans and occurrences come through
// the real PrudentRepository over a mock HTTP server.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prudent/generated/prudent/v1/plans.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/notification/local_notification_gateway.dart';
import 'package:prudent/notification/notification_providers.dart';
import 'package:prudent/notification/plan_reminder_notifications.dart';
import 'package:prudent/notification/reminder_notification.dart';
import 'package:prudent/notification/reminder_notification_outcome.dart';
import 'package:prudent/notification/reminder_notification_scheduler.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/providers.dart';
import 'package:fixnum/fixnum.dart';
import 'package:zen_transport/zen_transport.dart';

/// A device: whether it can schedule, whether the user has allowed notifications, what a prompt
/// would be answered with, and what was scheduled — keyed by id, as a real one is.
class _FakeGateway implements LocalNotificationGateway {
  _FakeGateway({
    this.supported = true,
    this.allowed = false,
    this.userAnswer = true,
    this.scheduleDelay = Duration.zero,
    this.failNextSchedule = false,
  });

  final bool supported;
  bool allowed;

  /// What the user says when the prompt appears.
  final bool userAnswer;

  /// How long a schedule call takes, so two passes can overlap.
  final Duration scheduleDelay;
  bool failNextSchedule;

  int prompts = 0;
  int permissionChecks = 0;
  int scheduleCalls = 0;
  int cancelCalls = 0;
  final Map<int, ReminderNotification> held = {};

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasPermission() async {
    permissionChecks++;
    return allowed;
  }

  @override
  Future<bool> requestPermission() async {
    prompts++;
    allowed = userAnswer;
    return allowed;
  }

  @override
  Future<void> schedule(ReminderNotification notification) async {
    scheduleCalls++;
    if (failNextSchedule) {
      failNextSchedule = false;
      throw StateError('the device refused');
    }
    await Future<void>.delayed(scheduleDelay);
    held[notification.id] = notification;
  }

  @override
  Future<Set<int>> pendingIds() async => held.keys.toSet();

  @override
  Future<void> cancel(int id) async {
    cancelCalls++;
    held.remove(id);
  }
}

Plan _plan(String id, {bool enabled = true, int? leadDays = 2}) => Plan(
  id: id,
  reminder: Reminder(enabled: enabled, leadDays: leadDays),
);

PlanOccurrence _occurrence(
  String id,
  String date, {
  String planId = 'plan-1',
  OccurrenceStatus status = OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
  String title = 'Rent',
  int amount = -250000,
}) => PlanOccurrence(
  id: id,
  planId: planId,
  occurrenceDate: date,
  status: status,
  title: title,
  amountMinor: Int64(amount),
  currency: 'PLN',
);

void main() {
  // main() loads this at startup; a test that formats a date has to as well.
  setUpAll(initializeDateFormatting);

  final en = lookupPrudentLocalizations(const Locale('en'));
  final now = DateTime(2026, 10, 6, 12);

  List<ReminderNotification> plan(
    List<Plan> plans,
    List<PlanOccurrence> occurrences, {
    DateTime? at,
    bool showAmounts = false,
    int limit = maxScheduledReminderNotifications,
    PrudentLocalizations? t,
    String locale = 'en',
  }) => planReminderNotifications(
    plans: plans,
    occurrences: occurrences,
    now: at ?? now,
    t: t ?? en,
    locale: locale,
    showAmounts: showAmounts,
    limit: limit,
  );

  group('which notifications are worked out', () {
    test('one per planned occurrence, at 09:00 on its date less the lead time', () {
      final result = plan([_plan('plan-1', leadDays: 2)], [_occurrence('o1', '2026-10-20')]);

      expect(result, hasLength(1));
      expect(result.single.occurrenceId, 'o1');
      expect(result.single.fireAt, DateTime(2026, 10, 18, reminderNotificationHour));
    });

    test('a lead time of 0 is the day itself, and one can reach back across a month end', () {
      expect(
        plan([_plan('plan-1', leadDays: 0)], [_occurrence('o1', '2026-10-20')]).single.fireAt,
        DateTime(2026, 10, 20, 9),
      );
      expect(
        plan([_plan('plan-1', leadDays: 7)], [_occurrence('o1', '2026-11-03')]).single.fireAt,
        DateTime(2026, 10, 27, 9),
      );
    });

    test('an absent lead time is the one the contract names, a day', () {
      final result = plan([_plan('plan-1', leadDays: null)], [_occurrence('o1', '2026-10-20')]);

      expect(result.single.fireAt, DateTime(2026, 10, 19, 9));
    });

    test('the reminder date is a calendar date across a daylight-saving change', () {
      // Europe falls back on 2026-10-25: a lead time counted in 24-hour spans would land on the
      // 23rd at 10:00 or the 24th at 08:00 instead.
      final result = plan([_plan('plan-1', leadDays: 2)], [_occurrence('o1', '2026-10-26')]);

      expect(result.single.fireAt, DateTime(2026, 10, 24, 9));
    });

    test('a plan whose reminder is off, or one that is unknown, produces none', () {
      final result = plan(
        [_plan('plan-1', enabled: false)],
        [_occurrence('o1', '2026-10-20'), _occurrence('o2', '2026-10-20', planId: 'gone')],
      );

      expect(result, isEmpty);
    });

    test('only a planned occurrence has one: overdue, confirmed and skipped do not', () {
      final result = plan(
        [_plan('plan-1')],
        [
          _occurrence('o1', '2026-10-20', status: OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE),
          _occurrence('o2', '2026-10-20', status: OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED),
          _occurrence('o3', '2026-10-20', status: OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED),
        ],
      );

      expect(result, isEmpty);
    });

    test('a reminder date that has passed is left to the in-app centre, today included', () {
      final occurrences = [_occurrence('o1', '2026-10-08')]; // reminder date 2026-10-06

      expect(plan([_plan('plan-1')], occurrences, at: DateTime(2026, 10, 6, 8, 59)), hasLength(1));
      expect(plan([_plan('plan-1')], occurrences, at: DateTime(2026, 10, 6, 9)), isEmpty);
      expect(plan([_plan('plan-1')], occurrences, at: DateTime(2026, 10, 7)), isEmpty);
    });

    test('are nearest first and capped, with the later ones left for a later pass', () {
      final result = plan(
        [_plan('plan-1', leadDays: 0)],
        [
          _occurrence('c', '2026-10-12'),
          _occurrence('a', '2026-10-08'),
          _occurrence('b', '2026-10-10'),
        ],
        limit: 2,
      );

      expect(result.map((n) => n.occurrenceId), ['a', 'b']);
    });

    test('a date that is not one is an error, not a guessed day', () {
      expect(() => plan([_plan('plan-1')], [_occurrence('o1', 'soon')]), throwsFormatException);
    });
  });

  group('what the text says', () {
    test('names the plan and the date and leaves the amount out by default', () {
      final result = plan([_plan('plan-1')], [_occurrence('o1', '2026-10-20', amount: -250000)]);

      expect(result.single.title, 'Planned transaction due');
      expect(result.single.body, 'Rent on Oct 20, 2026');
      expect('${result.single.title} ${result.single.body}', isNot(contains('2500')));
      expect('${result.single.title} ${result.single.body}', isNot(contains('PLN')));
    });

    test('carries the amount only when asked to', () {
      final result = plan(
        [_plan('plan-1')],
        [_occurrence('o1', '2026-10-20', amount: -250000)],
        showAmounts: true,
      );

      expect(result.single.body, 'Rent, -2500.00 PLN, on Oct 20, 2026');
    });

    test('is in the app language', () {
      final pl = lookupPrudentLocalizations(const Locale('pl'));
      final result = plan(
        [_plan('plan-1')],
        [_occurrence('o1', '2026-10-20')],
        t: pl,
        locale: 'pl',
      );

      expect(result.single.title, pl.reminderNotificationTitle);
      expect(result.single.title, isNot(en.reminderNotificationTitle));
      expect(result.single.channelName, pl.reminderNotificationChannel);
    });
  });

  group('the notification id', () {
    test('is the same for the same occurrence, so a repeat replaces rather than doubles', () {
      const id = '0b1f2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

      expect(reminderNotificationId(id), reminderNotificationId(id));
      expect(
        plan([_plan('plan-1')], [_occurrence(id, '2026-10-20')]).single.id,
        reminderNotificationId(id),
      );
    });

    test('is a non-negative 31-bit integer, and differs between occurrences', () {
      final ids = {
        for (var i = 0; i < 200; i++) reminderNotificationId('00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}'),
      };

      expect(ids, hasLength(200));
      expect(ids.every((id) => id >= 0 && id <= 0x7fffffff), isTrue);
    });
  });

  group('the scheduler', () {
    ReminderNotification one(String id) => plan([_plan('plan-1')], [_occurrence(id, '2026-10-20')]).single;

    test('does not touch a platform that cannot schedule, nor ask it anything', () async {
      final gateway = _FakeGateway(supported: false);

      final result = await ReminderNotificationScheduler(gateway).reconcile([one('o1')]);

      expect(result.outcome, ReminderNotificationOutcome.unsupported);
      expect(gateway.permissionChecks, 0);
      expect(gateway.prompts, 0);
      expect(gateway.scheduleCalls, 0);
    });

    test('asks for no permission when there is nothing to remind of', () async {
      final gateway = _FakeGateway();

      final result = await ReminderNotificationScheduler(gateway).reconcile(const []);

      expect(result.outcome, ReminderNotificationOutcome.nothingToSchedule);
      expect(gateway.permissionChecks, 0);
      expect(gateway.prompts, 0);
    });

    test('does not prompt a user who has already allowed notifications', () async {
      final gateway = _FakeGateway(allowed: true);

      final result = await ReminderNotificationScheduler(gateway).reconcile([one('o1'), one('o2')]);

      expect(result.outcome, ReminderNotificationOutcome.scheduled);
      expect(result.scheduled, 2);
      expect(gateway.prompts, 0);
      expect(gateway.held, hasLength(2));
    });

    test('prompts once there is a reminder to deliver, and schedules when it is granted', () async {
      final gateway = _FakeGateway();

      final result = await ReminderNotificationScheduler(gateway).reconcile([one('o1')]);

      expect(gateway.prompts, 1);
      expect(result.outcome, ReminderNotificationOutcome.scheduled);
      expect(gateway.held, hasLength(1));
    });

    test('schedules nothing when the user refuses, and does not ask again this session', () async {
      final gateway = _FakeGateway(userAnswer: false);
      final scheduler = ReminderNotificationScheduler(gateway);

      final first = await scheduler.reconcile([one('o1')]);
      final second = await scheduler.reconcile([one('o1')]);

      expect(first.outcome, ReminderNotificationOutcome.denied);
      expect(second.outcome, ReminderNotificationOutcome.denied);
      expect(gateway.prompts, 1);
      expect(gateway.scheduleCalls, 0);
    });

    test('cancels what is pending but no longer wanted, and keeps what still is', () async {
      final gateway = _FakeGateway(allowed: true);
      final scheduler = ReminderNotificationScheduler(gateway);
      await scheduler.reconcile([one('o1'), one('o2')]);

      final result = await scheduler.reconcile([one('o2')]);

      expect(result.outcome, ReminderNotificationOutcome.scheduled);
      expect(result.cancelled, 1);
      expect(gateway.held.keys, [reminderNotificationId('o2')]);
    });

    test('cancels everything when nothing is wanted any more, without asking for permission', () async {
      final gateway = _FakeGateway(allowed: true);
      final scheduler = ReminderNotificationScheduler(gateway);
      await scheduler.reconcile([one('o1')]);
      gateway.allowed = false;

      final result = await scheduler.reconcile(const []);

      expect(result.outcome, ReminderNotificationOutcome.nothingToSchedule);
      expect(result.cancelled, 1);
      expect(gateway.held, isEmpty);
      expect(gateway.prompts, 0);
    });

    test('cancels what is stale even when the user has since refused notifications', () async {
      final gateway = _FakeGateway(userAnswer: false, allowed: true);
      final scheduler = ReminderNotificationScheduler(gateway);
      await scheduler.reconcile([one('o1')]);
      gateway.allowed = false;

      final result = await scheduler.reconcile([one('o2')]);

      expect(result.outcome, ReminderNotificationOutcome.denied);
      expect(result.cancelled, 1);
      expect(gateway.held, isEmpty);
    });

    test('a pass repeated cancels nothing the second time', () async {
      final gateway = _FakeGateway(allowed: true);
      final scheduler = ReminderNotificationScheduler(gateway);
      await scheduler.reconcile([one('o1'), one('o2')]);

      await scheduler.reconcile([one('o2')]);
      final again = await scheduler.reconcile([one('o2')]);

      expect(again.cancelled, 0);
      expect(gateway.cancelCalls, 1);
      expect(gateway.held, hasLength(1));
    });

    test('does not cancel on a platform that cannot schedule', () async {
      final gateway = _FakeGateway(supported: false);

      await ReminderNotificationScheduler(gateway).reconcile(const []);

      expect(gateway.cancelCalls, 0);
    });

    test('passes run one after another, so the later one is the last word', () async {
      final gateway = _FakeGateway(allowed: true, scheduleDelay: const Duration(milliseconds: 20));
      final scheduler = ReminderNotificationScheduler(gateway);

      final first = scheduler.reconcile([one('o1')]);
      final second = scheduler.reconcile([one('o2')]);
      await Future.wait([first, second]);

      expect(gateway.held.keys, [reminderNotificationId('o2')]);
    });

    test('a failed pass does not stop the next one', () async {
      final gateway = _FakeGateway(allowed: true, failNextSchedule: true);
      final scheduler = ReminderNotificationScheduler(gateway);

      await expectLater(scheduler.reconcile([one('o1')]), throwsA(isA<StateError>()));
      final next = await scheduler.reconcile([one('o1')]);

      expect(next.outcome, ReminderNotificationOutcome.scheduled);
      expect(gateway.held, hasLength(1));
    });

    test('is idempotent: the same pass twice leaves one notification each', () async {
      final gateway = _FakeGateway(allowed: true);
      final scheduler = ReminderNotificationScheduler(gateway);

      await scheduler.reconcile([one('o1'), one('o2')]);
      await scheduler.reconcile([one('o1'), one('o2')]);

      expect(gateway.scheduleCalls, 4);
      expect(gateway.held, hasLength(2));
    });
  });

  group('the sync pass', () {
    Map<String, Object?> planJson({bool enabled = true}) => {
      'id': 'plan-1',
      'title': 'Rent',
      'currency': 'PLN',
      'reminder': {'enabled': enabled, 'leadDays': 2},
    };

    Map<String, Object?> occurrenceJson(String id, String date, {String status = 'OCCURRENCE_STATUS_PLANNED'}) => {
      'id': id,
      'planId': 'plan-1',
      'occurrenceDate': date,
      'status': status,
      'title': 'Rent',
      'amountMinor': '-250000',
      'currency': 'PLN',
    };

    ProviderContainer container(
      _FakeGateway gateway,
      List<String> calls, {
      bool enabled = true,
      int? failPlansWith,
    }) {
      final client = ZenClient(
        baseUrl: 'https://example.test',
        format: ZenTransportFormat.json,
        httpClient: MockClient((http.Request request) async {
          calls.add('${request.method} ${request.url.path}?${request.url.query}');
          const headers = {'X-Zen-Transport': 'json'};
          if (request.url.path == '/api/v1/plans') {
            if (failPlansWith != null) {
              return http.Response(jsonEncode({'code': 'boom', 'message': 'no plans'}), failPlansWith, headers: headers);
            }
            return http.Response(jsonEncode({'plans': [planJson(enabled: enabled)]}), 200, headers: headers);
          }
          if (request.url.path == '/api/v1/occurrences/upcoming') {
            return http.Response(
              jsonEncode({
                'occurrences': [
                  occurrenceJson('o1', '2026-10-20'),
                  occurrenceJson('o2', '2026-10-21', status: 'OCCURRENCE_STATUS_SKIPPED'),
                ],
              }),
              200,
              headers: headers,
            );
          }
          return http.Response('unexpected ${request.url.path}', 500);
        }),
      );
      final c = ProviderContainer(
        // Riverpod retries a failed provider with backoff; a test of the failure wants the first one.
        retry: (_, _) => null,
        overrides: [
          prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client)),
          localNotificationGatewayProvider.overrideWithValue(gateway),
          reminderNotificationClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    /// One pass, held alive by a listener as the signed-in shell holds it, until it completes.
    Future<ReminderNotificationResult> pass(ProviderContainer c) {
      c.listen(reminderNotificationSyncProvider, (_, _) {});
      return c.read(reminderNotificationSyncProvider.future);
    }

    test('schedules the notification for the reminder that is still ahead, and only that one', () async {
      final gateway = _FakeGateway(allowed: true);
      final calls = <String>[];
      final c = container(gateway, calls);

      final result = await pass(c);

      expect(result.outcome, ReminderNotificationOutcome.scheduled);
      expect(gateway.held.values.map((n) => n.occurrenceId), ['o1']);
      expect(gateway.held.values.single.fireAt, DateTime(2026, 10, 18, 9));
      expect(calls.any((c) => c.contains('days=$reminderNotificationHorizonDays')), isTrue);
    });

    test('does not prompt when no plan has its reminder on', () async {
      final gateway = _FakeGateway();
      final c = container(gateway, [], enabled: false);

      final result = await pass(c);

      expect(result.outcome, ReminderNotificationOutcome.nothingToSchedule);
      expect(gateway.prompts, 0);
    });

    test('does not even read the plans on a platform that cannot deliver', () async {
      final gateway = _FakeGateway(supported: false);
      final calls = <String>[];
      final c = container(gateway, calls);

      final result = await pass(c);

      expect(result.outcome, ReminderNotificationOutcome.unsupported);
      expect(calls, isEmpty);
    });

    test('shows a failure to read the plans as an error, and schedules nothing', () async {
      final gateway = _FakeGateway(allowed: true);
      final c = container(gateway, [], failPlansWith: 409);

      await expectLater(pass(c), throwsA(anything));
      expect(gateway.scheduleCalls, 0);
    });
  });

  group('reconciliation after a change', () {
    final server = _Server();
    late _FakeGateway gateway;
    late ProviderContainer c;

    ProviderContainer start({Map<int, ReminderNotification>? pending}) {
      gateway = _FakeGateway(allowed: true);
      if (pending != null) gateway.held.addAll(pending);
      final client = ZenClient(
        baseUrl: 'https://example.test',
        format: ZenTransportFormat.json,
        httpClient: MockClient(server.handle),
      );
      c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client)),
          localNotificationGatewayProvider.overrideWithValue(gateway),
          reminderNotificationClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(c.dispose);
      // Held alive as the signed-in shell holds it.
      c.listen(reminderNotificationSyncProvider, (_, _) {});
      return c;
    }

    /// The pass that follows a change, once it has finished.
    Future<ReminderNotificationResult> settled() async {
      await Future<void>.delayed(Duration.zero);
      return c.read(reminderNotificationSyncProvider.future);
    }

    Set<String> held() => gateway.held.values.map((n) => n.occurrenceId).toSet();

    setUp(server.reset);

    test('on sign-in, schedules what is wanted and cancels what an older version left behind', () async {
      final stale = ReminderNotification(
        id: reminderNotificationId('gone'),
        occurrenceId: 'gone',
        fireAt: DateTime(2026, 10, 18, 9),
        title: 'old',
        body: 'old',
        channelName: 'old',
      );
      final outdated = ReminderNotification(
        id: reminderNotificationId('o1'),
        occurrenceId: 'o1',
        fireAt: DateTime(2026, 10, 1, 9),
        title: 'old',
        body: 'old',
        channelName: 'old',
      );
      start(pending: {stale.id: stale, outdated.id: outdated});

      final result = await settled();

      expect(result.cancelled, 1);
      expect(held(), {'o1', 'o2'});
      expect(gateway.held[outdated.id]!.fireAt, DateTime(2026, 10, 18, 9));
      expect(gateway.held[outdated.id]!.body, 'Rent on Oct 20, 2026');
    });

    test('skipping cancels the notification, and restoring schedules it again', () async {
      start();
      await settled();
      expect(held(), {'o1', 'o2'});

      await c.read(occurrenceActionsProvider).skip('o1');
      expect((await settled()).cancelled, 1);
      expect(held(), {'o2'});

      await c.read(occurrenceActionsProvider).restore('o1');
      await settled();
      expect(held(), {'o1', 'o2'});
    });

    test('confirming cancels the notification', () async {
      start();
      await settled();

      await c.read(occurrenceActionsProvider).confirm('o2');
      await settled();

      expect(held(), {'o1'});
    });

    test('deleting the record that confirmed an occurrence reschedules it', () async {
      server.records = [
        {'id': 'rec-1', 'planOccurrenceId': 'o1'},
        {'id': 'rec-2'},
      ];
      server.occurrences[0]['status'] = 'OCCURRENCE_STATUS_COMPLETED';
      start();
      await settled();
      expect(held(), {'o2'});
      await c.read(recordsProvider.future);
      final passes = server.upcomingReads;

      // A record no occurrence made changes nothing a notification reads.
      await c.read(recordsProvider.notifier).removeRecord('rec-2');
      await settled();
      expect(server.upcomingReads, passes);

      server.occurrences[0]['status'] = 'OCCURRENCE_STATUS_PLANNED';
      await c.read(recordsProvider.notifier).removeRecord('rec-1');
      await settled();
      expect(held(), {'o1', 'o2'});
    });

    test('editing a plan reschedules for its new lead time, and switching the reminder off cancels', () async {
      start();
      await settled();

      server.leadDays = 5;
      await c.read(planActionsProvider).update('plan-1', UpdatePlanRequest());
      await settled();
      expect(gateway.held.values.map((n) => n.fireAt).toSet(), {DateTime(2026, 10, 15, 9), DateTime(2026, 10, 16, 9)});
      expect(gateway.held, hasLength(2));

      server.reminderEnabled = false;
      await c.read(planActionsProvider).update('plan-1', UpdatePlanRequest());
      final result = await settled();

      expect(result.outcome, ReminderNotificationOutcome.nothingToSchedule);
      expect(gateway.held, isEmpty);
      expect(gateway.prompts, 0);
    });

    test('deleting a plan cancels the notifications of its occurrences', () async {
      start();
      await settled();

      server.plans.clear();
      await c.read(planActionsProvider).delete('plan-1');
      await settled();

      expect(gateway.held, isEmpty);
    });

    test('creating a plan schedules its notifications', () async {
      server.plans.clear();
      start();
      await settled();
      expect(gateway.held, isEmpty);

      server.addPlan();
      await c.read(planActionsProvider).create(CreatePlanRequest());
      await settled();

      expect(held(), {'o1', 'o2'});
    });

    test('a pass repeated for the same state changes nothing on the device', () async {
      start();
      await settled();
      final before = Map.of(gateway.held);

      c.read(reminderScheduleRevisionProvider.notifier).bump();
      await settled();
      c.read(reminderScheduleRevisionProvider.notifier).bump();
      final last = await settled();

      expect(gateway.held, before);
      expect(last.cancelled, 0);
    });

    test('a pass superseded while it reads leaves the device to the one that replaced it', () async {
      start();
      c.read(reminderScheduleRevisionProvider.notifier).bump();
      c.read(reminderScheduleRevisionProvider.notifier).bump();

      final result = await settled();

      expect(result.outcome, ReminderNotificationOutcome.scheduled);
      expect(held(), {'o1', 'o2'});
      expect(gateway.cancelCalls, 0);
    });
  });
}

/// A server whose plans and occurrences can be changed under a test, answering the routes the
/// reconciliation reads and the actions write.
class _Server {
  late List<Map<String, Object?>> plans;
  late List<Map<String, Object?>> occurrences;
  late List<Map<String, Object?>> records;
  bool reminderEnabled = true;
  int leadDays = 2;
  int upcomingReads = 0;

  void reset() {
    reminderEnabled = true;
    leadDays = 2;
    upcomingReads = 0;
    records = [];
    plans = [];
    addPlan();
    occurrences = [_occurrenceJson('o1', '2026-10-20'), _occurrenceJson('o2', '2026-10-21')];
  }

  void addPlan() => plans.add({'id': 'plan-1', 'title': 'Rent', 'currency': 'PLN'});

  Map<String, Object?> _occurrenceJson(String id, String date) => {
    'id': id,
    'planId': 'plan-1',
    'occurrenceDate': date,
    'status': 'OCCURRENCE_STATUS_PLANNED',
    'title': 'Rent',
    'amountMinor': '-250000',
    'currency': 'PLN',
  };

  Map<String, Object?> _occurrence(String id) => occurrences.firstWhere((o) => o['id'] == id);

  Future<http.Response> handle(http.Request request) async {
    const headers = {'X-Zen-Transport': 'json'};
    http.Response ok(Object? body) => http.Response(jsonEncode(body), 200, headers: headers);

    final path = request.url.path;
    final method = request.method;
    if (path == '/api/v1/plans' && method == 'GET') {
      return ok({
        'plans': [
          for (final plan in plans) {...plan, 'reminder': {'enabled': reminderEnabled, 'leadDays': leadDays}},
        ],
      });
    }
    if (path == '/api/v1/plans' && method == 'POST') return ok(plans.isEmpty ? {'id': 'plan-1'} : plans.first);
    if (path == '/api/v1/plans/plan-1') return ok({'id': 'plan-1'});
    if (path == '/api/v1/occurrences/upcoming') {
      upcomingReads++;
      return ok({'occurrences': occurrences});
    }
    if (path == '/api/v1/occurrences/overdue') return ok({'occurrences': <Object>[]});
    if (path == '/api/v1/records' && method == 'GET') return ok({'records': records});
    if (path.startsWith('/api/v1/records/') && method == 'DELETE') {
      return ok({'id': path.split('/').last});
    }

    final action = RegExp(r'^/api/v1/occurrences/([^/]+)/(skip|restore|confirm)$').firstMatch(path);
    if (action != null && method == 'POST') {
      final occurrence = _occurrence(action.group(1)!);
      occurrence['status'] = switch (action.group(2)) {
        'skip' => 'OCCURRENCE_STATUS_SKIPPED',
        'restore' => 'OCCURRENCE_STATUS_PLANNED',
        _ => 'OCCURRENCE_STATUS_COMPLETED',
      };
      return ok(action.group(2) == 'confirm' ? {'occurrence': occurrence, 'record': {'id': 'rec-new'}} : occurrence);
    }
    return http.Response('unexpected $method $path', 500);
  }
}
