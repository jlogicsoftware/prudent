// The privacy screen (M0, jlogicsoftware/prudent#48): what Prudent keeps, a copy of it, and the
// two-step deletion. Driven through the real PrudentRepository over a mock HTTP server, so the
// requests it sends are the ones asserted.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/privacy/privacy_screen.dart';
import 'package:prudent/providers.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:zen_core/zen_core.dart' hide ZenError;
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_transport/zen_transport.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'zen_fields.dart';
import 'zen_platform_skip.dart';

const _headers = {'X-Zen-Transport': 'json'};

class _Identity implements IdentityRepository {
  int logouts = 0;

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => const ZenResult.ok(null);

  @override
  Future<ZenResult<void>> logout() async {
    logouts++;
    return const ZenResult.ok(null);
  }

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
      const ZenResult.err(ZenUnknownError('not used'));
}

void main() {
  late _Identity identity;
  late List<String> erased;
  late String? copied;

  Future<void> pump(WidgetTester tester) async {
    identity = _Identity();
    erased = [];
    copied = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final client = ZenClient(
      baseUrl: 'https://example.test',
      format: ZenTransportFormat.json,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/v1/privacy/export') {
          return http.Response(
            jsonEncode({
              'formatVersion': 1,
              'profile': {'email': 'alice@example.com'},
            }),
            200,
            headers: _headers,
          );
        }
        // The erase call: refused, because the address typed is not the account's.
        erased.add((jsonDecode(request.body) as Map)['confirmEmail'] as String);
        return http.Response(
          jsonEncode({
            'code': 'invalid',
            'message': 'Enter the email address of this account to confirm. Nothing was deleted.',
          }),
          400,
          headers: _headers,
        );
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client)),
          identityRepositoryProvider.overrideWithValue(identity),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            ...PrudentLocalizations.localizationsDelegates,
            zenWidgetsLocaleDelegate,
          ],
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: PrivacyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder button(String label) =>
      find.byWidgetPredicate((widget) => widget is ZenButton && widget.label == label);

  testWidgets('says what is kept, what a person can do, and what deletion leaves', (tester) async {
    await pump(tester);

    expect(find.textContaining('Prudent keeps the accounts'), findsOneWidget);
    expect(find.textContaining('copy everything'), findsOneWidget);
    // What deletion reaches, and what it leaves, is stated up front, not discovered afterwards.
    expect(find.textContaining('also deletes your sign-in'), findsOneWidget);
    expect(find.textContaining('A backup taken before keeps a copy'), findsOneWidget);
    expect(button('Copy my data'), findsOneWidget);
    expect(button('Delete my data'), findsOneWidget);
  });

  testWidgets('copying puts the readable export on the clipboard', (tester) async {
    await pump(tester);

    await tester.tap(button('Copy my data'));
    await tester.pumpAndSettle();

    expect(copied, isNotNull);
    expect(copied!.split('\n').length, greaterThan(2), reason: 'a single line is not readable');
    expect((jsonDecode(copied!) as Map)['profile'], {'email': 'alice@example.com'});
    expect(find.text('Your data was copied to the clipboard.'), findsOneWidget);
  });

  testWidgets('deletion needs the address, and a refusal keeps the form open and the user in', (
    tester,
  ) async {
    if (skipWithoutZenPlatform()) return;
    await pump(tester);

    // The screen scrolls, and on an 800×600 surface the button sits below the fold on some
    // platforms' layouts; a person scrolls to it, so the test does too.
    await tester.ensureVisible(button('Delete my data'));
    await tester.pumpAndSettle();
    await tester.tap(button('Delete my data'));
    await tester.pumpAndSettle();

    // Nothing is sent, and nothing can be, until an address is typed.
    final confirm = button('Delete everything');
    expect(tester.widget<ZenButton>(confirm).onPressed, isNull);

    await tester.enterText(textInput('Your email address'), 'someone@else.example');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(erased, ['someone@else.example']);
    expect(find.textContaining('Nothing was deleted'), findsOneWidget);
    expect(find.text('Delete all your data?'), findsOneWidget, reason: 'the form closed');
    expect(identity.logouts, 0, reason: 'a refused erasure signed the person out');
  });
}
