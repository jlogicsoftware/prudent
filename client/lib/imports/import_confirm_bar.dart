import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';
import 'import_review.dart';

/// The confirm button, and the reason it is disabled when it is. It is enabled only when every row to
/// be written has a category (its own or a default), the session has a destination and the row counts
/// the server returned agree with the rows held; the count it confirms is the server's.
class ImportConfirmBar extends StatelessWidget {
  const ImportConfirmBar({
    super.key,
    required this.review,
    required this.working,
    required this.onConfirm,
    required this.onReload,
  });

  final ImportReview review;

  /// A request is in flight; confirming waits for it.
  final bool working;
  final VoidCallback onConfirm;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final String? reason;
    var reloadable = false;
    if (!review.hasDestination) {
      reason = t.importNoAccountChosen;
    } else if (!review.countsAgree) {
      reason = t.importCountMismatch;
      reloadable = true;
    } else if (review.uncategorised > 0) {
      reason = t.importConfirmNeedsCategory(review.uncategorised);
    } else {
      reason = null;
    }
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reason != null)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(reason, style: theme.textTheme.bodySmall),
                  ),
                ),
              if (reloadable)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ZenButton(
                    label: t.loadErrorRetry,
                    variant: ZenButtonVariant.secondary,
                    onPressed: onReload,
                  ),
                ),
              ZenButton(
                label: t.importConfirm(review.confirmedRows),
                isLoading: working,
                onPressed: review.canConfirm && !working ? onConfirm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
