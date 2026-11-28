import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_ui/privacy/picker_copies.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_folder/zen_store_folder.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'protect_store_directory.dart';
import 'sync_starter.dart';

/// What an erasure that got through leaves on this device.
enum LocalErasure {
  /// No temporary copy a file dialog made is left.
  complete,

  /// The data is erased, but such a copy may still be there (ADR-138). The next launch tries again.
  copyMayRemain,
}

/// Everything this device holds: the open store, Prudent's collections and ledger on it, the sync
/// key and chosen folder, and the transport keeping it in step with the person's other devices.
///
/// Screens read it and listen to it; they never open a store or start a transport themselves. Sync
/// is restarted here whenever its inputs change (a folder chosen, a key made, joined or replaced,
/// the copy erased), and only ever through [SyncStarter] — by default `ZenSync.start` (jZen
/// ADR-079). The shape is jZen's Local reference app's `DeviceSession`; what Prudent adds is the
/// ledger, removing a device (a new sync key), erasing everywhere, and the folder refusal of ADR-100
/// T6.
///
/// Nothing here logs what the store holds, the sync key or a pairing code (ADR-100 T21): a failure
/// carries the store's own error, whose text names files and classes, never content.
final class LocalSession extends ChangeNotifier {
  static const String _keyName = 'prudent_local.sync_key';
  static const String _folderName = 'prudent_local.sync_folder';

  /// Where the store lives: a directory of its own inside [dataDirectory].
  final Directory directory;

  /// The app's own data directory. A sync folder inside it is refused (ADR-100 T6): the folder
  /// would be the store's neighbour, deleted with the app and never seen by a sync service.
  final Directory dataDirectory;

  /// What the person's other devices call this one in a conflict.
  final String deviceName;

  final List<int> _storeKey;
  final ZenLockStorage _secrets;
  final SyncStarter _start;
  final ZenFolderChoice Function(String reference) _restoreFolder;
  final Future<ZenFolderChoice?> Function() _pickFolder;
  final PickerCopies _pickerCopies;

  ZenStore _store;
  late PrudentLocalStore _prudent;
  late Ledger _ledger;
  late ImportWorkflow _imports;
  late PlanLedger _plans;
  late Analytics _analytics;
  StreamSubscription<void>? _erasures;
  Timer? _sweep;
  ZenSyncTransport? _transport;
  String? _syncProblem;
  ZenFolderChoice? _folder;
  List<int>? _syncKey;
  int _generation = 0;
  bool _closed = false;

  LocalSession._(
    this.directory,
    this.dataDirectory,
    this.deviceName,
    this._storeKey,
    this._secrets,
    this._start,
    this._restoreFolder,
    this._pickFolder,
    this._pickerCopies,
    this._store,
  ) {
    _attach();
  }

  /// Opens the store in [directory] and starts sync. Fails, writing nothing over the data, if the
  /// store cannot be read: a wrong key or a damaged file is never answered with an empty store
  /// (ADR-100 T8–T10). On iOS it fails too if the directory cannot be given Data Protection first
  /// ([protectStoreDirectory]): the store is then not opened and no file's content is changed, though
  /// iOS may already have created the directory or protected some of its files.
  static Future<ZenResult<LocalSession>> open({
    required Directory directory,
    required Directory dataDirectory,
    required String deviceName,
    required List<int> storeKey,
    required ZenLockStorage secrets,
    SyncStarter start = startSyncForBuild,
    ZenFolderChoice Function(String reference)? restoreFolder,
    Future<ZenFolderChoice?> Function()? pickFolder,
    PickerCopies pickerCopies = const PickerCopies(),
  }) async {
    final ZenStore store;
    switch (await _openStore(
      directory,
      deviceName: deviceName,
      key: storeKey,
    )) {
      case ZenSuccess(:final data):
        store = data;
      case ZenFailure(:final error):
        return ZenResult.err(error);
    }
    final session = LocalSession._(
      directory,
      dataDirectory,
      deviceName,
      storeKey,
      secrets,
      start,
      restoreFolder ?? ZenFolderPicker.restore,
      pickFolder ?? ZenFolderPicker.pick,
      pickerCopies,
      store,
    );
    try {
      final key = await secrets.read(_keyName);
      if (key != null) session._syncKey = base64Decode(key);
      final folder = await secrets.read(_folderName);
      if (folder != null) session._folder = session._restoreFolder(folder);
    } on Object catch (e, stack) {
      await session._detach();
      await store.close();
      return ZenResult.err(
        ZenUnknownError(
          'This device\'s sync settings cannot be read: ${e.runtimeType}',
          stackTrace: stack,
        ),
      );
    }
    await session._restartSync();
    return ZenResult.ok(session);
  }

