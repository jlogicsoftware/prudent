// Every row of the per-field merge table (docs/plans/prudent-local-phase0.md §0.2, frozen by
// ADR-102), proved through two real encrypted stores synced by jZen's ZenFolderCloud.
//
//   Merge      — a field of its own: alone it merges beside another field's edit; two different
//                values are a conflict on exactly that field; two equal values merge.
//   Group      — a nested message: a change to one part on each device is ONE conflict on the group,
//                never a combination neither device wrote.
//   Immutable  — refused by PrudentLocalStore once written (store_rules_test has the refusals; the
//                rows here name them so the table is complete in one place).
//   Derived    — not in the store message at all.
//   Same-intent— a policy keeps the earliest time when both devices reached the same state.
//   Device     — not in the synced store.
import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import 'support/two_devices.dart';

/// One record of one collection, as a table row needs it.
final class Kind<T extends GeneratedMessage> {
  final String name;
  final ZenCollection<T> Function(PrudentLocalStore) collection;
  final Future<T> Function(Device) create;
  final Future<ZenResult<Object?>> Function(PrudentLocalStore, T) put;

  const Kind(this.name, this.collection, this.create, this.put);

  T read(Device device, String id) => Device.ok(collection(device.store).get(id));

  Future<void> edit(Device device, String id, void Function(T) change) async {
    final next = read(device, id).deepCopy();
    change(next);
    final result = await put(device.store, next);
    expect(
      result.isSuccess,
      isTrue,
      reason: '$name edit on ${device.name}: ${result.errorOrNull?.message}',
    );
  }

  ZenConflict<T>? conflict(Device device, String id) =>
      Device.ok(collection(device.store).conflictFor(id));
}

int tagOf(GeneratedMessage message, String field) => message.info_.byName[field]!.tagNumber;

void setByName(GeneratedMessage message, String field, Object value) =>
    message.setField(tagOf(message, field), value);

Object? getByName(GeneratedMessage message, String field) =>
    message.getField(tagOf(message, field));

// ── The collections ─────────────────────────────────────────────────────────────────────────────

final accounts = Kind<Account>(
  'accounts',
  (s) => s.accounts,
  (d) async => Device.ok(await d.store.putAccount(Fixtures.account(d.store))),
  (s, v) => s.putAccount(v),
);

final accountCurrencies = Kind<AccountCurrency>('account_currencies', (s) => s.accountCurrencies, (
  d,
) async {
  final account = Device.ok(await d.store.putAccount(Fixtures.account(d.store)));
  return Device.ok(await d.store.putAccountCurrency(Fixtures.currency(account.id, 'PLN')));
}, (s, v) => s.putAccountCurrency(v));

final categories = Kind<Category>(
  'categories',
  (s) => s.categories,
  (d) async => Device.ok(await d.store.putCategory(Fixtures.category(d.store))),
  (s, v) => s.putCategory(v),
);

final records = Kind<Record>(
  'records',
  (s) => s.records,
  (d) async => (await Fixtures.ledger(d)).record,
  (s, v) => s.putRecord(v),
);

final budgets = Kind<Budget>('budgets', (s) => s.budgets, (d) async {
  final category = Device.ok(await d.store.putCategory(Fixtures.category(d.store)));
  return Device.ok(
    await d.store.putBudget(
      Budget(
        id: DerivedIds.budget(category.id, '2026-11', 'PLN'),
        categoryId: category.id,
        month: '2026-11',
        currency: 'PLN',
        amountMinor: Int64(50000),
      ),
    ),
  );
}, (s, v) => s.putBudget(v));

final goals = Kind<Goal>(
  'goals',
  (s) => s.goals,
  (d) async => Device.ok(
    await d.store.putGoal(
      Goal(
        id: d.store.newId(),
        name: 'Bike',
        currency: 'PLN',
        targetAmountMinor: Int64(200000),
        status: GoalState.GOAL_STATE_ACTIVE,
        statusChangedAtMs: Int64(1000),
        createdAtMs: Int64(1000),
      ),
    ),
  ),
  (s, v) => s.putGoal(v),
);

