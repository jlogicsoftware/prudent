import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/reminders.pb.dart';
import '../providers.dart';
import 'occurrence_detail_screen.dart';
import 'reminder_tile.dart';
import 'run_reminder_change.dart';

/// A titled group of reminders in the centre — the overdue ones, or the ones that are due soon.
///
/// Opening a reminder marks it read first (it has been seen) and then opens its occurrence; if the
/// server refuses the mark, the occurrence is not opened, because the reminder no longer exists.
class ReminderSection extends ConsumerWidget {
  const ReminderSection({super.key, required this.title, required this.reminders});

  final String title;
  final List<DueReminder> reminders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(remindersProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final reminder in reminders)
          ReminderTile(
            key: ValueKey(reminder.occurrence.id),
            reminder: reminder,
            onToggleRead:
                () => runReminderChange(
                  context,
                  ref,
                  () =>
                      reminder.read
                          ? notifier.markUnread(reminder.occurrence.id)
                          : notifier.markRead(reminder.occurrence.id),
                ),
            onOpen: () async {
              if (!reminder.read) {
                final marked = await runReminderChange(
                  context,
                  ref,
                  () => notifier.markRead(reminder.occurrence.id),
                );
                if (!marked) return;
              }
              if (!context.mounted) return;
              await showZenDetail<void>(
                context,
                builder: (_) => OccurrenceDetailScreen(occurrence: reminder.occurrence),
              );
            },
          ),
      ],
    );
  }
}
