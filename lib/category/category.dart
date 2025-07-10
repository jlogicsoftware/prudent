import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class CategoryIcon {
  final String value;
  final IconData icon;

  CategoryIcon({required this.value, required this.icon});
}

final selectableCategoryIcons = [
  CategoryIcon(icon: Icons.work_outline, value: 'Work'),
  CategoryIcon(icon: Icons.add_a_photo_outlined, value: 'Leisure'),
  CategoryIcon(icon: Icons.local_grocery_store_outlined, value: 'Food'),
  CategoryIcon(icon: Icons.fastfood_outlined, value: 'Restaurant'),
  CategoryIcon(icon: Icons.medical_services_outlined, value: 'Medicine'),
];

const selectableCategoryColors = [
  Colors.blue,
  Colors.red,
  Colors.green,
  Colors.yellow,
  Colors.deepPurple,
  Colors.orange,
  Colors.cyanAccent,
  Colors.brown,
  Colors.tealAccent,
  Colors.white,
];

class Category {
  final String id;
  final String title;
  final IconData icon;
  final String description;
  final Color color;

  Category({
    required this.title,
    required this.icon,
    this.description = '',
    this.color = Colors.black,
  }) : id = Uuid().v4();

  @override
  String toString() {
    return 'Category{id: $id, title: $title, icon: $icon, description: $description, color: $color}';
  }
}
