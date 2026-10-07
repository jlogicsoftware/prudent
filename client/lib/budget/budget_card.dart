import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../overview/planned_cash_flow_row.dart';
import 'budget_figures.dart';

/// One budget's plan, carry-over, actual and remaining amount with the percentage used — a
/// category's, or the month's total.
///
/// OVERSPENT IS SAID IN WORDS AND AN ICON, not by colour alone: the bar and the label turn to the
/// error colour, and the label states the amount, so a user who cannot tell the colours apart
/// still sees the state. The carry-over row is always shown, even at zero,
/// so the rows of every card line up and a zero reads as "nothing carried" rather than as missing.
class BudgetCard extends StatelessWidget {
  const BudgetCard({
    super.key,
    required this.title,
    required this.figures,
    required this.currency,
    this.archived = false,
    this.carryOverResetMonth,
  });

  final String title;
  final BudgetFigures figures;
  final String currency;

  /// The category is retired (ADR-047): its history is still shown, flagged.
  final bool archived;

  /// The already-formatted month a carry-over reset bounds this figure at, or null for none.
  final String? carryOverResetMonth;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final overspent = figures.isOverspent;
    final percent = figures.percentUsed;
    final accent = overspent ? theme.colorScheme.error : theme.colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                if (archived)
                  Text(
                    t.budgetCategoryArchived,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (percent != null) ...[
              const SizedBox(height: 8),
              ZenProgressBar(value: percent.clamp(0, 100) / 100, label: title, color: accent),
              const SizedBox(height: 4),
              Text(t.budgetPercentUsed(percent), style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            PlannedCashFlowRow(t.budgetPlan, figures.plan, currency),
            PlannedCashFlowRow(t.budgetCarryOver, figures.carryOver, currency),
            if (carryOverResetMonth != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t.budgetCarryOverReset(carryOverResetMonth!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            PlannedCashFlowRow(t.budgetActual, figures.actual, currency),
            const Divider(),
            PlannedCashFlowRow(t.budgetRemaining, figures.remaining, currency, emphasis: true),
            if (overspent)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: accent),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        t.budgetOverspent('${formatMinorUnits(figures.overspentBy)} $currency'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: accent),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
