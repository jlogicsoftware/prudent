import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// Asks before an irreversible step. Answers true only on [action]; its buttons are `ZenButton`s,
/// the one form of `AlertDialog` `verify:controls` allows (a confirmation, no input).
Future<bool> confirmStep(
  BuildContext context, {
  required String question,
  required String action,
  required String cancel,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      content: Text(question),
      actions: [
        ZenButton(
          label: cancel,
          variant: ZenButtonVariant.text,
          onPressed: () => Navigator.pop(dialog, false),
        ),
        ZenButton(
          label: action,
          variant: ZenButtonVariant.text,
          onPressed: () => Navigator.pop(dialog, true),
        ),
      ],
    ),
  );
  return answer == true;
}
