// The removal of the copies a file dialog leaves in the app's sandbox (#309, ADR-138): what goes,
// and above all what must never go. The directory names are the ones seen on an iOS 26.5 simulator
// and an Android emulator with the locked plugins; whether a real device uses them is plan unit
// 12's to see.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_ui/privacy/picker_copies.dart';
import 'package:zen_core/zen_core.dart';

/// `UUID.nameUUIDFromBytes` (version 3), as `file_selector_android` names one pick's directory.
const _androidPick = 'e72578ad-e8f4-3861-a42e-ddfb6870ca39';

/// A random (version 4) UUID, which other plugins name their own cache directories with.
const _otherPlugin = 'e72578ad-e8f4-4861-a42e-ddfb6870ca39';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory tmp;
  late Directory cache;
  late Directory outside;
  late PickerCopies copies;

  File plant(Directory parent, String path) => File('${parent.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync('statement');

  setUp(() {
    root = Directory.systemTemp.createTempSync('prudent_picker_copies');
    tmp = Directory('${root.path}/container/tmp')..createSync(recursive: true);
    cache = Directory('${root.path}/container/cache')..createSync(recursive: true);
    outside = Directory('${root.path}/Documents')..createSync();
    copies = PickerCopies(temporaryDirectory: () async => tmp, cacheDirectory: () async => cache);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    root.deleteSync(recursive: true);
  });

  group('on iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('removes picked and exported copies, and nothing else in the directories', () async {
      final picked = plant(tmp, 'com.example.app-Inbox/statement.csv');
      final exported = plant(tmp, 'flutter_file_picker/6F1A/prudent-export.json');
      final others = [
        plant(tmp, 'other-plugin/file'),
        plant(tmp, 'loose.txt'),
        plant(cache, 'flutter_callback_cache.json'),
        plant(cache, 'some-Inbox/file'),
      ];

      expect(await copies.remove(), isA<ZenSuccess<void>>());

      expect(picked.parent.existsSync(), isFalse);
      expect(exported.parent.parent.existsSync(), isFalse);
      for (final file in others) {
        expect(file.existsSync(), isTrue, reason: file.path);
      }
    });

    test('leaves a link that has a dialog\'s name, and what it points at', () async {
      final theirs = plant(outside, 'mine/statement.csv');
      final link = Link('${tmp.path}/com.example.app-Inbox')..createSync(theirs.parent.path);

      expect(await copies.remove(), isA<ZenSuccess<void>>());

      expect(link.existsSync(), isTrue);
      expect(theirs.existsSync(), isTrue);
    });

    test('a link inside a copy directory goes, what it points at stays', () async {
      final theirs = plant(outside, 'statement.csv');
      final inbox = Directory('${tmp.path}/com.example.app-Inbox')..createSync();
      Link('${inbox.path}/statement.csv').createSync(theirs.path);
      // A link to a directory, one level down: it must not be listed into.
      Directory('${inbox.path}/nested').createSync();
      Link('${inbox.path}/nested/theirs').createSync(outside.path);

      expect(await copies.remove(), isA<ZenSuccess<void>>());

      expect(inbox.existsSync(), isFalse);
      expect(theirs.readAsStringSync(), 'statement');
    });
  });

  group('on Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('removes each pick\'s directory, and nothing else in the cache', () async {
      final picked = plant(cache, '$_androidPick/statement.csv');
      final others = [
        plant(cache, '$_otherPlugin/photo.jpg'),
        plant(cache, 'images/photo.jpg'),
        plant(cache, '$_androidPick.txt'),
        plant(cache, 'x$_androidPick/file'),
        plant(tmp, '$_androidPick/file'),
      ];

      expect(await copies.remove(), isA<ZenSuccess<void>>());

      expect(picked.parent.existsSync(), isFalse);
      for (final file in others) {
        expect(file.existsSync(), isTrue, reason: file.path);
      }
    });

    test('does not look at the temporary directory iOS has', () async {
      final asked = <String>[];
      final observed = PickerCopies(
        temporaryDirectory: () async {
          asked.add('tmp');
          return tmp;
        },
        cacheDirectory: () async => cache,
      );

      await observed.remove();

      expect(asked, isEmpty);
    });
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group('the picked file on $platform', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);

      test('is removed when it is inside the app\'s directories, wherever', () async {
        final inCache = plant(cache, 'somewhere/new/statement.csv');

        expect(await copies.remove(picked: inCache.path), isA<ZenSuccess<void>>());

        expect(inCache.existsSync(), isFalse);
      });

      test('is removed when the directory is spelled through a link', () async {
        // As iOS's /var and /private/var, and Android's /data/user/0 and /data/data.
        final alias = Link('${root.path}/alias')..createSync(cache.path);
        final file = plant(cache, 'somewhere/statement.csv');

        await copies.remove(picked: '${alias.path}/somewhere/statement.csv');

        expect(file.existsSync(), isFalse);
      });

      test('is removed when the directory itself was named through a link', () async {
        final alias = Link('${root.path}/alias')..createSync(cache.path);
        final file = plant(cache, 'somewhere/statement.csv');
        final aliased = PickerCopies(
          temporaryDirectory: () async => tmp,
          cacheDirectory: () async => Directory(alias.path),
        );

        await aliased.remove(picked: file.path);

        expect(file.existsSync(), isFalse);
      });

      test('is never removed outside them', () async {
        final theirs = plant(outside, 'statement.csv');
        // A sibling whose name starts like the directory's.
        final sibling = plant(Directory('${cache.path}-mine'), 'statement.csv');
        final tmpSibling = plant(Directory('${tmp.path}evil'), 'statement.csv');
        // A path that starts inside and walks out.
        final walked = '${cache.path}/../../Documents/statement.csv';
        expect(File(walked).existsSync(), isTrue);
        // A link inside that leads out, to the file and to its directory.
        Link('${cache.path}/link.csv').createSync(theirs.path);
        Link('${cache.path}/linked').createSync(outside.path);

        for (final path in [
          theirs.path,
          sibling.path,
          tmpSibling.path,
          walked,
          '${cache.path}/link.csv',
          '${cache.path}/linked/statement.csv',
        ]) {
          expect(await copies.remove(picked: path), isA<ZenSuccess<void>>(), reason: path);
          expect(theirs.existsSync(), isTrue, reason: path);
          expect(sibling.existsSync(), isTrue, reason: path);
          expect(tmpSibling.existsSync(), isTrue, reason: path);
        }
      });

      test('a directory, a missing path or an object URL removes nothing', () async {
        final kept = plant(cache, 'somewhere/file');

        for (final path in [cache.path, kept.parent.path, '${cache.path}/gone', 'blob:abc', '']) {
          expect(await copies.remove(picked: path), isA<ZenSuccess<void>>(), reason: path);
        }

        expect(kept.existsSync(), isTrue);
      });
    });
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.linux, TargetPlatform.windows]) {
    test('on $platform nothing is removed, not even inside the directories', () async {
      debugDefaultTargetPlatformOverride = platform;
      // A desktop dialog answers with the person's own file, which may be anywhere.
      final files = [
        plant(tmp, 'mine.csv'),
        plant(cache, 'mine.csv'),
        plant(tmp, 'a-Inbox/mine.csv'),
        plant(cache, '$_androidPick/mine.csv'),
        plant(outside, 'mine.csv'),
      ];

      for (final file in files) {
        expect(await copies.remove(picked: file.path), isA<ZenSuccess<void>>());
      }

      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: file.path);
      }
    });
  }

  test('directories that do not exist are not a failure', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final nowhere = PickerCopies(
      temporaryDirectory: () async => Directory('${root.path}/no/tmp'),
      cacheDirectory: () async => Directory('${root.path}/no/cache'),
    );

    expect(await nowhere.remove(picked: '${root.path}/no/tmp/file'), isA<ZenSuccess<void>>());
  });

  test('on iOS a removal with no picked path does not need the cache directory', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final left = plant(tmp, 'a-Inbox/statement.csv');
    final noCache = PickerCopies(
      temporaryDirectory: () async => tmp,
      cacheDirectory: () async => throw const FileSystemException('refused'),
    );

    expect(await noCache.remove(), isA<ZenSuccess<void>>());

    expect(left.parent.existsSync(), isFalse);
  });

  group('what stays behind', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    /// Takes writing away from [directory], so nothing in it can be deleted, until the test ends.
    void freeze(Directory directory) {
      expect(Process.runSync('chmod', ['555', directory.path]).exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['755', directory.path]));
    }

    test('a directory that cannot be deleted but holds nothing is not a failure', () async {
      final picked = plant(tmp, 'a-Inbox/nested/statement.csv');
      // The Inbox itself stays, because its parent refuses; what is in it can go.
      freeze(tmp);

      expect(await copies.remove(), isA<ZenSuccess<void>>());

      expect(picked.parent.existsSync(), isFalse);
      expect(picked.parent.parent.existsSync(), isTrue);
    });

    test('a file that cannot be deleted is a failure, and the others still go', () async {
      final stuck = plant(tmp, 'a-Inbox/statement.csv');
      final other = plant(tmp, 'flutter_file_picker/6F1A/export.json');
      freeze(stuck.parent);

      expect(await copies.remove(), isA<ZenFailure<void>>());

      expect(stuck.existsSync(), isTrue);
      expect(other.existsSync(), isFalse);
    });

    test('a directory swapped for a link while the removal runs is not listed into', () async {
      final theirs = plant(outside, 'statement.csv');
      final nested = Directory('${tmp.path}/a-Inbox/nested')..createSync(recursive: true);
      var swapped = false;

      // The swap is made after the parent was listed, as the removal looks at the directory again.
      final result = await IOOverrides.runZoned(
        () => copies.remove(),
        fseGetType: (path, followLinks) {
          if (!swapped && path == nested.path) {
            swapped = true;
            nested.deleteSync();
            Link(nested.path).createSync(outside.path);
          }
          return Future.value(FileSystemEntity.typeSync(path, followLinks: followLinks));
        },
      );

      expect(swapped, isTrue);
      expect(theirs.existsSync(), isTrue);
      // The link stays, so the directory holding it does: nobody recorded why, and it is still said.
      expect(result, isA<ZenFailure<void>>());
    });

    test('a picked file that cannot be deleted is a failure', () async {
      final stuck = plant(tmp, 'somewhere/statement.csv');
      freeze(stuck.parent);

      expect(await copies.remove(picked: stuck.path), isA<ZenFailure<void>>());
      expect(stuck.existsSync(), isTrue);
    });
  }, skip: Platform.isWindows ? 'chmod is POSIX' : null);

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test('removals that overlap on $platform all succeed: gone is what they were for', () async {
      debugDefaultTargetPlatformOverride = platform;
      final inbox = platform == TargetPlatform.iOS ? tmp : cache;
      final name = platform == TargetPlatform.iOS ? 'a-Inbox' : _androidPick;

      for (var round = 0; round < 20; round++) {
        final picked = plant(inbox, '$name/statement.csv');
        for (var i = 0; i < 5; i++) {
          plant(inbox, '$name/nested$i/statement.csv');
        }

        final results = await Future.wait([
          for (var i = 0; i < 8; i++) copies.remove(picked: picked.path),
        ]);

        expect(results.whereType<ZenFailure<void>>(), isEmpty, reason: 'round $round');
        expect(picked.parent.existsSync(), isFalse, reason: 'round $round');
      }
    });
  }

  test('a failure is answered without a path, and the rest is still removed', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final picked = plant(tmp, 'a-Inbox/statement.csv');
    final broken = PickerCopies(
      temporaryDirectory: () async => tmp,
      cacheDirectory: () async => throw FileSystemException('refused', '/secret/statement.csv'),
    );

    final result = await broken.remove(picked: picked.path);

    expect(result, isA<ZenFailure<void>>());
    expect((result as ZenFailure<void>).error.message, isNot(contains('secret')));
    expect(picked.parent.existsSync(), isFalse);
  });

  group('as an app builds it, with no directory passed', () {
    const channel = MethodChannel('plugins.flutter.io/path_provider');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getTemporaryDirectory' ? cache.path : null,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    test('Android sweeps the directory path_provider calls temporary', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final picked = plant(cache, '$_androidPick/statement.csv');

      expect(await const PickerCopies().remove(), isA<ZenSuccess<void>>());

      expect(picked.parent.existsSync(), isFalse);
    });

    test('iOS sweeps the system temporary directory, not path_provider\'s', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final picked = plant(tmp, 'a-Inbox/statement.csv');
      final caches = plant(cache, 'a-Inbox/file');

      final result = await IOOverrides.runZoned(
        () => const PickerCopies().remove(),
        getSystemTempDirectory: () => tmp,
      );

      expect(result, isA<ZenSuccess<void>>());
      expect(picked.parent.existsSync(), isFalse);
      expect(caches.existsSync(), isTrue);
    });
  });
}
