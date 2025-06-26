import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'record.dart';

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

class RecordsNotifier extends StateNotifier<List<Record>> {
  RecordsNotifier() : super(registeredRecords);

  void addRecord(Record record) {
    state = [...state, record];
  }

  void removeRecord(Record record) {
    state = state.where((r) => r != record).toList();
  }

  void editRecord(int index, Record record) {
    final updatedRecords = List<Record>.from(state);
    updatedRecords[index] = record;
    state = updatedRecords;
  }

  void insertRecord(int index, Record record) {
    final updatedRecords = List<Record>.from(state);
    updatedRecords.insert(index, record);
    state = updatedRecords;
  }
}

final recordsProvider = StateNotifierProvider((ref) => RecordsNotifier());
