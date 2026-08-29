// Phase 3's localization test list (docs/prudent-migration-plan.md):
//   - a Prudent screen renders Polish;
//   - a framework screen renders Polish under Prudent's delegate, AND renders at all;
//   - the delegate ordering is pinned (composed first, SynchronousFuture) — the failure mode
//     jZen ADR-044 found by testing rather than by reading.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/l10n/pl_identity_delegate.dart';
import 'package:prudent/l10n/pl_identity_localizations.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

/// A repository that answers nothing — the widgets under test here never complete a real auth
/// flow, they only render.
class _IdleIdentityRepository implements IdentityRepository {
  const _IdleIdentityRepository();

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<void>> restorePassword({required String email}) async =>
      const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<IdentityContract>> exchangeLinkSession({
    required String accessToken,
    String? refreshToken,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<void>> setPassword({required String password}) async =>
      const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<IdentityContract>> refreshSession() async =>
      const ZenResult.err(ZenUnknownError('refreshSession not stubbed'));

  @override
  Future<ZenResult<void>> logout() async => const ZenResult.ok(null);
}

/// A delegate that violates the ordering rule ADR-044 pins against — composed AFTER the
/// framework's degrading delegate — to prove the "which one wins" test actually discriminates.
class _PlIdentityDelegateComposedLast extends LocalizationsDelegate<IdentityLocalizations> {
  const _PlIdentityDelegateComposedLast();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'pl';

  @override
  Future<IdentityLocalizations> load(Locale locale) =>
      SynchronousFuture<IdentityLocalizations>(PlIdentityLocalizations());

  @override
  bool shouldReload(_PlIdentityDelegateComposedLast old) => false;
}

Widget _app({required Widget home, required String locale, List<LocalizationsDelegate> extra = const []}) {
  return ProviderScope(
    overrides: [identityRepositoryProvider.overrideWithValue(const _IdleIdentityRepository())],
    child: MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: [
        ...extra,
        ...PrudentLocalizations.localizationsDelegates,
        identityLocaleDelegate,
      ],
      supportedLocales: const [Locale('en'), Locale('uk'), Locale('pl')],
      home: home,
    ),
  );
}

void main() {
  testWidgets('a Prudent screen renders Polish', (tester) async {
    await tester.pumpWidget(
      _app(
        locale: 'pl',
        home: Builder(
          builder: (context) => Scaffold(body: Text(PrudentLocalizations.of(context).settingsTitle)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ustawienia'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('a framework screen renders Polish under Prudent\'s delegate, and renders at all', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(locale: 'pl', extra: const [prudentPlIdentityDelegate], home: const LoginScreen()),
    );
    await tester.pumpAndSettle();

    // Renders AT ALL — no exception reached the test harness — and in Prudent's own Polish,
    // not the framework's English fallback.
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(FilledButton, 'Zaloguj się'), findsOneWidget);
    expect(find.text('Log In'), findsNothing);
  });

  testWidgets('the delegate ordering is pinned: composed after the framework degrades to English', (
    tester,
  ) async {
    // The negative case: the SAME Polish delegate, composed AFTER identityLocaleDelegate instead
    // of before it. If ordering did not matter, this would render identically to the test above —
    // it must not.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(const _IdleIdentityRepository())],
        child: MaterialApp(
          locale: const Locale('pl'),
          localizationsDelegates: const [
            identityLocaleDelegate,
            _PlIdentityDelegateComposedLast(),
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('uk'), Locale('pl')],
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Zaloguj się'), findsNothing);
  });

  test('the delegate load is synchronous, not async', () {
    // An `async` load leaves IdentityLocalizations unresolved for a frame, during which the
    // framework's delegate (composed second) answers in its place — a failure mode invisible to
    // a widget test that always pumpAndSettle()s past it. Asserted directly here.
    final future = const PlIdentityDelegate().load(const Locale('pl'));
    expect(future, isA<SynchronousFuture<IdentityLocalizations>>());
  });
}
