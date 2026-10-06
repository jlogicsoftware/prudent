import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/prudent_localizations.dart';
import 'notification_providers.dart';
import 'reminder_notification_outcome.dart';

/// Says why reminders are not arriving as device notifications, in the one place the user goes to
/// read them (ADR-058): this platform cannot schedule one, or the user has not allowed them.
///
/// The in-app reminder centre is the path that never depends on either, so the notice says where
/// the reminders are rather than asking for anything — no button, no prompt. It shows nothing
/// while the pass is still running, when it failed (the failure is the provider's own error state,
/// not a reason to talk about permissions), or when notifications are working.
class NotificationNotice extends ConsumerWidget {
  const NotificationNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outcome = ref.watch(reminderNotificationSyncProvider).value?.outcome;
    final t = PrudentLocalizations.of(context);
    final message = switch (outcome) {
      ReminderNotificationOutcome.unsupported => t.remindersNoticeUnsupported,
      ReminderNotificationOutcome.denied => t.remindersNoticeDenied,
      _ => null,
    };
    if (message == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
