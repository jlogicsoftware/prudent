import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent/category/category_provider.dart';
import 'package:http/http.dart' as http;
import 'package:prudent/main.dart';

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

class RecordsNotifier extends AsyncNotifier<List<Record>> {
  @override
  Future<List<Record>> build() async {
    final response = await http.get(url);
    print(response.body);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      print('1 $data');
      final res =
          data.entries.map((e) {
            final recordData = e.value as Map<String, dynamic>;
            return Record(
              title: recordData['title'],
              amount: (recordData['amount'] as num).toDouble(),
              date: DateTime.parse(recordData['date']),
              category: registeredCategories.firstWhere(
                (cat) => cat.id == recordData['category'],
                orElse: () => throw Exception('Category not found'),
              ),
            );
          }).toList();
      print('2 $res');
      return res;
    } else {
      throw Exception('Failed to load records');
    }
  }

  Future<String> addRecord(Record record) async {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(<String, dynamic>{
        'title': record.title,
        'amount': record.amount,
        'date': record.date.toIso8601String(),
        'category': record.category.id,
      }),
    );

    if (response.statusCode == 200) {
      final newRecord = jsonDecode(response.body);
      state = AsyncValue.data([...state.value!, newRecord]);
      return response.body;
    } else {
      return response.body;
    }
  }

  void removeRecord(Record record) {
    state = AsyncValue.data(state.value!.where((r) => r != record).toList());
  }

  void editRecord(int index, Record record) {
    final updatedRecords = List<Record>.from(state.value!);
    updatedRecords[index] = record;
    state = AsyncValue.data(updatedRecords);
  }

  void insertRecord(int index, Record record) {
    final updatedRecords = List<Record>.from(state.value!);
    updatedRecords.insert(index, record);
    state = AsyncValue.data(updatedRecords);
  }
}

final recordsProvider = AsyncNotifierProvider<RecordsNotifier, List<Record>>(
  () => RecordsNotifier(),
);
