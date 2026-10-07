import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/reminders.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../notification/notification_notice.dart';
import '../providers.dart';
import 'reminder_figures.dart';
import 'reminder_section.dart';
import 'run_reminder_change.dart';

/// The in-app reminder centre (M5, jlogicsoftware/prudent#68): the planned occurrences that are
/// overdue or have come within their plan's lead time, each with its read state, and a way into the
/// occurrence itself.
///
/// Which occurrences are here, and which are overdue, is the server's to say (ADR-055): this only
/// groups what it was given and never compares a date with the device's clock. A reminder is a
/// reminder only while its occurrence is planned, so confirming or skipping it from here takes it
/// off this list.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final remindersAsync = ref.watch(remindersProvider);
    final unread = ref.watch(unreadReminderCountProvider);

    return ZenPageScaffold(
      title: t.remindersTitle,
      actions: [
        ZenIconButton(
          icon: Icons.done_all,
          label: t.remindersMarkAllRead,
          onPressed:
              unread == 0
                  ? null
                  : () => runReminderChange(
                    context,
                    ref,
                    ref.read(remindersProvider.notifier).markAllRead,
                  ),
        ),
      ],
      body: Column(
        children: [
          const NotificationNotice(),
          Expanded(child: _reminders(context, ref, t, remindersAsync)),
        ],
      ),
    );
  }

  Widget _reminders(
    BuildContext context,
    WidgetRef ref,
    PrudentLocalizations t,
    AsyncValue<List<DueReminder>> remindersAsync,
  ) {
    return remindersAsync.when(
      loading: () => const Center(child: ZenProgressIndicator()),
      error: (error, _) => Center(child: Text(t.remindersLoadError(error.toString()))),
      data: (reminders) {
        if (reminders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                t.remindersEmpty,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }
        final overdue = overdueReminders(reminders);
        final due = dueReminders(reminders);
        return RefreshIndicator(
          onRefresh: () async => ref.refresh(remindersProvider.future),
          child: ListView(
            children: [
              if (overdue.isNotEmpty)
                ReminderSection(title: t.remindersSectionOverdue, reminders: overdue),
              if (due.isNotEmpty)
                ReminderSection(title: t.remindersSectionDue, reminders: due),
            ],
          ),
        );
      },
    );
  }
}
