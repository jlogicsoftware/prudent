import 'package:material_ui/material_ui.dart';

/// The heading of one part of a settings page.
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}
