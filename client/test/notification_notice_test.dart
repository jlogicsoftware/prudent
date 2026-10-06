// Unsupported and denied notifications (M5, jlogicsoftware/prudent#71, ADR-058): a refusal is
// remembered across launches so the prompt is not repeated, and the reminder centre says why
// reminders are not arriving as notifications while still listing them. The device is a fake
// behind LocalNotificationGateway, the server a mock HTTP client, and the sync pass's result is
// handed in directly where the screen's wording is what is under test.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/notification/local_notification_gateway.dart';
import 'package:prudent/notification/notification_notice.dart';
import 'package:prudent/notification/notification_permission_memory.dart';
import 'package:prudent/notification/notification_providers.dart';
import 'package:prudent/notification/plan_reminder_notifications.dart';
import 'package:prudent/notification/reminder_notification.dart';
import 'package:prudent/notification/reminder_notification_outcome.dart';
import 'package:prudent/notification/reminder_notification_scheduler.dart';
import 'package:prudent/notification/shared_preferences_permission_memory.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/providers.dart';
import 'package:prudent/reminder/reminders_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zen_transport/zen_transport.dart';

/// A device whose permission answers are scripted and whose prompts are counted.
class _Device implements LocalNotificationGateway {
  _Device({this.supported = true, this.promptThrows = false});

  final bool supported;
  final bool promptThrows;
  bool allowed = false;
  int prompts = 0;
  final Map<int, ReminderNotification> held = {};

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasPermission() async => allowed;

  @override
  Future<bool> requestPermission() async {
    prompts++;
    if (promptThrows) throw StateError('closed with the prompt up');
    // The user says no.
    return false;
  }

  @override
  Future<void> schedule(ReminderNotification notification) async => held[notification.id] = notification;

  @override
  Future<Set<int>> pendingIds() async => held.keys.toSet();

  @override
  Future<void> cancel(int id) async => held.remove(id);
}

ReminderNotification _notification(String occurrenceId) => ReminderNotification(
  id: reminderNotificationId(occurrenceId),
  occurrenceId: occurrenceId,
  fireAt: DateTime(2026, 10, 18, 9),
  title: 'Planned transaction due',
  body: 'Rent on Oct 20, 2026',
  channelName: 'Planned transactions',
);

