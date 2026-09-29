import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';

import '../money.dart';

/// One labelled amount in a planned-cash-flow card — income, spending or the net, which is set
/// apart by [emphasis].
class PlannedCashFlowRow extends StatelessWidget {
  const PlannedCashFlowRow(
    this.label,
    this.amount,
    this.currency, {
    this.emphasis = false,
    super.key,
  });

  final String label;
  final Int64 amount;
  final String currency;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final style =
        emphasis ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: style)),
          Text('${formatMinorUnits(amount)} $currency', style: style),
        ],
      ),
    );
  }
}
