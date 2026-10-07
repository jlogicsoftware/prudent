import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart' show zenPlatform;

/// Skips the running test, and says so, when `ZEN_PLATFORM` was not defined at compile time.
///
/// A test that opens a `zen_ui_widgets` presentation (`showAdaptivePresentation`) runs into the
/// framework's own assertion that the define is set, which a bare `flutter test` never passes. The
/// define is compile-time on purpose — a wrong value compiles cleanly and is wrong at runtime — so
/// Prudent does not default it; the test names the command that supplies it instead. Call it first
/// and return when it answers `true`:
///
/// ```dart
/// if (skipWithoutZenPlatform()) return;
/// ```
bool skipWithoutZenPlatform() {
  if (zenPlatform.isNotEmpty) return false;
  markTestSkipped(
    'ZEN_PLATFORM is not defined; run the client suite with `task zen:test:client` or '
    '`flutter test --dart-define=ZEN_ENV=local --dart-define=ZEN_PLATFORM=<platform>`.',
  );
  return true;
}
