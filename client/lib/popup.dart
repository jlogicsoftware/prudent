import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// An icon button that opens [popupBody] as an overlay.
///
/// Prudent's own widget: the button and what it opens are product UI. How the overlay is
/// presented — a sheet on native mobile, a dialog on desktop and web, Cupertino on Apple
/// platforms — is the framework's (`showAdaptivePresentation`), so no platform check lives here.
class Popup extends StatelessWidget {
  const Popup({super.key, required this.icon, required this.label, required this.popupBody});

  /// The glyph on the button.
  final IconData icon;

  /// The button's accessible name; an icon alone says nothing to a screen reader.
  final String label;

  final Widget popupBody;

  @override
  Widget build(BuildContext context) {
    return ZenIconButton(
      icon: icon,
      label: label,
      onPressed: () => showAdaptivePresentation<void>(context, builder: (_) => popupBody),
    );
  }
}
