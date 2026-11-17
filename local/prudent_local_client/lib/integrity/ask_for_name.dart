import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'recreate_name_form.dart';

/// Asks for a name through the app's own navigator, for an integrity action that needs one:
/// `ZenIssueAction` runs with no `BuildContext` and takes no input (jZenDev/jZen#256). Null when the
/// person cancelled or no screen is up.
Future<String?> askForName(GlobalKey<NavigatorState> navigator) async {
  final context = navigator.currentContext;
  if (context == null) return null;
  return showAdaptivePresentation<String>(
    context,
    builder: (_) => const RecreateNameForm(),
  );
}
