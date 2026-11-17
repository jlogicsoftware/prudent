import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store_key/zen_store_key.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'local_session.dart';

/// What the app needs before it can show a screen.
final class LocalBoot {
  final LocalSession session;
  final ZenPinLock lock;

  const LocalBoot(this.session, this.lock);
}

/// Opens this device's store and PIN lock, in the app's own data directory.
///
/// Any failure — a store key that cannot be read (no secret service on Linux, a locked keyring, a
/// Windows "nothing stored" beside existing files, an OS backup restored without its key) or a file
/// that does not decrypt — stops the open and is shown as it is (ADR-100 T8, T9, T10). Nothing here
/// makes a new key or an empty store over existing data, and nothing erases on its own
/// (jZen ADR-075, ADR-065).
Future<ZenResult<LocalBoot>> bootPrudentLocal({ZenLockStorage? secrets}) async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory(
    '${support.path}${Platform.pathSeparator}prudent_local',
  );
  final storeKey = await ZenDeviceStoreKey.load(dataDirectory: directory);
  if (storeKey case ZenFailure(:final error)) return ZenResult.err(error);

  final storage = secrets ?? ZenSecureLockStorage();
  final opened = await LocalSession.open(
    directory: directory,
    dataDirectory: support,
    deviceName: _deviceName(),
    storeKey: storeKey.dataOrNull!,
    secrets: storage,
  );
  final LocalSession session;
  switch (opened) {
    case ZenSuccess(:final data):
      session = data;
    case ZenFailure(:final error):
      return ZenResult.err(error);
  }
  final lock = await ZenPinLock.load(
    storage: storage,
    eraseDeviceCopy: session.eraseThisDevice,
  );
  switch (lock) {
    case ZenSuccess(:final data):
      return ZenResult.ok(LocalBoot(session, data));
    case ZenFailure(:final error):
      await session.shutDown();
      return ZenResult.err(error);
  }
}

// What another device shows in a conflict. A machine's host name is the one name a person already
// knows it by; it is only ever shown to them, never sent anywhere (there is no server).
String _deviceName() {
  final host = Platform.localHostname.trim();
  return host.isEmpty ? Platform.operatingSystem : host;
}
