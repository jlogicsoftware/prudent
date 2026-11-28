// A launch of the server-connected app removes what a file dialog left behind, signed in or not
// (#309, ADR-138): a launch that ended with a dialog open, or an earlier build. The app is pumped as
// `main` builds it; only the server and the platform's directories are stood in for. The test runs as
// Android; iOS's places are prudent_ui's tests.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/app.dart';
import 'package:prudent/app_root.dart';
import 'package:zen_core/zen_core.dart' hide ZenError;
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

/// Nobody is signed in.
class _SignedOut extends Fake implements IdentityRepository {
  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => const ZenResult.ok(null);

  @override
  Future<ZenResult<IdentityContract>> refreshSession() async =>
      const ZenResult.err(ZenUnknownError('signed out'));
}

void main() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  testWidgets('a launch removes the copies a file dialog left', (tester) async {
    final cache = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('prudent_launch'),
    ))!;
    addTearDown(() => cache.deleteSync(recursive: true));
    final copy = Directory('${cache.path}/e72578ad-e8f4-3861-a42e-ddfb6870ca39')..createSync();
    File('${copy.path}/statement.csv').writeAsStringSync('statement');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'getTemporaryDirectory' ? cache.path : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [identityRepositoryProvider.overrideWithValue(_SignedOut())],
        child: const PrudentApp(),
      ),
    );
    // File I/O finishes only on the real event loop.
    for (var i = 0; i < 50 && copy.existsSync(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(find.byType(AppRoot), findsOneWidget);
    expect(copy.existsSync(), isFalse);
  });
}
