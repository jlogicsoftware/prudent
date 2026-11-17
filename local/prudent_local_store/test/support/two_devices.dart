import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

/// One device: a real store in its own directory, encrypted with its own key, and the folder it
/// syncs through.
///
/// **A device is offline except inside [syncNow].** A running `ZenFolderCloud` syncs whenever a
/// record becomes unsent (`ZenStore.unsentChanges`), as CloudKit's engine does — `pollEvery: null`
/// stops only the polling. A transport left running would therefore carry every write to the folder
/// in the background, and a test's "offline" would hold or not depending on how that sync and the
/// next step interleave (main's run 44124134602: a repair that should not have seen another device's
/// repair did). So the transport is started for one sync and stopped after it; between syncs the
/// store works offline and its unsent records stay unsent (`ZenSyncTransport.stop`).
final class Device {
  final String name;
  final ZenStore zen;
  final PrudentLocalStore store;
  final Directory _folder;

  Device._(this.name, this.zen, this.store, this._folder);

  /// Sends what this device holds and fetches what the others sent, then goes offline again.
  Future<void> syncNow() async {
    final cloud = ok(await ZenFolderCloud.start(zen, _folder, pollEvery: null));
    try {
      await cloud.syncNow();
      // A sync that could not finish says so in its status; a test must not go on as if it had.
      expect(cloud.status.state, ZenSyncState.upToDate, reason: '$name: ${cloud.status}');
    } finally {
      await cloud.stop();
    }
  }

  /// The value [result] holds; fails the test with the error otherwise.
  static T ok<T>(ZenResult<T> result) => switch (result) {
    ZenSuccess(:final data) => data,
    ZenFailure(:final error) => fail(
      'expected success, got ${error.runtimeType}: ${error.message}',
    ),
  };

  IntegrityRunner integrity() => IntegrityRunner(store);
}

/// Two real sessions — two encrypted stores, each with its own key and directory — joined through
/// one real folder by jZen's `ZenFolderCloud`, the development stand-in for CloudKit. Nothing is
/// mocked, so a conflict or an issue seen here is the one a person would see. Modelled on jZen's
/// `apps/zen_demo_local/.../test/support/two_devices.dart`, without the Flutter session around it.
final class TwoDevices {
  final Directory root;
  final Device laptop;
  final Device phone;

  /// A third device, opened only when a test asks for one ([create] `withTablet`): the cases where
  /// three devices act on three different reads (ADR-120).
  final Device? tablet;

  TwoDevices._(this.root, this.laptop, this.phone, this.tablet);

  static Future<TwoDevices> create({bool withTablet = false}) async {
    final root = await Directory.systemTemp.createTemp('prudent_local_two_devices');
    final folder = Directory('${root.path}/cloud')..createSync();
    Future<Device> open(String name, int keyByte) async {
      final zen = Device.ok(
        await ZenStore.open(
          Directory('${root.path}/$name'),
          deviceName: name,
          key: List.filled(32, keyByte),
        ),
      );
      return Device._(name, zen, PrudentLocalStore(zen), folder);
    }

    return TwoDevices._(
      root,
      await open('Laptop', 1),
      await open('Phone', 2),
      withTablet ? await open('Tablet', 3) : null,
    );
  }

  /// Every device exchanges what it holds, three rounds, so a change made on one has reached the
  /// others and anything that came back has been merged.
  Future<void> sync() async {
    for (var round = 0; round < 3; round++) {
      for (final device in all) {
        await device.syncNow();
      }
    }
  }

  List<Device> get both => [laptop, phone];

  /// Every open device: [both], and the [tablet] when there is one.
  List<Device> get all => [laptop, phone, ?tablet];

  Future<void> dispose() async {
    for (final device in all) {
      await device.zen.close();
    }
    await root.delete(recursive: true);
  }
}

/// Synthetic data (ADR-088): made-up names and amounts, nothing real.
abstract final class Fixtures {
  static Account account(PrudentLocalStore store, {String name = 'Wallet'}) => Account(
    id: store.newId(),
    name: name,
    kind: AccountKind.ACCOUNT_KIND_CASH,
    active: true,
    includeInTotal: true,
    includeInOverview: true,
  );

  static AccountCurrency currency(
    String accountId,
    String code, {
    int opening = 0,
    int position = 0,
  }) => AccountCurrency(
    id: DerivedIds.accountCurrency(accountId, code),
    accountId: accountId,
    currency: code,
    openingMinor: Int64(opening),
    position: position,
  );

  static Category category(
    PrudentLocalStore store, {
    String title = 'Groceries',
    CategoryDirection kind = CategoryDirection.CATEGORY_DIRECTION_EXPENSE,
  }) => Category(id: store.newId(), title: title, iconKey: 'cart', kind: kind);

  static Record record(
    PrudentLocalStore store, {
    required String accountId,
    String currency = 'PLN',
    int amount = -1250,
    String? categoryId,
    String title = 'Bread',
  }) {
    final record = Record(
      id: store.newId(),
      title: title,
      posting: Posting(accountId: accountId, currency: currency, amountMinor: Int64(amount)),
      date: '2026-11-02',
    );
    if (categoryId != null) record.categoryId = categoryId;
    return record;
  }

  /// An account holding PLN, a category, and one record in both, written on [device].
  static Future<({Account account, Category category, Record record})> ledger(Device device) async {
    final store = device.store;
    final account = Device.ok(await store.putAccount(Fixtures.account(store)));
    Device.ok(await store.putAccountCurrency(Fixtures.currency(account.id, 'PLN', opening: 10000)));
    final category = Device.ok(await store.putCategory(Fixtures.category(store)));
    final record = Device.ok(
      await store.putRecord(Fixtures.record(store, accountId: account.id, categoryId: category.id)),
    );
    return (account: account, category: category, record: record);
  }
}
