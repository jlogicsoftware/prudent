import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent/category/category_provider.dart';
import 'package:http/http.dart' as http;
import 'package:prudent/main.dart';
import 'package:prudent/widgets/popup/popup.dart';
import 'record.dart';

final List<Record> registeredRecords = [
  Record(
    title: 'Flutter Course',
    amount: 19.99,
    date: DateTime.now(),
    category: registeredCategories.first,
  ),
  Record(
    title: 'Cinema',
    amount: 15.69,
    date: DateTime.now(),
    category: registeredCategories.last,
  ),
];

final url = Uri.parse('$serverUrl/records.json');

class RecordsNotifier extends Notifier<List<Record>> {
  @override
  List<Record> build() {
    return registeredRecords;
  }

  Future<String> addRecord(Record record) async {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(<String, dynamic>{
        'title': record.title,
        'amount': record.amount,
        'date': record.date.toIso8601String(),
        'category': record.category.toJson(),
      }),
    );

    if (response.statusCode == 200) {
      final newRecord = jsonDecode(response.body);
      state = [...state, newRecord];
      return response.body;
    } else {
      return response.body;
    }
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

final recordsProvider = NotifierProvider<RecordsNotifier, List<Record>>(
  () => RecordsNotifier(),
);
