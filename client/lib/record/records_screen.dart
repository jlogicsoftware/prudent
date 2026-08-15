import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent/utils.dart';

import 'new_record.dart';
import 'record.dart';
import 'records_list/records_list.dart';
import 'records_provider.dart';

class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key});

  static const routeName = '/records';

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsState();
}

class _RecordsState extends ConsumerState<RecordsScreen> {
  void _openAddRecordOverlay() {
    if (isMobile(context)) {
      showModalBottomSheet(
        isScrollControlled: true,
        useSafeArea: true,
        context: context,
        builder: (ctx) => NewRecord(onAddRecord: _addRecord),
        constraints: const BoxConstraints.expand(),
      );
    } else {
      showDialog(
        context: context,
        builder:
            (ctx) => Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              child: SizedBox(
                width: 400,
                height: 300,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: NewRecord(onAddRecord: _addRecord),
                ),
              ),
            ),
      );
    }
  }

  void _addRecord(Record record) {
    ref.read(recordsProvider.notifier).addRecord(record);
  }

  void _removeRecord(Record record) {
    // `read`, not `watch`: this is a callback, not a build. Watching outside build subscribes a
    // widget that is not rebuilding.
    final current = ref.read(recordsProvider).asData?.value ?? const <Record>[];
    final recordIndex = current.indexWhere((r) => r.id == record.id);
    ref.read(recordsProvider.notifier).removeRecord(record);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: const Text('Record deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            ref
                .read(recordsProvider.notifier)
                .insertRecord(recordIndex, record);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Read inside build, so the screen actually rebuilds when records change. Holding this in a
    // `late final` field captures the provider's value once — during the first frame, while it is
    // still loading — and never updates, which leaves the empty-state branch below permanently
    // selected no matter what the provider holds.
    final records = ref.watch(recordsProvider).asData?.value ?? const <Record>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prudent'),
        actions: [
          IconButton(
            onPressed: _openAddRecordOverlay,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child:
                records.isNotEmpty
                    ? RecordsList(onRemoveRecord: _removeRecord)
                    : const Center(
                      child: Text('No records found. Start adding some!'),
                    ),
          ),
        ],
      ),
    );
  }
}
