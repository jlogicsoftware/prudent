import 'package:material_ui/material_ui.dart';

/// A paragraph of explanation on a settings page, aligned with the controls around it.
class SettingsParagraph extends StatelessWidget {
  const SettingsParagraph(this.text, {super.key, this.warning = false});

  final String text;

  /// Drawn in the error colour: a warning the person reads before the step it is about.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        text,
        style: warning
            ? theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              )
            : theme.textTheme.bodyMedium,
      ),
    );
  }
}
