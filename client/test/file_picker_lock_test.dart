// The version of the Apple file picker this app resolves (#309, ADR-138). `file_picker_darwin` before
// 2.5.2 leaves each export, the whole ledger in plain text, in the app's temporary directory after
// the save sheet closes. `zen_save_file` still admits such a version (jZenDev/jZen#287), so only the
// lock file keeps it out, and this fails when it goes back.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The version [lock], a `pubspec.lock`, resolves [package] to, as numbers. Null when it does not
/// name the package, or resolves something that is not a plain release.
List<int>? _resolved(String lock, String package) {
  final entry = RegExp(
    '^  $package:\n(?:    .*\n)*?    version: "(\\d+)\\.(\\d+)\\.(\\d+)"\$',
    multiLine: true,
  ).firstMatch(lock);
  if (entry == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(entry[i]!)];
}

bool _removesItsExport(List<int>? version) {
  if (version == null) return false;
  final [major, minor, patch] = version;
  return major > 2 || (major == 2 && (minor > 5 || (minor == 5 && patch >= 2)));
}

void main() {
  test('file_picker_darwin is locked to 2.5.2 or later', () {
    final version = _resolved(File('pubspec.lock').readAsStringSync(), 'file_picker_darwin');

    expect(
      _removesItsExport(version),
      isTrue,
      reason: 'pubspec.lock resolves file_picker_darwin $version',
    );
  });

  test('an older, missing or pre-release version is not accepted', () {
    String lock(String version) =>
        'packages:\n  file_picker_darwin:\n    dependency: transitive\n    description:\n'
        '      name: file_picker_darwin\n    source: hosted\n    version: "$version"\n'
        '  file_picker_linux:\n    version: "9.0.0"\n';
    bool accepted(String version) =>
        _removesItsExport(_resolved(lock(version), 'file_picker_darwin'));

    expect(accepted('2.5.2'), isTrue);
    expect(accepted('2.6.0'), isTrue);
    expect(accepted('3.0.0'), isTrue);
    expect(accepted('2.5.1'), isFalse);
    expect(accepted('2.4.9'), isFalse);
    expect(accepted('2.5.2-dev.1'), isFalse);
    expect(_removesItsExport(_resolved('packages:\n', 'file_picker_darwin')), isFalse);
  });
}
