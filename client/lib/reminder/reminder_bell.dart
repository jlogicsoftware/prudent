import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'reminders_screen.dart';

/// The entry to the reminder centre: a bell with the number of unread reminders on it, shown in
/// the overview's app bar. The count is also in the tooltip and the semantics label, so it does
/// not depend on seeing the badge.
class ReminderBell extends ConsumerWidget {
  const ReminderBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final unread = ref.watch(unreadReminderCountProvider);

    return IconButton(
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      tooltip: t.remindersOpen(unread),
      onPressed:
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RemindersScreen())),
    );
  }
}
