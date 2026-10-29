// The unauthenticated flow (jlogicsoftware/prudent#161): an address pasted with a stray space is
// trimmed before it is validated on sign-in, registration and password restore, so the form never
// refuses what its submit would have sent. The validator is jZen's (jZenDev/jZen#143); this proves
// Prudent consumes it, through the delegates the app itself registers.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/auth/auth_flow.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/l10n/pl_identity_delegate.dart';
import 'package:prudent/l10n/pl_navigation_delegate.dart';
import 'package:prudent/l10n/pl_widgets_delegate.dart';
import 'package:zen_core/zen_core.dart' hide ZenError;
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// Records the address each call received and refuses every one, so the screen stays put and the
/// next call can be made from the same widget tree.
class _Identity implements IdentityRepository {
  final List<String> logins = [];
  final List<String> registrations = [];
  final List<String> restores = [];

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async =>
      const ZenResult.ok(null);

  @override
  Future<ZenResult<void>> logout() async => const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async {
    logins.add(email);
    return const ZenResult.err(ZenUnknownError('refused'));
  }

  @override
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  }) async {
    registrations.add(email);
    return const ZenResult.err(ZenUnknownError('refused'));
  }

  @override
  Future<ZenResult<void>> restorePassword({required String email}) async {
    restores.add(email);
    return const ZenResult.err(ZenUnknownError('refused'));
  }

  @override
  Future<ZenResult<IdentityContract>> confirmEmailLink({
    required String tokenHash,
    required String type,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

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
      const ZenResult.err(ZenUnknownError('not used'));
}

void main() {
  late _Identity identity;

  Future<void> pump(WidgetTester tester) async {
    identity = _Identity();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(identity)],
        child: MaterialApp(
          // The delegates PrudentApp registers, in its order (Prudent's Polish ahead of the
          // framework's fallback).
          localizationsDelegates: const [
            ...PrudentLocalizations.localizationsDelegates,
            prudentPlIdentityDelegate,
            identityLocaleDelegate,
            prudentPlNavigationDelegate,
            navigationLocaleDelegate,
            prudentPlWidgetsDelegate,
            zenWidgetsLocaleDelegate,
          ],
          supportedLocales: PrudentLocalizations.supportedLocales,
          theme: ThemeData(extensions: [IdentityThemeExtension.fallback()]),
          home: const AuthFlow(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder button(String label) => find.byWidgetPredicate(
    (widget) => widget is ZenButton && widget.label == label,
  );

  Future<void> enter(WidgetTester tester, List<String> values) async {
    final fields = find.byType(EditableText);
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(fields.at(i), values[i]);
    }
  }

  testWidgets(
    'sign-in accepts an address with surrounding spaces and sends it trimmed',
    (tester) async {
      await pump(tester);

      await enter(tester, ['  alice@example.com ', 'secret-pass']);
      await tester.tap(button('Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid email'), findsNothing);
      expect(identity.logins, ['alice@example.com']);
    },
  );

  testWidgets(
    'registration accepts an address with surrounding spaces and sends it trimmed',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      await enter(tester, [
        ' alice@example.com  ',
        'secret-pass',
        'secret-pass',
      ]);
      await tester.tap(button('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid email'), findsNothing);
      expect(identity.registrations, ['alice@example.com']);
    },
  );

  testWidgets(
    'password restore accepts an address with surrounding spaces and sends it trimmed',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Reset Password'));
      await tester.pumpAndSettle();

      await enter(tester, ['\talice@example.com ']);
      await tester.tap(button('Send Link'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid email'), findsNothing);
      expect(identity.restores, ['alice@example.com']);
    },
  );

  testWidgets('whitespace inside an address is still refused', (tester) async {
    await pump(tester);

    await enter(tester, ['alice @example.com', 'secret-pass']);
    await tester.tap(button('Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email'), findsOneWidget);
    expect(identity.logins, isEmpty);
  });
}