void main() {
  group('a refusal is remembered', () {
    test('across launches: a later one is not prompted again, and says denied', () async {
      final memory = InMemoryNotificationPermissionMemory();
      final device = _Device();

      final firstLaunch = await ReminderNotificationScheduler(device, memory: memory).reconcile([_notification('o1')]);
      // A new scheduler is a new launch; only the memory carries over.
      final secondLaunch = await ReminderNotificationScheduler(device, memory: memory).reconcile([_notification('o1')]);

      expect(firstLaunch.outcome, ReminderNotificationOutcome.denied);
      expect(secondLaunch.outcome, ReminderNotificationOutcome.denied);
      expect(device.prompts, 1);
      expect(device.held, isEmpty);
    });

    test('before the prompt, so a launch that ends with it on screen has still asked', () async {
      final memory = InMemoryNotificationPermissionMemory();

      await expectLater(
        ReminderNotificationScheduler(_Device(promptThrows: true), memory: memory).reconcile([_notification('o1')]),
        throwsA(isA<StateError>()),
      );
      final next = _Device();
      await ReminderNotificationScheduler(next, memory: memory).reconcile([_notification('o1')]);

      expect(await memory.hasAsked(), isTrue);
      expect(next.prompts, 0);
    });

    test('but not a grant given later in the system settings: it is scheduled without a prompt', () async {
      final memory = InMemoryNotificationPermissionMemory();
      final device = _Device();
      await ReminderNotificationScheduler(device, memory: memory).reconcile([_notification('o1')]);

      device.allowed = true;
      final result = await ReminderNotificationScheduler(device, memory: memory).reconcile([_notification('o1')]);

      expect(result.outcome, ReminderNotificationOutcome.scheduled);
      expect(device.prompts, 1);
      expect(device.held, hasLength(1));
    });

    test('and a platform that cannot deliver is never asked, so nothing is recorded', () async {
      final memory = InMemoryNotificationPermissionMemory();

      final result = await ReminderNotificationScheduler(_Device(supported: false), memory: memory).reconcile([
        _notification('o1'),
      ]);

      expect(result.outcome, ReminderNotificationOutcome.unsupported);
      expect(await memory.hasAsked(), isFalse);
    });

    test('nor is a user with nothing to be reminded of', () async {
      final memory = InMemoryNotificationPermissionMemory();
      final device = _Device();

      await ReminderNotificationScheduler(device, memory: memory).reconcile(const []);

      expect(await memory.hasAsked(), isFalse);
      expect(device.prompts, 0);
    });
  });

  group('the preferences memory', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts as not asked, and keeps having asked across instances', () async {
      expect(await const SharedPreferencesPermissionMemory().hasAsked(), isFalse);

      await const SharedPreferencesPermissionMemory().markAsked();

      expect(await const SharedPreferencesPermissionMemory().hasAsked(), isTrue);
    });

    test('is what the app uses unless a test says otherwise', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      expect(c.read(notificationPermissionMemoryProvider), isA<SharedPreferencesPermissionMemory>());
    });
  });

  group('the notice', () {
    Future<void> pump(
      WidgetTester tester,
      Future<ReminderNotificationResult> Function() pass, {
      Locale locale = const Locale('en'),
      Widget home = const Scaffold(body: NotificationNotice()),
      http.Client? server,
    }) async {
      final client = ZenClient(
        baseUrl: 'https://example.test',
        format: ZenTransportFormat.json,
        httpClient: server ?? MockClient((_) async => http.Response('unexpected', 500)),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client)),
            reminderNotificationSyncProvider.overrideWith((ref) => pass()),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: PrudentLocalizations.localizationsDelegates,
            supportedLocales: PrudentLocalizations.supportedLocales,
            home: home,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<ReminderNotificationResult> outcome(ReminderNotificationOutcome o) async => ReminderNotificationResult(o);

    final unsupportedText = find.textContaining("can't show reminders as notifications");
    final deniedText = find.textContaining('Notifications are turned off for Prudent');

    testWidgets('says a platform that cannot schedule them cannot, and where the reminders are', (tester) async {
      await pump(tester, () => outcome(ReminderNotificationOutcome.unsupported));

      expect(unsupportedText, findsOneWidget);
      expect(find.textContaining('They appear here'), findsOneWidget);
      expect(deniedText, findsNothing);
    });

    testWidgets('says a refusal left the reminders in the app, and where to change it', (tester) async {
      await pump(tester, () => outcome(ReminderNotificationOutcome.denied));

      expect(deniedText, findsOneWidget);
      expect(find.textContaining("device's settings"), findsOneWidget);
      expect(unsupportedText, findsNothing);
    });

    testWidgets('offers nothing to press: it explains, it does not ask', (tester) async {
      await pump(tester, () => outcome(ReminderNotificationOutcome.denied));

      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    for (final quiet in [
      ReminderNotificationOutcome.scheduled,
      ReminderNotificationOutcome.nothingToSchedule,
      ReminderNotificationOutcome.superseded,
    ]) {
      testWidgets('is silent when the outcome is $quiet', (tester) async {
        await pump(tester, () => outcome(quiet));

        expect(unsupportedText, findsNothing);
        expect(deniedText, findsNothing);
        expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
      });
    }

    testWidgets('is silent while the pass runs, and when it failed', (tester) async {
      final pending = Completer<ReminderNotificationResult>();
      await tester.pumpWidget(const SizedBox());
      await pump(tester, () => pending.future);
      expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await pump(tester, () async => throw StateError('could not read the plans'));
      expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
    });

    testWidgets('is in the app language', (tester) async {
      await pump(tester, () => outcome(ReminderNotificationOutcome.denied), locale: const Locale('pl'));

      expect(find.textContaining('Powiadomienia są wyłączone dla Prudent'), findsOneWidget);
      expect(deniedText, findsNothing);
    });

    group('in the reminder centre', () {
      http.Client reminders(List<Map<String, Object?>> due) => MockClient((request) async {
        if (request.url.path == '/api/v1/reminders') {
          return http.Response(jsonEncode({'reminders': due}), 200, headers: const {'X-Zen-Transport': 'json'});
        }
        return http.Response('unexpected ${request.url.path}', 500);
      });

      Map<String, Object?> rent() => {
        'occurrence': {
          'id': 'o1',
          'planId': 'plan-1',
          'occurrenceDate': '2026-10-10',
          'status': 'OCCURRENCE_STATUS_OVERDUE',
          'title': 'Rent',
          'amountMinor': '-250000',
          'currency': 'PLN',
        },
        'remindOn': '2026-10-08',
        'leadDays': 2,
        'read': false,
      };

      testWidgets('sits above the reminders, which are still listed', (tester) async {
        await pump(
          tester,
          () => outcome(ReminderNotificationOutcome.denied),
          home: const RemindersScreen(),
          server: reminders([rent()]),
        );

        expect(deniedText, findsOneWidget);
        expect(find.text('Rent'), findsOneWidget);
        expect(tester.getTopLeft(deniedText).dy, lessThan(tester.getTopLeft(find.text('Rent')).dy));
      });

      testWidgets('is shown with an empty list too, since the centre is all the user has', (tester) async {
        await pump(
          tester,
          () => outcome(ReminderNotificationOutcome.unsupported),
          home: const RemindersScreen(),
          server: reminders([]),
        );

        expect(unsupportedText, findsOneWidget);
        expect(find.textContaining('No reminders.'), findsOneWidget);
      });

      testWidgets('is absent when notifications work', (tester) async {
        await pump(
          tester,
          () => outcome(ReminderNotificationOutcome.scheduled),
          home: const RemindersScreen(),
          server: reminders([rent()]),
        );

        expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
        expect(find.text('Rent'), findsOneWidget);
      });
    });
  });
}
