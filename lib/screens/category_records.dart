import 'package:flutter/material.dart';
import 'package:prudent/category/category.dart';

class CategoryRecords extends StatelessWidget {
  final Category category;

  const CategoryRecords({super.key, required this.category});
  static const routeName = '/category-records';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: const Center(child: Text('Category Records Screen')),
    );
  }
}
