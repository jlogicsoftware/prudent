import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// One choice in the category form's icon grid, drawn on the colour chosen for the category.
///
/// Prudent's own domain control, like [CategoryColorSwatch]: reachable by Tab, activated by Enter
/// or Space, and ringed by a [FocusRing] while it holds keyboard focus.
class CategoryIconChoice extends StatelessWidget {
  const CategoryIconChoice({
    super.key,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  static const double _diameter = 50;

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
              border: Border.all(
                color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(icon, size: 30, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white),
          ),
        ),
      ),
    );
  }
}
