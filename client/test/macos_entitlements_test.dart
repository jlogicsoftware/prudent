// The macOS runner's sandbox must let the app write the file a person chooses (jlogicsoftware/prudent#286).
// `file_picker_darwin` refuses `saveFile` with ENTITLEMENT_REQUIRED_WRITE, before any panel opens,
// unless the signed app carries `files.user-selected.read-write`, and every other suite stands in for
// the plugin, so only the files themselves can say. The read-write entitlement also covers opening a
// file, which is what the statement picker needs.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _write = 'com.apple.security.files.user-selected.read-write';
const _read = 'com.apple.security.files.user-selected.read-only';

/// The runner folders held to the rule, relative to `client/`. Another app's runner is added here
/// (Prudent Local's is jlogicsoftware/prudent#296).
const _runners = ['macos/Runner'];

/// Whether an entitlements property list sets [_write] to true. Comments are dropped first, so a
/// commented-out grant does not count.
bool _grantsWrite(String plist) =>
    RegExp('<key>${RegExp.escape(_write)}</key>\\s*<true\\s*/>')
        .hasMatch(plist.replaceAll(RegExp('<!--.*?-->', dotAll: true), ''));

void main() {
  test('every macOS entitlements file lets the app write a file the person chose', () {
    for (final runner in _runners) {
      // Every file in the folder, so one added later (another signing configuration) is held too.
      final files = {
        for (final file in Directory(runner).listSync().whereType<File>())
          if (file.path.endsWith('.entitlements')) file.uri.pathSegments.last: file,
      };

      expect(
        files.keys,
        containsAll(<String>['Release.entitlements', 'DebugProfile.entitlements']),
      );
      for (final MapEntry(key: name, value: file) in files.entries) {
        expect(
          _grantsWrite(file.readAsStringSync()),
          isTrue,
          reason: '$runner/$name must set $_write to true, or saving a file fails on macOS',
        );
      }
    }
  });

  test('read-only, false and commented-out grants are not accepted', () {
    expect(_grantsWrite('<key>$_write</key>\n\t<true/>'), isTrue);
    expect(_grantsWrite('<key>$_read</key>\n\t<true/>'), isFalse);
    expect(_grantsWrite('<key>$_write</key>\n\t<false/>'), isFalse);
    expect(_grantsWrite('<!-- <key>$_write</key>\n\t<true/> -->'), isFalse);
  });
}
