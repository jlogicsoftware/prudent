import 'package:flutter/material.dart';

import '../generated/prudent/v1/goals.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import 'envelope_amount.dart';
import 'goal_figure_row.dart';
import 'goal_figures.dart';

/// One goal: its state, how far it is (ADR-052), what its envelope holds and what to do next.
///
/// [progress] is the server's calculation for this goal; while it is not there — still loading,
/// or failed — the card shows only what the goal itself says (name and target) rather than
/// drawing a zero envelope that would read as "nothing set aside".
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.goal, this.progress, this.onTap});

  final Goal goal;
  final GoalProgress? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final progress = this.progress;
    final guidance = progress == null ? null : goalGuidanceText(t, progress);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final statusLabel = switch (goal.status) {
      GoalStatus.GOAL_STATUS_COMPLETED => t.goalStatusCompleted,
      GoalStatus.GOAL_STATUS_ARCHIVED => t.goalStatusArchived,
      _ => null,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(goal.name, style: theme.textTheme.titleMedium)),
                  if (statusLabel != null)
                    Text(
                      statusLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (goal.hasTargetDate())
                Text(t.goalTargetDate(formatGoalDate(goal.targetDate, locale)), style: muted),
              if (progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress.progressPercent / 100,
                  color: theme.colorScheme.tertiary,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                const SizedBox(height: 4),
                Text(
                  t.goalProgressPercent(progress.progressPercent),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                GoalFigureRow(
                  t.goalSetAside,
                  EnvelopeAmount(progress.allocatedMinor, goal.currency),
                ),
              ] else
                const SizedBox(height: 8),
              GoalFigureRow(
                t.goalTarget,
                Text(
                  formatGoalAmount(goal.targetAmountMinor, goal.currency),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (progress != null)
                GoalFigureRow(
                  t.goalRemaining,
                  Text(
                    formatGoalAmount(progress.remainingMinor, goal.currency),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              if (guidance != null) ...[
                const SizedBox(height: 8),
                Text(guidance, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
