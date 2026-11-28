import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/core/local_session.dart';
import 'package:prudent_ui/privacy/picker_copies.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_folder/zen_store_folder.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'offline_folder_cloud.dart';
import 'test_picker_copies.dart';

/// How a test's two devices reach each other: the development emulation of CloudKit, or the shared
/// folder transport every Android, Windows and Linux build uses.
///
/// **Only [folderCloud] devices are offline between syncs** ([OfflineFolderCloud], ADR-126). A
/// [sharedFolder] device keeps jZen's `ZenSharedFolderSync` running, because removing a device and
/// waiting for it to rest need that class itself (`LocalSession.removeDevice` asks for it), and a
/// running one syncs whenever a record becomes unsent. A test that needs two devices to act on
/// different reads uses [folderCloud]; the shared-folder tests (removing a device, erasing
/// everywhere) do not depend on it.
enum TransportKind { folderCloud, sharedFolder }

/// Two real Prudent Local sessions — real encrypted stores, real files, the real ledger — joined
/// through one real folder, as jZen's Local reference app tests its own. Nothing is mocked: a
/// conflict or an issue seen here is the one a person would see.
final class TwoLocalDevices {
  final Directory root;
  final Directory cloud;
  final LocalSession laptop;
  final LocalSession phone;
  final ZenLockStorage laptopSecrets;
  final ZenLockStorage phoneSecrets;

  TwoLocalDevices._(
    this.root,
    this.cloud,
    this.laptop,
    this.phone,
    this.laptopSecrets,
    this.phoneSecrets,
  );

  /// [phoneCopies] stands in for the removal of the phone's file-dialog copies.
  static Future<TwoLocalDevices> create([
    TransportKind kind = TransportKind.folderCloud,
    PickerCopies? phoneCopies,
  ]) async {
    final root = await Directory.systemTemp.createTemp(
      'prudent_local_two_devices',
    );
    final cloud = Directory('${root.path}/cloud')..createSync();

    // `pollEvery: null` stops only the polling; see [TransportKind] for what is offline.
    Future<ZenResult<ZenSyncTransport>> start(
      ZenStore store, {
      required ZenFolderAccess folder,
      required List<int>? syncKey,
    }) async => switch (kind) {
      TransportKind.folderCloud => ZenResult.ok(
        OfflineFolderCloud(store, cloud),
      ),
      TransportKind.sharedFolder => await ZenSharedFolderSync.start(
        store,
        ZenDirectoryAccess(cloud),
        syncKey: syncKey,
        pollEvery: null,
        watch: false,
      ),
    };

    Future<LocalSession> open(
      String name,
      String deviceName,
      ZenLockStorage secrets, [
      PickerCopies? copies,
    ]) async {
      final data = Directory('${root.path}/$name')..createSync();
      final session = await LocalSession.open(
        directory: Directory('${data.path}/prudent_local'),
        dataDirectory: data,
        deviceName: deviceName,
        storeKey: List.filled(32, name.length),
        secrets: secrets,
        start: start,
        pickerCopies: copies ?? testPickerCopies(data),
        restoreFolder: (reference) => ZenFolderChoice(
          reference: reference,
          label: 'cloud',
          access: ZenDirectoryAccess(Directory(reference)),
        ),
        pickFolder: () async => ZenFolderChoice(
          reference: cloud.path,
          label: 'cloud',
          access: ZenDirectoryAccess(cloud),
        ),
      );
      return session.dataOrNull!;
    }

    final laptopSecrets = ZenMemoryLockStorage();
    final phoneSecrets = ZenMemoryLockStorage();
    final laptop = await open('laptop', 'Laptop', laptopSecrets);
    final phone = await open('phone', 'Phone', phoneSecrets, phoneCopies);
    final devices = TwoLocalDevices._(
      root,
      cloud,
      laptop,
      phone,
      laptopSecrets,
      phoneSecrets,
    );
    await laptop.chooseFolder();
    await phone.chooseFolder();
    if (kind == TransportKind.sharedFolder) {
      await laptop.createSyncKey();
      await phone.adoptSyncKey(laptop.syncKey!);
    }
    return devices;
  }

  /// Both devices exchange what they hold, three rounds, so a change made on one has reached the
  /// other and anything that came back has been merged.
  Future<void> sync() async {
    for (var round = 0; round < 3; round++) {
      for (final device in [laptop, phone]) {
        final transport = device.transport!;
        await syncAndRest(device);
        // A sync that could not finish says so in its status; a test must not go on as if it had.
        expect(
          transport.status.state,
          ZenSyncState.upToDate,
          reason: '${device.deviceName}: ${transport.status}',
        );
      }
    }
  }

  /// Syncs [device] once and waits until its transport is at rest: a shared-folder sync can queue
  /// another (an erasure's cleanup, a merge that needs a send).
  static Future<void> syncAndRest(LocalSession device) async {
    final transport = device.transport!;
    await transport.syncNow();
    if (transport is ZenSharedFolderSync) await transport.whenIdle();
  }

  Future<void> dispose() async {
    await laptop.shutDown();
    await phone.shutDown();
    await root.delete(recursive: true);
  }
}
