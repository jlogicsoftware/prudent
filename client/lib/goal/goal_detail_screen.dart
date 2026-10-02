import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/goal_allocations.pb.dart';
import '../generated/prudent/v1/goals.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'goal_allocation_form.dart';
import 'goal_card.dart';
import 'goal_form.dart';
import 'goal_history_tile.dart';

enum _LifecycleAction { edit, complete, archive, reactivate }

/// One goal: its figures, the actions its state allows, and its envelope history.
///
/// The actions offered follow the goal's state, as the server's rules do (goal_allocations.proto,
/// goals.proto): an active goal takes money in, gives it out and can be edited, completed or
/// archived; a completed one can still give money out; an archived one is read-only until it is
/// reactivated. Offering only what the state allows is a convenience — the server still decides,
/// and a refusal (archiving a goal that holds money, say) is shown in its words.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final goals = ref.watch(goalsProvider).value ?? const <Goal>[];
    final goal = goals.where((g) => g.id == goalId).firstOrNull;
    if (goal == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(t.goalNotFound)));
    }

    final progress = ref.watch(goalProgressProvider).value?[goalId];
    final historyAsync = ref.watch(goalHistoryProvider(goalId));
    final names = {for (final g in goals) g.id: g.name};
    final status = goal.status;
    final active = status == GoalStatus.GOAL_STATUS_ACTIVE;
    final archived = status == GoalStatus.GOAL_STATUS_ARCHIVED;

    void openAllocation(GoalAllocationKind kind) => showAdaptivePresentation<void>(
      context,
      builder: (_) => GoalAllocationForm(goal: goal, kind: kind),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(goal.name),
        actions: [
          PopupMenuButton<_LifecycleAction>(
            onSelected: (action) => _onLifecycle(context, ref, goal, action),
            itemBuilder:
                (_) => [
                  if (!archived)
                    PopupMenuItem(value: _LifecycleAction.edit, child: Text(t.goalActionEdit)),
                  if (active)
                    PopupMenuItem(
                      value: _LifecycleAction.complete,
                      child: Text(t.goalActionComplete),
                    ),
                  if (!archived)
                    PopupMenuItem(
                      value: _LifecycleAction.archive,
                      child: Text(t.goalActionArchive),
                    ),
                  if (!active)
                    PopupMenuItem(
                      value: _LifecycleAction.reactivate,
                      child: Text(t.goalActionReactivate),
                    ),
                ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GoalCard(goal: goal, progress: progress),
          const SizedBox(height: 8),
          if (archived)
            Text(t.goalArchivedReadOnly, style: Theme.of(context).textTheme.bodyMedium)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (active)
                  ZenButton(
                    label: t.goalActionAllocate,
                    icon: Icons.add,
                    onPressed:
                        () => openAllocation(GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE),
                  ),
                ZenButton(
                  label: t.goalActionWithdraw,
                  icon: Icons.remove,
                  variant: ZenButtonVariant.secondary,
                  onPressed: () => openAllocation(GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW),
                ),
                ZenButton(
                  label: t.goalActionMove,
                  icon: Icons.swap_horiz,
                  variant: ZenButtonVariant.secondary,
                  onPressed: () => openAllocation(GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE),
                ),
              ],
            ),
          const SizedBox(height: 24),
          Text(t.goalHistory, style: Theme.of(context).textTheme.titleMedium),
          historyAsync.when(
            loading:
                () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            error: (error, _) => Text(t.goalHistoryLoadError(error.toString())),
            data:
                (entries) =>
                    entries.isEmpty
                        ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(t.goalHistoryEmpty),
                        )
                        : Column(
                          children: [
                            for (final entry in entries)
                              GoalHistoryTile(entry: entry, goalId: goalId, goalNames: names),
                          ],
                        ),
          ),
        ],
      ),
    );
  }

  Future<void> _onLifecycle(
    BuildContext context,
    WidgetRef ref,
    Goal goal,
    _LifecycleAction action,
  ) async {
    final t = PrudentLocalizations.of(context);
    final goals = ref.read(goalsProvider.notifier);
    try {
      switch (action) {
        case _LifecycleAction.edit:
          await showAdaptivePresentation<void>(context, builder: (_) => GoalForm(goal: goal));
        case _LifecycleAction.complete:
          await goals.completeGoal(goal.id);
        case _LifecycleAction.archive:
          await goals.archiveGoal(goal.id);
        case _LifecycleAction.reactivate:
          await goals.reactivateGoal(goal.id);
      }
    } on ZenError catch (error) {
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(goal.name),
              content: Text(error.message.isEmpty ? t.goalActionFailed : error.message),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.okay))],
            ),
      );
    }
  }
}
