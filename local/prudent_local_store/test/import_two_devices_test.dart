// Unit 8b (ADR-114): one statement imported on two devices. Two real sessions — two encrypted
// stores synced through jZen's ZenFolderCloud, each holding its import sessions in a device-only
// collection (jZenDev/jZen#252) —
// so a record, a conflict or a figure seen here is what a person would see. Synthetic data only.
//
// What is proven: a statement committed on both devices offline ends with each row once on both;
// one committed after the other has synced is all duplicates; differing category choices are one
// plain disagreement per differing record between exactly the two devices — the shape jZen's
// "keep this device's version for all" sweeps up (jZenDev/jZen#234, `ZenConflictSweep`, offered by
// zen_ui_store's conflict screen that unit 9 wires) — and they leave every figure settled; a
// duplicate included on both is written once; and no session reaches the other device or the
// shared folder.
import 'dart:convert';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart' as wire;
import 'package:test/test.dart';

import 'support/imports.dart' hide ok;
import 'support/two_devices.dart';

/// One device's import side: its ledger, its store and its workflow.
final class Importer {
  final Ledger ledger;
  final PrudentLocalStore store;
  final ImportWorkflow imports;

  Importer(this.ledger, this.store, this.imports);

  Future<wire.ImportSession> previewed(
    String account, {
    required String expense,
    String? income,
  }) async {
    final parsed = Device.ok(
      await imports.create(
        wire.CreateImportSessionRequest(
          formatId: 'erste-pl-csv',
          content: Erste.base(),
          accountId: account,
        ),
      ),
    );
    final shown = Device.ok(await imports.preview(parsed.id, wire.PreviewImportSessionRequest()));
    final defaults = wire.SetImportDefaultsRequest(defaultExpenseCategoryId: expense);
    if (income != null) defaults.defaultIncomeCategoryId = income;
    Device.ok(await imports.setDefaults(parsed.id, defaults));
    return shown;
  }

  Future<wire.ImportSession> commit(String id, int confirmed) async => Device.ok(
    await imports.commit(id, wire.CommitImportSessionRequest(confirmedAcceptedRows: confirmed)),
  );
}

