// The structural rules PrudentLocalStore enforces on every write (ADR-102, ADR-111): ids from their
// natural keys, immutable fields, write-once and never-deleted records. These are the "Immutable" rows
// of the §0.2 table; merge_table_test proves the merge rows.
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import 'support/two_devices.dart';

void main() {
  late Directory dir;
  late ZenStore zen;
  late PrudentLocalStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prudent_local_store_rules');
    zen = Device.ok(await ZenStore.open(dir, deviceName: 'Laptop', key: List.filled(32, 7)));
    store = PrudentLocalStore(zen);
  });
  tearDown(() async {
    await zen.close();
    await dir.delete(recursive: true);
  });

  void refused(ZenResult<Object?> result, Pattern why) {
    expect(
      result.errorOrNull,
      isA<ZenValidationError>(),
      reason: 'expected a refusal, got $result',
    );
    expect(result.errorOrNull!.message, contains(why));
  }

  Future<Account> account() async => Device.ok(await store.putAccount(Fixtures.account(store)));

  group('ids', () {
    test('a random id is a local id', () async {
      refused(await store.putAccount(Fixtures.account(store)..id = 'ABC'), 'is not a local id');
      refused(
        await store.putCategory(Fixtures.category(store)..id = 'a' * 31),
        'is not a local id',
      );
    });

    test(
      'an account currency, a budget and an occurrence carry the id their key derives',
      () async {
        final a = await account();
        refused(
          await store.putAccountCurrency(Fixtures.currency(a.id, 'PLN')..id = store.newId()),
          'is not the id its natural key derives',
        );
        refused(
          await store.putAccountCurrency(Fixtures.currency(a.id, 'PLN')..currency = 'pln'),
          'not canonical',
        );
        final categoryId = store.newId();
        refused(
          await store.putBudget(
            Budget(id: store.newId(), categoryId: categoryId, month: '2026-11', currency: 'PLN'),
          ),
          'is not the id its natural key derives',
        );
        final planId = store.newId();
        refused(
          await store.putOccurrenceState(
            OccurrenceState(id: store.newId(), planId: planId, occurrenceDate: '2026-11-01'),
          ),
          'is not the id its natural key derives',
        );
        expect(
          (await store.putOccurrenceState(
            OccurrenceState(
              id: DerivedIds.occurrence(planId, '2026-11-01'),
              planId: planId,
              occurrenceDate: '2026-11-01',
            ),
          )).isSuccess,
          isTrue,
        );
      },
    );

    test('the settings record is "settings"', () async {
      refused(
        await store.putSettings(Settings(id: store.newId(), mainCurrency: 'PLN')),
        'settings',
      );
      expect(
        (await store.putSettings(Settings(id: 'settings', mainCurrency: 'PLN'))).isSuccess,
        isTrue,
      );
    });

    test('a confirming record and an imported record carry their derived ids', () async {
      final a = await account();
      final occurrence = DerivedIds.occurrence(store.newId(), '2026-11-01');
      final confirming = Fixtures.record(store, accountId: a.id)
        ..planLink = PlanLink(planId: store.newId(), occurrenceId: occurrence);
      refused(await store.putRecord(confirming), 'is not the id its natural key derives');
      confirming.id = DerivedIds.confirmation(occurrence);
      expect((await store.putRecord(confirming)).isSuccess, isTrue);

      final imported = Fixtures.record(store, accountId: a.id)
        ..importKey = ImportKey(fingerprint: 'v1:0f0f', occurrence: 1);
      refused(await store.putRecord(imported), 'is not the id its natural key derives');
      imported.id = DerivedIds.imported(a.id, 'v1:0f0f', 1);
      expect((await store.putRecord(imported)).isSuccess, isTrue);
    });
  });

  group('immutable fields', () {
    test('a correction is never edited, only deleted', () async {
      final a = await account();
      final correction = Device.ok(
        await store.putRecord(
          Fixtures.record(store, accountId: a.id, amount: 300)
            ..correction = CorrectionIntent(targetMinor: Int64(10300), seenMinor: Int64(10000)),
        ),
      );
      refused(
        await store.putRecord(correction.deepCopy()..note = 'adjusted'),
        'is a correction, which is never edited',
      );
      refused(
        await store.putRecord(correction.deepCopy()..clearCorrection()),
        '"correction" is written once',
      );
      expect((await store.deleteRecord(correction.id)).isSuccess, isTrue);
    });

    test(
      'an ordinary record cannot later claim a correction, a plan link or an import key',
      () async {
        final a = await account();
        final record = Device.ok(await store.putRecord(Fixtures.record(store, accountId: a.id)));
        refused(
          await store.putRecord(
            record.deepCopy()..correction = CorrectionIntent(targetMinor: Int64(1)),
          ),
          '"correction" is written once',
        );
        // Its other fields stay editable.
        expect((await store.putRecord(record.deepCopy()..note = 'fresh')).isSuccess, isTrue);
      },
    );

    test('an import key is never changed', () async {
      final a = await account();
      final id = DerivedIds.imported(a.id, 'v1:aa', 1);
      final record = Device.ok(
        await store.putRecord(
          Fixtures.record(store, accountId: a.id)
            ..id = id
            ..importKey = ImportKey(fingerprint: 'v1:aa', occurrence: 1),
        ),
      );
      refused(
        await store.putRecord(record.deepCopy()..clearImportKey()),
        '"importKey" is written once',
      );
      expect((await store.putRecord(record.deepCopy()..note = 'groceries')).isSuccess, isTrue);
    });

    test("a goal's currency and creation time never change", () async {
      final goal = Device.ok(
        await store.putGoal(
          Goal(id: store.newId(), name: 'Bike', currency: 'PLN', createdAtMs: Int64(1)),
        ),
      );
      refused(await store.putGoal(goal.deepCopy()..currency = 'EUR'), '"currency" is written once');
      refused(await store.putGoal(goal.deepCopy()..createdAtMs = Int64(2)), '"createdAtMs"');
      expect((await store.putGoal(goal.deepCopy()..name = 'E-bike')).isSuccess, isTrue);
    });
  });

  group('write-once and never-deleted records', () {
    test('a transfer is written once, and deleted', () async {
      final transfer = Transfer(
        id: store.newId(),
        title: 'Top up',
        date: '2026-11-03',
        source: Posting(accountId: store.newId(), currency: 'PLN', amountMinor: Int64(100)),
        destination: Posting(accountId: store.newId(), currency: 'PLN', amountMinor: Int64(100)),
      );
      expect((await store.addTransfer(transfer)).isSuccess, isTrue);
      refused(await store.addTransfer(transfer.deepCopy()..title = 'Moved'), 'written once');
      expect((await store.deleteTransfer(transfer.id)).isSuccess, isTrue);
    });

    test('a goal allocation is written once (and the store offers no way to delete one)', () async {
      final entry = GoalAllocation(
        id: store.newId(),
        kind: AllocationKind.ALLOCATION_KIND_ALLOCATE,
        targetGoalId: store.newId(),
        currency: 'PLN',
        amountMinor: Int64(500),
        createdBy: store.deviceId,
      );
      expect((await store.addGoalAllocation(entry)).isSuccess, isTrue);
      refused(
        await store.addGoalAllocation(entry.deepCopy()..amountMinor = Int64(1)),
        'written once',
      );
    });

    test('a carry-over reset is recorded unrevoked, revoked once, and never edited', () async {
      final reset = BudgetCarryOverReset(
        id: store.newId(),
        categoryId: store.newId(),
        month: '2026-11',
        currency: 'PLN',
        discardedMinor: Int64(700),
        note: 'new job',
        createdBy: store.deviceId,
        createdAtMs: Int64(1),
      );
      refused(
        await store.addBudgetReset(
          reset.deepCopy()..revocation = Revocation(by: 'x', atMs: Int64(2)),
        ),
        'recorded unrevoked',
      );
      expect((await store.addBudgetReset(reset)).isSuccess, isTrue);
      refused(await store.addBudgetReset(reset.deepCopy()..note = 'edited'), 'written once');
      final revoked = Device.ok(await store.revokeBudgetReset(reset.id, atMs: 99));
      expect(revoked.revocation, Revocation(by: store.deviceId, atMs: Int64(99)));
      refused(await store.revokeBudgetReset(reset.id, atMs: 100), 'already revoked');
      expect(
        (await store.revokeBudgetReset(store.newId(), atMs: 1)).errorOrNull,
        isA<ZenNotFoundError>(),
      );
    });
  });
}
