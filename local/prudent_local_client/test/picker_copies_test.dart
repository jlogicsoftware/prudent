// No copy a file dialog made outlives its use in Prudent Local (#309, ADR-138): the export picker,
// the launch and both erase actions. The copies are planted where Android's plugin puts them, which
// is the platform a test runs as; the removal's own rules, iOS's places among them, are
// prudent_ui's tests.
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/core/local_boot.dart';
import 'package:prudent_local_client/core/local_session.dart';
import 'package:prudent_local_client/move_in/export_file_picker.dart';
import 'package:prudent_ui/privacy/picker_copies.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'support/test_picker_copies.dart';

/// A file whose read takes a while, as a large one does.
class _SlowFile extends XFile {
  _SlowFile(super.path);

  @override
  Future<Uint8List> readAsBytes() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return super.readAsBytes();
  }
}

class _Dialog extends FileSelectorPlatform {
  _Dialog(this.answer);

  final Future<XFile?> Function() answer;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) => answer();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  /// A pick's copy, in the cache directory under [root].
  File plant([int length = 3]) =>
      File(
          '${root.path}/cache/e72578ad-e8f4-3861-a42e-ddfb6870ca39/export.json',
        )
        ..createSync(recursive: true)
        ..writeAsBytesSync(Uint8List(length));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('prudent_local_copies');
  });

  tearDown(() => root.delete(recursive: true));

  group('the export picker', () {
    final original = FileSelectorPlatform.instance;
    tearDown(() => FileSelectorPlatform.instance = original);

    late File copy;
    void answersWithCopy() {
      FileSelectorPlatform.instance = _Dialog(() async {
        copy = plant();
        return XFile(copy.path);
      });
    }

    Future<Uint8List?> pick() => pickExportFile(copies: testPickerCopies(root));

    test('leaves no copy of an export it read', () async {
      answersWithCopy();

      expect(await pick(), hasLength(3));

      expect(copy.parent.existsSync(), isFalse);
    });

    test('removes the copy only after the read has ended', () async {
      FileSelectorPlatform.instance = _Dialog(() async {
        copy = plant();
        return _SlowFile(copy.path);
      });

      expect(await pick(), hasLength(3));

      expect(copy.parent.existsSync(), isFalse);
    });

    test(
      'removes a copy the dialog put somewhere unforeseen in the cache',
      () async {
        FileSelectorPlatform.instance = _Dialog(() async {
          copy = File('${root.path}/cache/somewhere/export.json')
            ..createSync(recursive: true)
            ..writeAsBytesSync(Uint8List(3));
          return XFile(copy.path);
        });

        expect(await pick(), hasLength(3));

        expect(copy.existsSync(), isFalse);
      },
    );

    test('leaves no copy of an export it refused as too large', () async {
      FileSelectorPlatform.instance = _Dialog(() async {
        copy = plant(0);
        // A sparse file: over the bound without writing that much.
        copy.openSync(mode: FileMode.append)
          ..truncateSync(maxExportFileBytes + 1)
          ..closeSync();
        return XFile(copy.path);
      });

      await expectLater(pick(), throwsA(isA<ExportFileTooLarge>()));

      expect(copy.parent.existsSync(), isFalse);
    });

    test('leaves no copy of an export it could not read', () async {
      FileSelectorPlatform.instance = _Dialog(() async {
        copy = plant();
        return XFile('${copy.path}.gone');
      });

      await expectLater(pick(), throwsA(isA<FileSystemException>()));

      expect(copy.parent.existsSync(), isFalse);
    });

    test('leaves no copy when the dialog itself fails', () async {
      FileSelectorPlatform.instance = _Dialog(() async {
        copy = plant();
        throw StateError('copy failed');
      });

      await expectLater(pick(), throwsStateError);

      expect(copy.parent.existsSync(), isFalse);
    });
  });

  group('the session and the launch', () {
    const channel = MethodChannel('plugins.flutter.io/path_provider');

    // `path_provider`, answering with this test's directories: what an app asks when nothing stands
    // in for the removal.
    setUp(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'getTemporaryDirectory' => '${root.path}/cache',
          'getApplicationSupportDirectory' => '${root.path}/support',
          _ => null,
        },
      );
    });

    tearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    /// A session over `data/` under [root], shut down at the test's end unless [closedByTest].
    Future<LocalSession> open({
      PickerCopies? pickerCopies,
      bool closedByTest = false,
    }) async {
      final data = Directory('${root.path}/data')..createSync();
      Future<ZenResult<LocalSession>> session() {
        final directory = Directory('${data.path}/prudent_local');
        const noTransport = ZenValidationError('no transport in this test');
        return pickerCopies == null
            // As the app opens it: nothing said about the dialogs' copies.
            ? LocalSession.open(
                directory: directory,
                dataDirectory: data,
                deviceName: 'Phone',
                storeKey: List.filled(32, 7),
                secrets: ZenMemoryLockStorage(),
                start: (store, {required folder, required syncKey}) async =>
                    const ZenResult.err(noTransport),
              )
            : LocalSession.open(
                directory: directory,
                dataDirectory: data,
                deviceName: 'Phone',
                storeKey: List.filled(32, 7),
                secrets: ZenMemoryLockStorage(),
                start: (store, {required folder, required syncKey}) async =>
                    const ZenResult.err(noTransport),
                pickerCopies: pickerCopies,
              );
      }

      final opened = (await session()).dataOrNull!;
      if (!closedByTest) addTearDown(opened.shutDown);
      return opened;
    }

    test('erasing this device\'s copy leaves none', () async {
      final session = await open();
      final copy = plant();

      expect(await session.eraseThisDevice(), isA<ZenSuccess<void>>());

      expect(copy.parent.existsSync(), isFalse);
    });

    test('erasing everywhere leaves none', () async {
      final session = await open();
      final copy = plant();

      expect(await session.eraseEverywhere(), isA<ZenSuccess<void>>());

      expect(copy.parent.existsSync(), isFalse);
    });

    test('starting afresh leaves none', () async {
      final session = await open();
      await session.eraseEverywhere();
      final copy = plant();

      expect(await session.startAfresh(), isA<ZenSuccess<void>>());

      expect(copy.parent.existsSync(), isFalse);
    });

    final broken = PickerCopies(
      cacheDirectory: () async => throw const FileSystemException('refused'),
    );

    LocalErasure? left(ZenResult<LocalErasure> result) => result.dataOrNull;

    test('an erasure that removed every copy says so', () async {
      final session = await open();
      plant();

      expect(left(await session.eraseThisDevice()), LocalErasure.complete);
      expect(left(await session.eraseEverywhere()), LocalErasure.complete);
      expect(left(await session.startAfresh()), LocalErasure.complete);
    });

    test(
      'a copy that may remain is a success that says so, with the store erased',
      () async {
        final session = await open(pickerCopies: broken);
        final before = session.generation;

        expect(
          left(await session.eraseThisDevice()),
          LocalErasure.copyMayRemain,
        );

        expect(session.generation, greaterThan(before));
        expect(session.prudent.accounts.list().dataOrNull, isEmpty);
        expect(
          left(await session.eraseEverywhere()),
          LocalErasure.copyMayRemain,
        );
        expect(session.erasedEverywhere, isTrue);
        expect(left(await session.startAfresh()), LocalErasure.copyMayRemain);
        expect(session.erasedEverywhere, isFalse);
      },
    );

    test(
      'a copy that cannot be removed does not hold back "Forgot PIN?"',
      () async {
        final session = await open(pickerCopies: broken);
        final lock = (await ZenPinLock.load(
          storage: ZenMemoryLockStorage(),
          // As bootPrudentLocal wires it.
          eraseDeviceCopy: session.eraseThisDevice,
          iterations: 1,
        )).dataOrNull!;
        expect(await lock.enable('1234'), isA<ZenSuccess<void>>());

        expect(await lock.recoverByErasing(), isA<ZenSuccess<void>>());

        expect(lock.isEnabled, isFalse);
      },
    );

    // The other half of "a copy that stays does not fail an erasure": an erasure that did not get
    // through stays a failure, so a PIN is never reset over data that is still there.
    test(
      'a store that cannot be erased is a failure, and the PIN stays',
      () async {
        final session = await open();
        final lock = (await ZenPinLock.load(
          storage: ZenMemoryLockStorage(),
          eraseDeviceCopy: session.eraseThisDevice,
          iterations: 1,
        )).dataOrNull!;
        expect(await lock.enable('1234'), isA<ZenSuccess<void>>());
        // The store's directory cannot be removed from a directory that refuses writing.
        final data = '${root.path}/data';
        expect(Process.runSync('chmod', ['555', data]).exitCode, 0);
        addTearDown(() => Process.runSync('chmod', ['755', data]));

        expect(await lock.recoverByErasing(), isA<ZenFailure<void>>());

        expect(lock.isEnabled, isTrue);
      },
      skip: Platform.isWindows ? 'chmod is POSIX' : null,
    );

    test('an erasure everywhere that fails stays a failure', () async {
      final session = await open(closedByTest: true);
      // A closed store takes no erasure.
      await session.shutDown();

      expect(await session.eraseEverywhere(), isA<ZenFailure<void>>());
    });

    test(
      'a launch removes what an earlier one left, before the store is opened',
      () async {
        final copy = plant();

        // The store cannot be opened on a test host (there is no keystore), which is the point: the
        // copy goes whether it can or not.
        try {
          await bootPrudentLocal(secrets: ZenMemoryLockStorage());
        } on Object catch (_) {}

        expect(copy.parent.existsSync(), isFalse);
      },
    );
  });
}
