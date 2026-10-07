import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/goals.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'free_money_card.dart';
import 'goal_card.dart';
import 'goal_detail_screen.dart';
import 'goal_figures.dart';
import 'goal_form.dart';

/// The goals tab (M4, jlogicsoftware/prudent#67): the money free to set aside per currency, then the
/// goals in one state at a time — active, completed or archived — each with its envelope and
/// progress. A goal opens to its history and actions.
///
/// The state shown is view state, not a setting, so it lives here and starts at "active" each time
/// the tab is opened. Archived and completed goals are a tap away rather than hidden, because a goal
/// is retired and never deleted (ADR-049): its history is still the user's to read.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  GoalStatus _status = GoalStatus.GOAL_STATUS_ACTIVE;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final goalsAsync = ref.watch(goalsProvider);
    final progress = ref.watch(goalProgressProvider).value ?? const {};
    final freeMoneyAsync = ref.watch(goalFreeMoneyProvider);

    return ZenPageScaffold(
      title: t.goalsTitle,
      actions: [
        ZenIconButton(
          icon: Icons.add,
          label: t.goalNew,
          onPressed:
              () => showAdaptivePresentation<void>(
                context,
                builder: (_) => const GoalForm(),
              ),
        ),
      ],
      body: goalsAsync.when(
        loading: () => const Center(child: ZenProgressIndicator()),
        error:
            (error, _) => Center(child: Text(t.goalsLoadError(error.toString()))),
        data: (goals) {
          final shown = goalsWithStatus(goals, _status);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              freeMoneyAsync.when(
                loading: () => const Center(child: ZenProgressIndicator()),
                error:
                    (error, _) =>
                        Text(t.goalFreeMoneyLoadError(error.toString())),
                data: (currencies) => FreeMoneyCard(currencies: currencies),
              ),
              const SizedBox(height: 16),
              ZenSegmentedControl<GoalStatus>(
                segments: [
                  ZenSegment(
                    value: GoalStatus.GOAL_STATUS_ACTIVE,
                    label: t.goalSegmentActive,
                  ),
                  ZenSegment(
                    value: GoalStatus.GOAL_STATUS_COMPLETED,
                    label: t.goalSegmentCompleted,
                  ),
                  ZenSegment(
                    value: GoalStatus.GOAL_STATUS_ARCHIVED,
                    label: t.goalSegmentArchived,
                  ),
                ],
                selected: _status,
                onChanged: (status) => setState(() => _status = status),
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    switch (_status) {
                      GoalStatus.GOAL_STATUS_COMPLETED => t.goalsEmptyCompleted,
                      GoalStatus.GOAL_STATUS_ARCHIVED => t.goalsEmptyArchived,
                      _ => t.goalsEmptyActive,
                    },
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              for (final goal in shown)
                GoalCard(
                  goal: goal,
                  progress: progress[goal.id],
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GoalDetailScreen(goalId: goal.id),
                        ),
                      ),
                ),
            ],
          );
        },
      ),
    );
  }
}
