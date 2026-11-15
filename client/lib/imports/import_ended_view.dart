import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';

/// A session that can no longer be reviewed: expired after its 24 hours, discarded, or gone. Says so
/// in words, says what to do, and offers the way back. Nothing is shown of the session's rows; they
/// are deleted when it ends.
class ImportEndedView extends StatelessWidget {
  const ImportEndedView({
    super.key,
    required this.title,
    required this.body,
    required this.onBack,
  });

  final String title;
  final String body;

  /// Returns to the first step of the import. Not a pop: in a side pane the review is the pane's
  /// only page, and popping it would close the pane.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_disabled, size: 40, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ZenButton(
                label: t.importBackToImport,
                variant: ZenButtonVariant.secondary,
                onPressed: onBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
