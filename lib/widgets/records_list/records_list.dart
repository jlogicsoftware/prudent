import 'package:flutter/material.dart';
import 'package:prudent/new_record.dart';

import '../../models/record.dart';
import 'record_item.dart';

class RecordsList extends StatelessWidget {
  const RecordsList({
    super.key,
    required this.records,
    required this.onRemoveRecord,
  });

  final List<Record> records;
  final void Function(Record expense) onRemoveRecord;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: records.length,
      itemBuilder:
          (ctx, index) => Dismissible(
            key: ValueKey(records[index]),
            secondaryBackground: Container(
              color: Theme.of(context).colorScheme.error,
              margin: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Spacer(),
                  Icon(Icons.delete),
                  const SizedBox(width: 20),
                ],
              ),
            ),
            background: Container(
              color: Theme.of(context).colorScheme.inversePrimary,
              margin: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const SizedBox(width: 20),
                  Icon(Icons.edit),
                  const Spacer(),
                ],
              ),
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                await showModalBottomSheet(
                  isScrollControlled: true,
                  useSafeArea: true,
                  context: context,
                  builder:
                      (ctx) => NewRecord(
                        onAddRecord: (expense) {
                          onRemoveRecord(expense);
                        },
                        initialExpense: records[index],
                      ),
                );
                return false;
              } else {
                onRemoveRecord(records[index]);
                return true;
              }
            },
            child: RecordItem(records[index]),
          ),
    );
  }
}
