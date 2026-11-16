import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

/// One device: a real store in its own directory, encrypted with its own key, and its sync.
final class Device {
  final String name;
  final ZenStore zen;
  final PrudentLocalStore store;
  final ZenFolderCloud cloud;

  Device._(this.name, this.zen, this.store, this.cloud);

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

  TwoDevices._(this.root, this.laptop, this.phone);

  static Future<TwoDevices> create() async {
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
      // `pollEvery: null`: a test syncs when it says so, which is what makes "offline" exact.
      final cloud = Device.ok(await ZenFolderCloud.start(zen, folder, pollEvery: null));
      return Device._(name, zen, PrudentLocalStore(zen), cloud);
    }

    return TwoDevices._(root, await open('Laptop', 1), await open('Phone', 2));
  }

  /// Both devices exchange what they hold, three rounds, so a change made on one has reached the
  /// other and anything that came back has been merged.
  Future<void> sync() async {
    for (var round = 0; round < 3; round++) {
      await laptop.cloud.syncNow();
      await phone.cloud.syncNow();
    }
  }

  List<Device> get both => [laptop, phone];

  Future<void> dispose() async {
    for (final device in both) {
      await device.cloud.stop();
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
