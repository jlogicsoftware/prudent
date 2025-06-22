import 'package:flutter/material.dart';

import '../record.dart';

class RecordItem extends StatelessWidget {
  const RecordItem(this.record, {super.key});

  final Record record;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(child: Icon(categoryIcons[record.category])),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.category.name.toUpperCase(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  record.formattedDate,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '\$${record.amount.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}
