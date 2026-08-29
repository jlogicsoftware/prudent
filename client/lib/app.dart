import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

import 'l10n/generated/prudent_localizations.dart';
import 'l10n/pl_identity_delegate.dart';
import 'l10n/pl_navigation_delegate.dart';
import 'providers.dart';
import 'auth/auth_flow.dart';
import 'home_shell.dart';

/// The root of Prudent. Routes on the identity session: anonymous -> the auth flow,
/// authenticated -> the home shell. The whole app sits behind login (docs/prudent-migration-plan.md
/// "is the whole app behind login" — yes, decided for this phase): there is no signed-out screen
/// besides the auth flow itself.
class PrudentApp extends ConsumerWidget {
  const PrudentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Prudent',
      locale: ref.watch(localeProvider),
      // Per-package generation (jZen ADR-009): Prudent registers its own delegate plus one per
      // localized framework package it renders. `prudentPlIdentityDelegate` /
      // `prudentPlNavigationDelegate` come FIRST — Localizations takes the first delegate per
      // type that supports the locale — so Prudent's own Polish wins over the framework's
      // degrading English fallback (`identityLocaleDelegate` / `navigationLocaleDelegate`,
      // composed after them, still needed for {en, uk} and as the fallback for any locale
      // Prudent's own delegate declines).
      localizationsDelegates: const [
        ...PrudentLocalizations.localizationsDelegates,
        prudentPlIdentityDelegate,
        identityLocaleDelegate,
        prudentPlNavigationDelegate,
        navigationLocaleDelegate,
      ],
      supportedLocales: [for (final tag in prudentSupportedLocales) Locale(tag)],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const ZenAuthLinkListener(child: _Root()),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.green, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      extensions: [
        IdentityThemeExtension(
          successColor: Colors.green,
          errorColor: scheme.error,
          warningColor: Colors.orange,
          brandColor: scheme.primary,
          surfaceColor: scheme.surface,
          titleStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          subtitleStyle: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(identitySessionStoreProvider);

    return session.when(
      loading: () => const _Splash(),
      error: (_, _) => const AuthFlow(),
      data: (identity) {
        if (identity == null) return const AuthFlow();
        if (ref.watch(passwordResetRequiredProvider)) return const SetPasswordScreen();
        return const HomeShell();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
