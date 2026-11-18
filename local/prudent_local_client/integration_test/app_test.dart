// Prudent Local driven inside the built app on a device (plan unit 9). Run with:
//
//   flutter test integration_test/app_test.dart -d macos \
//     --dart-define=ZEN_ENV=local --dart-define=ZEN_PLATFORM=macos
//
// Real plugins, real files, the real store and ledger, the real screens. Not driven: the native save
// panel (the copy's bytes are taken at the save seam instead) and the platform keystore of the first
// case is the device's own. CI does not run it: it needs a device.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prudent_local_client/app/local_composition.dart';
import 'package:prudent_local_client/app/local_providers.dart';
import 'package:prudent_local_client/app/prudent_local_app.dart';
import 'package:prudent_local_client/core/local_session.dart';
import 'package:prudent_local_client/l10n/generated/local_localizations.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_key/zen_store_key.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import '../test/support/ledger_setup.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final t = lookupPrudentLocalizations(const Locale('en'));
  final l = lookupLocalLocalizations(const Locale('en'));

  Future<void> settle(WidgetTester tester, [int frames = 30]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    // A live app rebuilds after real I/O (a store change re-reads every provider): wait for the
    // target to be there, at most five seconds, rather than tap a frame that is still loading.
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    await settle(tester);
  }

  testWidgets(
    'the ledger, the missing parts, the data copy and erasing, in the built app',
    (tester) async {
      await initializeDateFormatting();
      final temp = await getTemporaryDirectory();
      final root = await Directory('${temp.path}/prudent_local_it')
          .create(recursive: true);
      addTearDown(() => root.delete(recursive: true));
      final cloud = await Directory('${root.path}/cloud').create();
      final secrets = ZenMemoryLockStorage();
      await secrets.write(firstRunSeenKey, '1');
      final session = (await LocalSession.open(
        directory: Directory('${root.path}/data/prudent_local'),
        dataDirectory: Directory('${root.path}/data'),
        deviceName: 'Integration',
        storeKey: List.filled(32, 9),
        secrets: secrets,
        start: (store, {required folder, required syncKey}) =>
            ZenFolderCloud.start(store, cloud, pollEvery: null).then((r) => r),
      )).dataOrNull!;
      addTearDown(session.shutDown);
      final books = await openBooks(session.ledger);
      await addRecord(session.ledger, books);
      final lock = (await ZenPinLock.load(storage: secrets)).dataOrNull!;
      Uint8List? copy;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...localOverrides(session: session, lock: lock, storage: secrets),
            saveFileProvider.overrideWithValue((name, bytes) async {
              copy = bytes;
              return true;
            }),
          ],
          child: const PrudentLocalApp(),
        ),
      );
      await settle(tester);

      // The overview: the derived balance from the store.
      expect(find.textContaining('90.00 PLN'), findsWidgets);

      // Records from the ledger; Budgets and Analytics load from the device too.
      await tap(tester, find.text(t.navRecords));
      expect(find.text('Bread'), findsOneWidget);
      await tap(tester, find.text(t.navBudgets));
      expect(find.text(t.budgetLoadError), findsNothing);
      await tap(tester, find.text(t.navAnalytics));
      expect(find.text(t.analyticsLoadError), findsNothing);

      // The data copy: a file of the whole ledger, through the save seam.
      await tap(tester, find.text(t.navSettings));
      await tap(tester, find.text(t.settingsPrivacy));
      await tap(tester, find.text(l.dataCopyButton));
      final document = jsonDecode(utf8.decode(copy!)) as Map<String, dynamic>;
      expect((document['records'] as List).single['title'], 'Bread');

      // Erase this device's copy: the store is empty afterwards.
      final generationBefore = session.generation;
      await tap(tester, find.text(l.dataEraseButton).last);
      await tap(tester, find.text(l.erase));
      // Closing, erasing and reopening the store and restarting sync is real I/O here: wait for it.
      for (
        var i = 0;
        i < 300 && find.text(l.dataErased).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text(l.dataErased), findsOneWidget);
      // A new store was opened, and what the sync folder holds came back into it: "erase this
      // device's copy" leaves the other copies, as the page says (ADR-100 T24).
      expect(session.generation, greaterThan(generationBefore));
      for (
        var i = 0;
        i < 100 && (session.prudent.accounts.list().dataOrNull ?? []).isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(session.prudent.accounts.list().dataOrNull, hasLength(1));
    },
  );

  testWidgets(
    'an unsigned macOS build cannot reach the keychain, and the store key is refused, not faked',
    (tester) async {
      // A sandboxed macOS app reaches the Keychain only with `keychain-access-groups`, which needs a
      // development certificate (jZen's documented no-signing boundary). This build is unsigned, so
      // the platform answers -34018 and `ZenDeviceStoreKey` must fail: no key in a file, no
      // fallback, nothing written beside the store (ADR-100 T8), which the app then shows as its
      // start failure. A signed build, where this succeeds, is unit 12's. A non-release `ZEN_ENV=dev`
      // build is different: since jZen ADR-087 it keeps the key in the login keychain, which needs no
      // signing, so it succeeds unsigned (the branch below) and this refusal is for every other build.
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/prudent_local_it_keystore');
      const name = 'prudent_local_it.store_key';
      addTearDown(() => ZenStore.erase(directory));
      final key = await ZenDeviceStoreKey.load(
        dataDirectory: directory,
        name: name,
      );
      if (key case ZenSuccess()) {
        // A signed build: the key must come back the same.
        final again = await ZenDeviceStoreKey.load(
          dataDirectory: directory,
          name: name,
        );
        expect(again.dataOrNull, key.dataOrNull);
        await ZenDeviceStoreKey.platformStorage.delete(key: name);
        return;
      }
      expect(
        zenIsDevBuild,
        isFalse,
        reason: 'a dev build uses the login keychain (jZen ADR-087) and must not be refused',
      );
      expect((key as ZenFailure).error.message, contains('-34018'));
      expect(
        directory.existsSync() && directory.listSync().isNotEmpty,
        isFalse,
      );
    },
  );
}
