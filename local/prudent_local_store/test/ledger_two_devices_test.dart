// Unit 5's two-device cases (ADR-113): the ledger on two real sessions — two encrypted stores, each
// with its own key and directory — synced through jZen's ZenFolderCloud. Nothing is mocked, so a
// figure, a conflict or an issue seen here is the one a person would see on both devices.
//
// What is proven: records added offline on both devices are all kept; edits to different fields of
// one record merge; a dispute about money leaves the record out of every figure on both devices, and
// says so, until it is settled; a dispute about text does not; an account deleted with its records is
// all or nothing even when a record of it is in conflict; and what the merge breaks across records —
// a record or transfer left on a deleted account, two corrections made apart — is listed on both
// devices and settled once.
import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

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

  List<Ledger> both() => [laptop, phone];

  /// An account holding PLN 100.00 and a category, made on the laptop and synced.
  Future<({String account, String category})> ledger() async {
    final account = Device.ok(
      await laptop.createAccount(
        wire.CreateAccountRequest(
          name: 'Wallet',
          type: wire.AccountType.ACCOUNT_TYPE_CASH,
          balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(10000))],
        ),
      ),
    );
    final category = Device.ok(
      await laptop.createCategory(wire.CreateCategoryRequest(title: 'Food', iconKey: 'food')),
    );
    await devices.sync();
    return (account: account.id, category: category.id);
  }

  Future<wire.Record> add(
    Ledger on,
    ({String account, String category}) l, {
    int amount = -1000,
    String title = 'Bread',
  }) async => Device.ok(
    await on.createRecord(
      wire.CreateRecordRequest(
        title: title,
        amountMinor: Int64(amount),
        date: '2026-11-02',
        categoryId: l.category,
        accountId: l.account,
        currency: 'PLN',
      ),
    ),
  );

  Future<wire.Record> edit(
    Ledger on,
    ({String account, String category}) l,
    String id, {
    int amount = -1000,
    String title = 'Bread',
    String? note,
  }) async => Device.ok(
    await on.updateRecord(
      id,
      wire.UpdateRecordRequest(
        title: title,
        amountMinor: Int64(amount),
        date: '2026-11-02',
        categoryId: l.category,
        accountId: l.account,
        currency: 'PLN',
        note: note,
      ),
    ),
  );

  Future<AccountBalances> figures(Ledger on, String account) async =>
      Device.ok(await on.accountBalances(account));

  test('records added offline on both devices are all kept, and both show one balance', () async {
    final l = await ledger();
    await add(laptop, l, amount: -1000, title: 'Bread');
    await add(phone, l, amount: -2500, title: 'Milk');
    await add(phone, l, amount: 400, title: 'Refund');
    await devices.sync();
    for (final device in both()) {
      expect((await figures(device, l.account)).minor, {'PLN': 6900});
      expect(Device.ok(await device.listRecords()).records, hasLength(3));
    }
  });

  test('a note edited on one device and the amount on the other merge into one record', () async {
    final l = await ledger();
    final r = await add(laptop, l);
    await devices.sync();
    await edit(laptop, l, r.id, note: 'rye');
    await edit(phone, l, r.id, amount: -1300);
    await devices.sync();
    for (final device in both()) {
      final merged = Device.ok(await device.getRecord(r.id));
      expect((merged.note, merged.amountMinor.toInt()), ('rye', -1300));
      final f = await figures(device, l.account);
      expect(f.minor, {'PLN': 8700});
      expect(f.unsettled, <String>[]);
    }
  });

  test(
    'two amounts for one record: it counts in no figure on either device until settled',
    () async {
      final l = await ledger();
      final r = await add(laptop, l);
      await add(laptop, l, amount: -500, title: 'Tea');
      await devices.sync();
      await edit(laptop, l, r.id, amount: -1200);
      await edit(phone, l, r.id, amount: -1800);
      await devices.sync();

      for (final (device, ledger) in [(devices.laptop, laptop), (devices.phone, phone)]) {
        expect(Device.ok(device.store.records.conflicts()).single.id, r.id);
        final f = await figures(ledger, l.account);
        // Opening 100.00 and the undisputed tea only: neither 12.00 nor 18.00 is chosen by a clock.
        expect(f.minor, {'PLN': 9500});
        expect(f.unsettled, [r.id]);
        // The list still shows the record, as the store shows it: a person has to see what they settle.
        expect(Device.ok(await ledger.listRecords()).records.map((x) => x.id), contains(r.id));
        // A correction would be a delta from a guess: refused on both devices.
        final correction = await ledger.createCorrection(
          wire.CreateCorrectionRequest(
            accountId: l.account,
            currency: 'PLN',
            balanceMinor: Int64(1),
            date: '2026-11-03',
          ),
        );
        expect(LedgerErrors.statusOf(correction.errorOrNull!), 409);
      }

      // The person settles it once, on the phone, with the laptop's amount.
      final conflict = Device.ok(devices.phone.store.records.conflicts()).single;
      final chosen = conflict.sides.firstWhere((s) => s.value!.posting.amountMinor == Int64(-1200));
      Device.ok(await devices.phone.store.records.resolve(r.id, chosen.value));
      await devices.sync();
      for (final device in both()) {
        final f = await figures(device, l.account);
        expect(f.minor, {'PLN': 8300});
        expect(f.unsettled, <String>[]);
      }
    },
  );

  test('two notes for one record: a dispute about text leaves the money counted', () async {
    final l = await ledger();
    final r = await add(laptop, l);
    await devices.sync();
    await edit(laptop, l, r.id, note: 'rye');
    await edit(phone, l, r.id, note: 'spelt');
    await devices.sync();
    for (final (device, ledger) in [(devices.laptop, laptop), (devices.phone, phone)]) {
      expect(Device.ok(device.store.records.conflicts()), hasLength(1));
      final f = await figures(ledger, l.account);
      expect(f.minor, {'PLN': 9000});
      expect(f.unsettled, <String>[]);
    }
  });

  test('two opening amounts: that currency\'s opening counts as nothing until settled', () async {
    final l = await ledger();
    await add(laptop, l);
    await devices.sync();
    Future<void> reopen(Ledger on, int opening) async => Device.ok(
      await on.updateAccount(
        l.account,
        wire.UpdateAccountRequest(
          name: 'Wallet',
          type: wire.AccountType.ACCOUNT_TYPE_CASH,
          balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(opening))],
        ),
      ),
    );
    await reopen(laptop, 20000);
    await reopen(phone, 30000);
    await devices.sync();
    for (final device in both()) {
      final f = await figures(device, l.account);
      expect(f.minor, {'PLN': -1000});
      expect(f.unsettled, [DerivedIds.accountCurrency(l.account, 'PLN')]);
    }
  });

  test(
    'an edit against a delete: out of every figure, and the account cannot be half-deleted',
    () async {
      final l = await ledger();
      final r = await add(laptop, l);
      await add(laptop, l, amount: -500, title: 'Tea');
      await devices.sync();
      Device.ok(await laptop.deleteRecord(r.id));
      await edit(phone, l, r.id, amount: -1100);
      await devices.sync();
      for (final (device, ledger) in [(devices.laptop, laptop), (devices.phone, phone)]) {
        expect(Device.ok(device.store.records.conflicts()).single.isDeleteConflict, isTrue);
        final f = await figures(ledger, l.account);
        expect(f.minor, {'PLN': 9500});
        expect(f.unsettled, [r.id]);
        // ADR-081 through writeAll: the disputed record is in the batch, the store refuses it, and
        // nothing at all is deleted — not the account, not the undisputed tea.
        final delete = await ledger.deleteAccount(l.account, deleteRecords: true);
        expect(delete.errorOrNull, isA<ZenConflictError>());
        expect(
          LedgerErrors.statusOf(delete.errorOrNull!),
          isNull,
          reason: 'the store\'s, not a rule',
        );
        expect(Device.ok(device.store.accounts.list()), hasLength(1));
        expect(Device.ok(device.store.records.list()), hasLength(2));
      }
    },
  );

  test('an account deleted with its records on one device while the other adds one', () async {
    final l = await ledger();
    await add(laptop, l);
    final other = Device.ok(
      await laptop.createAccount(
        wire.CreateAccountRequest(
          name: 'Savings',
          type: wire.AccountType.ACCOUNT_TYPE_SAVINGS,
          balances: [wire.CurrencyBalance(currency: 'PLN')],
        ),
      ),
    );
    await devices.sync();

    Device.ok(await laptop.deleteAccount(l.account, deleteRecords: true));
    final late = await add(phone, l, amount: -700, title: 'Late');
    final transfer = Device.ok(
      await phone.createTransfer(
        wire.CreateTransferRequest(
          title: 'Late move',
          fromAccountId: l.account,
          toAccountId: other.id,
          fromAmountMinor: Int64(100),
          toAmountMinor: Int64(100),
          fromCurrency: 'PLN',
          toCurrency: 'PLN',
          date: '2026-11-04',
        ),
      ),
    );
    await devices.sync();

    // The delete was one write on the laptop; the phone's new record and transfer were not part of
    // it, so both devices now hold them pointing at an account that is gone. Nothing fixed them.
    for (final device in devices.both) {
      final issues = Device.ok(device.integrity().evaluate());
      expect(
        {for (final i in issues) '${i.code} ${i.recordId}'},
        {
          'reference.record_account_missing ${late.id}',
          'reference.transfer_account_missing ${transfer.id}',
        },
      );
      expect(Device.ok(device.store.accounts.list()).map((a) => a.id), [other.id]);
    }
    // The other account's balance already counts the late transfer's leg, as it does on the server
    // until the person decides; the phone settles both issues with one action each.
    expect((await figures(phone, other.id)).minor, {'PLN': 100});
    for (final issue in Device.ok(devices.phone.integrity().evaluate())) {
      final delete = issue.actions.firstWhere((a) => a.code.startsWith('delete_'));
      Device.ok(await delete.run());
    }
    await devices.sync();
    for (final device in devices.both) {
      expect(Device.ok(device.integrity().evaluate()), isEmpty);
    }
    expect((await figures(laptop, other.id)).minor, {'PLN': 0});
  });

  test('two corrections made apart are one issue on both devices; one action settles it', () async {
    final l = await ledger();
    await add(laptop, l, amount: -2000);
    await devices.sync();
    // Both devices count the cash and correct the same balance, offline.
    Future<wire.Record> correct(Ledger on, int target) async => Device.ok(
      await on.createCorrection(
        wire.CreateCorrectionRequest(
          accountId: l.account,
          currency: 'PLN',
          balanceMinor: Int64(target),
          date: '2026-11-05',
        ),
      ),
    );
    final mine = await correct(laptop, 7000);
    final theirs = await correct(phone, 7000);
    await devices.sync();

    for (final device in both()) {
      // Each correction is -10.00 from the 80.00 it saw: together they overshoot to 60.00.
      expect((await figures(device, l.account)).minor, {'PLN': 6000});
    }
    final ids = ([mine.id, theirs.id]..sort());
    for (final device in devices.both) {
      final issue = Device.ok(device.integrity().evaluate()).single;
      expect((issue.code, issue.facts['corrections']), ('correction.made_apart', ids.join(',')));
    }

    // The phone replaces both by one correction to the balance the laptop's asked for.
    final issue = Device.ok(devices.phone.integrity().evaluate()).single;
    Device.ok(await issue.actions.firstWhere((a) => a.code == 'correct_to_target').run(mine.id));
    await devices.sync();
    for (final (device, ledger) in [(devices.laptop, laptop), (devices.phone, phone)]) {
      expect((await figures(ledger, l.account)).minor, {'PLN': 7000});
      expect(Device.ok(device.integrity().evaluate()), isEmpty);
      final corrections = Device.ok(await ledger.listRecords(const RecordQuery(type: 'correction')))
          .records;
      expect(corrections.single.amountMinor.toInt(), -1000);
    }

    // A later correction on either device saw the replacement, so it is no issue.
    await correct(laptop, 6500);
    await devices.sync();
    expect(Device.ok(devices.phone.integrity().evaluate()), isEmpty);
    expect((await figures(phone, l.account)).minor, {'PLN': 6500});
  });

  test('two corrections made apart, settled by deleting one', () async {
    final l = await ledger();
    Future<void> correct(Ledger on, int target) async => Device.ok(
      await on.createCorrection(
        wire.CreateCorrectionRequest(
          accountId: l.account,
          currency: 'PLN',
          balanceMinor: Int64(target),
          date: '2026-11-05',
        ),
      ),
    );
    await correct(laptop, 9000);
    await correct(phone, 9500);
    await devices.sync();
    final issue = Device.ok(devices.laptop.integrity().evaluate()).single;
    final deleteOne = issue.actions.firstWhere((a) => a.code == 'delete_correction');
    final phoneOwn = Device.ok(await laptop.listRecords(const RecordQuery(type: 'correction')))
        .records
        .firstWhere((r) => r.amountMinor.toInt() == -500);
    // The person keeps the laptop's count (90.00) and deletes the phone's.
    Device.ok(await deleteOne.run(phoneOwn.id));
    await devices.sync();
    for (final device in both()) {
      expect((await figures(device, l.account)).minor, {'PLN': 9000});
    }
    expect(Device.ok(devices.phone.integrity().evaluate()), isEmpty);
  });

  test('two devices that start fresh write the same five starters once', () async {
    Device.ok(await laptop.startFresh());
    Device.ok(await phone.startFresh());
    await devices.sync();
    for (final (device, ledger) in [(devices.laptop, laptop), (devices.phone, phone)]) {
      expect(Device.ok(await ledger.listCategories()).categories, hasLength(5));
      expect(Device.ok(device.store.categories.conflicts()), isEmpty);
    }
  });
}
