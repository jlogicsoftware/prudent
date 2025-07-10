import 'package:flutter/material.dart';

import 'category.dart';

class CategoryItem extends StatelessWidget {
  const CategoryItem({super.key, required this.category, this.iconSize = 40});

  final Category category;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: iconSize,
      backgroundColor: category.color,
      foregroundColor:
          category.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
      child: Icon(category.icon, size: iconSize),
    );
  }
}
