// Unit 4's done-when (docs/plans/PRUDENT-LOCAL-PLAN.md): two real sessions, each with its own
// encrypted store, merge disjoint edits and surface the conflicts of §0.2 through ZenFolderCloud —
// modelled on jZen's zen_demo_local two_devices_test — and, after the merge, list the rules across
// records it broke (F-05), which one device's action then settles for both.
import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:test/test.dart';

import 'support/two_devices.dart';

void main() {
  late TwoDevices devices;
  setUp(() async => devices = await TwoDevices.create());
  tearDown(() async => devices.dispose());

  test('a ledger made on one device appears whole on the other', () async {
    final l = await Fixtures.ledger(devices.laptop);
    await devices.sync();
    final phone = devices.phone.store;
    expect(Device.ok(phone.accounts.get(l.account.id)), l.account);
    expect(Device.ok(phone.categories.get(l.category.id)), l.category);
    expect(Device.ok(phone.records.get(l.record.id)), l.record);
    expect(Device.ok(phone.accountCurrencies.list()).single.openingMinor, Int64(10000));
  });

  test('disjoint edits made offline on both devices merge; nothing is asked', () async {
    final l = await Fixtures.ledger(devices.laptop);
    final bakery = Device.ok(
      await devices.laptop.store.putCategory(
        Fixtures.category(devices.laptop.store, title: 'Bakery'),
      ),
    );
    await devices.sync();

    // Laptop: renames the account, notes the record, adds EUR. Phone: leaves the account out of the
    // total, re-files and re-prices the record, plans a budget.
    final laptop = devices.laptop.store;
    final phone = devices.phone.store;
    Device.ok(await laptop.putAccount(l.account.deepCopy()..name = 'Everyday'));
    Device.ok(await laptop.putRecord(l.record.deepCopy()..note = 'rye'));
    Device.ok(await laptop.putAccountCurrency(Fixtures.currency(l.account.id, 'EUR', position: 1)));
    Device.ok(await phone.putAccount(l.account.deepCopy()..includeInTotal = false));
    Device.ok(
      await phone.putRecord(
        l.record.deepCopy()
          ..categoryId = bakery.id
          ..posting = (l.record.posting.deepCopy()..amountMinor = Int64(-1300)),
      ),
    );
    Device.ok(
      await phone.putBudget(
        Budget(
          id: DerivedIds.budget(bakery.id, '2026-11', 'PLN'),
          categoryId: bakery.id,
          month: '2026-11',
          currency: 'PLN',
          amountMinor: Int64(20000),
        ),
      ),
    );
    await devices.sync();

    for (final device in devices.both) {
      final s = device.store;
      expect(device.zen.conflictCount, 0, reason: device.name);
      final account = Device.ok(s.accounts.get(l.account.id));
      expect((account.name, account.includeInTotal), ('Everyday', false));
      final record = Device.ok(s.records.get(l.record.id));
      expect(
        (record.note, record.categoryId, record.posting.amountMinor),
        ('rye', bakery.id, Int64(-1300)),
      );
      expect(Device.ok(s.accountCurrencies.list()).map((c) => c.currency).toSet(), {'PLN', 'EUR'});
      expect(Device.ok(s.budgets.list()), hasLength(1));
      expect(Device.ok(device.integrity().evaluate()), isEmpty, reason: device.name);
    }
  });

  test('the conflicts of §0.2 surface on both devices and wait for the person', () async {
    final l = await Fixtures.ledger(devices.laptop);
    Device.ok(
      await devices.laptop.store.putAccountCurrency(
        Fixtures.currency(l.account.id, 'EUR', position: 1),
      ),
    );
    final bank = Device.ok(
      await devices.laptop.store.putAccount(Fixtures.account(devices.laptop.store, name: 'Bank')),
    );
    Device.ok(
      await devices.laptop.store.putSettings(
        Settings(id: DerivedIds.settings, mainCurrency: 'PLN'),
      ),
    );
    await devices.sync();

    final laptop = devices.laptop.store;
    final phone = devices.phone.store;
    // One note, two texts. One posting, a currency here and an amount there. Two defaults.
    Device.ok(
      await laptop.putRecord(
        l.record.deepCopy()
          ..note = 'rye'
          ..posting = (l.record.posting.deepCopy()..currency = 'EUR'),
      ),
    );
    Device.ok(
      await phone.putRecord(
        l.record.deepCopy()
          ..note = 'wheat'
          ..posting = (l.record.posting.deepCopy()..amountMinor = Int64(-6000)),
      ),
    );
    Device.ok(
      await laptop.putSettings(
        Settings(id: DerivedIds.settings, mainCurrency: 'PLN', defaultAccountId: l.account.id),
      ),
    );
    Device.ok(
      await phone.putSettings(
        Settings(id: DerivedIds.settings, mainCurrency: 'PLN', defaultAccountId: bank.id),
      ),
    );
    await devices.sync();

    for (final device in devices.both) {
      expect(device.zen.conflictCount, 2, reason: device.name);
      final record = Device.ok(device.store.records.conflicts()).single;
      expect(record.fields, {3, 7}); // the posting group and the note, nothing else
      final settings = Device.ok(device.store.settings.conflicts()).single;
      expect(settings.fields, {3}); // default_account_id
    }

    // A record in conflict refuses writes until it is settled; nothing is overwritten meanwhile.
    final refused = await phone.putRecord(
      Device.ok(phone.records.get(l.record.id)).deepCopy()..title = 'x',
    );
    expect(refused.isFailure, isTrue);

    // The person keeps the phone's version of each, on the laptop.
    for (final conflict in [Device.ok(laptop.records.conflicts()).single]) {
      final side = conflict.sides.firstWhere((s) => s.deviceName == 'Phone');
      Device.ok(await laptop.records.resolve(conflict.id, side.value));
    }
    final settingsSide = Device.ok(laptop.settings.conflicts()).single.sides
        .firstWhere((s) => s.deviceName == 'Phone');
    Device.ok(await laptop.settings.resolve(DerivedIds.settings, settingsSide.value));
    await devices.sync();

    for (final device in devices.both) {
      expect(device.zen.conflictCount, 0, reason: device.name);
      final record = Device.ok(device.store.records.get(l.record.id));
      expect(
        (record.note, record.posting.currency, record.posting.amountMinor),
        ('wheat', 'PLN', Int64(-6000)),
      );
      expect(Device.ok(device.store.settings.get(DerivedIds.settings)).defaultAccountId, bank.id);
    }
  });

  test('a merge that breaks a rule across records is listed on both devices, and settled once', () async {
    final l = await Fixtures.ledger(devices.laptop);
    final bakery = Device.ok(
      await devices.laptop.store.putCategory(
        Fixtures.category(devices.laptop.store, title: 'Bakery'),
      ),
    );
    await devices.sync();

    // Laptop deletes the Groceries category (moving its record first, as the ledger will require);
    // the phone, offline, files a new record under it. Each write was valid where it was made.
    final laptop = devices.laptop.store;
    final phone = devices.phone.store;
    Device.ok(await laptop.putRecord(l.record.deepCopy()..categoryId = bakery.id));
    Device.ok(await laptop.deleteCategory(l.category.id));
    final late = Device.ok(
      await phone.putRecord(
        Fixtures.record(phone, accountId: l.account.id, categoryId: l.category.id, title: 'Milk'),
      ),
    );
    await devices.sync();

    for (final device in devices.both) {
      expect(device.zen.conflictCount, 0, reason: 'different records: the store sees no conflict');
      final issues = Device.ok(device.integrity().evaluate());
      expect(issues.map((i) => i.id), [
        'reference.record_category_missing:records/${late.id}',
      ], reason: device.name);
      expect(issues.single.actions.map((a) => a.code), [
        'delete_record',
        'move_to_category',
        'recreate_category',
      ]);
    }

    // Nothing was fixed on its own: the record still names the deleted category on both devices.
    expect(Device.ok(phone.records.get(late.id)).categoryId, l.category.id);

    final issue = Device.ok(devices.phone.integrity().evaluate()).single;
    final move = issue.actions.firstWhere((a) => a.code == 'move_to_category');
    expect(move.choices, [bakery.id]);
    expect((await move.run(bakery.id)).isSuccess, isTrue);
    await devices.sync();

    for (final device in devices.both) {
      expect(Device.ok(device.integrity().evaluate()), isEmpty, reason: device.name);
      expect(Device.ok(device.store.records.get(late.id)).categoryId, bakery.id);
    }
  });

  test('one account number given to two accounts on two devices is listed, then cleared', () async {
    final laptop = devices.laptop.store;
    final phone = devices.phone.store;
    const number = 'PL00000000000000000000000005';
    final a = Device.ok(await laptop.putAccount(Fixtures.account(laptop)..accountNumber = number));
    final b = Device.ok(
      await phone.putAccount(Fixtures.account(phone, name: 'Bank')..accountNumber = number),
    );
    await devices.sync();
    for (final device in devices.both) {
      expect(Device.ok(device.integrity().evaluate()).map((i) => i.code), [
        'account.number_duplicate',
      ]);
    }
    final issue = Device.ok(devices.laptop.integrity().evaluate()).single;
    expect((await issue.actions.single.run(a.id)).isSuccess, isTrue);
    await devices.sync();
    for (final device in devices.both) {
      expect(Device.ok(device.integrity().evaluate()), isEmpty);
      expect(Device.ok(device.store.accounts.get(b.id)).accountNumber, number);
    }
  });

  test('the runner re-evaluates on the store\'s change stream, which a sync fires', () async {
    final changes = <void>[];
    final sub = devices.phone.integrity().changes.listen(changes.add);
    await Fixtures.ledger(devices.laptop);
    await devices.sync();
    await Future<void>.delayed(Duration.zero);
    expect(changes, isNotEmpty);
    await sub.cancel();
  });
}
