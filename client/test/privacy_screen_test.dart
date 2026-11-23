// The privacy screen (M0, jlogicsoftware/prudent#48): what Prudent keeps, a copy of it, and the
// two-step deletion. Driven through the real PrudentRepository over a mock HTTP server, so the
// requests it sends are the ones asserted.
import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/auth/identity_settings_session.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:prudent_proto/generated/prudent/v1/privacy.pb.dart';
import 'package:prudent_ui/privacy/export_file_saver.dart';
import 'package:zen_save_file/zen_save_file.dart';
import 'package:prudent_ui/privacy/privacy_screen.dart';
import 'package:prudent_ui/providers.dart';
import 'package:prudent/server_prudent_repository.dart';
import 'package:zen_core/zen_core.dart' hide ZenError;
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_transport/zen_transport.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'zen_fields.dart';
import 'zen_platform_skip.dart';

const _headers = {'X-Zen-Transport': 'json'};

/// A synthetic export that carries one statement-import key (ADR-091), because the file has to keep it.
final _exportBody = {
  'formatVersion': 1,
  'exportedAtMs': '1794700800000',
  'profile': {'email': 'alice@example.com'},
  'records': [
    {'id': 'r1', 'title': 'Synthetic', 'amountMinor': '-500', 'currency': 'PLN'},
  ],
  'recordImportKeys': [
    {'recordId': 'r1', 'fingerprint': 'v1:${'ab' * 32}', 'occurrence': 2},
  ],
};

class _Identity implements IdentityRepository {
  // Nothing here changes the server's copy of the language (jZen #275).
  @override
  Future<ZenResult<void>> setLanguage(String language) async => const ZenResult.ok(null);

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
  late List<String> erased;
  late String? copied;
  late List<({String name, Uint8List bytes})> saved;
  bool cancelSave = false;
  bool failSave = false;
  Object? throwOnSave;
  bool byDownload = false;

  Future<void> pump(WidgetTester tester, {bool download = false}) async {
    identity = _Identity();
    erased = [];
    copied = null;
    // The screen is a lazy list; a tall surface keeps every button built, so a finder can see it.
    tester.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    saved = [];
    cancelSave = false;
    failSave = false;
    throwOnSave = null;
    byDownload = download;
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
            jsonEncode(_exportBody),
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
          prudentRepositoryProvider.overrideWithValue(ServerPrudentRepository(client: client)),
          identityRepositoryProvider.overrideWithValue(identity),
          identitySettingsSession,
          exportFileSavedByDownloadProvider.overrideWithValue(byDownload),
          exportFileSaverProvider.overrideWithValue((name, bytes) async {
            if (throwOnSave != null) throw throwOnSave!;
            if (failSave) throw const ZenSaveFileError('disk refused');
            if (cancelSave) return false;
            saved.add((name: name, bytes: bytes));
            return true;
          }),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            ...PrudentLocalizations.localizationsDelegates,
            ...GlobalMaterialLocalizations.delegates,
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

  testWidgets('warns that the file is not encrypted before the save button, in the open', (
    tester,
  ) async {
    await pump(tester);

    expect(find.textContaining('The file is not encrypted'), findsOneWidget);
    expect(button('Save to a file'), findsOneWidget);
    final warning = tester.getTopLeft(find.textContaining('The file is not encrypted')).dy;
    expect(warning, lessThan(tester.getTopLeft(button('Save to a file')).dy));
    expect(find.textContaining('shared with other apps'), findsOneWidget);
  });

  testWidgets('a saved file reads back as an equal DataExport, import key included', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(button('Save to a file'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.name, 'prudent-export-2026-11-15.json');
    final read = DataExport()
      ..mergeFromProto3Json(jsonDecode(utf8.decode(saved.single.bytes)));
    final sent = DataExport()..mergeFromProto3Json(_exportBody);
    expect(read, sent);
    expect(read.recordImportKeys.single.fingerprint, 'v1:${'ab' * 32}');
    expect(read.recordImportKeys.single.occurrence, 2);
    expect(find.textContaining('Your data was saved'), findsOneWidget);
    expect(copied, isNull, reason: 'saving a file must not also copy to the clipboard');
  });

  testWidgets('cancelling the save panel says nothing; a refused write says so', (tester) async {
    await pump(tester);

    cancelSave = true;
    await tester.tap(button('Save to a file'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.textContaining('was saved'), findsNothing);
    expect(find.textContaining('could not be saved'), findsNothing);

    cancelSave = false;
    failSave = true;
    await tester.tap(button('Save to a file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(find.textContaining('disk refused'), findsNothing, reason: 'the cause is logged, not shown');
  });

  testWidgets('an Error from the platform still stops the spinner; the screen stays usable', (
    tester,
  ) async {
    await pump(tester);

    throwOnSave = UnimplementedError('no save location here');
    // The handler's future is not awaited by anyone, so the Error surfaces as an uncaught async
    // error: it is not swallowed here, and the zone below is how the test sees it.
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      await tester.tap(button('Save to a file'));
      await tester.pump();
    }, (error, stack) => uncaught.add(error));
    await tester.pumpAndSettle();
    expect(uncaught.single, isA<UnimplementedError>());
    expect(tester.widget<ZenButton>(button('Save to a file')).isLoading, isFalse);
    expect(tester.widget<ZenButton>(button('Copy my data')).isLoading, isFalse);
  });

  testWidgets('on the web the confirmation says downloaded, not saved', (tester) async {
    await pump(tester, download: true);

    await tester.tap(button('Save to a file'));
    await tester.pumpAndSettle();
    expect(find.textContaining("handed to your browser's downloads"), findsOneWidget);
    expect(find.textContaining('Your data was saved'), findsNothing);
  });

  group('saveExportFile over a fake of the framework port', () {
    final bytes = Uint8List.fromList(utf8.encode('{"a":1}'));

    test('passes the name, the bytes and the JSON type through, and reports a write', () async {
      final port = _FakeSavePort();
      expect(await saveExportFile('x.json', bytes, port: port), isTrue);
      expect(port.calls.single, ('x.json', bytes, 'application/json'));
    });

    test('a cancel is false, not an error', () async {
      final port = _FakeSavePort()..cancel = true;
      expect(await saveExportFile('x.json', bytes, port: port), isFalse);
    });

    test('a refused write throws ZenSaveFileError', () async {
      final port = _FakeSavePort()..refuse = true;
      await expectLater(
        saveExportFile('x.json', bytes, port: port),
        throwsA(isA<ZenSaveFileError>()),
      );
    });
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

class _FakeSavePort implements ZenSaveFilePort {
  final calls = <(String, Uint8List, String)>[];
  bool cancel = false;
  bool refuse = false;

  @override
  Future<bool> save(String name, Uint8List bytes, String mimeType) async {
    if (refuse) throw const ZenSaveFileError('no space');
    if (cancel) return false;
    calls.add((name, bytes, mimeType));
    return true;
  }
}
