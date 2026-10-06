import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'local_notification_gateway.dart';
import 'local_notification_gateway_factory.dart';
import 'plan_reminder_notifications.dart';
import 'reminder_notification_outcome.dart';
import 'reminder_notification_scheduler.dart';

/// The device's notification facility. Overridden in tests with a fake, so no test reaches a
/// plugin.
final localNotificationGatewayProvider = Provider<LocalNotificationGateway>(
  (ref) => createLocalNotificationGateway(),
);

final reminderNotificationSchedulerProvider = Provider<ReminderNotificationScheduler>(
  (ref) => ReminderNotificationScheduler(ref.watch(localNotificationGatewayProvider)),
);

/// The moment "now" is for working out which reminders are still ahead. Overridden in tests.
final reminderNotificationClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// One scheduling pass: reads the plans and the occurrences coming up, works out which
/// notifications are still ahead, and hands them to the device (M5, jlogicsoftware/prudent#69,
/// ADR-056).
///
/// It is watched by the signed-in shell, so it runs on each sign-in and is dropped on sign-out.
/// Scheduling is idempotent, so running it again is harmless; *when* to run it again — after an
/// edit, a confirmation, a skip, an app update — is the reconciliation task's. A failure to read
/// or to schedule is the provider's error state, not swallowed: the in-app reminder centre does
/// not depend on it.
final reminderNotificationSyncProvider = FutureProvider.autoDispose<ReminderNotificationResult>((ref) async {
  final gateway = ref.watch(localNotificationGatewayProvider);
  // A platform that cannot deliver one is not asked anything, not even for the plans.
  if (!gateway.isSupported) {
    return const ReminderNotificationResult(ReminderNotificationOutcome.unsupported);
  }

  final repository = ref.watch(prudentRepositoryProvider);
  final plans = await repository.listPlans();
  final upcoming = await repository.listUpcomingOccurrences(days: reminderNotificationHorizonDays);

  final locale = ref.read(localeProvider);
  final notifications = planReminderNotifications(
    plans: plans.fold((response) => response.plans, (error) => throw error),
    occurrences: upcoming.fold((response) => response.occurrences, (error) => throw error),
    now: ref.read(reminderNotificationClockProvider)(),
    t: lookupPrudentLocalizations(locale),
    locale: locale.toLanguageTag(),
  );
  return ref.read(reminderNotificationSchedulerProvider).schedule(notifications);
});
