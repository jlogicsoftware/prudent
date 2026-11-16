import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import 'import_row_warning.dart';
import 'import_rule_messages.dart';

/// One row the user can still decide: an accepted row, or a duplicate they may include.
///
/// Tapping it opens the row's category and note. A duplicate also carries an explicit "Import
/// anyway" switch in plain view, with the risk said in words, because ADR-091 requires the user to
/// be able to override a wrong duplicate verdict and the override writes a second record.
class ImportRowTile extends StatelessWidget {
  const ImportRowTile({
    super.key,
    required this.row,
    required this.currency,
    required this.categoryName,
    required this.categoryIsDefault,
    required this.onEdit,
    required this.onIncludeDuplicate,
    this.enabled = true,
  });

  final ImportRow row;
  final String currency;

  /// The category the row will be filed under, or null when it has none and no default applies.
  final String? categoryName;
  final bool categoryIsDefault;
  final VoidCallback onEdit;
  final ValueChanged<bool> onIncludeDuplicate;
  final bool enabled;

  /// The statement's civil date (`YYYY-MM-DD`) in the app's locale, as a record shows it.
  static String _formattedDate(BuildContext context, String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return DateFormat.yMd(Localizations.localeOf(context).toLanguageTag()).format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final isDuplicate = row.status == ImportRowStatus.IMPORT_ROW_STATUS_DUPLICATE;
    final description = row.hasDescription() ? row.description.trim() : '';
    final amount = row.hasAmountMinor() ? '${formatMinorUnits(row.amountMinor)} $currency' : '';
    final date = row.hasTransactionDate() ? _formattedDate(context, row.transactionDate) : '';

    // A duplicate that is left out is not written, so having no category is not a problem for it.
    final missing = categoryName == null && (!isDuplicate || row.includeDuplicate);
    final categoryLine =
        categoryName == null
            ? (missing ? t.importRowCategoryMissing : t.importNoCategory)
            : categoryIsDefault
            ? t.importRowCategoryDefault(categoryName!)
            : t.importRowCategoryOwn(categoryName!);

    final hintMessage = row.hintCode.isEmpty ? null : importRuleMessage(t, row.hintCode);
    final duplicateMessage =
        row.duplicateCode.isEmpty
            ? null
            : importRuleMessage(t, row.duplicateCode) ?? t.importRowUnknownCode(row.duplicateCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          hint: t.importRowEditAction(row.rowNumber),
          child: ZenListRow(
            title: description.isEmpty ? t.importRowEditTitle(row.rowNumber) : description,
            subtitleContent: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (date.isNotEmpty) Text(date),
                Text(
                  categoryLine,
                  style: missing ? TextStyle(color: theme.colorScheme.error) : null,
                ),
                if (row.hasNote() && row.note.isNotEmpty)
                  Text(t.importRowNoteShown(row.note), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
            trailing: Text(amount, style: theme.textTheme.titleSmall),
            onTap: enabled ? onEdit : null,
          ),
        ),
        if (hintMessage != null)
          ImportRowWarning(title: t.importRowOwnTransferWarning, message: hintMessage),
        if (isDuplicate) ...[
          if (duplicateMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(duplicateMessage, style: theme.textTheme.bodySmall),
            ),
          ZenSwitchRow(
            label: t.importRowIncludeDuplicate,
            subtitle: t.importRowIncludeDuplicateHint,
            value: row.includeDuplicate,
            onChanged: enabled ? onIncludeDuplicate : null,
          ),
        ],
        const Divider(height: 1),
      ],
    );
  }
}
