// The statement picker leaves no copy behind, however the pick ends (#309, ADR-138). The dialog is
// stood in for at `file_selector`'s own seam: it writes the copy where the phone's plugin would and
// answers with its path.
@TestOn('vm')
library;

import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_ui/imports/statement_format.dart';
import 'package:prudent_ui/imports/statement_picker.dart';
import 'package:prudent_ui/privacy/picker_copies.dart';

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
  late Directory root;
  late Directory tmp;
  late Directory cache;
  late PickerCopies copies;
  final original = FileSelectorPlatform.instance;

  setUp(() {
    root = Directory.systemTemp.createTempSync('prudent_statement_picker');
    tmp = Directory('${root.path}/tmp')..createSync();
    cache = Directory('${root.path}/cache')..createSync();
    copies = PickerCopies(temporaryDirectory: () async => tmp, cacheDirectory: () async => cache);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    FileSelectorPlatform.instance = original;
    root.deleteSync(recursive: true);
  });

  File write(String path, [List<int> bytes = const [1, 2, 3]]) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  // Where each phone's plugin puts a pick's copy.
  const places = {
    TargetPlatform.iOS: 'tmp/com.example-Inbox/statement.csv',
    TargetPlatform.android: 'cache/e72578ad-e8f4-3861-a42e-ddfb6870ca39/statement.csv',
  };

  for (final MapEntry(key: platform, value: place) in places.entries) {
    group('on $platform', () {
      late File copy;

      setUp(() => debugDefaultTargetPlatformOverride = platform);

      void answersWithCopy([List<int> bytes = const [1, 2, 3]]) {
        FileSelectorPlatform.instance = _Dialog(() async {
          copy = write(place, bytes);
          return XFile(copy.path);
        });
      }

      test('a statement that was read leaves no copy', () async {
        answersWithCopy();

        final picked = await pickStatementFile(copies: copies);

        expect(picked!.bytes, [1, 2, 3]);
        expect(picked.name, 'statement.csv');
        expect(copy.parent.existsSync(), isFalse);
      });

      test('a statement refused as too large leaves no copy', () async {
        answersWithCopy(Uint8List(maxStatementBytes + 1));

        await expectLater(pickStatementFile(copies: copies), throwsA(isA<StatementTooLarge>()));

        expect(copy.parent.existsSync(), isFalse);
      });

      test('a statement that cannot be read leaves no copy', () async {
        // The dialog answers with a path that is not there, beside a copy that is.
        late File left;
        FileSelectorPlatform.instance = _Dialog(() async {
          left = write(place);
          return XFile('${left.path}.gone');
        });

        await expectLater(pickStatementFile(copies: copies), throwsA(isA<FileSystemException>()));

        expect(left.parent.existsSync(), isFalse);
      });

      test('a dialog that fails after copying leaves no copy, and still fails', () async {
        late File half;
        FileSelectorPlatform.instance = _Dialog(() async {
          half = write(place);
          throw StateError('copy failed');
        });

        await expectLater(pickStatementFile(copies: copies), throwsStateError);

        expect(half.parent.existsSync(), isFalse);
      });

      test('a copy the dialog put somewhere unforeseen in the app\'s cache goes too', () async {
        // As after a plugin update that moves its copy: only the path it answered with names it.
        late File moved;
        FileSelectorPlatform.instance = _Dialog(() async {
          moved = write('cache/somewhere/statement.csv');
          return XFile(moved.path);
        });

        expect((await pickStatementFile(copies: copies))!.bytes, [1, 2, 3]);

        expect(moved.existsSync(), isFalse);
      });

      test('a cancelled pick removes what an earlier one left', () async {
        final left = write(place);
        FileSelectorPlatform.instance = _Dialog(() async => null);

        expect(await pickStatementFile(copies: copies), isNull);

        expect(left.parent.existsSync(), isFalse);
      });
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.macOS]) {
    test('on $platform a file outside the app\'s directories is read and kept', () async {
      debugDefaultTargetPlatformOverride = platform;
      final theirs = write('Documents/statement.csv');
      FileSelectorPlatform.instance = _Dialog(() async => XFile(theirs.path));

      expect((await pickStatementFile(copies: copies))!.bytes, [1, 2, 3]);

      expect(theirs.existsSync(), isTrue);
    });
  }
}
