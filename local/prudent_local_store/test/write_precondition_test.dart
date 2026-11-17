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

  // ── Review of #264: deletes, and every write path that carries a precondition ─────────────────

  Future<String> secondAccount() async => Device.ok(
    await laptop.createAccount(
      wire.CreateAccountRequest(
        name: 'Bank',
        type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
        isActive: true,
        balances: [wire.CurrencyBalance(currency: 'PLN')],
      ),
    ),
  ).value.id;

  Future<String> correct(Ledger on, String account, int balance) async => Device.ok(
    await on.createCorrection(
      wire.CreateCorrectionRequest(
        accountId: account,
        currency: 'PLN',
        balanceMinor: Int64(balance),
        date: '2026-11-04',
      ),
    ),
  ).id;

  group('a delete of a record a sync deleted answers the ledger\'s 404, not a store error', () {
    // jZen answers an absent record on a delete before any precondition runs; the ledger maps it.
    test('a record (5.15)', () async {
      final l = await ledger();
      Device.ok(await phone.deleteRecord(l.record));
      final received = queuePhoneChanges(['records:${l.record}']);
      final delete = laptop.deleteRecord(l.record);
      expectRefused(await delete, status: 404, rule: '5.15');
      await received;
      expectNoConflicts();
    });

    test('a transfer (5.31)', () async {
      final l = await ledger();
      final bank = await secondAccount();
      final transfer = Device.ok(
        await laptop.createTransfer(
          wire.CreateTransferRequest(
            fromAccountId: l.account,
            toAccountId: bank,
            fromCurrency: 'PLN',
            toCurrency: 'PLN',
            fromAmountMinor: Int64(500),
            toAmountMinor: Int64(500),
            date: '2026-11-03',
          ),
        ),
      );
      final id = transfer.fromRecord.transferId;
      await devices.sync();
      Device.ok(await phone.deleteTransfer(id));
      final received = queuePhoneChanges(['transfers:$id']);
      final delete = laptop.deleteTransfer(id);
      expectRefused(await delete, status: 404, rule: '5.31');
      await received;
      expect(devices.laptop.store.transfers.get(id).errorOrNull, isA<ZenNotFoundError>());
    });

    test('a correction (5.37)', () async {
      final l = await ledger();
      final id = await correct(laptop, l.account, 5000);
      await devices.sync();
      Device.ok(await phone.deleteCorrection(id));
      final received = queuePhoneChanges(['records:$id']);
      final delete = laptop.deleteCorrection(id);
      expectRefused(await delete, status: 404, rule: '5.37');
      await received;
    });

    test('an account deleted with its records, one of which a sync deleted: 409 X.7, nothing '
        'written', () async {
      final l = await ledger();
      Device.ok(await phone.deleteRecord(l.record));
      final before = snapshot(devices.laptop);
      final received = queuePhoneChanges(['records:${l.record}']);
      final delete = laptop.deleteAccount(l.account, deleteRecords: true);
      expectRefused(await delete, status: 409, rule: 'X.7');
      await received;
      final after = snapshot(devices.laptop)..remove('records:${l.record}');
      expect(after.keys, before.keys.where((k) => k != 'records:${l.record}'));
    });
  });

  group('an edit or delete decided on a version a sync changed is refused (409 X.7)', () {
    test('an account update that drops a currency whose opening a sync changed', () async {
      final l = await ledger();
      Device.ok(
        await laptop.updateAccount(
          l.account,
          wire.UpdateAccountRequest(
            name: 'Wallet',
            type: wire.AccountType.ACCOUNT_TYPE_CASH,
            isActive: true,
            balances: [
              wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(10000)),
              wire.CurrencyBalance(currency: 'EUR'),
            ],
          ),
        ),
      );
      await devices.sync();
      final eur = DerivedIds.accountCurrency(l.account, 'EUR');
      final opening = Device.ok(devices.phone.store.accountCurrencies.get(eur));
      Device.ok(
        await devices.phone.store.putAccountCurrency(
          opening.deepCopy()..openingMinor = Int64(700),
          expect: WriteExpects.asRead(opening),
        ),
      );
      final received = queuePhoneChanges(['account_currencies:$eur']);
      final update = laptop.updateAccount(
        l.account,
        wire.UpdateAccountRequest(
          name: 'Wallet',
          type: wire.AccountType.ACCOUNT_TYPE_CASH,
          isActive: true,
          balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(10000))],
        ),
      );
      expectRefused(await update, status: 409, rule: 'X.7');
      await received;
      expect(Device.ok(devices.laptop.store.accountCurrencies.get(eur)).openingMinor, Int64(700));
    });

    Future<String> sharedCategory() async {
      final c = Device.ok(
        await laptop.createCategory(wire.CreateCategoryRequest(title: 'Fun', iconKey: 'leisure')),
      );
      await devices.sync();
      Device.ok(
        await phone.updateCategory(
          c.id,
          wire.UpdateCategoryRequest(title: 'Games', iconKey: 'leisure'),
        ),
      );
      return c.id;
    }

    test('an archive', () async {
      final id = await sharedCategory();
      final received = queuePhoneChanges(['categories:$id']);
      final archive = laptop.archiveCategory(id);
      expectRefused(await archive, status: 409, rule: 'X.7');
      await received;
      final c = Device.ok(devices.laptop.store.categories.get(id));
      expect((c.title, c.archived), ('Games', false));
    });

    test('a category delete', () async {
      final id = await sharedCategory();
      final received = queuePhoneChanges(['categories:$id']);
      final delete = laptop.deleteCategory(id);
      expectRefused(await delete, status: 409, rule: 'X.7');
      await received;
      expect(Device.ok(devices.laptop.store.categories.get(id)).title, 'Games');
    });
  });

  test('the correction-intent replacement is refused whole when a sync deleted a correction it '
      'summed, and nothing is written', () async {
    final l = await ledger();
    final mine = await correct(laptop, l.account, 5000);
    final theirs = await correct(phone, l.account, 7000);
    await devices.sync();
    final issue = Device.ok(devices.laptop.integrity().evaluate())
        .singleWhere((i) => i.code == 'correction.made_apart');
    Device.ok(await phone.deleteCorrection(theirs));
    final before = snapshot(devices.laptop);

    final received = queuePhoneChanges(['records:$theirs']);
    final replace = issue.actions.singleWhere((a) => a.code == 'correct_to_target').run(mine);

    expect((await replace).errorOrNull, isNotNull, reason: 'the replacement went through');
    await received;
    final after = snapshot(devices.laptop);
    expect(after.keys.toSet(), before.keys.toSet().difference({'records:$theirs'}));
    expect(after['records:$mine'], before['records:$mine'], reason: 'the chosen one is untouched');
  });

  test('re-creating a deleted account is refused once another device restored it; its version '
      'stays', () async {
    final l = await ledger();
    Device.ok(await devices.phone.store.deleteAccount(l.account));
    await devices.sync();
    final issue = Device.ok(devices.laptop.integrity().evaluate())
        .firstWhere((i) => i.code == 'reference.record_account_missing');
    Device.ok(
      await devices.phone.store.putAccount(
        Account(id: l.account, name: 'Restored', kind: AccountKind.ACCOUNT_KIND_CASH),
        expect: WriteExpects.asRead(null),
      ),
    );

    final received = queuePhoneChanges(['accounts:${l.account}']);
    final recreate = issue.actions.singleWhere((a) => a.code == 'recreate_account').run('Again');

    expect((await recreate).errorOrNull, isA<ZenConflictError>());
    await received;
    expect(Device.ok(devices.laptop.store.accounts.get(l.account)).name, 'Restored');
  });

  test('an import session\'s immutable fields are checked in the write\'s turn: a second write '
      'queued behind the first cannot change its currency', () async {
    final store = devices.laptop.store;
    final session = LocalImportSession(
      id: store.newId(),
      formatId: 'erste-pl-csv',
      currency: 'PLN',
      createdAtMs: Int64(1000),
    );
    final first = store.putImportSession(session);
    // Checked before the turn, this would have seen no session yet and passed.
    final second = store.putImportSession(session.deepCopy()..currency = 'EUR');
    expect((await first).isSuccess, isTrue);
    expect((await second).errorOrNull?.message, contains('"currency" is written once'));
    expect(Device.ok(store.importSessions.get(session.id)).currency, 'PLN');
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
