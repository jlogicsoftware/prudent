import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import '../core/local_session.dart';
import '../l10n/generated/local_localizations.dart';

/// Why sync is stopped, if it is: the transport's own status in words the person can act on
/// (`zen_ui_store`'s banner), or the reason no transport could be started at all.
class SyncStatusSlot extends StatelessWidget {
  const SyncStatusSlot({super.key, required this.session});

  final LocalSession session;

  @override
  Widget build(BuildContext context) {
    final transport = session.transport;
    if (transport != null) return ZenSyncStatusBanner(transport: transport);
    final problem = session.syncProblem;
    if (problem == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: scheme.errorContainer,
        padding: const EdgeInsets.all(12),
        child: Text(
          // The sentence is in the person's language ("Sync is off: …" in en, uk and pl); the reason after
          // it is the transport's or ZenSyncPlan's own English detail (a refused build combination, a file
          // or class name, never content). jZen gives no code to word it by, so it follows the localized
          // sentence and never stands alone.
          LocalLocalizations.of(context).syncRefused(problem),
          style: TextStyle(color: scheme.onErrorContainer),
        ),
      ),
    );
  }
}
