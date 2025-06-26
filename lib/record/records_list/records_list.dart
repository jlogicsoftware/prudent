import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../new_record.dart';
import '../records_provider.dart';
import '../record.dart';
import 'record_item.dart';

class RecordsList extends ConsumerWidget {
  const RecordsList({super.key, required this.onRemoveRecord});

  final void Function(Record record) onRemoveRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recordsProvider);
    if (records.isEmpty) {
      return const Center(
        child: Text(
          'No records found. Add some expenses!',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

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
                        onAddRecord: (record) {
                          ref
                              .read(recordsProvider.notifier)
                              .editRecord(index, record);
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
