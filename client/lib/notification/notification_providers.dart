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

/// One reconciliation pass: reads the plans and the occurrences coming up, works out which
/// notifications are still ahead, and makes the device's pending notifications exactly those —
/// scheduling what is missing or changed, cancelling what is stale (M5, jlogicsoftware/prudent#69
/// and #70, ADR-056, ADR-057).
///
/// It is listened to by the signed-in shell, so it runs each time the signed-in shell is built —
/// a sign-in, a launch with a saved session, and the first launch after an app update, which is
/// when what an older version scheduled is replaced — and is dropped on sign-out. It runs again
/// whenever [reminderScheduleRevisionProvider] changes: an occurrence skipped, restored or
/// confirmed, a plan edited or deleted, a confirming record removed. Every pass computes the whole
/// wanted set from what the server says now and reconciles to it, so a pass never needs to know what
/// changed and repeating one changes nothing. A failure to read or to schedule is the provider's
/// error state, not swallowed: the in-app reminder centre does not depend on it.
final reminderNotificationSyncProvider = FutureProvider.autoDispose<ReminderNotificationResult>((ref) async {
  ref.watch(reminderScheduleRevisionProvider);
  // A pass superseded while it reads has data older than the one that replaced it, and must not
  // touch the device after it.
  var superseded = false;
  ref.onDispose(() => superseded = true);

  final gateway = ref.watch(localNotificationGatewayProvider);
  // A platform that cannot deliver one is not asked anything, not even for the plans.
  if (!gateway.isSupported) {
    return const ReminderNotificationResult(ReminderNotificationOutcome.unsupported);
  }

  final repository = ref.watch(prudentRepositoryProvider);
  final plans = await repository.listPlans();
  final upcoming = await repository.listUpcomingOccurrences(days: reminderNotificationHorizonDays);

  if (superseded) return const ReminderNotificationResult(ReminderNotificationOutcome.superseded);

  final locale = ref.read(localeProvider);
  final notifications = planReminderNotifications(
    plans: plans.fold((response) => response.plans, (error) => throw error),
    occurrences: upcoming.fold((response) => response.occurrences, (error) => throw error),
    now: ref.read(reminderNotificationClockProvider)(),
    t: lookupPrudentLocalizations(locale),
    locale: locale.toLanguageTag(),
  );
  return ref.read(reminderNotificationSchedulerProvider).reconcile(notifications);
});
