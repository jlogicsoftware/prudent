import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/reminders.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import 'reminder_figures.dart';

/// One reminder: what is coming due, when, how much, and whether it has been read.
///
/// Unread is said three ways — a filled bell, a bold title and the semantics label — so it is not
/// carried by weight or colour alone. The trailing button flips the read state; tapping the tile
/// opens the occurrence.
class ReminderTile extends StatelessWidget {
  const ReminderTile({super.key, required this.reminder, required this.onOpen, required this.onToggleRead});

  final DueReminder reminder;
  final VoidCallback onOpen;
  final VoidCallback onToggleRead;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final occurrence = reminder.occurrence;
    final date = formatReminderDate(occurrence.occurrenceDate, locale);
    final when = isOverdue(reminder) ? t.reminderOverdueSince(date) : t.reminderDueOn(date);
    final unread = !reminder.read;

    return ListTile(
      leading: Icon(
        unread ? Icons.notifications_active : Icons.notifications_none,
        semanticLabel: unread ? t.reminderUnread : null,
      ),
      title: Text(
        occurrence.title,
        style: unread ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      subtitle: Text('$when · ${formatMinorUnits(occurrence.amountMinor)} ${occurrence.currency}'),
      trailing: ZenIconButton(
        icon: unread ? Icons.drafts_outlined : Icons.mark_email_unread_outlined,
        label: unread ? t.reminderMarkRead : t.reminderMarkUnread,
        onPressed: onToggleRead,
      ),
      onTap: onOpen,
    );
  }
}
