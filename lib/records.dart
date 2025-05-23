import 'package:flutter/material.dart';
import 'package:prudent/utils.dart';

import 'new_record.dart';
import 'models/record.dart';
import 'widgets/records_list/records_list.dart';

class Records extends StatefulWidget {
  const Records({super.key});

  @override
  State<Records> createState() {
    return _RecordsState();
  }
}

class _RecordsState extends State<Records> {
  final List<Record> registeredRecords = [
    Record(
      title: 'Flutter Course',
      amount: 19.99,
      date: DateTime.now(),
      category: Category.work,
    ),
    Record(
      title: 'Cinema',
      amount: 15.69,
      date: DateTime.now(),
      category: Category.leisure,
    ),
  ];

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
    setState(() {
      registeredRecords.add(record);
    });
  }

  void _removeExpense(Record record) {
    final recordIndex = registeredRecords.indexWhere((r) => r.id == record.id);
    setState(() {
      registeredRecords.remove(record);
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: const Text('Record deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              registeredRecords.insert(recordIndex, record);
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                registeredRecords.isNotEmpty
                    ? RecordsList(
                      records: registeredRecords,
                      onRemoveRecord: _removeExpense,
                    )
                    : const Center(
                      child: Text('No expenses found. Start adding some!'),
                    ),
          ),
        ],
      ),
    );
  }
}