  /// The one way this session opens a store, at launch and after an erasure alike: the directory is
  /// protected first, so no file is written into one that is not.
  static Future<ZenResult<ZenStore>> _openStore(
    Directory directory, {
    required String deviceName,
    required List<int> key,
  }) async {
    final protected = await protectStoreDirectory(directory);
    if (protected case ZenFailure(:final error)) return ZenResult.err(error);
    return ZenStore.open(directory, deviceName: deviceName, key: key);
  }

  void _attach() {
    _prudent = PrudentLocalStore(_store);
    _ledger = Ledger(_prudent);
    _plans = PlanLedger(_prudent);
    _analytics = Analytics(_prudent);
    // Unit 8b (ADR-114): import sessions live in the store's device-only collection, which
    // PrudentLocalStore declared above, before any transport starts. An overdue session is ended at
    // launch and every hour after, as the server's sweep does; a read ends one on its own as well.
    _imports = ImportWorkflow(
      ledger: _prudent,
      nowMs: () => DateTime.now().millisecondsSinceEpoch,
    );
    unawaited(_expireImports());
    _sweep = Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(_expireImports()),
    );
    _erasures = _store.erasures.listen((_) {
      if (!_closed) notifyListeners();
    });
    _generation++;
  }

  /// Ends every overdue import session. A failure is logged as its class only (ADR-100 T21) and the
  /// next sweep tries again; the lazy expiry on a read still holds meanwhile.
  Future<void> _expireImports() async {
    if (_store.erasedEverywhere) return;
    final result = await _imports.expireDue();
    if (result case ZenFailure(:final error)) {
      developer.log(
        'import sweep failed: ${error.runtimeType}',
        name: 'prudent',
      );
    }
  }

  Future<void> _detach() async {
    _sweep?.cancel();
    _sweep = null;
    final erasures = _erasures;
    _erasures = null;
    await erasures?.cancel();
  }

  /// The open store. Replaced by a new one when this device's copy is erased: read it each time.
  ZenStore get store => _store;

  /// Prudent's collections on [store].
  PrudentLocalStore get prudent => _prudent;

  /// The ledger over [prudent] (ADR-113).
  Ledger get ledger => _ledger;

  /// Spend by category and by period over [prudent] (unit 7, ADR-118).
  Analytics get analytics => _analytics;

  /// Plans, occurrences and reminders over [prudent] (unit 6b, ADR-119).
  PlanLedger get plans => _plans;

  /// Statement import over [prudent] (unit 8b, ADR-114).
  ImportWorkflow get imports => _imports;

  /// Changes each time the store is replaced, so whatever was read from the old one is read again.
  int get generation => _generation;

  /// Null while sync could not start; [syncProblem] says why.
  ZenSyncTransport? get transport => _transport;
  String? get syncProblem => _syncProblem;

  ZenFolderChoice? get folder => _folder;
  bool get hasSyncKey => _syncKey != null;

  /// The key a new device joins with. Held only by devices that are part of the group.
  List<int>? get syncKey =>
      _syncKey == null ? null : List.unmodifiable(_syncKey!);

  /// Whether this device can replace the sync key to remove a device (ADR-100 T3): only the shared
  /// folder transport has a key to replace. CloudKit's keys are the person's iCloud Keychain's, so a
  /// device is removed from the Apple ID instead (jZen ADR-085).
  bool get canRemoveDevice =>
      _transport is ZenSharedFolderSync && _syncKey != null;

  /// Whether the person's data was erased everywhere — here, or on another device whose erasure
  /// reached this one. The store then holds nothing and refuses every write until [startAfresh].
  bool get erasedEverywhere => _store.erasedEverywhere;

  /// Lets the person pick the folder, keeps the choice and restarts sync through it. Succeeds with
  /// `false` when they cancelled, and fails when the dialog failed, keeping the choice failed, or the
  /// folder is inside the app's own data directory (ADR-100 T6).
  Future<ZenResult<bool>> chooseFolder() async {
    final ZenFolderChoice? choice;
    try {
      choice = await _pickFolder();
      if (choice == null) return const ZenResult.ok(false);
      if (isInsideAppData(choice.reference, dataDirectory.path)) {
        return const ZenResult.err(
          ZenValidationError(
            'The sync folder cannot be inside the app\'s own data.',
            internalData: {'code': 'folder_inside_app_data'},
          ),
        );
      }
      await _secrets.write(_folderName, choice.reference);
    } on Object catch (e, stack) {
      return ZenResult.err(
        ZenUnknownError(
          'The folder cannot be chosen: ${e.runtimeType}',
          stackTrace: stack,
        ),
      );
    }
    _folder = choice;
    await _restartSync();
    return const ZenResult.ok(true);
  }

  /// Whether [reference] names a folder inside [appData], compared as absolute, normalised paths. A
  /// content URI (Android's folder access) is never a path inside the app's data.
  @visibleForTesting
  static bool isInsideAppData(String reference, String appData) {
    if (reference.contains('://')) return false;
    final folder = _normalised(reference);
    final data = _normalised(appData);
    final separator = Platform.pathSeparator;
    return folder == data ||
        folder.startsWith(data.endsWith(separator) ? data : '$data$separator');
  }

  static String _normalised(String path) =>
      File(path).absolute.uri.normalizePath().toFilePath();

  /// Makes this device the first of the group: a fresh 32-byte sync key, kept in the keystore.
  Future<ZenResult<void>> createSyncKey() {
    final random = Random.secure();
    return adoptSyncKey(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  /// Joins the group whose sync [key] a paired device showed (`ZenJoinScreen`'s `onKey`).
  Future<ZenResult<void>> adoptSyncKey(List<int> key) async {
    try {
      await _secrets.write(_keyName, base64Encode(key));
    } on Object catch (e, stack) {
      return ZenResult.err(
        ZenUnknownError(
          'The sync key cannot be kept: ${e.runtimeType}',
          stackTrace: stack,
        ),
      );
    }
    _syncKey = List<int>.of(key);
    await _restartSync();
    return const ZenResult.ok(null);
  }

  /// Removes a lost, sold or shared device from the group (ADR-100 T3, jZenDev/jZen#237): replaces
  /// the sync key, so a device that holds the old one can no longer read or write what the others
  /// share. The new key is kept before anything in the folder changes; every remaining device then
  /// stops with "key replaced" until it is paired again with this one.
  ///
  /// What it cannot do is said by the screen, never claimed away: take back what the removed device
  /// already read, or stop it reading the folder's ciphertext while the folder is shared with it.
  Future<ZenResult<void>> removeDevice() async {
    final transport = _transport;
    if (transport is! ZenSharedFolderSync || _syncKey == null) {
      return const ZenResult.err(
        ZenValidationError(
          'Only a device that syncs through a folder has a key to replace.',
        ),
      );
    }
    final replaced = await transport.rekey(
      persist: (key) async {
        await _secrets.write(_keyName, base64Encode(key));
        _syncKey = List<int>.of(key);
      },
    );
    if (!_closed) notifyListeners();
    return switch (replaced) {
      ZenSuccess() => const ZenResult.ok(null),
      ZenFailure(:final error) => ZenResult.err(error),
    };
  }

  /// Deletes this device's copy and starts over, empty. The sync key and folder stay, so what the
  /// other devices hold comes back. Never routed through the sync engine: a deletion would erase the
  /// data on every device (`ZenPinLock`'s contract for "Forgot PIN?").
  ///
  /// Copies a file dialog left are removed too (ADR-138). A failure here means the store was not
  /// erased or could not be opened again, and nothing else: a copy that stays is
  /// [LocalErasure.copyMayRemain] of a success, so that "Forgot PIN?", which asks only whether the
  /// data went, is never held back by it.
  Future<ZenResult<LocalErasure>> eraseThisDevice() async {
    await _stopSync();
    await _detach();
    await _store.close();
    final erased = await ZenStore.erase(directory);
    final copies = await _pickerCopies.remove();
    // Reopen either way: after a failed erase what is still there must keep working.
    final reopened = await _reopen();
    if (erased case ZenFailure(:final error)) return ZenResult.err(error);
    if (reopened case ZenFailure(:final error)) return ZenResult.err(error);
    return ZenResult.ok(_after(copies));
  }

  static LocalErasure _after(ZenResult<void> copies) =>
      copies is ZenFailure ? LocalErasure.copyMayRemain : LocalErasure.complete;

  /// Erases the person's data on every device and in the sync place, not only here (ADR-100 T24,
  /// jZenDev/jZen#239). Irreversible. Goes through the transport where there is one, so the shared
  /// place is cleaned and the other devices are told; without one (sync never started), only this
  /// store is marked, and the screen says the other devices are not reached.
  ///
  /// Afterwards the store holds nothing and refuses writes; [startAfresh] makes a new one. Copies a
  /// file dialog left on this device are removed too, whether or not the erasure got through
  /// (ADR-138); a failure is the erasure's alone, and a copy that stays is
  /// [LocalErasure.copyMayRemain].
  Future<ZenResult<LocalErasure>> eraseEverywhere() async {
    final transport = _transport;
    final result = transport != null
        ? await transport.eraseEverywhere()
        : await _store.eraseEverywhere();
    final copies = await _pickerCopies.remove();
    if (!_closed) notifyListeners();
    if (result case ZenFailure(:final error)) return ZenResult.err(error);
    return ZenResult.ok(_after(copies));
  }

  /// After an erasure everywhere: erases this device's directory, forgets the sync key (an erased key
  /// is never reused, jZen ADR-085), and opens a new, empty store. The folder choice stays.
  Future<ZenResult<LocalErasure>> startAfresh() async {
    try {
      await _secrets.delete(_keyName);
    } on Object catch (e, stack) {
      return ZenResult.err(
        ZenUnknownError(
          'The old sync key cannot be removed: ${e.runtimeType}',
          stackTrace: stack,
        ),
      );
    }
    _syncKey = null;
    return eraseThisDevice();
  }

  Future<ZenResult<void>> _reopen() async {
    switch (await _openStore(
      directory,
      deviceName: deviceName,
      key: _storeKey,
    )) {
      case ZenSuccess(:final data):
        _store = data;
        _attach();
      case ZenFailure(:final error):
        // The old store is closed and nothing replaced it: say so rather than carry on.
        if (!_closed) notifyListeners();
        return ZenResult.err(error);
    }
    await _restartSync();
    return const ZenResult.ok(null);
  }

  Future<void> _restartSync() async {
    await _stopSync();
    final ZenFolderAccess folder = _folder?.access ?? ZenDirectoryAccess(null);
    final result = await _start(_store, folder: folder, syncKey: _syncKey);
    switch (result) {
      case ZenSuccess(:final data):
        _transport = data;
        _syncProblem = null;
      case ZenFailure(:final error):
        _transport = null;
        _syncProblem = error.message;
    }
    if (!_closed) notifyListeners();
  }

  Future<void> _stopSync() async {
    final transport = _transport;
    _transport = null;
    if (transport != null) await transport.stop();
  }

  /// Stops sync and closes the store; the session is unusable afterwards.
  Future<void> shutDown() async {
    _closed = true;
    await _stopSync();
    await _detach();
    await _store.close();
    super.dispose();
  }
}
