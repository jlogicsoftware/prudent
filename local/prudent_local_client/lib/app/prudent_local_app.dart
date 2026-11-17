import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:prudent_ui/l10n/pl_navigation_delegate.dart';
import 'package:prudent_ui/l10n/pl_widgets_delegate.dart';
import 'package:prudent_ui/providers.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:zen_ui_store/zen_ui_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/local_localizations.dart';
import '../l10n/pl_local_delegates.dart';
import 'local_providers.dart';
import 'local_root.dart';

/// Prudent Local: the shared screens behind the PIN lock, in English, Ukrainian or Polish.
///
/// **Screen capture is refused** (`ZenLockGate(secureScreen: true)`, jZenDev/jZen#240, ADR-100
/// T15): a ledger's balances do not belong in Android's recents thumbnail, a screen recording or a
/// cast. The cost — a person cannot screenshot their own balance to share it on purpose — is the
/// right one for this app. On iOS and the desktops the platform offers no such flag; the lock's
/// cover on `inactive` is the protection there.
class PrudentLocalApp extends ConsumerWidget {
  const PrudentLocalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(pinLockProvider);
    return MaterialApp(
      onGenerateTitle: (context) => LocalLocalizations.of(context).appTitle,
      navigatorKey: ref.watch(rootNavigatorKeyProvider),
      locale: ref.watch(localeProvider),
      // Prudent's own Polish comes FIRST for every framework package that ships only en and uk:
      // Localizations takes the first delegate per type that supports the locale.
      localizationsDelegates: [
        ...PrudentLocalizations.localizationsDelegates,
        ...LocalLocalizations.localizationsDelegates,
        prudentPlNavigationDelegate,
        navigationLocaleDelegate,
        prudentPlWidgetsDelegate,
        zenWidgetsLocaleDelegate,
        const PlStoreDelegate(),
        storeLocaleDelegate,
        const PlLockDelegate(),
        lockLocaleDelegate,
        // Flutter 3.50: material_ui's MaterialApp reads its own Material localizations (ADR-099).
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: [
        for (final tag in prudentSupportedLocales) Locale(tag),
      ],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      // Above the navigator, so a pushed page is covered too (ZenLockGate's contract).
      builder: (context, child) =>
          ZenLockGate(lock: lock, secureScreen: true, child: child!),
      home: const LocalRoot(),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: brightness,
    ),
    useMaterial3: true,
    pageTransitionsTheme: ZenPageTransitions.theme,
  );
}
