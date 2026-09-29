import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// An icon button that opens [popupBody] as an overlay.
///
/// Prudent's own widget: the button and what it opens are product UI. How the overlay is
/// presented — a sheet on native mobile, a dialog on desktop and web, Cupertino on Apple
/// platforms — is the framework's (`showAdaptivePresentation`), so no platform check lives here.
class Popup extends StatelessWidget {
  const Popup({super.key, required this.popupLeading, required this.popupBody});

  final Widget popupLeading;
  final Widget popupBody;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: popupLeading,
      onPressed: () => showAdaptivePresentation<void>(context, builder: (_) => popupBody),
    );
  }
}
