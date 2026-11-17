import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:prudent_ui/l10n/pl_widgets_delegate.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/local_localizations.dart';
import 'start_failed_page.dart';

/// What the person sees when this device's data cannot be opened (ADR-100 T8, T9, T10): the key
/// cannot be read (no secret service on Linux, a locked keyring, a Windows "nothing stored" beside
/// existing files, files restored from a backup without their key) or the files do not decrypt.
///
/// Nothing was changed, and nothing is erased on its own. Where erasing and re-syncing is the way
/// out (Windows, a restored backup) it is offered, behind a question; on Linux, where the fix is to
/// install or unlock the keyring, nothing that erases is offered (T8).
class StartFailedApp extends StatelessWidget {
  const StartFailedApp({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onErase,
    this.isLinux,
  });

  final ZenError error;

  /// Opens the store again, after the person fixed what was wrong.
  final VoidCallback onRetry;

  /// Erases this device's copy (never automatic), then opens again.
  final Future<void> Function() onErase;

  /// Whether this is Linux, where no erase is offered. Defaults to the running platform.
  final bool? isLinux;

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => LocalLocalizations.of(context).appTitle,
    localizationsDelegates: [
      ...LocalLocalizations.localizationsDelegates,
      ...PrudentLocalizations.localizationsDelegates,
      prudentPlWidgetsDelegate,
      zenWidgetsLocaleDelegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: LocalLocalizations.supportedLocales,
    home: StartFailedPage(
      error: error,
      onRetry: onRetry,
      onErase: onErase,
      isLinux: isLinux ?? Platform.isLinux,
    ),
  );
}
