import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../generated/prudent/v1/categories.pb.dart';
import '../generated/prudent/v1/records.pb.dart';
import '../money.dart';
import '../providers.dart';
import 'new_record.dart';
import 'record_item.dart';

class RecordsList extends ConsumerWidget {
  const RecordsList({super.key, required this.records, required this.onRemoveRecord});

  final List<Record> records;
  final void Function(Record record) onRemoveRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    Category? categoryFor(String id) {
      for (final c in categories) {
        if (c.id == id) return c;
      }
      return null;
    }

    return ListView.builder(
      itemCount: records.length,
      itemBuilder:
          (ctx, index) => Dismissible(
            key: ValueKey(records[index].id),
            secondaryBackground: Container(
              color: Theme.of(context).colorScheme.error,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [Spacer(), Icon(Icons.delete), SizedBox(width: 20)],
              ),
            ),
            background: Container(
              color: Theme.of(context).colorScheme.inversePrimary,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [SizedBox(width: 20), Icon(Icons.edit), Spacer()],
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
                        initialRecord: records[index],
                        onSave:
                            ({
                              required title,
                              required amountInput,
                              required date,
                              required categoryId,
                              required accountId,
                              required currency,
                            }) => ref
                                .read(recordsProvider.notifier)
                                .editRecord(
                                  records[index].id,
                                  UpdateRecordRequest(
                                    title: title,
                                    amountMinor: parseMinorUnits(amountInput),
                                    date: date,
                                    categoryId: categoryId,
                                    accountId: accountId,
                                    currency: currency,
                                  ),
                                ),
                      ),
                );
                return false;
              }
              onRemoveRecord(records[index]);
              return true;
            },
            child: RecordItem(records[index], category: categoryFor(records[index].categoryId)),
          ),
    );
  }
}
