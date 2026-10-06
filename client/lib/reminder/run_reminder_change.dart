import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';

/// Runs a reminder change and says whether it was made.
///
/// A refusal is shown in the server's words, and the list is fetched again so the screen shows what
/// is stored: a reminder refused with a conflict has ended elsewhere (confirmed or skipped on
/// another device), and leaving it on screen would be wrong.
Future<bool> runReminderChange(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() change,
) async {
  final t = PrudentLocalizations.of(context);
  try {
    await change();
    return true;
  } on ZenError catch (error) {
    ref.invalidate(remindersProvider);
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(t.remindersTitle),
              content: Text(error.message.isEmpty ? t.reminderActionFailed : error.message),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.okay))],
            ),
      );
    }
    return false;
  }
}
