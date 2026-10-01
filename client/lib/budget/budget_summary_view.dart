import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../generated/prudent/v1/budgets.pb.dart';
import '../generated/prudent/v1/categories.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import 'budget_card.dart';
import 'budget_figures.dart';
import 'budget_month.dart';

/// One month's budgets in one currency: the totals, then a card per budgeted category.
///
/// A month with no budgeted category gets its own empty state rather than a card of zeros — an
/// empty summary says "nothing is budgeted", which is different from "everything budgeted is at
/// zero" (ADR-047), and spending in an unbudgeted category is in no figure to show (ADR-044).
class BudgetSummaryView extends StatelessWidget {
  const BudgetSummaryView({
    super.key,
    required this.summary,
    required this.month,
    required this.categories,
  });

  final BudgetSummaryResponse summary;
  final BudgetMonth month;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final monthLabel = DateFormat.yMMMM(locale).format(month.firstDay);

    if (summary.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.savings_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                t.budgetEmpty(monthLabel, summary.currency),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    final items = budgetItemsByTitle(summary.items, categories, t.chartUnknownCategory);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        BudgetCard(
          title: t.budgetTotal,
          figures: BudgetFigures.ofTotals(summary),
          currency: summary.currency,
        ),
        const SizedBox(height: 8),
        for (final item in items)
          BudgetCard(
            title: categories[item.categoryId]?.title ?? t.chartUnknownCategory,
            archived: categories[item.categoryId]?.archived ?? false,
            figures: BudgetFigures.ofItem(item),
            currency: summary.currency,
            carryOverResetMonth:
                item.carryOverResetMonth.isEmpty
                    ? null
                    : _formatWireMonth(item.carryOverResetMonth, locale),
          ),
      ],
    );
  }

  /// `YYYY-MM` from the server to a readable month; the raw text if it is somehow not one, so a
  /// reset is never shown as a blank or a guess.
  static String _formatWireMonth(String wire, String locale) {
    final parts = wire.split('-');
    final year = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final monthNumber = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (year == null || monthNumber == null) return wire;
    return DateFormat.yMMMM(locale).format(BudgetMonth(year, monthNumber).firstDay);
  }
}