void main() {
  late TwoDevices devices;
  late Importer laptop;
  late Importer phone;
  late String erste;
  late String food;
  late String shopping;
  late String income;

  const now = 1794830400000; // 2026-11-16 at noon UTC.

  Importer importer(Device device) => Importer(
    Ledger(device.store),
    device.store,
    ImportWorkflow(ledger: device.store, nowMs: () => now),
  );

  setUp(() async {
    devices = await TwoDevices.create();
    laptop = importer(devices.laptop);
    phone = importer(devices.phone);
    erste = Device.ok(
      await laptop.ledger.createAccount(
        wire.CreateAccountRequest(
          name: 'Erste',
          type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
          isActive: true,
          accountNumber: Erste.account,
          balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64.ZERO)],
        ),
      ),
    ).value.id;
    Future<String> category(String title, wire.CategoryKind kind) async => Device.ok(
      await laptop.ledger.createCategory(
        wire.CreateCategoryRequest(title: title, iconKey: 'food', kind: kind),
      ),
    ).id;
    food = await category('Food', wire.CategoryKind.CATEGORY_KIND_EXPENSE);
    shopping = await category('Shopping', wire.CategoryKind.CATEGORY_KIND_EXPENSE);
    income = await category('Income', wire.CategoryKind.CATEGORY_KIND_INCOME);
    await devices.sync();
  });

  tearDown(() => devices.dispose());

  Map<String, Record> records(Device device) => {
    for (final r in Device.ok(device.store.records.list())) r.id: r,
  };

  Future<int> balance(Importer on) async =>
      Device.ok(await on.ledger.accountBalances(erste)).minor['PLN']!;

  test('one statement committed on both devices offline ends with each row once on both', () async {
    final onLaptop = await laptop.previewed(erste, expense: food, income: income);
    final onPhone = await phone.previewed(erste, expense: food, income: income);
    expect((await laptop.commit(onLaptop.id, 5)).committedWritten, 5);
    expect((await phone.commit(onPhone.id, 5)).committedWritten, 5);

    await devices.sync();

    for (final device in devices.both) {
      expect(records(device), hasLength(5), reason: device.name);
      expect(Device.ok(device.store.records.conflicts()), isEmpty, reason: device.name);
      expect(Device.ok(device.integrity().evaluate()), isEmpty, reason: device.name);
    }
    expect(records(devices.laptop).keys.toSet(), records(devices.phone).keys.toSet());
    expect(await balance(laptop), Erste.baseNet);
    expect(await balance(phone), Erste.baseNet);
  });

  test(
    'a statement committed after the other device\'s import arrived is all duplicates',
    () async {
      final first = await laptop.previewed(erste, expense: food, income: income);
      await laptop.commit(first.id, 5);
      await devices.sync();

      final second = await phone.previewed(erste, expense: food, income: income);
      expect((second.acceptedRows, second.duplicateRows), (0, 5));
      final done = await phone.commit(second.id, 0);
      expect((done.committedWritten, done.committedAlreadyImported), (0, 0));
      await devices.sync();
      for (final device in devices.both) {
        expect(records(device), hasLength(5));
      }
    },
  );

  test('differing category choices are one plain two-device disagreement per record, which '
      'leaves every figure settled and is settled for all at once', () async {
    final onLaptop = await laptop.previewed(erste, expense: food, income: income);
    final onPhone = await phone.previewed(erste, expense: shopping, income: income);
    await laptop.commit(onLaptop.id, 5);
    await phone.commit(onPhone.id, 5);
    await devices.sync();

    final categoryTag = Record().info_.byName['categoryId']!.tagNumber;
    for (final device in devices.both) {
      expect(records(device), hasLength(5), reason: 'each row once, conflict or not');
      final conflicts = Device.ok(device.store.records.conflicts());
      // The four expense rows differ; the income row agreed and merged.
      expect(conflicts, hasLength(4), reason: device.name);
      for (final conflict in conflicts) {
        // What zen_ui_store's ZenConflictSweep takes in: exactly two sides, neither a delete, from
        // two different devices — the same two for every record.
        expect(conflict.fields, {categoryTag});
        expect(conflict.isDeleteConflict, isFalse);
        expect(conflict.sides, hasLength(2));
        expect(conflict.sides.every((side) => side.value != null), isTrue);
        expect(conflict.sides.map((side) => side.device).toSet(), {
          devices.laptop.zen.deviceId,
          devices.phone.zen.deviceId,
        });
        expect(conflict.sides.map((side) => side.value!.categoryId).toSet(), {food, shopping});
      }
      // A category is not money: the balance counts every row and leaves nothing out.
      final balances = Device.ok(await Ledger(device.store).accountBalances(erste));
      expect(balances.minor['PLN'], Erste.baseNet);
      expect(balances.unsettled, isEmpty);
    }

    // "Keep the laptop's version for all four", as the sweep does it: each record settled with the
    // laptop's side. (The sweep itself is a Flutter screen's; unit 9 drives it in a widget test.)
    for (final conflict in Device.ok(devices.phone.store.records.conflicts())) {
      final side = conflict.sides.firstWhere((s) => s.device == devices.laptop.zen.deviceId);
      Device.ok(await devices.phone.store.records.resolve(conflict.id, side.value));
    }
    await devices.sync();
    for (final device in devices.both) {
      expect(Device.ok(device.store.records.conflicts()), isEmpty, reason: device.name);
      final expenses = records(device).values.where((r) => r.posting.amountMinor < 0);
      expect(expenses.every((r) => r.categoryId == food), isTrue, reason: device.name);
    }
  });

  test('a duplicate included on both devices offline is written once', () async {
    final first = await laptop.previewed(erste, expense: food, income: income);
    await laptop.commit(first.id, 5);
    await devices.sync();

    final onLaptop = await laptop.previewed(erste, expense: food, income: income);
    final onPhone = await phone.previewed(erste, expense: food, income: income);
    for (final (on, s) in [(laptop, onLaptop), (phone, onPhone)]) {
      Device.ok(
        await on.imports.updateRow(s.id, 1, wire.UpdateImportRowRequest(includeDuplicate: true)),
      );
      expect((await on.commit(s.id, 1)).committedWritten, 1);
    }
    await devices.sync();
    for (final device in devices.both) {
      final row1 = records(device).values.where((r) => r.posting.amountMinor == Int64(-710));
      // Both chose "the next free occurrence", 2, of the same row: the same id, one record.
      expect(row1.map((r) => r.importKey.occurrence).toList()..sort(), [1, 2]);
      expect(records(device), hasLength(6));
      expect(Device.ok(device.store.records.conflicts()), isEmpty);
    }
  });

  test('no session reaches the other device or the shared folder', () async {
    final open = await laptop.previewed(erste, expense: food, income: income);
    await devices.sync();
    expect(Device.ok(phone.store.importSessions.list()), isEmpty);
    expect(Device.ok(laptop.store.importSessions.list()).single.id, open.id);
    expect(devices.laptop.zen.unsent.where((name) => name.contains('import_sessions')), isEmpty);
    // ZenFolderCloud writes payloads as they are (jZen's development transport), so the folder can
    // be read: the BLIK row's counterparty account lives only in the session, and is not there.
    final folder = Directory('${devices.root.path}/cloud');
    final everything = [
      for (final entity in folder.listSync(recursive: true))
        if (entity is File) latin1.decode(entity.readAsBytesSync()),
    ].join();
    expect(everything, isNot(contains('00000000000000000000000010')));
    expect(everything, isNot(contains('0000 0000 0000 0000 0000 0010')));
  });
}
