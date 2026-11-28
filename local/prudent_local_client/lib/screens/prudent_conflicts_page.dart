import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import '../app/local_providers.dart';
import '../conflicts/prudent_conflict_sources.dart';
import '../integrity/prudent_issue_source.dart';
import '../l10n/generated/local_localizations.dart';

/// Settings → Conflicts and issues: `zen_ui_store`'s list of what waits for the person — the
/// store's conflicts, settled one by one or many at once (jZenDev/jZen#234), and the integrity
/// runner's issues beside them (jZenDev/jZen#233). The banner on the home screen opens the same list.
class PrudentConflictsPage extends ConsumerWidget {
  const PrudentConflictsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LocalLocalizations.of(context);
    final session = ref.watch(localSessionProvider);
    return ZenConflictsScreen(
      store: session.store,
      sources: prudentConflictSources(session.prudent, t),
      issues: [prudentIssueSource(IntegrityRunner(session.prudent), t)],
    );
  }
}
