import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../category/selectable_categories.dart';
import '../generated/prudent/v1/categories.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import 'import_review.dart';

/// The session's default category for expenses and for income. A statement has far more rows than a
/// person will categorise one by one, so a row without a category of its own is filed under the
/// default for its direction (ADR-092). A select is shown only for a direction the statement has.
class ImportDefaultsCard extends StatelessWidget {
  const ImportDefaultsCard({
    super.key,
    required this.review,
    required this.categories,
    required this.onChanged,
    this.enabled = true,
  });

  final ImportReview review;
  final List<Category> categories;

  /// An empty string clears a default.
  final void Function({String? expenseCategoryId, String? incomeCategoryId}) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    // A rejected row has no amount and is never written, so it needs no category.
    final hasExpense = review.rows.any((r) => r.hasAmountMinor() && ImportReview.isExpense(r));
    final hasIncome = review.rows.any((r) => r.hasAmountMinor() && !ImportReview.isExpense(r));
    if (!hasExpense && !hasIncome) return const SizedBox.shrink();

    Widget select({
      required String label,
      required bool expense,
      required String current,
      required void Function(String) set,
    }) {
      final offered = selectableCategories(
        categories,
        keep: current.isEmpty ? null : current,
        expense: expense,
      );
      final names = {for (final c in offered) c.id: c.title};
      return ZenSelect<String>(
        label: label,
        items: ['', ...names.keys],
        itemLabel: (id) => id.isEmpty ? t.importNoCategory : names[id] ?? t.importNoCategory,
        value: names.containsKey(current) ? current : '',
        onChanged: enabled ? set : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(t.importDefaultsTitle, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 4),
        Text(t.importDefaultsHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        if (hasExpense)
          select(
            label: t.importDefaultExpense,
            expense: true,
            current: review.session.defaultExpenseCategoryId,
            set: (id) => onChanged(expenseCategoryId: id),
          ),
        // Room for the next select's floating label, as the account form leaves.
        if (hasExpense && hasIncome) const SizedBox(height: 16),
        if (hasIncome)
          select(
            label: t.importDefaultIncome,
            expense: false,
            current: review.session.defaultIncomeCategoryId,
            set: (id) => onChanged(incomeCategoryId: id),
          ),
      ],
    );
  }
}
