import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../generated/prudent/v1/categories.pb.dart';
import '../generated/prudent/v1/imports.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import 'import_confirm_bar.dart';
import 'import_defaults_card.dart';
import 'import_destination_field.dart';
import 'import_group.dart';
import 'import_review.dart';
import 'import_row_tile.dart';
import 'rejected_import_row_tile.dart';

/// The review of an open import: the destination and default categories, the three groups of rows
/// (to import, duplicates, not readable) one at a time, and the confirm bar.
///
/// Everything it shows comes from [review]; it decides nothing itself and calls back for every
/// change, so the figures on screen are the ones the server last answered.
class ImportReviewBody extends StatelessWidget {
  const ImportReviewBody({
    super.key,
    required this.review,
    required this.accounts,
    required this.categories,
    required this.group,
    required this.working,
    required this.onGroupChanged,
    required this.onDestination,
    required this.onDefaults,
    required this.onEditRow,
    required this.onIncludeDuplicate,
    required this.onConfirm,
    required this.onReload,
  });

  final ImportReview review;
  final List<Account> accounts;
  final List<Category> categories;
  final ImportGroup group;
  final bool working;
  final ValueChanged<ImportGroup> onGroupChanged;
  final ValueChanged<String> onDestination;
  final void Function({String? expenseCategoryId, String? incomeCategoryId}) onDefaults;
  final ValueChanged<ImportRow> onEditRow;
  final void Function(ImportRow row, bool include) onIncludeDuplicate;
  final VoidCallback onConfirm;
  final VoidCallback onReload;

  List<ImportRow> get _shown => switch (group) {
    ImportGroup.accepted => review.accepted,
    ImportGroup.duplicates => review.duplicates,
    ImportGroup.rejected => review.rejected,
  };

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final shown = _shown;
    final names = {for (final c in categories) c.id: c.title};
    final currency = review.session.currency;
    final accountName =
        accounts.where((a) => a.id == review.session.accountId).firstOrNull?.name;

    final header = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (accountName != null)
            Text(t.importDestinationSummary(accountName, currency), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          ImportDestinationField(
            review: review,
            accounts: accounts,
            onChanged: onDestination,
            enabled: !working,
          ),
          const SizedBox(height: 16),
          ImportDefaultsCard(
            review: review,
            categories: categories,
            onChanged: onDefaults,
            enabled: !working,
          ),
          const SizedBox(height: 16),
          ZenSegmentedControl<ImportGroup>(
            segments: [
              ZenSegment(
                value: ImportGroup.accepted,
                label: t.importGroupAccepted(review.accepted.length),
              ),
              ZenSegment(
                value: ImportGroup.duplicates,
                label: t.importGroupDuplicates(review.duplicates.length),
              ),
              ZenSegment(
                value: ImportGroup.rejected,
                label: t.importGroupRejected(review.rejected.length),
              ),
            ],
            selected: group,
            onChanged: onGroupChanged,
          ),
          const SizedBox(height: 8),
          if (group == ImportGroup.duplicates && shown.isNotEmpty)
            Text(t.importDuplicatesHint, style: theme.textTheme.bodySmall),
          if (group == ImportGroup.rejected && shown.isNotEmpty)
            Text(t.importRejectedHint, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            // The header is item 0; an empty group shows one line instead of rows.
            itemCount: 1 + (shown.isEmpty ? 1 : shown.length),
            itemBuilder: (context, index) {
              if (index == 0) return header;
              if (shown.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    switch (group) {
                      ImportGroup.accepted => t.importGroupEmptyAccepted,
                      ImportGroup.duplicates => t.importGroupEmptyDuplicates,
                      ImportGroup.rejected => t.importGroupEmptyRejected,
                    },
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                );
              }
              final row = shown[index - 1];
              if (row.status == ImportRowStatus.IMPORT_ROW_STATUS_REJECTED) {
                return RejectedImportRowTile(key: ValueKey('row-${row.rowNumber}'), row: row);
              }
              final own = row.hasCategoryId() && row.categoryId.isNotEmpty;
              final effective = review.effectiveCategory(row);
              return ImportRowTile(
                key: ValueKey('row-${row.rowNumber}'),
                row: row,
                currency: currency,
                categoryName: effective == null ? null : names[effective],
                categoryIsDefault: !own,
                enabled: !working,
                onEdit: () => onEditRow(row),
                onIncludeDuplicate: (include) => onIncludeDuplicate(row, include),
              );
            },
          ),
        ),
        ImportConfirmBar(
          review: review,
          working: working,
          onConfirm: onConfirm,
          onReload: onReload,
        ),
      ],
    );
  }
}
