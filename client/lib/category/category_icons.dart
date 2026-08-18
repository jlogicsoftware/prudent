import 'package:flutter/material.dart';

/// The icons Prudent ships, keyed by the stable `icon_key` string that crosses the wire
/// (proto/prudent/v1/categories.proto) — never a code point, which would defeat
/// `--tree-shake-icons` by making `IconData` non-const.
///
/// This map is the ONLY place `icon_key` becomes an `IconData`; nowhere else in the client holds
/// this mapping.
const Map<String, IconData> prudentCategoryIcons = {
  'work': Icons.work_outline,
  'leisure': Icons.add_a_photo_outlined,
  'food': Icons.local_grocery_store_outlined,
  'restaurant': Icons.fastfood_outlined,
  'medicine': Icons.medical_services_outlined,
};

/// Rendered for a key this client does not recognize — a category created by a newer client must
/// not break an older one (proto/prudent/v1/categories.proto).
const IconData prudentUnknownCategoryIcon = Icons.category_outlined;

/// Resolves [iconKey] to its icon, falling back to [prudentUnknownCategoryIcon] rather than
/// throwing.
IconData prudentIconFor(String iconKey) =>
    prudentCategoryIcons[iconKey] ?? prudentUnknownCategoryIcon;

/// The colour swatches a category can be created with. A colour is a value (`color_argb` on the
/// wire); this list is only the picker's palette, not a closed set — `Color(value)` at the widget
/// boundary is what actually converts, and it accepts any ARGB value, including one outside this
/// list (proto/prudent/v1/categories.proto §2.2).
const List<Color> prudentCategoryColors = [
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
