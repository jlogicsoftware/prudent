import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/local_localizations.dart';
import '../widgets/confirm_step.dart';

/// The body of [StartFailedApp]: what went wrong, what to do, and the way out the platform allows.
class StartFailedPage extends StatelessWidget {
  const StartFailedPage({
    super.key,
    required this.error,
    required this.onRetry,
    this.onErase,
    required this.isLinux,
  });

  final ZenError error;
  final VoidCallback onRetry;

  /// Erases this device's copy after a question; null when erasing would not help (the store opened,
  /// only the device's secret storage did not answer), and then nothing that erases is offered.
  final Future<void> Function()? onErase;
  final bool isLinux;

  @override
  Widget build(BuildContext context) {
    final t = LocalLocalizations.of(context);
    final theme = Theme.of(context);
    return ZenPageScaffold(
      title: t.appTitle,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Semantics(
            header: true,
            child: Text(t.startFailedTitle, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 12),
          Text(t.startFailedBody),
          const SizedBox(height: 12),
          if (isLinux)
            Text(t.startFailedLinux)
          else if (onErase != null)
            Text(t.startFailedRestored),
          const SizedBox(height: 12),
          // The store's error names files and classes, never what they hold (ADR-100 T21).
          Text(
            t.startFailedDetail(error.message),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ZenButton(label: t.startFailedRetry, onPressed: onRetry),
          if (!isLinux && onErase != null) ...[
            const SizedBox(height: 8),
            ZenButton(
              label: t.startFailedErase,
              variant: ZenButtonVariant.text,
              onPressed: () async {
                final go = await confirmStep(
                  context,
                  question: t.startFailedEraseConfirm,
                  action: t.erase,
                  cancel: t.cancel,
                );
                if (go) await onErase!();
              },
            ),
          ],
        ],
      ),
    );
  }
}
