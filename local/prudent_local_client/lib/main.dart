import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'app/local_composition.dart';
import 'app/prudent_local_app.dart';
import 'app/start_failed_app.dart';
import 'core/local_boot.dart';

/// Prudent Local: no server, no sign-in. The app opens its own encrypted store and syncs it through
/// the transport its build names (ADR-101, jZen ADR-073). Nothing here reaches a server; the
/// pubspec has no package that could (`task verify:boundaries`, check F).
Future<void> main() async {
  // Plugins (the keystore, the data directory) are reached over platform channels.
  WidgetsFlutterBinding.ensureInitialized();
  // `intl`'s DateFormat needs symbol data for uk and pl, which the shared screens format dates in.
  await initializeDateFormatting();
  await _start();
}

Future<void> _start() async {
  final storage = ZenSecureLockStorage();
  switch (await bootPrudentLocal(secrets: storage)) {
    case ZenSuccess(:final data):
      runApp(
        ProviderScope(
          overrides: localOverrides(
            session: data.session,
            lock: data.lock,
            storage: storage,
          ),
          child: const PrudentLocalApp(),
        ),
      );
    case ZenFailure(:final error):
      // A ProviderScope with nothing in it: the failure page reads no provider, and the analyzer's
      // riverpod rule wants every app rooted in one.
      runApp(
        ProviderScope(
          child: StartFailedApp(
            error: error,
            onRetry: _start,
            onErase: _eraseAndStart,
          ),
        ),
      );
  }
}

/// The person's own step after a store that cannot be opened (ADR-100 T9, T10): this device's copy
/// is erased, never automatically, and the app opens again, empty, to sync back what the other
/// devices hold. The key goes with the files, so a new one is made beside an empty directory only.
Future<void> _eraseAndStart() async {
  final support = await getApplicationSupportDirectory();
  await ZenStore.erase(
    Directory('${support.path}${Platform.pathSeparator}prudent_local'),
  );
  await _start();
}
