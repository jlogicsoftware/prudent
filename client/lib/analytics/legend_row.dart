import 'package:flutter/material.dart';

/// One category in the spend chart's legend: its colour, name, share of the total and amount.
class LegendRow extends StatelessWidget {
  const LegendRow({super.key, required this.color, required this.label, required this.amount, required this.percent});

  final Color color;
  final String label;
  final String amount;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text('$percent%', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 12),
          Text(amount, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
