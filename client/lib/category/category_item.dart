import 'package:flutter/material.dart';

import '../generated/prudent/v1/categories.pb.dart';
import 'category_icons.dart';

/// Converts the wire's `color_argb` / `icon_key` into `dart:ui` types at the widget boundary —
/// the only place either conversion happens (proto/prudent/v1/categories.proto §2.2).
class CategoryItem extends StatelessWidget {
  const CategoryItem({super.key, required this.category, this.iconSize = 40});

  final Category category;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorArgb);
    return CircleAvatar(
      radius: iconSize,
      backgroundColor: color,
      foregroundColor: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
      child: Icon(prudentIconFor(category.iconKey), size: iconSize),
    );
  }
}
