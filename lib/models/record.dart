import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

final formatter = DateFormat.yMd('pl_PL');

const uuid = Uuid();

enum Category { food, travel, leisure, work }

const categoryIcons = {
  Category.food: Icons.lunch_dining,
  Category.travel: Icons.flight_takeoff,
  Category.leisure: Icons.movie,
  Category.work: Icons.work,
};

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

class RecordBucket {
  const RecordBucket({required this.category, required this.records});

  RecordBucket.forCategory(List<Record> allRecords, this.category)
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
