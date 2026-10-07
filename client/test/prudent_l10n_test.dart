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
import 'package:prudent/app.dart';
import 'package:prudent/l10n/pl_navigation_delegate.dart';
import 'package:prudent/l10n/pl_widgets_delegate.dart';
import 'package:prudent/l10n/pl_widgets_localizations.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// A repository that answers nothing — the widgets under test here never complete a real auth
/// flow, they only render.
class _IdleIdentityRepository implements IdentityRepository {
  const _IdleIdentityRepository();

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async =>
      const ZenResult.ok(null);

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
  Future<ZenResult<void>> setPassword({
    required String password,
    String? currentPassword,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<IdentityContract>> refreshSession() async =>
      const ZenResult.err(ZenUnknownError('refreshSession not stubbed'));

  @override
  Future<ZenResult<void>> logout() async => const ZenResult.ok(null);
}

/// The widgets counterpart of [_PlIdentityDelegateComposedLast].
class _PlWidgetsDelegateComposedLast
    extends LocalizationsDelegate<ZenWidgetsLocalizations> {
  const _PlWidgetsDelegateComposedLast();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'pl';

  @override
  Future<ZenWidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture<ZenWidgetsLocalizations>(PlWidgetsLocalizations());

  @override
  bool shouldReload(_PlWidgetsDelegateComposedLast old) => false;
}

/// A delegate that violates the ordering rule ADR-044 pins against — composed AFTER the
/// framework's degrading delegate — to prove the "which one wins" test actually discriminates.
class _PlIdentityDelegateComposedLast
    extends LocalizationsDelegate<IdentityLocalizations> {
  const _PlIdentityDelegateComposedLast();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'pl';

  @override
  Future<IdentityLocalizations> load(Locale locale) =>
      SynchronousFuture<IdentityLocalizations>(PlIdentityLocalizations());

  @override
  bool shouldReload(_PlIdentityDelegateComposedLast old) => false;
}

Widget _app({
  required Widget home,
  required String locale,
  List<LocalizationsDelegate> extra = const [],
}) {
  return ProviderScope(
    overrides: [
      identityRepositoryProvider.overrideWithValue(
        const _IdleIdentityRepository(),
      ),
    ],
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
          builder:
              (context) => Scaffold(
                body: Text(PrudentLocalizations.of(context).settingsTitle),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ustawienia'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets(
    'a framework screen renders Polish under Prudent\'s delegate, and renders at all',
    (tester) async {
      await tester.pumpWidget(
        _app(
          locale: 'pl',
          extra: const [prudentPlIdentityDelegate],
          home: const LoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Renders AT ALL — no exception reached the test harness — and in Prudent's own Polish,
      // not the framework's English fallback.
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(ZenButton, 'Zaloguj się'), findsOneWidget);
      expect(find.text('Log In'), findsNothing);
    },
  );

  testWidgets(
    'the delegate ordering is pinned: composed after the framework degrades to English',
    (tester) async {
      // The negative case: the SAME Polish delegate, composed AFTER identityLocaleDelegate instead
      // of before it. If ordering did not matter, this would render identically to the test above —
      // it must not.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityRepositoryProvider.overrideWithValue(
              const _IdleIdentityRepository(),
            ),
          ],
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

      expect(find.widgetWithText(ZenButton, 'Log In'), findsOneWidget);
      expect(find.widgetWithText(ZenButton, 'Zaloguj się'), findsNothing);
    },
  );

  test('the delegate load is synchronous, not async', () {
    // An `async` load leaves IdentityLocalizations unresolved for a frame, during which the
    // framework's delegate (composed second) answers in its place — a failure mode invisible to
    // a widget test that always pumpAndSettle()s past it. Asserted directly here.
    final future = const PlIdentityDelegate().load(const Locale('pl'));
    expect(future, isA<SynchronousFuture<IdentityLocalizations>>());
  });

  testWidgets(
    'the framework widgets\' own strings render Polish under Prudent\'s delegate',
    (tester) async {
      // An amount field reads its error from ZenWidgetsLocalizations; without a delegate it throws,
      // and with only the framework's it degrades to English under `pl`.
      await tester.pumpWidget(
        _app(
          locale: 'pl',
          extra: const [prudentPlWidgetsDelegate, zenWidgetsLocaleDelegate],
          home: const Scaffold(
            body: ZenAmountField(label: 'Kwota', errorText: null),
          ),
        ),
      );
      await tester.enterText(find.byType(ZenTextField), '1.2.3');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(ZenAmountField));
      expect(
        ZenWidgetsLocalizations.of(context).invalidAmount,
        'Wpisz poprawną kwotę',
      );
      expect(ZenWidgetsLocalizations.of(context).clearDate, 'Wyczyść datę');
    },
  );

  test(
    'the widgets delegate load is synchronous, for the reason the identity one is',
    () {
      final future = const PlWidgetsDelegate().load(const Locale('pl'));
      expect(future, isA<SynchronousFuture<ZenWidgetsLocalizations>>());
    },
  );

  testWidgets(
    'the widgets delegate ordering is pinned: composed after the framework degrades to English',
    (tester) async {
      // The negative case, as for identity: the same Polish strings, composed AFTER
      // zenWidgetsLocaleDelegate, are never reached — the framework's English wins.
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pl'),
          localizationsDelegates: const [
            zenWidgetsLocaleDelegate,
            _PlWidgetsDelegateComposedLast(),
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('uk'), Locale('pl')],
          home: const Scaffold(
            body: ZenAmountField(label: 'Kwota', errorText: null),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(ZenAmountField));
      expect(
        ZenWidgetsLocalizations.of(context).clearDate,
        isNot('Wyczyść datę'),
      );
    },
  );

  testWidgets(
    'PrudentApp registers each Polish delegate before the framework one it shadows',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityRepositoryProvider.overrideWithValue(
              const _IdleIdentityRepository(),
            ),
          ],
          child: const PrudentApp(),
        ),
      );
      await tester.pump();

      final delegates =
          tester
              .widget<MaterialApp>(find.byType(MaterialApp))
              .localizationsDelegates!
              .toList();
      void expectBefore(
        LocalizationsDelegate polish,
        LocalizationsDelegate framework,
      ) {
        final first = delegates.indexOf(polish);
        final second = delegates.indexOf(framework);
        expect(first, isNonNegative, reason: '$polish is not registered');
        expect(second, isNonNegative, reason: '$framework is not registered');
        expect(first, lessThan(second));
      }

      expectBefore(prudentPlIdentityDelegate, identityLocaleDelegate);
      expectBefore(prudentPlNavigationDelegate, navigationLocaleDelegate);
      expectBefore(prudentPlWidgetsDelegate, zenWidgetsLocaleDelegate);
    },
  );
}
