import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../generated/prudent/v1/goal_allocations.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import 'envelope_amount.dart';
import 'goal_figures.dart';

/// One entry of a goal's envelope history (ADR-050), read from that goal's side: what happened,
/// when, the note, and how the envelope changed — `+` in, `−` out. A move names the other goal.
class GoalHistoryTile extends StatelessWidget {
  const GoalHistoryTile({
    super.key,
    required this.entry,
    required this.goalId,
    required this.goalNames,
  });

  final GoalAllocation entry;

  /// The goal whose history this is.
  final String goalId;

  /// Every goal's name by id, to name the other side of a move.
  final Map<String, String> goalNames;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final change = envelopeChange(entry, goalId);
    String other(String id) => goalNames[id] ?? t.goalUnknown;

    final (icon, label) = switch (entry.kind) {
      GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE => (Icons.add, t.goalEntryAllocate),
      GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW => (Icons.remove, t.goalEntryWithdraw),
      _ =>
        change.isNegative
            ? (Icons.east, t.goalEntryMoveOut(other(entry.targetGoalId)))
            : (Icons.west, t.goalEntryMoveIn(other(entry.sourceGoalId))),
    };
    final date = DateFormat.yMMMd(
      locale,
    ).format(DateTime.fromMillisecondsSinceEpoch(entry.createdAtMs.toInt()));

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(entry.note.isEmpty ? date : '$date · ${entry.note}'),
      trailing: EnvelopeAmount(change, entry.currency, signed: true),
    );
  }
}
