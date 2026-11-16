// Unit 5's rules on one device (phase-0 §0.3 rows 5.1–5.53, ADR-113): each rule of the ledger, the
// values it writes, and what it refuses with which status. The same rules run against the live server
// through the parity scenarios (local/prudent_local_core/parity/scenarios, tools/prudent_parity_server);
// these tests pin what the scenarios cannot see — the store records written, presence-exactness, the
// all-or-nothing delete — and every refusal by rule.
import 'dart:io';

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
  late Directory directory;
  late ZenStore zen;
  late PrudentLocalStore store;
  late Ledger ledger;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prudent_ledger_test');
    zen = Device.ok(await ZenStore.open(directory, deviceName: 'one', key: List.filled(32, 3)));
    store = PrudentLocalStore(zen);
    ledger = Ledger(store);
  });
  tearDown(() async {
    await zen.close();
    await directory.delete(recursive: true);
  });

  /// The status and rule of a refusal; fails the test on success or on a store error.
  (int, String) refused<T>(ZenResult<T> result) => switch (result) {
    ZenSuccess(:final data) => fail('expected a refusal, got $data'),
    ZenFailure(:final error) => (
      LedgerErrors.statusOf(error) ??
          fail('not a ledger refusal: ${error.runtimeType} ${error.message}'),
      error.internalData!['rule'] as String,
    ),
  };

  Future<wire.Account> account({
    String name = 'Wallet',
    Map<String, int> balances = const {'PLN': 10000},
    bool isDefault = false,
    String number = '',
  }) async => Device.ok(
    await ledger.createAccount(
      wire.CreateAccountRequest(
        name: name,
        type: wire.AccountType.ACCOUNT_TYPE_CASH,
        isDefault: isDefault,
        accountNumber: number,
        balances: [
          for (final MapEntry(:key, :value) in balances.entries)
            wire.CurrencyBalance(currency: key, amountMinor: Int64(value)),
        ],
      ),
    ),
  );

  Future<wire.Category> category({
    String title = 'Groceries',
    wire.CategoryKind kind = wire.CategoryKind.CATEGORY_KIND_UNSPECIFIED,
  }) async => Device.ok(
    await ledger.createCategory(
      wire.CreateCategoryRequest(title: title, iconKey: 'food', kind: kind),
    ),
  );

  wire.CreateRecordRequest recordRequest(
    String accountId,
    String categoryId, {
    int amount = -1250,
    String currency = 'PLN',
    String date = '2026-11-02',
    String title = 'Bread',
  }) => wire.CreateRecordRequest(
    title: title,
    amountMinor: Int64(amount),
    date: date,
    categoryId: categoryId,
    accountId: accountId,
    currency: currency,
  );

  Map<String, int> balances(wire.Account a) => {
    for (final b in a.balances) b.currency: b.amountMinor.toInt(),
  };

  Future<Map<String, int>> balanceOf(String accountId) async =>
      balances(Device.ok(await ledger.getAccount(accountId)));

  group('accounts', () {
    test(
      '5.1–5.4: a create is refused for a blank name, no type, no currency, a repeated one',
      () async {
        Future<(int, String)> create(wire.CreateAccountRequest r) async =>
            refused(await ledger.createAccount(r));
        final pln = [wire.CurrencyBalance(currency: 'PLN')];
        expect(
          await create(
            wire.CreateAccountRequest(
              name: ' ',
              type: wire.AccountType.ACCOUNT_TYPE_CASH,
              balances: pln,
            ),
          ),
          (400, '5.1'),
        );
        expect(await create(wire.CreateAccountRequest(name: 'A', balances: pln)), (400, '5.2'));
        expect(
          await create(
            wire.CreateAccountRequest(name: 'A', type: wire.AccountType.ACCOUNT_TYPE_CASH),
          ),
          (400, '5.3'),
        );
        expect(
          await create(
            wire.CreateAccountRequest(
              name: 'A',
              type: wire.AccountType.ACCOUNT_TYPE_CASH,
              balances: [
                wire.CurrencyBalance(currency: 'pln'),
                wire.CurrencyBalance(currency: ' PLN '),
              ],
            ),
          ),
          (400, '5.4'),
        );
        expect(Device.ok(store.accounts.list()), isEmpty, reason: 'nothing was written');
      },
    );

    test(
      'a create writes the account, one opening record per currency in order, presence-exact',
      () async {
        final a = await account(name: '  Wallet ', balances: {'eur': 0, 'PLN': 500});
        expect(a.name, 'Wallet');
        expect(
          [for (final b in a.balances) b.currency],
          ['EUR', 'PLN'],
          reason: '5.5: declared order',
        );
        final stored = Device.ok(store.accounts.get(a.id));
        // Only what differs from a default is set: false flags and an empty number are absent, so a
        // later edit on another device never conflicts with a default nobody chose (jZenDev/jZen#245).
        expect(stored.hasActive(), isFalse);
        expect(stored.hasAccountNumber(), isFalse);
        expect(stored.hasEligibleForGoals(), isFalse, reason: '5.13: off by default');
        final eur = Device.ok(store.accountCurrencies.get(DerivedIds.accountCurrency(a.id, 'EUR')));
        expect(eur.hasOpeningMinor(), isFalse);
        expect(eur.hasPosition(), isFalse);
        final pln = Device.ok(store.accountCurrencies.get(DerivedIds.accountCurrency(a.id, 'PLN')));
        expect((pln.openingMinor.toInt(), pln.position), (500, 1));
      },
    );

    test('5.8: the default is one settings field; a new default replaces the old', () async {
      final a = await account(name: 'A', isDefault: true);
      final b = await account(name: 'B', isDefault: true);
      expect(Device.ok(store.settings.get(DerivedIds.settings)).defaultAccountId, b.id);
      expect(Device.ok(await ledger.getAccount(a.id)).isDefault, isFalse);
      expect(Device.ok(await ledger.getAccount(b.id)).isDefault, isTrue);
    });

    test('5.9: one account number per person, whatever its spelling (409)', () async {
      await account(name: 'A', number: 'PL61 1090 1014 0000 0000 0000 0000');
      final r = await ledger.createAccount(
        wire.CreateAccountRequest(
          name: 'B',
          type: wire.AccountType.ACCOUNT_TYPE_CARD,
          accountNumber: '61109010140000000000000000',
          balances: [wire.CurrencyBalance(currency: 'PLN')],
        ),
      );
      expect(refused(r), (409, '5.9'));
      expect(
        (r.errorOrNull!.internalData!['code'], r.errorOrNull!.message),
        ('conflict', 'Another of your accounts already has this account number.'),
        reason: 'the code and words the shared account form already reads',
      );
    });

    test(
      '5.6, 5.7: a currency in use by a record, a transfer or a plan cannot be dropped',
      () async {
        final a = await account(balances: {'PLN': 0, 'EUR': 0, 'USD': 0});
        final b = await account(name: 'B', balances: {'USD': 0});
        final c = await category();
        Device.ok(await ledger.createRecord(recordRequest(a.id, c.id)));
        Device.ok(
          await ledger.createTransfer(
            wire.CreateTransferRequest(
              fromAccountId: b.id,
              toAccountId: a.id,
              fromAmountMinor: Int64(1),
              toAmountMinor: Int64(1),
              fromCurrency: 'USD',
              toCurrency: 'USD',
              date: '2026-11-01',
            ),
          ),
        );
        wire.UpdateAccountRequest keep(List<String> codes) => wire.UpdateAccountRequest(
          name: 'Wallet',
          type: wire.AccountType.ACCOUNT_TYPE_CASH,
          balances: [for (final c in codes) wire.CurrencyBalance(currency: c)],
        );
        expect(refused(await ledger.updateAccount(a.id, keep(['EUR', 'USD']))), (409, '5.6'));
        expect(refused(await ledger.updateAccount(a.id, keep(['PLN', 'EUR']))), (409, '5.6'));
        Device.ok(
          await store.putPlan(
            Plan(
              id: store.newId(),
              title: 'Rent',
              posting: Posting(accountId: a.id, currency: 'EUR'),
            ),
          ),
        );
        expect(refused(await ledger.updateAccount(a.id, keep(['PLN', 'USD']))), (409, '5.7'));
        final updated = Device.ok(await ledger.updateAccount(a.id, keep(['USD', 'EUR', 'PLN'])));
        expect([for (final b in updated.balances) b.currency], ['USD', 'EUR', 'PLN']);
      },
    );

    test('an update drops an unused currency\'s opening record in the same write', () async {
      final a = await account(balances: {'PLN': 0, 'EUR': 700});
      Device.ok(
        await ledger.updateAccount(
          a.id,
          wire.UpdateAccountRequest(
            name: 'Wallet',
            type: wire.AccountType.ACCOUNT_TYPE_CASH,
            balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(9))],
          ),
        ),
      );
      expect(Device.ok(store.accountCurrencies.list()).map((c) => c.currency), ['PLN']);
      expect(await balanceOf(a.id), {'PLN': 9});
    });

    test('5.10, 5.11, 5.53: a delete is refused while records or plans remain', () async {
      final a = await account();
      final c = await category();
      Device.ok(await ledger.createRecord(recordRequest(a.id, c.id)));
      expect(refused(await ledger.deleteAccount(a.id)), (409, '5.10'));
      Device.ok(
        await store.putPlan(
          Plan(
            id: store.newId(),
            title: 'Rent',
            posting: Posting(accountId: a.id, currency: 'PLN'),
          ),
        ),
      );
      expect(refused(await ledger.deleteAccount(a.id, deleteRecords: true)), (
        409,
        '5.11',
      ), reason: 'a plan refuses even with the flag');
      expect(Device.ok(store.records.list()), hasLength(1), reason: 'checked before anything goes');
    });

    test(
      '5.12: deleted with its records — every kind, both legs, the default — in one write',
      () async {
        final a = await account(name: 'A', isDefault: true, balances: {'PLN': 1000});
        final b = await account(name: 'B', balances: {'PLN': 0});
        final c = await category();
        Device.ok(await ledger.createRecord(recordRequest(a.id, c.id)));
        Device.ok(
          await ledger.createCorrection(
            wire.CreateCorrectionRequest(
              accountId: a.id,
              currency: 'PLN',
              balanceMinor: Int64(1),
              date: '2026-11-03',
            ),
          ),
        );
        Device.ok(
          await ledger.createTransfer(
            wire.CreateTransferRequest(
              fromAccountId: a.id,
              toAccountId: b.id,
              fromAmountMinor: Int64(300),
              toAmountMinor: Int64(300),
              fromCurrency: 'PLN',
              toCurrency: 'PLN',
              date: '2026-11-04',
            ),
          ),
        );
        final kept = Device.ok(await ledger.createRecord(recordRequest(b.id, c.id, amount: -5)));
        expect(await balanceOf(b.id), {'PLN': 295});

        Device.ok(await ledger.deleteAccount(a.id, deleteRecords: true));

        expect(Device.ok(store.accounts.list()).map((x) => x.id), [b.id]);
        expect(Device.ok(store.records.list()).map((r) => r.id), [kept.id]);
        expect(Device.ok(store.transfers.list()), isEmpty);
        expect(Device.ok(store.accountCurrencies.list()).map((x) => x.accountId), [b.id]);
        expect(Device.ok(store.settings.get(DerivedIds.settings)).hasDefaultAccountId(), isFalse);
        expect(await balanceOf(b.id), {'PLN': -5}, reason: 'the other leg went with the transfer');
        expect(
          Device.ok(IntegrityRunner(store).evaluate()),
          isEmpty,
          reason: 'nothing left dangling',
        );
      },
    );

    test('writeAll is all or nothing: one refused operation and no other is written', () async {
      final a = await account();
      final c = await category();
      final records = [
        for (var i = 1; i <= 3; i++)
          Device.ok(await ledger.createRecord(recordRequest(a.id, c.id, amount: -i))),
      ];
      final batch = StoreBatch(store);
      for (final r in records) {
        batch.deleteRecord(r.id);
      }
      batch.deleteAccount(a.id);
      batch.deleteRecord(store.newId()); // not there: the whole batch is refused
      expect((await store.writeAll(batch)).errorOrNull, isA<ZenNotFoundError>());
      expect(Device.ok(store.records.list()), hasLength(3));
      expect(Device.ok(store.accounts.list()), hasLength(1));
      // And a batch member that breaks a store rule is refused before anything is written.
      final rogue = StoreBatch(store)
        ..deleteRecord(records.first.id)
        ..putAccount(Account(id: 'NOT-A-LOCAL-ID'));
      expect((await store.writeAll(rogue)).errorOrNull, isA<ZenValidationError>());
      expect(Device.ok(store.records.list()), hasLength(3));
    });

    test('5.51: accounts are listed by TextRules.compareNames', () async {
      for (final name in ['Zupa', 'Łazienka', 'Lato', 'mleko', 'Mleko']) {
        await account(name: name);
      }
      final names = [for (final a in Device.ok(await ledger.listAccounts()).accounts) a.name];
      expect(names, ['Lato', 'Łazienka', 'Mleko', 'mleko', 'Zupa']);
    });

    test('404 for an id that is not one, or names nothing', () async {
      expect(refused(await ledger.getAccount('nope')), (404, '5.1'));
      expect(refused(await ledger.getAccount(store.newId())), (404, '5.1'));
    });
  });

  group('categories', () {
    test('5.38–5.40: title, icon from the permitted set, kind', () async {
      expect(
        refused(
          await ledger.createCategory(wire.CreateCategoryRequest(title: ' ', iconKey: 'food')),
        ),
        (400, '5.38'),
      );
      expect(
        refused(
          await ledger.createCategory(wire.CreateCategoryRequest(title: 'A', iconKey: 'cart')),
        ),
        (400, '5.39'),
      );
      final c = Device.ok(
        await ledger.createCategory(
          wire.CreateCategoryRequest(
            title: ' Food ',
            iconKey: 'food',
            description: ' x ',
            colorArgb: 0xFF00FF00,
          ),
        ),
      );
      expect(
        (c.title, c.description, c.colorArgb),
        ('Food', ' x ', 0xFF00FF00),
        reason: 'the description is kept as sent, as on the server',
      );
      final stored = Device.ok(store.categories.get(c.id));
      expect((stored.hasKind(), stored.hasArchived()), (false, false));
    });

    test(
      '5.41: archive and restore refuse what changes nothing; an edit keeps the state',
      () async {
        final c = await category();
        expect(Device.ok(await ledger.archiveCategory(c.id)).archived, isTrue);
        expect(refused(await ledger.archiveCategory(c.id)), (409, '5.41'));
        final edited = Device.ok(
          await ledger.updateCategory(
            c.id,
            wire.UpdateCategoryRequest(title: 'Food', iconKey: 'food'),
          ),
        );
        expect(edited.archived, isTrue);
        expect(Device.ok(await ledger.restoreCategory(c.id)).archived, isFalse);
        expect(
          Device.ok(store.categories.get(c.id)).hasArchived(),
          isFalse,
          reason: 'cleared, not false',
        );
        expect(refused(await ledger.restoreCategory(c.id)), (409, '5.41'));
      },
    );

    test('5.42: a delete is refused while a record, plan, budget or reset names it', () async {
      final a = await account();
      Future<void> refusedWhile(
        Future<void> Function(String id) use,
        Future<void> Function() undo,
      ) async {
        final c = await category();
        await use(c.id);
        expect(refused(await ledger.deleteCategory(c.id)), (409, '5.42'));
        await undo();
        Device.ok(await ledger.deleteCategory(c.id));
      }

      late String id;
      await refusedWhile(
        (c) async => id = Device.ok(await ledger.createRecord(recordRequest(a.id, c))).id,
        () async => Device.ok(await ledger.deleteRecord(id)),
      );
      await refusedWhile((c) async {
        id = store.newId();
        Device.ok(await store.putPlan(Plan(id: id, title: 'P', categoryId: c)));
      }, () async => Device.ok(await store.deletePlan(id)));
      await refusedWhile((c) async {
        id = DerivedIds.budget(c, '2026-11', 'PLN');
        Device.ok(
          await store.putBudget(
            Budget(id: id, categoryId: c, month: '2026-11', currency: 'PLN', amountMinor: Int64(1)),
          ),
        );
      }, () async => Device.ok(await store.deleteBudget(id)));
      // A reset is never deleted, so a category with one is never deleted either.
      final c = await category();
      Device.ok(
        await store.addBudgetReset(
          BudgetCarryOverReset(
            id: store.newId(),
            categoryId: c.id,
            month: '2026-11',
            currency: 'PLN',
          ),
        ),
      );
      expect(refused(await ledger.deleteCategory(c.id)), (409, '5.42'));
    });

    test(
      '5.43: start fresh seeds the five starters once, with derived ids, and only when empty',
      () async {
        Device.ok(await ledger.startFresh());
        Device.ok(await ledger.startFresh());
        final titles = [
          for (final c in Device.ok(await ledger.listCategories()).categories) c.title,
        ];
        expect(titles, ['Food', 'Health', 'Leisure', 'Restaurant', 'Work']);
        expect(Device.ok(store.categories.get(DerivedIds.starterCategory('food'))).iconKey, 'food');
        expect(Device.ok(store.settings.list()), isEmpty, reason: 'no settings choice is invented');
      },
    );

    test('5.43: a store that already has a category is not seeded', () async {
      await category(title: 'Mine');
      Device.ok(await ledger.startFresh());
      expect(Device.ok(store.categories.list()), hasLength(1));
    });

    test('5.52: categories are listed by TextRules.compareNames', () async {
      for (final title in ['Żywność', 'Zakupy', 'Źródło', 'apteka']) {
        await category(title: title);
      }
      final titles = [for (final c in Device.ok(await ledger.listCategories()).categories) c.title];
      expect(titles, ['apteka', 'Zakupy', 'Źródło', 'Żywność']);
    });
  });

  group('records', () {
    late wire.Account a;
    late wire.Category food;
    setUp(() async {
      a = await account(balances: {'PLN': 10000, 'EUR': 0});
      food = await category(kind: wire.CategoryKind.CATEGORY_KIND_EXPENSE);
    });

    test('5.15–5.20, 5.23: RecordWriter.apply refuses in its order', () async {
      final archived = await category(title: 'Old');
      Device.ok(await ledger.archiveCategory(archived.id));
      Future<(int, String)> create(wire.CreateRecordRequest r) async =>
          refused(await ledger.createRecord(r));
      expect(await create(recordRequest(a.id, food.id, title: ' ')), (400, '5.15'));
      expect(await create(recordRequest(a.id, food.id, amount: 0)), (400, '5.16'));
      expect(await create(recordRequest('', food.id)), (400, '5.17'));
      expect(await create(recordRequest(store.newId(), food.id)), (400, '5.17'));
      expect(await create(recordRequest(a.id, store.newId())), (400, '5.17'));
      expect(await create(recordRequest(a.id, archived.id)), (409, '5.20'));
      expect(await create(recordRequest(a.id, food.id, amount: 5)), (400, '5.19'));
      expect(await create(recordRequest(a.id, food.id, currency: 'USD')), (400, '5.18'));
      expect(await create(recordRequest(a.id, food.id, currency: 'XX')), (400, '3.2'));
      expect(await create(recordRequest(a.id, food.id, date: '2026-02-29')), (400, '5.23'));
      // Everything wrong at once: the first rule in the server's order decides.
      expect(
        await create(
          recordRequest('', archived.id, amount: 0, title: ' ', currency: 'XX', date: ''),
        ),
        (400, '5.15'),
      );
      expect(Device.ok(store.records.list()), isEmpty);
    });

    test(
      'a title of only a control character is not blank and is stored empty, as on the server',
      () async {
        final r = Device.ok(
          await ledger.createRecord(recordRequest(a.id, food.id, title: '\u0001')),
        );
        expect(r.title, '');
        expect(Device.ok(store.records.get(r.id)).hasTitle(), isFalse);
      },
    );

    test('payee and note: trimmed, and absent when nothing is left', () async {
      final r = Device.ok(
        await ledger.createRecord(
          recordRequest(a.id, food.id)
            ..payee = '  Shop '
            ..note = ' \t ',
        ),
      );
      expect((r.payee, r.hasNote()), ('Shop', false));
    });

    test('5.14, 5.24: create, edit and delete move the derived balance', () async {
      final r = Device.ok(await ledger.createRecord(recordRequest(a.id, food.id)));
      expect(await balanceOf(a.id), {'PLN': 8750, 'EUR': 0});
      Device.ok(
        await ledger.updateRecord(
          r.id,
          wire.UpdateRecordRequest(
            title: 'Bread',
            amountMinor: Int64(-300),
            date: '2026-11-02',
            categoryId: food.id,
            accountId: a.id,
            currency: 'EUR',
          ),
        ),
      );
      expect(await balanceOf(a.id), {'PLN': 10000, 'EUR': -300});
      Device.ok(await ledger.deleteRecord(r.id));
      expect(await balanceOf(a.id), {'PLN': 10000, 'EUR': 0});
      expect(refused(await ledger.deleteRecord(r.id)), (404, '5.15'));
    });

    test(
      'an edit checks the archived state and the kind only when the category or sign changes',
      () async {
        final either = await category(title: 'Either');
        final r = Device.ok(await ledger.createRecord(recordRequest(a.id, either.id, amount: 100)));
        Device.ok(await ledger.archiveCategory(either.id));
        Device.ok(
          await ledger.updateCategory(
            either.id,
            wire.UpdateCategoryRequest(
              title: 'Either',
              iconKey: 'food',
              kind: wire.CategoryKind.CATEGORY_KIND_EXPENSE,
            ),
          ),
        );
        wire.UpdateRecordRequest edit(int amount) => wire.UpdateRecordRequest(
          title: 'Changed',
          amountMinor: Int64(amount),
          date: '2026-11-02',
          categoryId: either.id,
          accountId: a.id,
          currency: 'PLN',
        );
        // Same category, same sign: neither the archived state nor the (now expense-only) kind is
        // checked again, so an old income record stays editable.
        expect(Device.ok(await ledger.updateRecord(r.id, edit(200))).title, 'Changed');
        Device.ok(
          await ledger.updateCategory(
            either.id,
            wire.UpdateCategoryRequest(
              title: 'Either',
              iconKey: 'food',
              kind: wire.CategoryKind.CATEGORY_KIND_INCOME,
            ),
          ),
        );
        // The sign changes, so the kind is checked, and an income-only category refuses an expense.
        expect(refused(await ledger.updateRecord(r.id, edit(-200))), (400, '5.19'));
      },
    );

    test('5.22: a correction is not edited or deleted as a record', () async {
      final c = Device.ok(
        await ledger.createCorrection(
          wire.CreateCorrectionRequest(
            accountId: a.id,
            currency: 'PLN',
            balanceMinor: Int64(1),
            date: '2026-11-03',
          ),
        ),
      );
      expect(refused(await ledger.deleteRecord(c.id)), (409, '5.22'));
      expect(
        refused(
          await ledger.updateRecord(
            c.id,
            wire.UpdateRecordRequest(
              title: 'x',
              amountMinor: Int64(-1),
              date: '2026-11-03',
              categoryId: food.id,
              accountId: a.id,
              currency: 'PLN',
            ),
          ),
        ),
        (409, '5.22'),
      );
    });

    test(
      'a record moved to another account loses its statement key and so its derived id',
      () async {
        final b = await account(name: 'B');
        final imported = Record(
          id: DerivedIds.imported(a.id, 'f' * 64, 1),
          title: 'Card',
          posting: Posting(accountId: a.id, currency: 'PLN', amountMinor: Int64(-10)),
          date: '2026-11-01',
          categoryId: food.id,
          importKey: ImportKey(fingerprint: 'f' * 64, occurrence: 1),
        );
        Device.ok(await store.putRecord(imported));
        final moved = Device.ok(
          await ledger.updateRecord(
            imported.id,
            wire.UpdateRecordRequest(
              title: 'Card',
              amountMinor: Int64(-10),
              date: '2026-11-01',
              categoryId: food.id,
              accountId: b.id,
              currency: 'PLN',
            ),
          ),
        );
        expect(moved.id, isNot(imported.id));
        expect(store.records.get(imported.id).isSuccess, isFalse);
        expect(Device.ok(store.records.get(moved.id)).hasImportKey(), isFalse);
        // Editing it in place keeps the key.
        Device.ok(await store.putRecord(imported));
        final edited = Device.ok(
          await ledger.updateRecord(
            imported.id,
            wire.UpdateRecordRequest(
              title: 'Card!',
              amountMinor: Int64(-11),
              date: '2026-11-01',
              categoryId: food.id,
              accountId: a.id,
              currency: 'PLN',
            ),
          ),
        );
        expect(edited.id, imported.id);
        expect(Device.ok(store.records.get(imported.id)).importKey.occurrence, 1);
      },
    );
  });

  group('transfers', () {
    test('5.27–5.32: one immutable record, two legs, two balances, refused requests', () async {
      final a = await account(name: 'A', balances: {'PLN': 50000});
      final b = await account(name: 'B', balances: {'EUR': 0});
      wire.CreateTransferRequest t({
        int from = 10000,
        int to = 2300,
        String? toAccount,
        String toCur = 'EUR',
        String date = '2026-11-05',
      }) => wire.CreateTransferRequest(
        title: ' ',
        fromAccountId: a.id,
        toAccountId: toAccount ?? b.id,
        fromAmountMinor: Int64(from),
        toAmountMinor: Int64(to),
        fromCurrency: 'PLN',
        toCurrency: toCur,
        date: date,
      );
      expect(refused(await ledger.createTransfer(t(from: 0))), (400, '5.27'));
      expect(refused(await ledger.createTransfer(t(to: -1))), (400, '5.27'));
      expect(refused(await ledger.createTransfer(t(toAccount: a.id))), (400, '5.28'));
      expect(refused(await ledger.createTransfer(t(toCur: 'PLN'))), (400, '5.29'));
      expect(refused(await ledger.createTransfer(t(date: '2026-11-31'))), (400, '5.32'));
      final transfer = Device.ok(await ledger.createTransfer(t()));
      expect(
        (
          transfer.fromRecord.title,
          transfer.fromRecord.amountMinor.toInt(),
          transfer.toRecord.amountMinor.toInt(),
        ),
        ('Transfer', -10000, 2300),
      );
      expect(transfer.fromRecord.hasCategoryId(), isFalse, reason: '5.30: no category');
      expect(
        Device.ok(store.records.list()),
        isEmpty,
        reason: 'one transfer record, no leg records',
      );
      expect(await balanceOf(a.id), {'PLN': 40000});
      expect(await balanceOf(b.id), {'EUR': 2300});
      // 5.21: a leg is not edited or deleted through the record routes.
      expect(refused(await ledger.deleteRecord(transfer.fromRecord.id)), (409, '5.21'));
      expect(Device.ok(await ledger.getRecord(transfer.toRecord.id)).accountId, b.id);
      Device.ok(await ledger.deleteTransfer(transfer.id));
      expect(await balanceOf(a.id), {'PLN': 50000});
      expect(refused(await ledger.deleteTransfer(transfer.id)), (404, '5.31'));
    });
  });

  group('corrections', () {
    test('5.33–5.37: the delta from the derived balance, with its intent', () async {
      final a = await account(balances: {'PLN': 10000});
      final c = await category();
      Device.ok(await ledger.createRecord(recordRequest(a.id, c.id, amount: -2575)));
      final first = Device.ok(
        await ledger.createCorrection(
          wire.CreateCorrectionRequest(
            accountId: a.id,
            currency: 'pln',
            balanceMinor: Int64(7000),
            date: '2026-11-05',
            note: '  ',
          ),
        ),
      );
      expect(
        (first.amountMinor.toInt(), first.title, first.isCorrection, first.hasNote()),
        (-425, 'Balance correction', true, false),
      );
      final stored = Device.ok(store.records.get(first.id));
      expect(
        (stored.correction.targetMinor.toInt(), stored.correction.seenMinor.toInt()),
        (7000, 7425),
      );
      expect(stored.correction.seenCorrections, isEmpty);
      expect(
        refused(
          await ledger.createCorrection(
            wire.CreateCorrectionRequest(
              accountId: a.id,
              currency: 'PLN',
              balanceMinor: Int64(7000),
              date: '2026-11-05',
            ),
          ),
        ),
        (400, '5.34'),
      );
      final second = Device.ok(
        await ledger.createCorrection(
          wire.CreateCorrectionRequest(
            accountId: a.id,
            currency: 'PLN',
            balanceMinor: Int64(0),
            date: '2026-11-06',
            title: ' Count ',
          ),
        ),
      );
      expect(second.title, 'Count');
      final secondStored = Device.ok(store.records.get(second.id));
      expect(secondStored.correction.seenCorrections, [first.id], reason: 'it saw the first');
      expect(secondStored.correction.hasTargetMinor(), isFalse, reason: 'zero left unset');
      expect(await balanceOf(a.id), {'PLN': 0});
      expect(refused(await ledger.deleteCorrection(store.newId())), (404, '5.37'));
      Device.ok(await ledger.deleteCorrection(second.id));
      expect(await balanceOf(a.id), {'PLN': 7000});
    });
  });

  group('settings', () {
    test('5.44, 5.45: an absent record reads as PLN; a code is normalised; blank resets', () async {
      expect(Device.ok(await ledger.getSettings()).mainCurrency, 'PLN');
      expect(
        Device.ok(await ledger.updateSettings(wire.UpdateSettingsRequest(mainCurrency: ' usd ')))
            .mainCurrency,
        'USD',
      );
      expect(
        refused(await ledger.updateSettings(wire.UpdateSettingsRequest(mainCurrency: 'EURO'))),
        (400, '3.2'),
      );
      expect(
        Device.ok(await ledger.updateSettings(wire.UpdateSettingsRequest(mainCurrency: ' ')))
            .mainCurrency,
        'PLN',
      );
    });

    test(
      'the main currency and the default account are one record and survive each other',
      () async {
        final a = await account(isDefault: true);
        Device.ok(await ledger.updateSettings(wire.UpdateSettingsRequest(mainCurrency: 'EUR')));
        expect(Device.ok(await ledger.getAccount(a.id)).isDefault, isTrue);
      },
    );
  });

  group('the record list', () {
    test('legs first, then every filter per leg, date desc then id, search last', () async {
      final a = await account(name: 'A', balances: {'PLN': 0});
      final b = await account(name: 'B', balances: {'EUR': 0});
      final c = await category();
      final bread = Device.ok(
        await ledger.createRecord(recordRequest(a.id, c.id, date: '2026-11-01', title: 'Bread')),
      );
      final t = Device.ok(
        await ledger.createTransfer(
          wire.CreateTransferRequest(
            title: 'Save',
            fromAccountId: a.id,
            toAccountId: b.id,
            fromAmountMinor: Int64(10000),
            toAmountMinor: Int64(2300),
            fromCurrency: 'PLN',
            toCurrency: 'EUR',
            date: '2026-11-02',
          ),
        ),
      );
      Future<List<String>> ids([RecordQuery q = const RecordQuery()]) async => [
        for (final r in Device.ok(await ledger.listRecords(q)).records) r.id,
      ];
      final legs = ([t.fromRecord.id, t.toRecord.id]..sort());
      expect(await ids(), [...legs, bread.id]);
      expect(await ids(const RecordQuery(type: ' TRANSFER ')), legs);
      expect(await ids(const RecordQuery(type: 'expense')), [bread.id]);
      expect(await ids(RecordQuery(accountId: b.id)), [t.toRecord.id]);
      expect(await ids(RecordQuery(categoryId: c.id)), [bread.id]);
      expect(await ids(const RecordQuery(amountMin: 2300, amountMax: 2300)), [t.toRecord.id]);
      expect(await ids(const RecordQuery(amountMin: 5000)), [t.fromRecord.id]);
      expect(await ids(const RecordQuery(dateTo: '2026-11-01')), [bread.id]);
      expect(await ids(const RecordQuery(search: 'SAVE')), legs);
      expect(await ids(const RecordQuery(search: '\u0001')), [...legs, bread.id]);
      expect(await ids(const RecordQuery(search: '﻿')), isEmpty);
      expect(refused(await ledger.listRecords(const RecordQuery(type: 'refund'))), (400, '5.47'));
      expect(refused(await ledger.listRecords(const RecordQuery(amountMax: -1))), (400, '5.48'));
      expect(refused(await ledger.listRecords(const RecordQuery(dateFrom: '1/1/2026'))), (
        400,
        '5.46',
      ));
      expect(refused(await ledger.listRecords(const RecordQuery(accountId: 'x'))), (400, '5.46'));
    });

    test(
      'an amount bound on a row of Long.MIN_VALUE fails as Postgres abs() does, never wraps',
      () async {
        final a = await account(balances: {'PLN': 0});
        final c = await category();
        Device.ok(
          await ledger.createRecord(recordRequest(a.id, c.id, amount: -0x8000000000000000)),
        );
        final result = await ledger.listRecords(const RecordQuery(amountMin: 1));
        expect(result.errorOrNull, isA<ZenUnknownError>());
        expect(Device.ok(await ledger.listRecords()).records, hasLength(1));
      },
    );
  });

  group('a figure never reads a value two devices disagree about (ADR-113)', () {
    // The conflicts themselves need two devices; see ledger_two_devices_test.dart. Here: nothing in
    // conflict, nothing unsettled.
    test('a settled ledger reports nothing left out', () async {
      final a = await account();
      final c = await category();
      Device.ok(await ledger.createRecord(recordRequest(a.id, c.id)));
      final figures = Device.ok(await ledger.accountBalances(a.id));
      expect(figures.minor, {'PLN': 8750});
      expect(figures.unsettled, isEmpty);
    });
  });
}
