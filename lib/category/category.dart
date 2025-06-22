import 'package:flutter/material.dart';

class Category {
  final String id;
  final String title;
  final IconData icon;
  final String description;
  final Color color;

  const Category({
    required this.id,
    required this.title,
    required this.icon,
    this.description = '',
    this.color = Colors.green,
  });

  @override
  String toString() {
    return 'Category{id: $id, title: $title, icon: $icon, description: $description, color: $color}';
  }

  static List<Category> categories = [
    Category(
      id: 'c1',
      title: 'Work',
      icon: Icons.work,
      description: 'Work-related expenses',
      color: Colors.blue,
    ),
    Category(
      id: 'c2',
      title: 'Food',
      icon: Icons.fastfood,
      description: 'Food and dining expenses',
      color: Colors.red,
    ),
    Category(
      id: 'c3',
      title: 'Travel',
      icon: Icons.travel_explore,
      description: 'Travel expenses',
      color: Colors.orange,
    ),
    Category(
      id: 'c4',
      title: 'Leisure',
      icon: Icons.add_a_photo,
      description: 'Leisure activities',
      color: Colors.purple,
    ),
    Category(
      id: 'c5',
      title: 'Health',
      icon: Icons.health_and_safety,
      description: 'Health-related expenses',
      color: Colors.green,
    ),
  ];

  static Category getCategoryById(String id) {
    return categories.firstWhere((category) => category.id == id);
  }

  static void addCategory(Category category) {
    categories.add(category);
  }

  static void removeCategory(String id) {
    categories.removeWhere((category) => category.id == id);
  }

  static void updateCategory(String id, Category newCategory) {
    int index = categories.indexWhere((category) => category.id == id);
    if (index != -1) {
      categories[index] = newCategory;
    }
  }

  static List<Category> getCategories() {
    return categories;
  }
}
