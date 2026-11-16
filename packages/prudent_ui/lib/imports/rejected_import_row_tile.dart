import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/imports.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import 'import_rule_messages.dart';

/// A row the importer could not make sense of. It shows the row number and why, in words, and has no
/// control: the server takes no decision on a rejected row and nothing here pretends otherwise. It
/// shows no statement text; the importer returns none for a rejected row.
class RejectedImportRowTile extends StatelessWidget {
  const RejectedImportRowTile({super.key, required this.row});

  final ImportRow row;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final code = row.rejectionCode;
    final reason =
        code.isEmpty
            ? t.importRowUnknownCode('?')
            : importRuleMessage(t, code) ?? t.importRowUnknownCode(code);
    return Column(
      children: [
        ZenListRow(
          leading: Icon(Icons.block, color: Theme.of(context).colorScheme.error),
          title: t.importRejectedRow(row.rowNumber),
          subtitleContent: Text(reason),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