final plans = Kind<Plan>('plans', (s) => s.plans, (d) async {
  final ledger = await Fixtures.ledger(d);
  return Device.ok(
    await d.store.putPlan(
      Plan(
        id: d.store.newId(),
        title: 'Rent',
        posting: Posting(accountId: ledger.account.id, currency: 'PLN', amountMinor: Int64(-90000)),
        categoryId: ledger.category.id,
        schedule: Schedule(
          frequency: Frequency.FREQUENCY_MONTHLY,
          interval: 1,
          startDate: '2026-11-01',
          timeZone: 'Europe/Warsaw',
        ),
        reminder: ReminderSetting(enabled: false, leadDays: 1),
      ),
    ),
  );
}, (s, v) => s.putPlan(v));

final occurrences = Kind<OccurrenceState>('occurrences', (s) => s.occurrences, (d) async {
  final planId = d.store.newId();
  return Device.ok(
    await d.store.putOccurrenceState(
      OccurrenceState(
        id: DerivedIds.occurrence(planId, '2026-12-01'),
        planId: planId,
        occurrenceDate: '2026-12-01',
      ),
    ),
  );
}, (s, v) => s.putOccurrenceState(v));

final settings = Kind<Settings>(
  'settings',
  (s) => s.settings,
  (d) async =>
      Device.ok(await d.store.putSettings(Settings(id: DerivedIds.settings, mainCurrency: 'PLN'))),
  (s, v) => s.putSettings(v),
);

/// A "Merge" row: [field] alone, with two different values [a] and [b], and another field
/// ([other] = [otherValue]) to prove an edit beside it merges.
final class MergeRow<T extends GeneratedMessage> {
  final Kind<T> kind;
  final String field;
  final Object a;
  final Object b;
  final String other;
  final Object otherValue;

  const MergeRow(this.kind, this.field, this.a, this.b, this.other, this.otherValue);
}

