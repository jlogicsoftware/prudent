import 'package:prudent/category/category.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

final formatter = DateFormat.yMd('pl_PL');

const uuid = Uuid();

class Record {
  Record({
    required this.title,
    required this.amount,
    required this.date,
    required this.category,
  }) : id = uuid.v4();

  final String id;
  final String title;
  final double amount;
  final DateTime date;
  final Category category;

  String get formattedDate {
    return formatter.format(date);
  }
}

class RecordByCategory {
  const RecordByCategory({required this.category, required this.records});

  RecordByCategory.forCategory(List<Record> allRecords, this.category)
    : records = allRecords.where((r) => r.category == category).toList();

  final Category category;
  final List<Record> records;

  double get totalRecords {
    double sum = 0;

    for (final record in records) {
      sum += record.amount;
    }

    return sum;
  }
}
