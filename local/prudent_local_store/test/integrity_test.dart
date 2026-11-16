// The integrity-check runner (finding F-05, ADR-102 D6) and each check of the store model: every rule
// is broken here on one device — PrudentLocalStore refuses no cross-record break, exactly so that what a
// merge produces can be written in a test — and each issue is then settled by one of its own actions.
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
  late IntegrityRunner runner;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prudent_local_integrity');
    zen = Device.ok(await ZenStore.open(dir, deviceName: 'Laptop', key: List.filled(32, 9)));
    store = PrudentLocalStore(zen);
    runner = IntegrityRunner(store);
  });
  tearDown(() async {
    await zen.close();
    await dir.delete(recursive: true);
  });

  List<IntegrityIssue> issues() => Device.ok(runner.evaluate());
  IntegrityIssue only(String code) {
    final found = issues();
    expect(found.map((i) => i.code), [code], reason: '$found');
    return found.single;
  }

  IntegrityAction action(IntegrityIssue issue, String code) =>
      issue.actions.firstWhere((a) => a.code == code, orElse: () => fail('no $code in $issue'));

  Future<void> settle(IntegrityIssue issue, String code, [String? input]) async {
    final result = await action(issue, code).run(input);
    expect(result.isSuccess, isTrue, reason: '$code: ${result.errorOrNull?.message}');
  }

  Future<({Account account, Category category, Record record})> ledger() async {
    final account = Device.ok(await store.putAccount(Fixtures.account(store)));
    Device.ok(await store.putAccountCurrency(Fixtures.currency(account.id, 'PLN')));
    final category = Device.ok(await store.putCategory(Fixtures.category(store)));
    final record = Device.ok(
      await store.putRecord(Fixtures.record(store, accountId: account.id, categoryId: category.id)),
    );
    return (account: account, category: category, record: record);
  }

  test('a consistent store has no issues', () async {
    await ledger();
    Device.ok(await store.putSettings(Settings(id: 'settings', mainCurrency: 'PLN')));
    expect(issues(), isEmpty);
  });

  group('dangling references', () {
    test('a record on a deleted account: delete it, move it, or re-create the account', () async {
      final l = await ledger();
      final other = Device.ok(await store.putAccount(Fixtures.account(store, name: 'Bank')));
      Device.ok(await store.putAccountCurrency(Fixtures.currency(other.id, 'PLN')));
      Device.ok(await store.deleteAccount(l.account.id));
      // The deleted account's currency record dangles too; it is an issue of its own.
      expect(issues().map((i) => i.code), [
        'reference.currency_account_missing',
        'reference.record_account_missing',
      ]);
      final issue = issues().last;
      expect(issue.id, 'reference.record_account_missing:records/${l.record.id}');
      expect(issue.facts, {'accountId': l.account.id});
      expect(issue.actions.map((a) => a.code), [
        'delete_record',
        'move_to_account',
        'recreate_account',
      ]);
      expect(action(issue, 'move_to_account').choices, [other.id]);
      await settle(issue, 'move_to_account', other.id);
      expect(Device.ok(store.records.get(l.record.id)).posting.accountId, other.id);
      final rest = only('reference.currency_account_missing');
      await settle(rest, 'delete_account_currency');
      expect(issues(), isEmpty);
    });

    test('re-creating a deleted account takes the name the person gives', () async {
      final l = await ledger();
      Device.ok(await store.deleteAccount(l.account.id));
      final issue = issues().firstWhere((i) => i.code == 'reference.record_account_missing');
      expect(action(issue, 'recreate_account').needsText, isTrue);
      await settle(issue, 'recreate_account', 'Wallet again');
      expect(Device.ok(store.accounts.get(l.account.id)).name, 'Wallet again');
      expect(issues(), isEmpty); // the currency record is no longer dangling either
    });

    test('a correction or an imported record on a deleted account is not offered a move', () async {
      final account = Device.ok(await store.putAccount(Fixtures.account(store)));
      final other = Device.ok(await store.putAccount(Fixtures.account(store, name: 'Bank')));
      final correction = Device.ok(
        await store.putRecord(
          Fixtures.record(store, accountId: account.id)
            ..correction = CorrectionIntent(targetMinor: Int64(1), seenMinor: Int64(0)),
        ),
      );
      Device.ok(await store.putAccountCurrency(Fixtures.currency(other.id, 'PLN')));
      Device.ok(await store.deleteAccount(account.id));
      final issue = only('reference.record_account_missing');
      expect(issue.recordId, correction.id);
      expect(issue.actions.map((a) => a.code), ['delete_record', 'recreate_account']);
    });

    test('a record under a deleted category: move it to another, or delete it', () async {
      final l = await ledger();
      final bakery = Device.ok(await store.putCategory(Fixtures.category(store, title: 'Bakery')));
      final archived = Device.ok(
        await store.putCategory(Fixtures.category(store, title: 'Old')..archived = true),
      );
      Device.ok(await store.deleteCategory(l.category.id));
      final issue = only('reference.record_category_missing');
      // An archived category refuses new records, so it is not offered.
      expect(action(issue, 'move_to_category').choices, [bakery.id]);
      expect(action(issue, 'move_to_category').choices, isNot(contains(archived.id)));
      await settle(issue, 'move_to_category', bakery.id);
      expect(issues(), isEmpty);
    });

    test('a transfer whose account was deleted can only be deleted (it is never edited)', () async {
      final l = await ledger();
      final bank = Device.ok(await store.putAccount(Fixtures.account(store, name: 'Bank')));
      Device.ok(await store.putAccountCurrency(Fixtures.currency(bank.id, 'PLN')));
      final transfer = Device.ok(
        await store.addTransfer(
          Transfer(
            id: store.newId(),
            title: 'Top up',
            date: '2026-11-03',
            source: Posting(accountId: l.account.id, currency: 'PLN', amountMinor: Int64(100)),
            destination: Posting(accountId: bank.id, currency: 'PLN', amountMinor: Int64(100)),
          ),
        ),
      );
      Device.ok(await store.deleteRecord(l.record.id));
      Device.ok(await store.deleteAccountCurrency(DerivedIds.accountCurrency(bank.id, 'PLN')));
      Device.ok(await store.deleteAccount(bank.id));
      final found = issues();
      expect(found.map((i) => i.id), [
        'reference.transfer_account_missing:transfers/${transfer.id}:destination',
      ]);
      expect(found.single.actions.map((a) => a.code), ['delete_transfer', 'recreate_account']);
      await settle(found.single, 'delete_transfer');
      expect(issues(), isEmpty);
    });

    test('a plan on a deleted account or category', () async {
      final l = await ledger();
      final plan = Device.ok(
        await store.putPlan(
          Plan(
            id: store.newId(),
            title: 'Rent',
            posting: Posting(accountId: l.account.id, currency: 'PLN', amountMinor: Int64(-90000)),
            categoryId: l.category.id,
          ),
        ),
      );
      Device.ok(await store.deleteRecord(l.record.id));
      Device.ok(await store.deleteCategory(l.category.id));
      final issue = only('reference.plan_category_missing');
      expect(issue.recordId, plan.id);
      await settle(issue, 'recreate_category', 'Housing');
      expect(issues(), isEmpty);
      Device.ok(await store.deleteAccountCurrency(DerivedIds.accountCurrency(l.account.id, 'PLN')));
      Device.ok(await store.deleteAccount(l.account.id));
      await settle(only('reference.plan_account_missing'), 'delete_plan');
      expect(issues(), isEmpty);
    });

    test('a budget under a deleted category: delete it or bring the category back', () async {
      final category = Device.ok(await store.putCategory(Fixtures.category(store)));
      final budget = Device.ok(
        await store.putBudget(
          Budget(
            id: DerivedIds.budget(category.id, '2026-11', 'PLN'),
            categoryId: category.id,
            month: '2026-11',
            currency: 'PLN',
            amountMinor: Int64(100),
          ),
        ),
      );
      Device.ok(await store.deleteCategory(category.id));
      final issue = only('reference.budget_category_missing');
      expect(issue.recordId, budget.id);
      expect(issue.actions.map((a) => a.code), ['delete_budget', 'recreate_category']);
      await settle(issue, 'delete_budget');
      expect(issues(), isEmpty);
    });

    test('a reset under a deleted category is never deleted: the category comes back', () async {
      final category = Device.ok(await store.putCategory(Fixtures.category(store)));
      Device.ok(
        await store.addBudgetReset(
          BudgetCarryOverReset(
            id: store.newId(),
            categoryId: category.id,
            month: '2026-11',
            currency: 'PLN',
            createdBy: store.deviceId,
            createdAtMs: Int64(1),
          ),
        ),
      );
      Device.ok(await store.deleteCategory(category.id));
      final issue = only('reference.reset_category_missing');
      expect(issue.actions.map((a) => a.code), ['recreate_category']);
      await settle(issue, 'recreate_category', 'Groceries');
      expect(issues(), isEmpty);
    });
  });

  test('a default account that was deleted: clear it or choose another', () async {
    final l = await ledger();
    final bank = Device.ok(await store.putAccount(Fixtures.account(store, name: 'Bank')));
    Device.ok(
      await store.putSettings(
        Settings(id: 'settings', mainCurrency: 'PLN', defaultAccountId: l.account.id),
      ),
    );
    Device.ok(await store.deleteRecord(l.record.id));
    Device.ok(await store.deleteAccountCurrency(DerivedIds.accountCurrency(l.account.id, 'PLN')));
    Device.ok(await store.deleteAccount(l.account.id));
    final issue = only('reference.default_account_missing');
    expect(action(issue, 'choose_default_account').choices, [bank.id]);
    await settle(issue, 'choose_default_account', bank.id);
    expect(Device.ok(store.settings.get('settings')).defaultAccountId, bank.id);
    expect(issues(), isEmpty);
  });

  test('money in a currency its account no longer holds: add the currency, or delete', () async {
    final l = await ledger();
    final eur = Device.ok(
      await store.putRecord(
        Fixtures.record(store, accountId: l.account.id, currency: 'EUR', categoryId: l.category.id),
      ),
    );
    final issue = only('currency.record_not_held');
    expect(issue.facts, {'accountId': l.account.id, 'currency': 'EUR'});
    expect(issue.recordId, eur.id);
    await settle(issue, 'add_currency');
    final added = Device.ok(
      store.accountCurrencies.get(DerivedIds.accountCurrency(l.account.id, 'EUR')),
    );
    expect((added.openingMinor.toInt(), added.position), (0, 1));
    expect(issues(), isEmpty);
  });

  test(
    'a record whose sign its category refuses: let the category take both, or move it',
    () async {
      final l = await ledger();
      final income = Device.ok(
        await store.putCategory(
          Fixtures.category(
            store,
            title: 'Refunds',
            kind: CategoryDirection.CATEGORY_DIRECTION_INCOME,
          ),
        ),
      );
      final refund = Device.ok(
        await store.putRecord(
          Fixtures.record(store, accountId: l.account.id, amount: 900, categoryId: l.category.id),
        ),
      );
      final issue = only('category.kind_refuses_sign');
      expect(issue.recordId, refund.id);
      // Only a category that accepts a positive amount is offered.
      expect(action(issue, 'move_to_category').choices, [income.id]);
      await settle(issue, 'category_takes_both');
      expect(
        Device.ok(store.categories.get(l.category.id)).kind,
        CategoryDirection.CATEGORY_DIRECTION_UNSPECIFIED,
      );
      expect(issues(), isEmpty);
    },
  );

  test('canFile is CategoryEntity.canFile, value for value', () {
    const expense = CategoryDirection.CATEGORY_DIRECTION_EXPENSE;
    const income = CategoryDirection.CATEGORY_DIRECTION_INCOME;
    const either = CategoryDirection.CATEGORY_DIRECTION_UNSPECIFIED;
    expect(
      [
        for (final a in [-1, 0, 1]) CategoryKindCheck.canFile(expense, a),
      ],
      [true, true, false],
    );
    expect(
      [
        for (final a in [-1, 0, 1]) CategoryKindCheck.canFile(income, a),
      ],
      [false, true, true],
    );
    expect(
      [
        for (final a in [-1, 0, 1]) CategoryKindCheck.canFile(either, a),
      ],
      [true, true, true],
    );
  });

  test(
    'two accounts with one number: clear it on one; the number never enters the issue',
    () async {
      const number = 'PL00000000000000000000000004';
      final a = Device.ok(await store.putAccount(Fixtures.account(store)..accountNumber = number));
      final b = Device.ok(
        await store.putAccount(Fixtures.account(store, name: 'Bank')..accountNumber = number),
      );
      final issue = only('account.number_duplicate');
      final ids = [a.id, b.id]..sort();
      expect(issue.id, 'account.number_duplicate:accounts/${ids.join('+')}');
      expect(issue.toString(), isNot(contains(number)));
      await settle(issue, 'clear_account_number', b.id);
      expect(Device.ok(store.accounts.get(b.id)).hasAccountNumber(), isFalse);
      expect(issues(), isEmpty);
    },
  );

  test('two live resets for one slot: revoke one; a revoked reset does not count', () async {
    final category = Device.ok(await store.putCategory(Fixtures.category(store)));
    BudgetCarryOverReset reset() => BudgetCarryOverReset(
      id: store.newId(),
      categoryId: category.id,
      month: '2026-11',
      currency: 'PLN',
      createdBy: store.deviceId,
      createdAtMs: Int64(1),
    );
    final first = Device.ok(await store.addBudgetReset(reset()));
    final second = Device.ok(await store.addBudgetReset(reset()));
    final issue = only('budget.reset_slot_twice');
    expect(action(issue, 'revoke_reset').choices, ([first.id, second.id]..sort()));
    await settle(issue, 'revoke_reset', second.id);
    expect(Device.ok(store.budgetResets.get(second.id)).hasRevocation(), isTrue);
    expect(issues(), isEmpty);
  });

  group('the runner', () {
    test('later units extend it with checks of their own', () async {
      final extended = IntegrityRunner(
        store,
        checks: [...IntegrityRunner.storeModelChecks, _AlwaysOneIssue()],
      );
      expect(Device.ok(extended.evaluate()).map((i) => i.code), ['test.always']);
      expect(
        () => IntegrityRunner(store, checks: [_AlwaysOneIssue(), _AlwaysOneIssue()]),
        throwsArgumentError,
      );
    });

    test(
      'issues come ordered by id, and an issue fixed elsewhere simply leaves the list',
      () async {
        final l = await ledger();
        Device.ok(
          await store.putRecord(
            Fixtures.record(
              store,
              accountId: l.account.id,
              currency: 'EUR',
              categoryId: l.category.id,
            ),
          ),
        );
        Device.ok(
          await store.putRecord(
            Fixtures.record(
              store,
              accountId: l.account.id,
              currency: 'USD',
              categoryId: l.category.id,
            ),
          ),
        );
        final found = issues();
        expect(found.map((i) => i.id).toList(), (found.map((i) => i.id).toList()..sort()));
        expect(found, hasLength(2));
        Device.ok(
          await store.putAccountCurrency(Fixtures.currency(l.account.id, 'EUR', position: 1)),
        );
        Device.ok(
          await store.putAccountCurrency(Fixtures.currency(l.account.id, 'USD', position: 2)),
        );
        expect(issues(), isEmpty);
      },
    );

    test('an action refuses input it does not take, and needs the input it does', () async {
      final l = await ledger();
      Device.ok(await store.deleteCategory(l.category.id));
      final issue = only('reference.record_category_missing');
      expect(
        (await action(issue, 'delete_record').run('x')).errorOrNull,
        isA<ZenValidationError>(),
      );
      expect(
        (await action(issue, 'recreate_category').run('  ')).errorOrNull,
        isA<ZenValidationError>(),
      );
      expect(issue.actions.where((a) => a.code == 'move_to_category'), isEmpty); // nowhere to move
      expect(store.records.get(l.record.id).isSuccess, isTrue, reason: 'nothing was written');
    });

    test('an issue needs an action', () {
      expect(
        () => IntegrityIssue(code: 'x', collection: 'records', recordId: 'r', actions: const []),
        throwsArgumentError,
      );
    });
  });
}

final class _AlwaysOneIssue implements IntegrityCheck {
  @override
  String get name => 'always';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) => [
    IntegrityIssue(
      code: 'test.always',
      collection: 'settings',
      recordId: 'settings',
      actions: [IntegrityAction.now('noop', () async => const ZenResult.ok(null))],
    ),
  ];
}
