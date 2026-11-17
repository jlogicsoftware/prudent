import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/local_localizations.dart';

/// Asks for the name of an account or category being brought back by an integrity action: the
/// store keeps nothing of a deleted record but its id, so the name is the person's. Pops the text,
/// or nothing when cancelled.
class RecreateNameForm extends StatefulWidget {
  const RecreateNameForm({super.key});

  @override
  State<RecreateNameForm> createState() => _RecreateNameFormState();
}

class _RecreateNameFormState extends State<RecreateNameForm> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LocalLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.recreateNameTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          ZenTextField(label: t.recreateNameField, controller: _name),
          const SizedBox(height: 16),
          ZenButton(
            label: t.recreateNameSave,
            onPressed: () {
              final text = _name.text.trim();
              if (text.isNotEmpty) Navigator.of(context).pop(text);
            },
          ),
          const SizedBox(height: 8),
          ZenButton(
            label: t.cancel,
            variant: ZenButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
