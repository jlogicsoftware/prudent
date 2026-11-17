import 'dart:async';
import 'dart:io';

import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

/// jZen's `ZenFolderCloud`, running only while a test asks it to sync, so a device is offline
/// between its syncs.
///
/// A running `ZenFolderCloud` syncs whenever a record becomes unsent (`ZenStore.unsentChanges`), as
/// CloudKit's engine does; `pollEvery: null` stops only the polling. Kept running, it would carry
/// every write to the folder in the background, and whether another device read it would depend on
/// how that sync and the test's next step interleave (ADR-126, main's run 44124134602). So each
/// [syncNow] starts the transport, syncs, and stops it again (`ZenSyncTransport.stop`: the store
/// works offline and its unsent records stay unsent); [eraseEverywhere] does the same around the
/// erasure. [status] is the status the last of them ended with.
final class OfflineFolderCloud implements ZenSyncTransport {
  final ZenStore _store;
  final Directory _folder;
  final StreamController<ZenSyncStatus> _statusChanges =
      StreamController<ZenSyncStatus>.broadcast();
  ZenSyncStatus _status = ZenSyncStatus.off;
  Future<void> _running = Future<void>.value();
  bool _stopped = false;

  OfflineFolderCloud(this._store, this._folder);

  @override
  ZenSyncStatus get status => _status;

  @override
  Stream<ZenSyncStatus> get statusChanges => _statusChanges.stream;

  @override
  Future<void> syncNow() => _online((cloud) async {
    await cloud.syncNow();
    return null;
  }).then((_) {});

  @override
  Future<ZenResult<void>> eraseEverywhere() async {
    final result = await _online((cloud) => cloud.eraseEverywhere());
    return result ??
        const ZenResult.err(ZenStorageError('The transport is stopped.'));
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await _running;
    _setStatus(ZenSyncStatus.off);
    await _statusChanges.close();
  }

  /// Runs [action] on a `ZenFolderCloud` started for it and stopped after it, one at a time.
  Future<T?> _online<T>(Future<T> Function(ZenFolderCloud cloud) action) {
    final run = _running.then((_) async {
      if (_stopped) return null;
      final cloud = switch (await ZenFolderCloud.start(
        _store,
        _folder,
        pollEvery: null,
      )) {
        ZenSuccess(:final data) => data,
        ZenFailure(:final error) => throw StateError(error.message),
      };
      try {
        final result = await action(cloud);
        _setStatus(cloud.status);
        return result;
      } finally {
        await cloud.stop();
      }
    });
    _running = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  void _setStatus(ZenSyncStatus status) {
    if (status == _status || _statusChanges.isClosed) return;
    _status = status;
    _statusChanges.add(status);
  }
}
