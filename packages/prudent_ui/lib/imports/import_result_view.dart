import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart';
import '../l10n/generated/prudent_localizations.dart';

/// What a committed import did: how many records it wrote and how many rows were already in the
/// account (counts only; the rows are gone), and a way back to the accounts.
class ImportResultView extends StatelessWidget {
  const ImportResultView({super.key, required this.session});

  final ImportSession session;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final written = session.hasCommittedWritten() ? session.committedWritten : 0;
    final already = session.hasCommittedAlreadyImported() ? session.committedAlreadyImported : 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(t.importResultTitle, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(t.importResultWritten(written), textAlign: TextAlign.center),
              if (already > 0) Text(t.importResultAlready(already), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                t.importResultHint,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ZenButton(
                label: t.importResultToAccounts,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
