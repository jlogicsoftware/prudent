// ADR-100 T18, proven on a real release build. NOT part of the app: built by
// `task test:local-release-refusal` as `flutter build <host> --release -t tool/release_sync_probe.dart`
// with `--dart-define=ZEN_SYNC=folder`, then run.
//
// jZen's `ZenSync` refuses any ZEN_SYNC in a release build (`ZenSyncPlan`, jZenDev/jZen#238); this
// does not re-implement that, it asks the app's own starter, `startSyncForBuild`, what a release build
// does and exits 0 only when it is refused for THAT reason. `flutter test` cannot answer: it is never a
// release build and ignores a `dart.vm.product` define, so a unit test of `release: true` proves the
// table (threat_model_test does) and not the build.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:prudent_local_client/core/sync_starter.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const release = bool.fromEnvironment('dart.vm.product');
  if (!release) {
    stderr.writeln('PROBE-FAIL this is not a release build (dart.vm.product is false)');
    exit(2);
  }
  final dir = await Directory.systemTemp.createTemp('prudent_local_probe');
  try {
    final opened = await ZenStore.open(
      Directory('${dir.path}/store')..createSync(),
      deviceName: 'probe',
      key: List.generate(32, (i) => i),
    );
    final result = await startSyncForBuild(
      opened.dataOrNull!,
      folder: _NoFolder(),
      syncKey: null,
    );
    final error = result.errorOrNull;
    if (error is ZenValidationError &&
        error.message.contains('ZEN_SYNC') &&
        error.message.contains('release build')) {
      stdout.writeln('PROBE-OK refused: ${error.message}');
      exit(0);
    }
    stderr.writeln('PROBE-FAIL a release build with ZEN_SYNC was not refused: $result');
    exit(1);
  } finally {
    await dir.delete(recursive: true);
  }
}

/// Never reached: a refused plan fails before any transport.
class _NoFolder implements ZenFolderAccess {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('a refused plan must not touch the folder');
}
