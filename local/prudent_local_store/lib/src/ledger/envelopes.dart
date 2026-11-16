import 'package:prudent_local_core/prudent_local_core.dart';

import '../../generated/prudent_local/v1/store.pb.dart';

/// Every goal's envelope from its entries (`GoalAllocationEntity.balances`, ADR-050): `+amount` for
/// each entry that targets the goal, `−amount` for each that takes from it. A goal with no entry is
/// absent (zero). An envelope has no stored amount anywhere; the ledger's figures and the integrity
/// checks both read it from here, so they cannot disagree about it.
Map<String, int> goalEnvelopes(Iterable<GoalAllocation> entries) {
  final out = <String, int>{};
  for (final entry in entries) {
    final amount = entry.amountMinor.toInt();
    if (entry.hasTargetGoalId()) {
      out[entry.targetGoalId] = addExact(out[entry.targetGoalId] ?? 0, amount);
    }
    if (entry.hasSourceGoalId()) {
      out[entry.sourceGoalId] = subtractExact(out[entry.sourceGoalId] ?? 0, amount);
    }
  }
  return out;
}
