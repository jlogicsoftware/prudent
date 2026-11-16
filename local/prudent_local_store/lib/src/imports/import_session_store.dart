import 'dart:io';

import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import '../../generated/prudent_local/v1/imports.pb.dart';

/// The second store of ADR-102: import sessions, on this device only (unit 8b, ADR-114).
///
/// A session holds normalised statement rows — personal data — for at most 24 hours (ADR-089).
/// They must never reach another device or the sync service, so they live in a store of their own
/// that **no transport is ever attached to**: this class opens that [ZenStore] itself and keeps it
/// private, so no code outside it can hand it to `ZenSync` or `ZenFolderCloud`. The store is still
/// encrypted on the device with its own key (the Local app loads it with `ZenDeviceStoreKey.load`
/// under a name of its own, unit 9), because a statement is as private as the ledger.
///
/// Only the records a commit writes travel, through the ledger's own synced store.
final class ImportSessionStore {
  /// The device name the store records; nothing reads it, as nothing syncs.
  static const deviceName = 'import-sessions';

  final ZenStore _zen;

  /// Every session, ended ones included (they keep their counts, never their rows).
  final ZenCollection<LocalImportSession> sessions;

  ImportSessionStore._(this._zen)
    : sessions = _zen.collection('import_sessions', LocalImportSession.fromBuffer);

  /// Opens (or creates) the session store in [directory], encrypted with [key] (32 bytes). It is
  /// never synced: there is no way to reach the store it opens.
  static Future<ZenResult<ImportSessionStore>> open(
    Directory directory, {
    required List<int> key,
  }) async => switch (await ZenStore.open(directory, deviceName: deviceName, key: key)) {
    ZenSuccess(:final data) => ZenResult.ok(ImportSessionStore._(data)),
    ZenFailure(:final error) => ZenResult.err(error),
  };

  /// A new random session id, 32 lower-case hex characters like every Local id.
  String newId() => _zen.newId();

  /// Writes [session] whole. Every change to a session is this one write of one record, which the
  /// store makes atomic: a phase, a row decision, and the end that deletes the rows.
  Future<ZenResult<LocalImportSession>> put(LocalImportSession session) {
    if (!LocalIds.isValid(session.id)) {
      return Future.value(
        ZenResult.err(const ZenValidationError('An import session id is a local id.')),
      );
    }
    return sessions.put(session.id, session);
  }

  Future<void> close() => _zen.close();
}
