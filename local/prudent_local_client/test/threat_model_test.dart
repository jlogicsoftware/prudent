// ADR-100, the rows unit 9 answers with a test that needs no second device. Every other row is
// either a two-device test in this directory (T3, T23, T24), a written refusal or acceptance in
// docs/DECISIONS.md (the unit-9 ADR lists all 26), or another unit's.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/app/start_failed_app.dart';
import 'package:prudent_local_client/app/start_failed_page.dart';
import 'package:prudent_local_client/core/local_session.dart';
import 'package:prudent_local_client/l10n/generated/local_localizations.dart';
import 'package:prudent_local_client/screens/first_run_notice.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store_folder/zen_store_folder.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';
import 'package:zen_store_sync/zen_store_sync.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'support/local_app_harness.dart';
import 'support/test_picker_copies.dart';

void main() {
  final l = lookupLocalLocalizations(const Locale('en'));

  // T15 — balances in Android's recents, a screen recording or a cast.
  testWidgets('T15: the app asks for FLAG_SECURE for as long as it runs', (
    tester,
  ) async {
    final calls = <Object?>[];
    const channel = MethodChannel('zen_ui_lock/screen');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.arguments);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final devices = await twoDevices(tester);
    await LocalAppHarness.pump(tester, devices.phone);
    expect(calls, [
      {'secure': true},
    ]);
  });

  // T6 — a folder inside the app's own data is refused.
  test('T6: a sync folder inside the app\'s data directory is refused, outside it is kept', () async {
    final root = await Directory.systemTemp.createTemp('prudent_local_t6');
    addTearDown(() => root.delete(recursive: true));
    final data = Directory('${root.path}/data')..createSync();
    final inside = Directory('${data.path}/sync')..createSync();
    final outside = Directory('${root.path}/cloud')..createSync();
    var pick = inside;
    final secrets = ZenMemoryLockStorage();
    final session = (await LocalSession.open(
      directory: Directory('${data.path}/prudent_local'),
      dataDirectory: data,
      deviceName: 'Phone',
      storeKey: List.filled(32, 7),
      secrets: secrets,
      start: (store, {required folder, required syncKey}) async =>
          const ZenResult.err(ZenValidationError('no transport in this test')),
      pickerCopies: testPickerCopies(root),
      restoreFolder: (reference) => ZenFolderChoice(
        reference: reference,
        label: reference,
        access: ZenDirectoryAccess(Directory(reference)),
      ),
      pickFolder: () async => ZenFolderChoice(
        reference: pick.path,
        label: 'x',
        access: ZenDirectoryAccess(pick),
      ),
    )).dataOrNull!;
    addTearDown(session.shutDown);

    final refused = await session.chooseFolder();
    expect(refused, isA<ZenFailure<bool>>());
    expect(session.folder, isNull);
    expect(await secrets.read('prudent_local.sync_folder'), isNull);

    pick = outside;
    expect((await session.chooseFolder()).dataOrNull, isTrue);
    expect(session.folder?.reference, outside.path);
    expect(LocalSession.isInsideAppData(data.path, data.path), isTrue);
    expect(
      LocalSession.isInsideAppData('${data.path}/../cloud', data.path),
      isFalse,
    );
    expect(
      LocalSession.isInsideAppData('content://com.android/tree/x', data.path),
      isFalse,
    );
  });

  // T18 — a release build syncing through the unencrypted development folder.
  test('T18: a release build refuses ZEN_SYNC, so the unencrypted folder never ships', () {
    for (final platform in ['android', 'windows', 'linux', 'ios', 'macos']) {
      final plan = ZenSyncPlan(platform, 'folder', release: true);
      expect(plan.kind, isNull, reason: platform);
      expect(plan.refusal, contains('ZEN_SYNC'), reason: platform);
    }
    expect(
      const ZenSyncPlan('linux', '', release: true).kind,
      ZenSyncKind.sharedFolder,
    );
    expect(
      const ZenSyncPlan('macos', '', release: true).kind,
      ZenSyncKind.cloudKit,
    );
  });

  // T10 — Android Auto Backup restoring the store without its key.
  test('T10: the Android manifest refuses Auto Backup', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
  });

  // T21 — nothing the ledger holds in a log line.
  test('T21: every log line in the app names classes and codes, never content', () {
    final logs = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.contains('/generated/')) {
        continue;
      }
      final source = file.readAsStringSync();
      expect(source, isNot(contains('print(')), reason: file.path);
      for (final match in RegExp(
        r"developer\.log\(\s*'([^']*)'",
      ).allMatches(source)) {
        logs.add('${file.path}: ${match.group(1)}');
        final interpolated = RegExp(r'\$\{?([a-zA-Z_.]+)')
            .allMatches(match.group(1)!);
        for (final value in interpolated) {
          expect(
            value.group(1),
            endsWith('runtimeType'),
            reason: '${file.path}: ${match.group(0)}',
          );
        }
      }
    }
    expect(
      logs,
      isNotEmpty,
      reason:
          'the scan found no log line at all; it is looking in the wrong place',
    );
  });

  // T8, T9, T10 — a key that cannot be read, or files restored without it.
  testWidgets(
    'T8: on Linux the failure says how to fix the keyring and offers nothing that erases',
    (tester) async {
      await tester.pumpWidget(
        StartFailedApp(
          error: const ZenUnknownError('no secret service'),
          onRetry: () {},
          onErase: () async => fail('nothing erases on Linux'),
          isLinux: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l.startFailedTitle), findsOneWidget);
      expect(find.text(l.startFailedLinux), findsOneWidget);
      expect(find.text(l.startFailedErase), findsNothing);
    },
  );

  testWidgets(
    'T9, T10: elsewhere erasing is offered, only after a question, never on its own',
    (tester) async {
      var erased = 0;
      await tester.pumpWidget(
        StartFailedApp(
          error: const ZenUnknownError('the files do not decrypt'),
          onRetry: () {},
          onErase: () async => erased++,
          isLinux: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l.startFailedRestored), findsOneWidget);
      expect(erased, 0);
      await tester.tap(find.text(l.startFailedErase));
      await tester.pumpAndSettle();
      expect(find.text(l.startFailedEraseConfirm), findsOneWidget);
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();
      expect(erased, 0);
      await tester.tap(find.text(l.startFailedErase));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.erase));
      await tester.pumpAndSettle();
      expect(erased, 1);
    },
  );

  // T2, T5 — said once, on the first launch.
  testWidgets(
    'T2, T5: the first launch says nobody can recover the data and offers a PIN',
    (tester) async {
      final devices = await twoDevices(tester);
      final app = await LocalAppHarness.pump(
        tester,
        devices.phone,
        firstRunSeen: false,
      );
      expect(find.byType(FirstRunNotice), findsOneWidget);
      expect(find.text(l.firstRunLoss), findsOneWidget);
      expect(find.text(l.firstRunPin), findsOneWidget);
      expect(
        app.lock.isEnabled,
        isFalse,
        reason: 'a PIN is offered, never forced',
      );
      await app.tapText(l.firstRunNotNow);
      expect(find.byType(FirstRunNotice), findsNothing);
      expect(
        await tester.runAsync(
          () => app.storage.read('prudent_local.first_run_seen'),
        ),
        '1',
      );
    },
  );

  // T8 again, after boot: the device's secret storage refuses a read the app makes later (the
  // Keychain's -34018 on an unsigned macOS build). The app says so; it never waits on a splash.
  testWidgets(
    'a secret storage that refuses the first-run read shows the start failure, not a splash',
    (tester) async {
      final devices = await twoDevices(tester);
      final storage = _RefusingFirstRun();
      await LocalAppHarness.pump(
        tester,
        devices.phone,
        storage: storage,
        firstRunSeen: false,
      );
      expect(find.byType(StartFailedPage), findsOneWidget);
      expect(find.text(l.startFailedTitle), findsOneWidget);
      expect(
        find.text(l.startFailedErase),
        findsNothing,
        reason: 'the store opened; erasing would not help',
      );

      storage.refuse = false;
      await tester.tap(find.text(l.startFailedRetry));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(StartFailedPage), findsNothing);
      expect(find.byType(FirstRunNotice), findsOneWidget);
    },
  );
}

/// Secret storage that refuses to read whether the first-run notice was seen, until told not to.
final class _RefusingFirstRun implements ZenLockStorage {
  final ZenMemoryLockStorage _inner = ZenMemoryLockStorage();
  bool refuse = true;

  @override
  Future<String?> read(String key) async {
    if (refuse && key == 'prudent_local.first_run_seen') {
      throw PlatformException(
        code: '-34018',
        message: 'A required entitlement is not present.',
      );
    }
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);

  @override
  Future<void> delete(String key) => _inner.delete(key);
}
