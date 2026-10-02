import 'package:flutter/material.dart';

/// One labelled figure on a goal or free-money card: the label on the left, the value — plain
/// text, or an [EnvelopeAmount] for money set aside — on the right.
class GoalFigureRow extends StatelessWidget {
  const GoalFigureRow(this.label, this.value, {super.key});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          const SizedBox(width: 8),
          value,
        ],
      ),
    );
  }
}
