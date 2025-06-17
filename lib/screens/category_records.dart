import 'package:flutter/material.dart';

class CategoryRecords extends StatelessWidget {
  final String? categoryTitle;

  const CategoryRecords({super.key, this.categoryTitle});
  static const routeName = '/category-records';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(categoryTitle ?? 'Category Records')),
      body: Center(
        child: Text(
          'Records for category: ${categoryTitle ?? 'Unknown'}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}