void main() {
  late TwoDevices devices;
  setUp(() async => devices = await TwoDevices.create());
  tearDown(() async => devices.dispose());

  Future<T> shared<T extends GeneratedMessage>(Kind<T> kind) async {
    final value = await kind.create(devices.laptop);
    await devices.sync();
    return value;
  }

  void expectNoConflicts() {
    for (final device in devices.both) {
      expect(device.zen.conflictCount, 0, reason: 'conflicts on ${device.name}');
    }
  }

  void expectConflict<T extends GeneratedMessage>(Kind<T> kind, String id, Set<int> fields) {
    for (final device in devices.both) {
      final conflict = kind.conflict(device, id);
      expect(conflict, isNotNull, reason: '${kind.name}/$id is not in conflict on ${device.name}');
      expect(conflict!.fields, fields, reason: 'conflicting fields on ${device.name}');
      expect(conflict.isDeleteConflict, isFalse);
      expect(device.zen.conflictCount, 1, reason: 'only this record conflicts');
    }
  }

  // ── Merge rows ────────────────────────────────────────────────────────────────────────────────

  final mergeRows = <MergeRow<GeneratedMessage>>[
    MergeRow(accounts, 'name', 'Cash', 'Pocket', 'includeInTotal', false),
    MergeRow(
      accounts,
      'kind',
      AccountKind.ACCOUNT_KIND_CARD,
      AccountKind.ACCOUNT_KIND_SAVINGS,
      'name',
      'Main',
    ),
    MergeRow(accounts, 'active', false, false, 'name', 'Main'),
    MergeRow(accounts, 'includeInTotal', false, false, 'name', 'Main'),
    MergeRow(accounts, 'includeInOverview', false, false, 'name', 'Main'),
    MergeRow(accounts, 'eligibleForGoals', true, true, 'name', 'Main'),
    MergeRow(
      accounts,
      'accountNumber',
      'PL00000000000000000000000001',
      'PL00000000000000000000000002',
      'name',
      'Main',
    ),
    MergeRow(accountCurrencies, 'openingMinor', Int64(500), Int64(700), 'position', 3),
    MergeRow(accountCurrencies, 'position', 1, 2, 'openingMinor', Int64(900)),
    MergeRow(categories, 'title', 'Food', 'Shop', 'colorArgb', 0xFF00FF00),
    MergeRow(categories, 'iconKey', 'basket', 'bag', 'title', 'Food'),
    MergeRow(categories, 'description', 'Weekly', 'Daily', 'title', 'Food'),
    MergeRow(categories, 'colorArgb', 0xFF112233, 0xFF445566, 'title', 'Food'),
    MergeRow(categories, 'archived', true, true, 'title', 'Food'),
    MergeRow(
      categories,
      'kind',
      CategoryDirection.CATEGORY_DIRECTION_INCOME,
      CategoryDirection.CATEGORY_DIRECTION_UNSPECIFIED,
      'title',
      'Food',
    ),
    MergeRow(records, 'title', 'Rolls', 'Baguette', 'note', 'warm'),
    MergeRow(records, 'date', '2026-11-03', '2026-11-04', 'note', 'warm'),
    MergeRow(records, 'payee', 'Bakery', 'Market', 'date', '2026-11-05'),
    MergeRow(records, 'note', 'warm', 'stale', 'title', 'Rolls'),
    MergeRow(budgets, 'amountMinor', Int64(40000), Int64(60000), 'amountMinor', Int64(40000)),
    MergeRow(goals, 'name', 'Bicycle', 'E-bike', 'targetAmountMinor', Int64(250000)),
    MergeRow(goals, 'targetAmountMinor', Int64(250000), Int64(300000), 'name', 'Bicycle'),
    MergeRow(goals, 'targetDate', '2027-06-01', '2027-09-01', 'name', 'Bicycle'),
    MergeRow(plans, 'title', 'Flat', 'Home', 'note', 'landlord'),
    MergeRow(plans, 'payee', 'Landlord', 'Agency', 'title', 'Flat'),
    MergeRow(plans, 'note', 'landlord', 'agency', 'title', 'Flat'),
    MergeRow(occurrences, 'skipped', true, true, 'reminderReadAtMs', Int64(5000)),
    MergeRow(settings, 'mainCurrency', 'EUR', 'USD', 'defaultAccountId', 'a' * 32),
    MergeRow(settings, 'defaultAccountId', 'a' * 32, 'b' * 32, 'mainCurrency', 'EUR'),
  ];

  for (final row in mergeRows) {
    group('Merge ${row.kind.name}.${row.field}', () {
      final distinct = row.a != row.b;
      if (distinct) {
        test('two different values are a conflict on that field alone', () async {
          final base = await shared(row.kind);
          final id = getByName(base, 'id') as String;
          await row.kind.edit(devices.laptop, id, (v) => setByName(v, row.field, row.a));
          await row.kind.edit(devices.phone, id, (v) => setByName(v, row.field, row.b));
          await devices.sync();
          expectConflict(row.kind, id, {tagOf(base, row.field)});
        });
      }

      test('beside an edit to another field it merges, nothing is asked', () async {
        final base = await shared(row.kind);
        final id = getByName(base, 'id') as String;
        if (row.other == row.field) return; // a one-field record: the conflict test is the row
        await row.kind.edit(devices.laptop, id, (v) => setByName(v, row.field, row.a));
        await row.kind.edit(devices.phone, id, (v) => setByName(v, row.other, row.otherValue));
        await devices.sync();
        expectNoConflicts();
        for (final device in devices.both) {
          final value = row.kind.read(device, id);
          expect(getByName(value, row.field), row.a);
          expect(getByName(value, row.other), row.otherValue);
        }
      });

      test('the same value on both devices merges', () async {
        final base = await shared(row.kind);
        final id = getByName(base, 'id') as String;
        await row.kind.edit(devices.laptop, id, (v) => setByName(v, row.field, row.a));
        await row.kind.edit(devices.phone, id, (v) => setByName(v, row.field, row.a));
        await devices.sync();
        expectNoConflicts();
        for (final device in devices.both) {
          expect(getByName(row.kind.read(device, id), row.field), row.a);
        }
      });
    });
  }

  test(
    'Merge records.category_id: re-filing on one device beside an amount fix on the other merges',
    () async {
      final base = await shared(records);
      final other = Device.ok(
        await devices.laptop.store.putCategory(
          Fixtures.category(devices.laptop.store, title: 'Bakery'),
        ),
      );
      await devices.sync();
      await records.edit(devices.laptop, base.id, (r) => r.categoryId = other.id);
      await records.edit(
        devices.phone,
        base.id,
        (r) => r.posting = (r.posting.deepCopy()..amountMinor = Int64(-1300)),
      );
      await devices.sync();
      expectNoConflicts();
      for (final device in devices.both) {
        final r = records.read(device, base.id);
        expect(r.categoryId, other.id);
        expect(r.posting.amountMinor, Int64(-1300));
      }
    },
  );

  test('Merge plans.category_id: two different categories are a conflict on that field', () async {
    final base = await shared(plans);
    final c1 = Device.ok(
      await devices.laptop.store.putCategory(
        Fixtures.category(devices.laptop.store, title: 'Home'),
      ),
    );
    final c2 = Device.ok(
      await devices.laptop.store.putCategory(
        Fixtures.category(devices.laptop.store, title: 'Bills'),
      ),
    );
    await devices.sync();
    await plans.edit(devices.laptop, base.id, (p) => p.categoryId = c1.id);
    await plans.edit(devices.phone, base.id, (p) => p.categoryId = c2.id);
    await devices.sync();
    expectConflict(plans, base.id, {tagOf(base, 'categoryId')});
  });

  // ── Group rows ────────────────────────────────────────────────────────────────────────────────

  group('Group', () {
    test('records.posting: a currency on one device and an amount on the other never become money '
        'nobody entered — one conflict on the posting', () async {
      final ledger = await Fixtures.ledger(devices.laptop);
      Device.ok(
        await devices.laptop.store.putAccountCurrency(
          Fixtures.currency(ledger.account.id, 'EUR', position: 1),
        ),
      );
      await devices.sync();
      final id = ledger.record.id;
      await records.edit(
        devices.laptop,
        id,
        (r) => r.posting = (r.posting.deepCopy()..currency = 'EUR'),
      );
      await records.edit(
        devices.phone,
        id,
        (r) => r.posting = (r.posting.deepCopy()..amountMinor = Int64(-6000)),
      );
      await devices.sync();
      expectConflict(records, id, {tagOf(ledger.record, 'posting')});
      for (final device in devices.both) {
        final sides = records.conflict(device, id)!.sides.map((s) => s.value!.posting).toSet();
        // Each side is a whole posting a device wrote; the mixed "60.00 EUR" is on neither.
        expect(sides, {
          Posting(accountId: ledger.account.id, currency: 'EUR', amountMinor: Int64(-1250)),
          Posting(accountId: ledger.account.id, currency: 'PLN', amountMinor: Int64(-6000)),
        });
      }
    });

    test(
      'plans.posting: an account on one device and an amount on the other conflict as one',
      () async {
        final base = await shared(plans);
        final second = Device.ok(
          await devices.laptop.store.putAccount(
            Fixtures.account(devices.laptop.store, name: 'Bank'),
          ),
        );
        await devices.sync();
        await plans.edit(
          devices.laptop,
          base.id,
          (p) => p.posting = (p.posting.deepCopy()..accountId = second.id),
        );
        await plans.edit(
          devices.phone,
          base.id,
          (p) => p.posting = (p.posting.deepCopy()..amountMinor = Int64(-95000)),
        );
        await devices.sync();
        expectConflict(plans, base.id, {tagOf(base, 'posting')});
      },
    );

    test('plans.schedule: an interval on one device and an end on the other are a schedule nobody chose', () async {
      final base = await shared(plans);
      await plans.edit(
        devices.laptop,
        base.id,
        (p) => p.schedule = (p.schedule.deepCopy()..interval = 2),
      );
      await plans.edit(
        devices.phone,
        base.id,
        (p) => p.schedule = (p.schedule.deepCopy()..untilDate = '2027-12-01'),
      );
      await devices.sync();
      expectConflict(plans, base.id, {tagOf(base, 'schedule')});
    });

    test(
      'plans.reminder: enabled on one device and a lead time on the other conflict as one',
      () async {
        final base = await shared(plans);
        await plans.edit(
          devices.laptop,
          base.id,
          (p) => p.reminder = (p.reminder.deepCopy()..enabled = true),
        );
        await plans.edit(
          devices.phone,
          base.id,
          (p) => p.reminder = (p.reminder.deepCopy()..leadDays = 7),
        );
        await devices.sync();
        expectConflict(plans, base.id, {tagOf(base, 'reminder')});
      },
    );
  });

  // ── Same-intent rows (earliest: jZenDev/jZen#235; earliestBy: #244) ────────────────────────────

  group('Same-intent', () {
    test(
      'goals.status: completed on both devices at two moments merges and keeps the first',
      () async {
        final base = await shared(goals);
        await goals.edit(
          devices.laptop,
          base.id,
          (g) => g
            ..status = GoalState.GOAL_STATE_COMPLETED
            ..statusChangedAtMs = Int64(5000),
        );
        await goals.edit(
          devices.phone,
          base.id,
          (g) => g
            ..status = GoalState.GOAL_STATE_COMPLETED
            ..statusChangedAtMs = Int64(4000),
        );
        await devices.sync();
        expectNoConflicts();
        for (final device in devices.both) {
          final goal = goals.read(device, base.id);
          expect(goal.status, GoalState.GOAL_STATE_COMPLETED);
          expect(goal.statusChangedAtMs, Int64(4000));
        }
      },
    );

    test('goals.status: completed on one device and archived on the other is a question', () async {
      final base = await shared(goals);
      await goals.edit(
        devices.laptop,
        base.id,
        (g) => g
          ..status = GoalState.GOAL_STATE_COMPLETED
          ..statusChangedAtMs = Int64(5000),
      );
      await goals.edit(
        devices.phone,
        base.id,
        (g) => g
          ..status = GoalState.GOAL_STATE_ARCHIVED
          ..statusChangedAtMs = Int64(4000),
      );
      await devices.sync();
      expectConflict(goals, base.id, {tagOf(base, 'status')});
    });

    test('occurrences.reminder_read_at: read on both devices keeps the first moment', () async {
      final base = await shared(occurrences);
      await occurrences.edit(devices.laptop, base.id, (o) => o.reminderReadAtMs = Int64(9000));
      await occurrences.edit(devices.phone, base.id, (o) => o.reminderReadAtMs = Int64(7000));
      await devices.sync();
      expectNoConflicts();
      for (final device in devices.both) {
        expect(occurrences.read(device, base.id).reminderReadAtMs, Int64(7000));
      }
    });

    test(
      'occurrences.reminder_read_at: unread on one device against read on the other is a question',
      () async {
        final base = await shared(occurrences);
        await occurrences.edit(devices.laptop, base.id, (o) => o.reminderReadAtMs = Int64(9000));
        await devices.sync();
        await occurrences.edit(devices.laptop, base.id, (o) => o.clearReminderReadAtMs());
        await occurrences.edit(devices.phone, base.id, (o) => o.reminderReadAtMs = Int64(8000));
        await devices.sync();
        expectConflict(occurrences, base.id, {tagOf(base, 'reminderReadAtMs')});
      },
    );

    test('budget_resets.revocation: revoked on both devices merges and keeps the first revocation '
        'whole, who and when (jZenDev/jZen#244)', () async {
      final category = Device.ok(
        await devices.laptop.store.putCategory(Fixtures.category(devices.laptop.store)),
      );
      final reset = BudgetCarryOverReset(
        id: devices.laptop.store.newId(),
        categoryId: category.id,
        month: '2026-11',
        currency: 'PLN',
        discardedMinor: Int64(1200),
        note: 'fresh start',
        createdBy: devices.laptop.store.deviceId,
        createdAtMs: Int64(1000),
      );
      Device.ok(await devices.laptop.store.addBudgetReset(reset));
      await devices.sync();
      Device.ok(await devices.laptop.store.revokeBudgetReset(reset.id, atMs: 3000));
      Device.ok(await devices.phone.store.revokeBudgetReset(reset.id, atMs: 2000));
      await devices.sync();
      expectNoConflicts();
      for (final device in devices.both) {
        final revocation = Device.ok(device.store.budgetResets.get(reset.id)).revocation;
        // The phone revoked first; its device id comes with its time, never the laptop's.
        expect((revocation.by, revocation.atMs.toInt()), (devices.phone.store.deviceId, 2000));
      }
    });

    test('the policies are declared on exactly those fields', () {
      expect(StorePolicies.goals, {tagOf(Goal(), 'statusChangedAtMs'): ZenMergePolicy.earliest});
      expect(StorePolicies.occurrences, {
        tagOf(OccurrenceState(), 'reminderReadAtMs'): ZenMergePolicy.earliest,
      });
      expect(StorePolicies.budgetResets, {
        tagOf(BudgetCarryOverReset(), 'revocation'): ZenMergePolicy.earliestBy(
          tagOf(Revocation(), 'atMs'),
        ),
      });
      // Field numbers are frozen: a renumbering would move a policy onto another field.
      expect(tagOf(Goal(), 'statusChangedAtMs'), 7);
      expect(tagOf(OccurrenceState(), 'reminderReadAtMs'), 5);
      expect(tagOf(BudgetCarryOverReset(), 'revocation'), 9);
      expect(tagOf(Revocation(), 'atMs'), 2);
    });
  });

  // ── Ids from natural keys ─────────────────────────────────────────────────────────────────────

  group('Ids from natural keys', () {
    test('account_currencies: the same currency added on both devices is one record', () async {
      final account = await shared(accounts);
      Device.ok(
        await devices.laptop.store.putAccountCurrency(
          Fixtures.currency(account.id, 'EUR', opening: 300),
        ),
      );
      Device.ok(
        await devices.phone.store.putAccountCurrency(
          Fixtures.currency(account.id, 'EUR', opening: 300),
        ),
      );
      await devices.sync();
      expectNoConflicts();
      for (final device in devices.both) {
        expect(
          Device.ok(device.store.accountCurrencies.list()).where((c) => c.currency == 'EUR'),
          hasLength(1),
        );
      }
    });

    test('account_currencies: two different openings for one currency are a question', () async {
      final account = await shared(accounts);
      final id = DerivedIds.accountCurrency(account.id, 'EUR');
      Device.ok(
        await devices.laptop.store.putAccountCurrency(
          Fixtures.currency(account.id, 'EUR', opening: 300),
        ),
      );
      Device.ok(
        await devices.phone.store.putAccountCurrency(
          Fixtures.currency(account.id, 'EUR', opening: 400),
        ),
      );
      await devices.sync();
      expectConflict(accountCurrencies, id, {tagOf(AccountCurrency(), 'openingMinor')});
    });

    test(
      'budgets: one slot planned on both devices is one record; two plans for it are a question',
      () async {
        final category = await shared(categories);
        final id = DerivedIds.budget(category.id, '2026-12', 'PLN');
        Budget slot(int amount) => Budget(
          id: id,
          categoryId: category.id,
          month: '2026-12',
          currency: 'PLN',
          amountMinor: Int64(amount),
        );
        Device.ok(await devices.laptop.store.putBudget(slot(30000)));
        Device.ok(await devices.phone.store.putBudget(slot(35000)));
        await devices.sync();
        expectConflict(budgets, id, {tagOf(Budget(), 'amountMinor')});
        for (final device in devices.both) {
          expect(Device.ok(device.store.budgets.list()), hasLength(1));
        }
      },
    );

    test(
      'settings: started on both devices, it is one record, and two main currencies are a question',
      () async {
        Device.ok(
          await devices.laptop.store.putSettings(
            Settings(id: DerivedIds.settings, mainCurrency: 'PLN'),
          ),
        );
        Device.ok(
          await devices.phone.store.putSettings(
            Settings(id: DerivedIds.settings, mainCurrency: 'EUR'),
          ),
        );
        await devices.sync();
        expectConflict(settings, DerivedIds.settings, {tagOf(Settings(), 'mainCurrency')});
      },
    );

    test(
      'settings.default_account_id: two defaults are impossible — choosing two is a question',
      () async {
        await shared(settings);
        final a = Device.ok(
          await devices.laptop.store.putAccount(Fixtures.account(devices.laptop.store)),
        );
        final b = Device.ok(
          await devices.laptop.store.putAccount(
            Fixtures.account(devices.laptop.store, name: 'Bank'),
          ),
        );
        await devices.sync();
        await settings.edit(devices.laptop, DerivedIds.settings, (s) => s.defaultAccountId = a.id);
        await settings.edit(devices.phone, DerivedIds.settings, (s) => s.defaultAccountId = b.id);
        await devices.sync();
        expectConflict(settings, DerivedIds.settings, {tagOf(Settings(), 'defaultAccountId')});
      },
    );

    test('a record confirming one occurrence on both devices is one record', () async {
      final ledger = await Fixtures.ledger(devices.laptop);
      await devices.sync();
      final planId = devices.laptop.store.newId();
      final occurrence = DerivedIds.occurrence(planId, '2026-11-01');
      Record confirming() =>
          Fixtures.record(
              devices.laptop.store,
              accountId: ledger.account.id,
              categoryId: ledger.category.id,
            )
            ..id = DerivedIds.confirmation(occurrence)
            ..planLink = PlanLink(planId: planId, occurrenceId: occurrence);
      Device.ok(await devices.laptop.store.putRecord(confirming()));
      Device.ok(await devices.phone.store.putRecord(confirming()));
      await devices.sync();
      expectNoConflicts();
      for (final device in devices.both) {
        expect(Device.ok(device.store.records.list()).where((r) => r.hasPlanLink()), hasLength(1));
      }
    });
  });

  // ── Records that are written once ─────────────────────────────────────────────────────────────

  group('Immutable records', () {
    test('transfers: one record arrives whole, and deleting it on both devices merges', () async {
      final ledger = await Fixtures.ledger(devices.laptop);
      final bank = Device.ok(
        await devices.laptop.store.putAccount(Fixtures.account(devices.laptop.store, name: 'Bank')),
      );
      Device.ok(await devices.laptop.store.putAccountCurrency(Fixtures.currency(bank.id, 'PLN')));
      final transfer = Device.ok(
        await devices.laptop.store.addTransfer(
          Transfer(
            id: devices.laptop.store.newId(),
            title: 'Top up',
            date: '2026-11-03',
            source: Posting(
              accountId: ledger.account.id,
              currency: 'PLN',
              amountMinor: Int64(2000),
            ),
            destination: Posting(accountId: bank.id, currency: 'PLN', amountMinor: Int64(2000)),
          ),
        ),
      );
      await devices.sync();
      expect(Device.ok(devices.phone.store.transfers.get(transfer.id)), transfer);
      Device.ok(await devices.laptop.store.deleteTransfer(transfer.id));
      Device.ok(await devices.phone.store.deleteTransfer(transfer.id));
      await devices.sync();
      expectNoConflicts();
      for (final device in devices.both) {
        expect(Device.ok(device.store.transfers.list()), isEmpty);
      }
    });

    test('goal_allocations: entries made on two devices never meet', () async {
      final goal = await shared(goals);
      GoalAllocation entry(Device d, int amount) => GoalAllocation(
        id: d.store.newId(),
        kind: AllocationKind.ALLOCATION_KIND_ALLOCATE,
        targetGoalId: goal.id,
        currency: 'PLN',
        amountMinor: Int64(amount),
        createdAtMs: Int64(1),
        createdBy: d.store.deviceId,
      );
      Device.ok(await devices.laptop.store.addGoalAllocation(entry(devices.laptop, 100)));
      Device.ok(await devices.phone.store.addGoalAllocation(entry(devices.phone, 200)));
      await devices.sync();
      expectNoConflicts();
      for (final device in devices.both) {
        expect(
          Device.ok(device.store.goalAllocations.list()).map((a) => a.amountMinor.toInt()).toSet(),
          {100, 200},
        );
      }
    });
  });

  // ── Edit against delete ───────────────────────────────────────────────────────────────────────

  test('an edit on one device against a delete on the other is a question (D5)', () async {
    final base = await shared(budgets);
    await budgets.edit(devices.laptop, base.id, (b) => b.amountMinor = Int64(70000));
    Device.ok(await devices.phone.store.deleteBudget(base.id));
    await devices.sync();
    for (final device in devices.both) {
      final conflict = budgets.conflict(device, base.id)!;
      expect(conflict.isDeleteConflict, isTrue);
      expect(conflict.sides.where((s) => s.isDelete), hasLength(1));
    }
  });

  // ── Derived and device rows: not in the store ─────────────────────────────────────────────────

  group('Derived and device-only', () {
    Set<String> fields(GeneratedMessage m) => m.info_.byName.keys.toSet();

    test('no stored figure two devices could both change', () {
      expect(fields(Account()), isNot(contains('balances'))); // derived (F-03)
      expect(fields(Account()), isNot(contains('isDefault'))); // moved to Settings
      expect(fields(Record()), isNot(contains('transferId'))); // a transfer is its own record
      expect(fields(Record()), isNot(contains('isCorrection'))); // the correction intent's presence
      for (final derived in [
        'status',
        'title',
        'amountMinor',
        'currency',
        'accountId',
        'categoryId',
      ]) {
        expect(fields(OccurrenceState()), isNot(contains(derived)));
      }
      expect(fields(Goal()), isNot(contains('allocatedMinor'))); // envelopes are sums of entries
    });

    test('import sessions and rows are not a synced collection', () {
      final names = {
        for (final c in [
          devices.laptop.store.accounts,
          devices.laptop.store.accountCurrencies,
          devices.laptop.store.categories,
          devices.laptop.store.records,
          devices.laptop.store.transfers,
          devices.laptop.store.budgets,
          devices.laptop.store.budgetResets,
          devices.laptop.store.goals,
          devices.laptop.store.goalAllocations,
          devices.laptop.store.plans,
          devices.laptop.store.occurrences,
          devices.laptop.store.settings,
        ])
          c.name,
      };
      expect(names.where((n) => n.contains('import')), isEmpty);
    });
  });
}
