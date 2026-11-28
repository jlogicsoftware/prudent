import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/local_localizations.dart';

/// Says that an erasure got through but a temporary copy a file dialog made may still be on this
/// device (ADR-138), until the person acknowledges it.
///
/// Over [navigator], the app's own: erasing everywhere and starting again replace the screen that
/// asked, so the sentence cannot be that screen's to show.
Future<void> showCopyMayRemainNotice(
  NavigatorState navigator,
  LocalLocalizations t,
) async {
  if (!navigator.mounted) return;
  await showDialog<void>(
    context: navigator.context,
    builder: (dialog) => AlertDialog(
      content: Text(t.erasedCopyMayRemain),
      actions: [
        ZenButton(
          label: t.confirm,
          variant: ZenButtonVariant.text,
          onPressed: () => Navigator.pop(dialog),
        ),
      ],
    ),
  );
}
