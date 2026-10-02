import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/goal_allocations.pb.dart';
import '../generated/prudent/v1/goals.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';
import 'goal_figures.dart';

/// Adds money to [goal]'s envelope, withdraws it, or moves it to another goal — one immutable
/// history entry each (ADR-050). Nothing moves between accounts.
///
/// The form shows what the entry draws on (free money for an addition, the envelope for a
/// withdrawal or a move) but does not enforce it: the server is the one place that rule lives
/// (ADR-050, ADR-051), and a refusal is shown in its words, with the form left open.
class GoalAllocationForm extends ConsumerStatefulWidget {
  const GoalAllocationForm({super.key, required this.goal, required this.kind});

  final Goal goal;
  final GoalAllocationKind kind;

  @override
  ConsumerState<GoalAllocationForm> createState() => _GoalAllocationFormState();
}

class _GoalAllocationFormState extends ConsumerState<GoalAllocationForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  Goal? _moveTarget;
  String? _amountError;
  String? _failure;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(PrudentLocalizations t) async {
    final canonical = normalizeAmount(_amount.text, maxFractionDigits: 2, allowNegative: false);
    final minor = canonical == null ? null : parseMinorUnits(canonical);
    final amountValid = minor != null && minor > Int64.ZERO;
    setState(() => _amountError = amountValid ? null : t.goalAmountInvalid);
    if (!amountValid) return;

    final goal = widget.goal;
    final request = CreateGoalAllocationRequest(
      kind: widget.kind,
      amountMinor: minor,
      note: _note.text.trim(),
    );
    switch (widget.kind) {
      case GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE:
        request.targetGoalId = goal.id;
      case GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW:
        request.sourceGoalId = goal.id;
      default:
        request
          ..sourceGoalId = goal.id
          ..targetGoalId = _moveTarget!.id;
    }

    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      await ref.read(goalsProvider.notifier).recordAllocation(request);
      if (mounted) Navigator.pop(context);
    } on ZenError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failure = error.message.isEmpty ? t.goalActionFailed : error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final goal = widget.goal;
    final isMove = widget.kind == GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE;
    final isAllocate = widget.kind == GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE;

    final title = switch (widget.kind) {
      GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE => t.goalAllocateTitle(goal.name),
      GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW => t.goalWithdrawTitle(goal.name),
      _ => t.goalMoveTitle(goal.name),
    };

    String? available;
    if (isAllocate) {
      final free = ref.watch(goalFreeMoneyProvider).value;
      if (free != null) {
        // A currency with no eligible account and no goal is absent (ADR-051): nothing is free.
        final entry = free.where((c) => c.currency == goal.currency).firstOrNull;
        available = t.goalAvailableFree(
          formatGoalAmount(entry?.freeMinor ?? Int64.ZERO, goal.currency),
        );
      }
    } else {
      final progress = ref.watch(goalProgressProvider).value?[goal.id];
      if (progress != null) {
        available = t.goalAvailableEnvelope(
          formatGoalAmount(progress.allocatedMinor, goal.currency),
        );
      }
    }

    final targets =
        isMove ? moveTargets(ref.watch(goalsProvider).value ?? const [], goal) : const <Goal>[];
    final moveTarget = targets.contains(_moveTarget) ? _moveTarget : null;
    final blocked = isMove && targets.isEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          if (available != null) ...[
            const SizedBox(height: 4),
            Text(available, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          if (blocked)
            Text(t.goalMoveNoTarget(goal.currency), style: theme.textTheme.bodyLarge)
          else ...[
            if (isMove) ...[
              ZenSelect<Goal>(
                label: t.goalMoveTo,
                items: targets,
                itemLabel: (g) => g.name,
                value: moveTarget,
                onChanged: (value) => setState(() => _moveTarget = value),
              ),
              const SizedBox(height: 16),
            ],
            ZenAmountField(
              label: '${t.goalAmountField} (${goal.currency})',
              controller: _amount,
              maxFractionDigits: 2,
              allowNegative: false,
              errorText: _amountError,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: t.goalNoteField,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_failure != null) ...[
              const SizedBox(height: 8),
              Text(_failure!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ZenButton(
                label: t.cancel,
                variant: ZenButtonVariant.text,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              ZenButton(
                label: t.goalSave,
                isLoading: _saving,
                onPressed: blocked || (isMove && moveTarget == null) ? null : () => _submit(t),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
