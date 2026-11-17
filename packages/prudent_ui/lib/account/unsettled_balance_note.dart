import 'package:material_ui/material_ui.dart';

import '../l10n/generated/prudent_localizations.dart';

/// Said beside a balance that leaves something out: how many entries the person's devices disagree
/// about, which no figure counts until they are settled (Prudent Local, ADR-113). Never a bare
/// number that silently drops money. Draws nothing when [count] is zero, which is always the case
/// for the server-connected app.
class UnsettledBalanceNote extends StatelessWidget {
  const UnsettledBalanceNote({super.key, required this.count});

  /// How many records, transfers or opening amounts the figure leaves out.
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(Icons.sync_problem, size: 16, color: color)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              PrudentLocalizations.of(context).unsettledBalanceNote(count),
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
