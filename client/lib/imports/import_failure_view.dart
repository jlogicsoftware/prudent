import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';
import 'import_failure.dart';
import 'import_failure_text.dart';

/// Why an import request failed, as a sentence the user can act on: what was wrong and what to do,
/// plus the row numbers the server named. Never the server's own text, and never statement content;
/// see [ImportFailure].
class ImportFailureView extends StatelessWidget {
  const ImportFailureView({
    super.key,
    required this.failure,
    this.title,
    this.onRetry,
    this.retryLabel,
  });

  final ImportFailure failure;

  /// A heading above the message; the upload screen uses "The statement was not accepted".
  final String? title;

  /// When set, a button that tries again.
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final rows = importFailureRows(t, failure);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      Text(
                        importFailureMessage(t, failure),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      if (rows != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            rows,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              ZenButton(
                label: retryLabel ?? t.loadErrorRetry,
                variant: ZenButtonVariant.secondary,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
