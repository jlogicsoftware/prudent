import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// One choice in the category form's colour grid.
///
/// The grid is Prudent's own domain control — `zen_ui_widgets` has no selectable grid — but a
/// screen-specific control still meets the accessibility bar: the [InkWell] makes the swatch
/// reachable by Tab and activated by Enter or Space, and the [FocusRing] inside it shows where a
/// keyboard user is, which Material's own focus overlay does not do at a readable contrast.
class CategoryColorSwatch extends StatelessWidget {
  const CategoryColorSwatch({super.key, required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// The circle's diameter; the cell around it stays the grid's full height, so the touch target
  /// is larger than what is drawn.
  static const double _diameter = 26;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: FocusRing(
          child: Container(
            width: _diameter,
            height: _diameter,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? Colors.black : Colors.transparent, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
