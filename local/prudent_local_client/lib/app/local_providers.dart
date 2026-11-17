import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_save_file/zen_save_file.dart';
import 'package:zen_store_sync/zen_store_sync.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import '../core/local_session.dart';

/// This device's session: the store, the ledger, sync. Overridden by the composition root.
final localSessionProvider = Provider<LocalSession>((ref) {
  throw UnimplementedError('localSessionProvider must be overridden');
});

/// The PIN lock. Overridden by the composition root.
final pinLockProvider = Provider<ZenPinLock>((ref) {
  throw UnimplementedError('pinLockProvider must be overridden');
});

/// Where the app keeps its small secrets (the sync key, the folder, whether the first-run notice
/// was seen): the platform's secret storage, or memory in a test.
final lockStorageProvider = Provider<ZenLockStorage>((ref) {
  throw UnimplementedError('lockStorageProvider must be overridden');
});

/// The navigator of the whole app, for what is asked outside any screen's own context (an
/// integrity action that needs a name; `ZenIssueAction` gives none, jZenDev/jZen#256).
final rootNavigatorKeyProvider = Provider<GlobalKey<NavigatorState>>(
  (ref) => GlobalKey<NavigatorState>(),
);

/// Whether this device can confirm its owner (passcode, Face ID, Touch ID, Windows Hello), which is
/// how a forgotten PIN is reset without erasing (ADR-100 T4). A failure to find out answers false,
/// so the stronger warning is the one shown.
final ownerCheckAvailableProvider = FutureProvider<bool>((ref) async {
  final result = await ZenDeviceOwnerCheck().isAvailable();
  return result.dataOrNull ?? false;
});

/// The key under which the first-run notice (ADR-100 T2, T5) is remembered as seen.
const String firstRunSeenKey = 'prudent_local.first_run_seen';

/// Offers bytes to the person as a file they choose the place of (`zen_save_file`, jZenDev/jZen#246,
/// on every platform Prudent Local runs on). True when written, false when they cancelled; a
/// refused write throws. A test replaces it.
final saveFileProvider =
    Provider<Future<bool> Function(String name, Uint8List bytes)>(
      (ref) =>
          (name, bytes) =>
              zenSaveFile(name, bytes, mimeType: 'application/json'),
    );

/// What this build syncs through (`ZenSync.plan`, fixed at compile time by `ZEN_PLATFORM` and
/// `ZEN_SYNC`); null when the build's combination is refused. A test of the folder pages on a
/// macOS host overrides it.
final syncKindProvider = Provider<ZenSyncKind?>((ref) => ZenSync.plan.kind);
