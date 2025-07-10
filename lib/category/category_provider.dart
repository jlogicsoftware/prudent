import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'category.dart';

final List<Category> registeredCategories = [
  Category(
    title: 'Work',
    icon: Icons.work_outline,
    description: 'Work-related expenses',
    color: Colors.blue,
  ),
  Category(
    title: 'Leisure',
    icon: Icons.add_a_photo_outlined,
    description: 'Leisure activities',
    color: Colors.purple,
  ),
];

class CategoryNotifier extends StateNotifier<List<Category>> {
  CategoryNotifier() : super(registeredCategories);

  void addCategory(Category category) {
    state = [...state, category];
  }

  void removeCategory(Category category) {
    state = state.where((r) => r != category).toList();
  }

  void editCategory(int index, Category category) {
    final updatedCategory = List<Category>.from(state);
    updatedCategory[index] = category;
    state = updatedCategory;
  }

  void insertCategory(int index, Category category) {
    final updatedCategory = List<Category>.from(state);
    updatedCategory.insert(index, category);
    state = updatedCategory;
  }
}

final categoryProvider = StateNotifierProvider((ref) => CategoryNotifier());
