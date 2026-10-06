import 'package:flutter/material.dart';

/// One labelled fact about an occurrence: the label on the left, its value on the right.
class OccurrenceFigureRow extends StatelessWidget {
  const OccurrenceFigureRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 8),
          Flexible(child: Text(value, style: theme.textTheme.bodyLarge, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
