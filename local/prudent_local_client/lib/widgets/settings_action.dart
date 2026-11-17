import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// One button on a settings page, aligned with the paragraphs around it.
class SettingsAction extends StatelessWidget {
  const SettingsAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ZenButtonVariant.secondary,
  });

  final String label;
  final VoidCallback? onPressed;
  final ZenButtonVariant variant;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: ZenButton(label: label, variant: variant, onPressed: onPressed),
  );
}
