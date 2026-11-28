// iOS Data Protection on the store's directory (ADR-100 T1, ADR-137, #285). The platform side is
// jZen's plugin, stood in for here by a handler on its channel, so what is pinned is the call that
// reaches it: made on iOS before the store writes anything, at launch and again after an erasure,
// and never made elsewhere. The platform is set with Flutter's own debug override, so what is tested
// is the question production asks. Whether an iPhone then locks the files is plan unit 12's to see.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/app/start_failed_app.dart';
import 'package:prudent_local_client/core/local_session.dart';
import 'package:prudent_local_client/core/protect_store_directory.dart';
import 'package:prudent_local_client/l10n/generated/local_localizations.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

const _channel = MethodChannel('zen_store_cloudkit');

/// One call to the plugin, with what the directory it named held at that moment.
typedef _Call = ({String method, String path, List<String> files});

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory directory;
  late List<_Call> calls;

  /// Answers the plugin's channel with [reply]; with none, the plugin is not registered.
  void plugin(Future<Object?> Function()? reply) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      reply == null
          ? null
          : (call) async {
              final path = (call.arguments as Map)['path'] as String;
              final named = Directory(path);
              calls.add((
                method: call.method,
                path: path,
                files: named.existsSync()
                    ? [
                        for (final f in named.listSync(recursive: true))
                          if (f is File) f.path.substring(path.length + 1),
                      ]
                    : const [],
              ));
              return reply();
            },
    );
  }

  /// Opens a session as `bootPrudentLocal` does: nothing here says which platform it is.
  Future<ZenResult<LocalSession>> open() => LocalSession.open(
    directory: directory,
    dataDirectory: root,
    deviceName: 'Phone',
    storeKey: List.filled(32, 7),
    secrets: ZenMemoryLockStorage(),
    start: (store, {required folder, required syncKey}) async =>
        const ZenResult.err(ZenValidationError('no transport in this test')),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('prudent_local_protection');
    directory = Directory('${root.path}/prudent_local');
    calls = [];
    plugin(() async => true);
  });

  tearDown(() async {
    plugin(null);
    await root.delete(recursive: true);
  });

  group('on iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test(
      'the directory is protected before the store writes into it',
      () async {
        final session = (await open()).dataOrNull!;
        addTearDown(session.shutDown);

        expect(calls, hasLength(1));
        expect(calls.single.method, 'protectDirectory');
        expect(calls.single.path, directory.path);
        expect(calls.single.files, isEmpty);
        expect(File('${directory.path}/device.id').existsSync(), isTrue);
      },
    );

    test('every launch protects the files an earlier one left', () async {
      await (await open()).dataOrNull!.shutDown();
      final session = (await open()).dataOrNull!;
      addTearDown(session.shutDown);

      expect(calls, hasLength(2));
      expect(calls.last.files, contains('device.id'));
    });

    test('the new directory after an erasure is protected too', () async {
      final session = (await open()).dataOrNull!;
      addTearDown(session.shutDown);
      final first = File('${directory.path}/device.id').readAsStringSync();

      expect(await session.eraseThisDevice(), isA<ZenSuccess<void>>());

      expect(calls, hasLength(2));
      expect(calls.last.path, directory.path);
      expect(calls.last.files, isEmpty);
      expect(
        File('${directory.path}/device.id').readAsStringSync(),
        isNot(first),
      );
    });

    test(
      'starting afresh after erasing everywhere protects the new directory',
      () async {
        final session = (await open()).dataOrNull!;
        addTearDown(session.shutDown);
        await session.eraseEverywhere();

        expect(await session.startAfresh(), isA<ZenSuccess<void>>());

        expect(calls, hasLength(2));
        expect(calls.last.files, isEmpty);
      },
    );

    final failures = <String, Future<Object?> Function()?>{
      'the plugin reports an error': () async =>
          throw PlatformException(code: 'protect_failed', message: 'refused'),
      'the plugin answers false': () async => false,
      'the plugin is not registered': null,
    };
    for (final MapEntry(key: name, value: reply) in failures.entries) {
      test('when $name, the store is not opened', () async {
        plugin(reply);

        final result = await open();

        expect(result, isA<ZenFailure<LocalSession>>());
        final error = (result as ZenFailure<LocalSession>).error;
        expect(error.internalData?['code'], dataProtectionFailedCode);
        expect(directory.existsSync(), isFalse);
      });
    }

    test('a failure leaves an existing store\'s files as they were', () async {
      await (await open()).dataOrNull!.shutDown();
      Map<String, List<int>> contents() => {
        for (final f in directory.listSync(recursive: true))
          if (f is File) f.path: f.readAsBytesSync(),
      };
      final before = contents();
      plugin(() async => false);

      expect(await open(), isA<ZenFailure<LocalSession>>());

      expect(contents(), before);
    });

    test(
      'a failure after an erasure is reported and no new store is written',
      () async {
        final session = (await open()).dataOrNull!;
        addTearDown(session.shutDown);
        plugin(() async => false);

        final result = await session.eraseThisDevice();

        expect(result, isA<ZenFailure<void>>());
        expect(
          (result as ZenFailure<void>).error.internalData?['code'],
          dataProtectionFailedCode,
        );
        expect(directory.existsSync(), isFalse);
      },
    );
  });

  for (final platform in TargetPlatform.values) {
    if (platform == TargetPlatform.iOS) continue;
    test('on ${platform.name} the plugin is never called', () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final session = (await open()).dataOrNull!;
      addTearDown(session.shutDown);
      await session.eraseThisDevice();

      expect(calls, isEmpty);
    });
  }

  for (final locale in ['en', 'uk', 'pl']) {
    testWidgets(
      '$locale: the start failure says so and offers nothing that erases',
      (tester) async {
        tester.platformDispatcher.localesTestValue = [Locale(locale)];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        final l = lookupLocalLocalizations(Locale(locale));

        await tester.pumpWidget(
          StartFailedApp(
            error: const ZenUnknownError(
              'refused',
              internalData: {'code': dataProtectionFailedCode},
            ),
            onRetry: () {},
            onErase: () async => fail('erasing would not help'),
            isLinux: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(l.startFailedProtection), findsOneWidget);
        expect(find.text(l.startFailedRetry), findsOneWidget);
        expect(find.text(l.startFailedBody), findsNothing);
        expect(find.text(l.startFailedRestored), findsNothing);
        expect(find.text(l.startFailedErase), findsNothing);
      },
    );
  }
}
