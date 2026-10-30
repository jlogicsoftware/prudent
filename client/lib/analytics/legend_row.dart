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
    // Read at the app's body size: the colour only ties a row to its slice, while the name, the
    // share and the amount carry the meaning.
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text('$percent%', style: style),
          const SizedBox(width: 16),
          Text(amount, style: style),
        ],
      ),
    );
  }
}
