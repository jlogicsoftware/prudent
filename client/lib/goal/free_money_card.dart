import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';

import '../generated/prudent/v1/goal_allocations.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import 'envelope_amount.dart';
import 'goal_figure_row.dart';
import 'goal_figures.dart';

/// Per currency, what the eligible accounts hold, what the envelopes hold and what is still free
/// to set aside (ADR-051) — and, in words, that envelopes are not money taken out of an account.
///
/// Each currency is its own block: there is no FX, so the figures are never summed across them
/// (ADR-009). Free money can be negative after a later spend; that is said in words and an icon,
/// not colour alone, because it is the state that refuses every further allocation.
class FreeMoneyCard extends StatelessWidget {
  const FreeMoneyCard({super.key, required this.currencies});

  final List<CurrencyFreeMoney> currencies;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.goalFreeMoneyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(t.goalFreeMoneyNote, style: muted),
            if (currencies.isEmpty) ...[
              const SizedBox(height: 8),
              Text(t.goalFreeMoneyEmpty, style: theme.textTheme.bodyMedium),
            ],
            for (final entry in currencies) ...[
              const Divider(),
              GoalFigureRow(
                t.goalEligible,
                Text(
                  formatGoalAmount(entry.eligibleMinor, entry.currency),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              GoalFigureRow(t.goalSetAside, EnvelopeAmount(entry.allocatedMinor, entry.currency)),
              GoalFigureRow(
                t.goalFree,
                Text(
                  formatGoalAmount(entry.freeMinor, entry.currency),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (entry.freeMinor < Int64.ZERO)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: theme.colorScheme.error),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          t.goalOverAllocated(formatGoalAmount(-entry.freeMinor, entry.currency)),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
