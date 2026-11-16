// Every write is held to what it was decided against, inside the store's write turn (jZenDev/jZen#251,
// ADR-115), on two real encrypted stores synced through jZen's ZenFolderCloud.
//
// The interleaving that matters is a sync's receive queued *before* a write and run *after* the
// rules were checked: the operation reads the record, decides, and its write waits behind the
// receive. ZenFolderCloud reads its folder asynchronously, so it gives no point at which to step in
// between; these tests queue the receive themselves, with exactly the payload the other device's
// store hands its transport, and then let ZenFolderCloud carry everything else. The repair case at
// the end runs wholly through ZenFolderCloud: there the gap is between finding an issue and acting.
import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/settings.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import 'support/two_devices.dart';

void main() {
  late TwoDevices devices;
  late Ledger laptop;
  late Ledger phone;
  setUp(() async {
    devices = await TwoDevices.create();
    laptop = Ledger(devices.laptop.store);
    phone = Ledger(devices.phone.store);
  });
  tearDown(() async => devices.dispose());

  /// Queues on the laptop the receive of what the phone holds for [names], as its transport would
  /// deliver it; it runs only after whatever the laptop has already queued.
  Future<ZenResult<ZenSyncReport>> queuePhoneChanges(List<String> names) =>
      devices.laptop.zen.receive([
        for (final name in names)
          ZenIncomingRecord(name, devices.phone.zen.outgoing(name)!.payload, null),
      ]);

  /// What [device] holds in the ledger's collections, as bytes: "everything as it was" is exact.
  Map<String, List<int>> snapshot(Device device) => {
    for (final a in Device.ok(device.store.accounts.list())) 'accounts:${a.id}': a.writeToBuffer(),
    for (final c in Device.ok(device.store.accountCurrencies.list()))
      'account_currencies:${c.id}': c.writeToBuffer(),
    for (final c in Device.ok(device.store.categories.list()))
      'categories:${c.id}': c.writeToBuffer(),
    for (final r in Device.ok(device.store.records.list())) 'records:${r.id}': r.writeToBuffer(),
    for (final t in Device.ok(device.store.transfers.list()))
      'transfers:${t.id}': t.writeToBuffer(),
    for (final s in Device.ok(device.store.settings.list())) 'settings:${s.id}': s.writeToBuffer(),
  };

  void expectRefused<T>(ZenResult<T> result, {required int status, required String rule}) {
    final error = result.errorOrNull;
    expect(error, isNotNull, reason: 'the write went through');
    expect(LedgerErrors.statusOf(error!), status, reason: error.message);
    expect(error.internalData?['rule'], rule);
  }

  void expectNoConflicts() {
    for (final device in devices.both) {
      expect(device.zen.conflictCount, 0, reason: 'conflicts on ${device.name}');
    }
  }

  /// An account holding PLN 100.00, a category, and one record in both, made on the laptop and
  /// synced to the phone.
  Future<({String account, String category, String record})> ledger() async {
    final account = Device.ok(
      await laptop.createAccount(
        wire.CreateAccountRequest(
          name: 'Wallet',
          type: wire.AccountType.ACCOUNT_TYPE_CASH,
          isActive: true,
          balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(10000))],
        ),
      ),
    ).value;
    final category = Device.ok(
      await laptop.createCategory(wire.CreateCategoryRequest(title: 'Food', iconKey: 'food')),
    );
    final record = Device.ok(await laptop.createRecord(_recordRequest(account.id, category.id)));
    await devices.sync();
    return (account: account.id, category: category.id, record: record.id);
  }

  group('an edit cannot bring back a record a sync just deleted', () {
    test('a record: 404, it stays deleted on both devices, and nothing conflicts', () async {
      final l = await ledger();
      Device.ok(await phone.deleteRecord(l.record));

      final received = queuePhoneChanges(['records:${l.record}']);
      // The ledger's own check passes here: the laptop still holds the record when it reads.
      final edit = laptop.updateRecord(
        l.record,
        _recordUpdate(l.account, l.category, title: 'Rye'),
      );

      expectRefused(await edit, status: 404, rule: '5.15');
      expect((await received).isSuccess, isTrue);
      await devices.sync();
      for (final device in devices.both) {
        expect(device.store.records.get(l.record).errorOrNull, isA<ZenNotFoundError>());
      }
      expectNoConflicts();
    });

    test('a category restore: 404, and the category is not resurrected', () async {
      final l = await ledger();
      Device.ok(await laptop.archiveCategory(l.category));
      Device.ok(await laptop.deleteRecord(l.record)); // so the phone may delete the category
      await devices.sync();
      Device.ok(await phone.deleteCategory(l.category));

      final received = queuePhoneChanges(['categories:${l.category}']);
      final restore = laptop.restoreCategory(l.category);

      expectRefused(await restore, status: 404, rule: '5.38');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(device.store.categories.get(l.category).errorOrNull, isA<ZenNotFoundError>());
      }
      expectNoConflicts();
    });
  });

  group('a write never goes over an edit a sync merged in meanwhile', () {
    test('a record: 409 under X.7, and the other device\'s note survives on both', () async {
      final l = await ledger();
      Device.ok(
        await phone.updateRecord(l.record, _recordUpdate(l.account, l.category, note: 'rye')),
      );

      final received = queuePhoneChanges(['records:${l.record}']);
      final edit = laptop.updateRecord(
        l.record,
        _recordUpdate(l.account, l.category, title: 'Baguette'),
      );

      expectRefused(await edit, status: 409, rule: 'X.7');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        final r = Device.ok(device.store.records.get(l.record));
        expect((r.title, r.note), ('Bread', 'rye'));
      }
      expectNoConflicts();
    });

    test('the settings: the default account another device chose is not written away', () async {
      final l = await ledger();
      Device.ok(
        await phone.updateAccount(
          l.account,
          wire.UpdateAccountRequest(
            name: 'Wallet',
            type: wire.AccountType.ACCOUNT_TYPE_CASH,
            isActive: true,
            isDefault: true,
            balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(10000))],
          ),
        ),
      );

      final received = queuePhoneChanges(['settings:${DerivedIds.settings}']);
      final update = laptop.updateSettings(wire.UpdateSettingsRequest(mainCurrency: 'EUR'));

      expectRefused(await update, status: 409, rule: 'X.7');
      await received;
      final settings = Device.ok(devices.laptop.store.settings.get(DerivedIds.settings));
      expect((settings.hasMainCurrency(), settings.defaultAccountId), (false, l.account));
    });

    test('an account deleted with its records: a record a sync moved to another account refuses '
        'the whole batch, and nothing of it is written', () async {
      final l = await ledger();
      final other = Device.ok(
        await laptop.createAccount(
          wire.CreateAccountRequest(
            name: 'Bank',
            type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
            balances: [wire.CurrencyBalance(currency: 'PLN')],
          ),
        ),
      ).value;
      await devices.sync();
      Device.ok(await phone.updateRecord(l.record, _recordUpdate(other.id, l.category)));
      final before = snapshot(devices.laptop);

      final received = queuePhoneChanges(['records:${l.record}']);
      final delete = laptop.deleteAccount(l.account, deleteRecords: true);

      expectRefused(await delete, status: 409, rule: 'X.7');
      expect(snapshot(devices.laptop).keys, before.keys, reason: 'nothing deleted');
      await received;
      final moved = Device.ok(devices.laptop.store.records.get(l.record));
      expect(moved.posting.accountId, other.id, reason: 'the move arrived, untouched');
      expect(Device.ok(devices.laptop.store.accounts.get(l.account)).name, 'Wallet');
      await devices.sync();
      expectNoConflicts();
    });
  });

  test(
    '"Start fresh" while the other device\'s identical starters arrive writes them once',
    () async {
      Device.ok(await phone.startFresh());
      final names = [
        for (final c in Device.ok(devices.phone.store.categories.list())) 'categories:${c.id}',
      ];
      expect(names, hasLength(5));

      final received = queuePhoneChanges(names);
      final fresh = laptop.startFresh();

      expect((await fresh).isSuccess, isTrue, reason: 'writing the same starters is no edit');
      await received;
      await devices.sync();
      for (final device in devices.both) {
        expect(Device.ok(device.store.categories.list()), hasLength(5));
      }
      expectNoConflicts();
    },
  );

  test('a store rule is checked in the write\'s turn: a transfer that arrives before an add of the '
      'same id is never edited by it', () async {
    final l = await ledger();
    final transfer = Transfer(
      id: devices.phone.store.newId(),
      title: 'Savings',
      date: '2026-11-02',
      source: Posting(accountId: l.account, currency: 'PLN', amountMinor: Int64(500)),
      destination: Posting(accountId: l.account, currency: 'PLN', amountMinor: Int64(500)),
    );
    Device.ok(await devices.phone.store.addTransfer(transfer));

    final received = queuePhoneChanges(['transfers:${transfer.id}']);
    final add = devices.laptop.store.addTransfer(transfer.deepCopy()..title = 'Other');

    expect((await add).errorOrNull, isA<ZenValidationError>());
    expect((await add).errorOrNull!.message, contains('written once'));
    await received;
    expect(Device.ok(devices.laptop.store.transfers.get(transfer.id)).title, 'Savings');
  });

  test('a repair built from what the check saw is refused once a sync changed that record — '
      'wholly through ZenFolderCloud', () async {
    final l = await ledger();
    final store = devices.laptop.store;
    final category = Device.ok(store.categories.get(l.category));
    Device.ok(
      await store.putCategory(
        category.deepCopy()..kind = CategoryDirection.CATEGORY_DIRECTION_EXPENSE,
        expect: WriteExpects.asRead(category),
      ),
    );
    Device.ok(
      await store.putRecord(
        Record(
          id: store.newId(),
          title: 'Refund',
          posting: Posting(accountId: l.account, currency: 'PLN', amountMinor: Int64(900)),
          date: '2026-11-03',
          categoryId: l.category,
        ),
      ),
    );
    await devices.sync();
    final issue = Device.ok(devices.laptop.integrity().evaluate())
        .singleWhere((i) => i.code == 'category.kind_refuses_sign');

    // The phone renames the category; ZenFolderCloud brings it to the laptop.
    Device.ok(
      await phone.updateCategory(
        l.category,
        wire.UpdateCategoryRequest(
          title: 'Groceries',
          iconKey: 'food',
          kind: wire.CategoryKind.CATEGORY_KIND_EXPENSE,
        ),
      ),
    );
    await devices.sync();

    final result = await issue.actions.singleWhere((a) => a.code == 'category_takes_both').run();

    expect(result.errorOrNull, isA<ZenConflictError>());
    for (final device in devices.both) {
      final c = Device.ok(device.store.categories.get(l.category));
      expect((c.title, c.kind), ('Groceries', CategoryDirection.CATEGORY_DIRECTION_EXPENSE));
    }
    expectNoConflicts();
  });
}

wire.CreateRecordRequest _recordRequest(String account, String category) =>
    wire.CreateRecordRequest(
      title: 'Bread',
      amountMinor: Int64(-1250),
      date: '2026-11-02',
      categoryId: category,
      accountId: account,
      currency: 'PLN',
    );

wire.UpdateRecordRequest _recordUpdate(
  String account,
  String category, {
  String title = 'Bread',
  String? note,
}) => wire.UpdateRecordRequest(
  title: title,
  amountMinor: Int64(-1250),
  date: '2026-11-02',
  categoryId: category,
  accountId: account,
  currency: 'PLN',
  note: note,
);
