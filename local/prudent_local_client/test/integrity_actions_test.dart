// What an integrity action needs from the person, asked on the real screens (ADR-140): a choice among
// records and a name, both asked by jZen's `ZenIssueScreen` (jZenDev/jZen#256). Every choice picks a
// candidate that is not first, and one picks the middle of three, so a wiring that runs the first or
// the last one whatever was picked fails here; cancelling writes nothing; a write the store refuses is
// said and writes nothing; and a repair that asks nothing writes from its button.
//
// A broken state is made on one device through `PrudentLocalStore`, which refuses no cross-record
// break so that what a merge produces can be written in a test; corrections made apart need two
// devices.
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/l10n/generated/local_localizations.dart';
import 'package:prudent_local_client/l10n/pl_store_localizations.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:zen_ui_store/zen_ui_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'support/ledger_setup.dart';
import 'support/local_app_harness.dart';
import 'support/two_local_devices.dart';

const _en = Locale('en');
final _t = lookupPrudentLocalizations(_en);
final _l = lookupLocalLocalizations(_en);
final _s = lookupStoreLocalizations(_en);

/// The radio options of the open choice prompt.
Finder _options(Pattern text) => find.descendant(
  of: find.byType(ZenRadioGroup<String>),
  matching: find.textContaining(text),
);

bool _enabled(WidgetTester tester, String button) =>
    tester
        .widget<ZenButton>(find.widgetWithText(ZenButton, button))
        .onPressed !=
    null;

/// One device with the app open on its list of conflicts and issues.
final class _Case {
  final WidgetTester tester;
  final LocalAppHarness app;
  final TwoLocalDevices devices;

  /// How many times the store changed since [watch].
  int writes = 0;

  _Case(this.tester, this.app, this.devices);

  PrudentLocalStore get store => devices.phone.prudent;

  void watch() {
    writes = 0;
    final subscription = devices.phone.store.changes.listen((_) => writes++);
    addTearDown(subscription.cancel);
  }

  /// Presses the issue's button [action], which asks something before it writes. On the real event
  /// loop, because what is written after the prompt closes runs where the press started.
  Future<void> ask(String action) =>
      app.tapReal(find.text(action), wait: const Duration(milliseconds: 100));

  /// Picks the [index]th option showing [text] and confirms.
  Future<void> choose(Pattern text, {int index = 0}) async {
    final option = _options(text).at(index);
    await tester.ensureVisible(option);
    await tester.pump();
    await tester.tap(option);
    await app.settle();
    await app.tapReal(find.text(_s.issueContinue));
  }

  /// Types [name] into the open name prompt and confirms.
  Future<void> name(String name) async {
    await tester.enterText(find.byType(ZenTextField), name);
    await tester.pump();
    await app.tapReal(find.text(_s.issueContinue));
  }

  /// Cancels the open prompt: it closes, nothing was written, and the issue is still shown.
  Future<void> cancel(String body) async {
    await app.tapText(_s.cancelButton);
    expect(find.text(_s.issueContinue), findsNothing);
    expect(find.text(body), findsOneWidget);
    expect(writes, 0, reason: 'cancelling writes nothing');
  }
}

/// Builds a state with [arrange] on the phone (or both devices), opens the app and the issue [title].
Future<(_Case, T)> _open<T>(
  WidgetTester tester,
  String title,
  Future<T> Function(TwoLocalDevices devices) arrange,
) async {
  final devices = await twoDevices(tester);
  final made = (await tester.runAsync(() => arrange(devices))) as T;
  final app = await LocalAppHarness.pump(tester, devices.phone);
  await app.openTab(_t.navSettings);
  await app.tapText(_l.settingsConflicts);
  await app.tapText(title);
  final c = _Case(tester, app, devices)..watch();
  return (c, made);
}

Future<String> _account(Ledger ledger, String name) async => ok(
  await ledger.createAccount(
    wire.CreateAccountRequest(
      name: name,
      type: wire.AccountType.ACCOUNT_TYPE_SAVINGS,
      isActive: true,
      balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(0))],
    ),
  ),
).value.id;

Future<String> _category(Ledger ledger, String title) async => ok(
  await ledger.createCategory(
    wire.CreateCategoryRequest(title: title, iconKey: 'food'),
  ),
).id;

/// "Wallet" with one purchase, deleted from under it, and three accounts the purchase can move to,
/// as (id, name) in the order the prompt offers them (by id).
Future<({Books books, List<(String, String)> others})> _recordWithoutAccount(
  TwoLocalDevices devices,
) async {
  final ledger = devices.phone.ledger;
  final books = await openBooks(ledger);
  await addRecord(ledger, books);
  final others = [
    (await _account(ledger, 'Savings'), 'Savings'),
    (await _account(ledger, 'Cash'), 'Cash'),
    (await _account(ledger, 'Reserve'), 'Reserve'),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  ok(await devices.phone.prudent.deleteAccount(books.account));
  return (books: books, others: others);
}

/// Makes the account [id], deleted here if it is still there, the missing default, and leaves no
/// record or currency of its behind: only the default is broken.
Future<void> _leaveDefaultOn(PrudentLocalStore store, String id) async {
  for (final record in store.records.list().dataOrNull!) {
    ok(await store.deleteRecord(record.id));
  }
  for (final held in store.accountCurrencies.list().dataOrNull!) {
    if (held.accountId == id) ok(await store.deleteAccountCurrency(held.id));
  }
  if (store.accounts.get(id).isSuccess) ok(await store.deleteAccount(id));
  final settings =
      store.settings.get(DerivedIds.settings).dataOrNull ??
      Settings(id: DerivedIds.settings, mainCurrency: 'PLN');
  ok(await store.putSettings(settings.deepCopy()..defaultAccountId = id));
}

/// Two corrections of one balance made apart: the laptop asks for 70.00, the phone for 50.00.
Future<({String account, List<Record> corrections})> _correctionsMadeApart(
  TwoLocalDevices devices,
) async {
  final books = await openBooks(devices.laptop.ledger);
  await devices.sync();
  for (final (ledger, target, date) in [
    (devices.laptop.ledger, 7000, '2026-11-05'),
    (devices.phone.ledger, 5000, '2026-11-06'),
  ]) {
    ok(
      await ledger.createCorrection(
        wire.CreateCorrectionRequest(
          accountId: books.account,
          currency: 'PLN',
          balanceMinor: Int64(target),
          date: date,
        ),
      ),
    );
  }
  await devices.sync();
  final corrections = devices.phone.prudent.records.list().dataOrNull!.toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  return (account: books.account, corrections: corrections);
}

void main() {
  group('a choice among records', () {
    testWidgets(
      'move_to_account: one question; cancel writes nothing; the picked account gets the record',
      (tester) async {
        final (c, made) = await _open(
          tester,
          _l.issueRecordAccountMissing,
          _recordWithoutAccount,
        );
        // One button for the whole choice, not one per candidate.
        expect(find.text(_l.actionMoveToAnotherAccount), findsOneWidget);
        expect(find.text(_l.actionMoveToAccount('Savings')), findsNothing);

        await c.ask(_l.actionMoveToAnotherAccount);
        expect(_options('Savings'), findsOneWidget);
        expect(_options('Cash'), findsOneWidget);
        expect(_options('Reserve'), findsOneWidget);
        expect(_enabled(tester, _s.issueContinue), isFalse);
        await c.cancel(_l.issueRecordAccountMissingBody);

        // The middle one: neither "the first" nor "the last" would pass for it.
        final (id, name) = made.others[1];
        await c.ask(_l.actionMoveToAnotherAccount);
        await c.choose(name);
        final record = c.store.records.list().dataOrNull!.single;
        expect(record.posting.accountId, id);
        expect(find.text(_l.issueRecordAccountMissing), findsNothing);
      },
    );

    testWidgets(
      'a record deleted while the choice is open: said, nothing written',
      (tester) async {
        final (c, made) = await _open(
          tester,
          _l.issueRecordAccountMissing,
          _recordWithoutAccount,
        );
        await c.ask(_l.actionMoveToAnotherAccount);
        await c.app.run(() async {
          final record = c.store.records.list().dataOrNull!.single;
          ok(await c.store.deleteRecord(record.id));
        });
        c.watch();
        await c.choose(made.others.last.$2);
        expect(find.textContaining(_s.issueFailed('')), findsOneWidget);
        expect(c.store.records.list().dataOrNull, isEmpty);
        expect(c.writes, 0);
      },
    );

    testWidgets('move_to_category: the record is filed under the picked one', (
      tester,
    ) async {
      final (c, others) = await _open(tester, _l.issueRecordCategoryMissing, (
        devices,
      ) async {
        final ledger = devices.phone.ledger;
        final books = await openBooks(ledger);
        await addRecord(ledger, books);
        final others = [
          (await _category(ledger, 'Bakery'), 'Bakery'),
          (await _category(ledger, 'Travel'), 'Travel'),
        ]..sort((a, b) => a.$1.compareTo(b.$1));
        ok(await devices.phone.prudent.deleteCategory(books.category));
        return others;
      });
      await c.ask(_l.actionMoveToAnotherCategory);
      await c.cancel(_l.issueRecordCategoryMissingBody);
      await c.ask(_l.actionMoveToAnotherCategory);
      await c.choose(others.last.$2);
      expect(
        c.store.records.list().dataOrNull!.single.categoryId,
        others.last.$1,
      );
      expect(find.text(_l.issueRecordCategoryMissing), findsNothing);
    });

    testWidgets(
      'choose_default_account: the picked account becomes the default',
      (tester) async {
        final (c, made) = await _open(tester, _l.issueDefaultAccountMissing, (
          devices,
        ) async {
          final made = await _recordWithoutAccount(devices);
          await _leaveDefaultOn(devices.phone.prudent, made.books.account);
          return made;
        });
        await c.ask(_l.actionChooseAnotherDefault);
        await c.cancel(_l.issueDefaultAccountMissingBody);
        await c.ask(_l.actionChooseAnotherDefault);
        await c.choose(made.others.last.$2);
        expect(
          c.store.settings
              .get(DerivedIds.settings)
              .dataOrNull!
              .defaultAccountId,
          made.others.last.$1,
        );
        expect(find.text(_l.issueDefaultAccountMissing), findsNothing);
      },
    );

    testWidgets(
      'delete_correction: the picked correction goes, the other stays',
      (tester) async {
        final (c, made) = await _open(
          tester,
          _l.issueCorrectionsMadeApart,
          _correctionsMadeApart,
        );
        final [kept, deleted] = made.corrections;
        await c.ask(_l.actionDeleteOneCorrection);
        await c.cancel(_l.issueCorrectionsMadeApartBody);
        await c.ask(_l.actionDeleteOneCorrection);
        await c.choose(deleted.date);
        expect(c.store.records.list().dataOrNull!.map((r) => r.id), [kept.id]);
        expect(find.text(_l.issueCorrectionsMadeApart), findsNothing);
      },
    );

    testWidgets(
      'correct_to_target: one correction replaces both, to the balance of the picked one',
      (tester) async {
        final (c, made) = await _open(
          tester,
          _l.issueCorrectionsMadeApart,
          _correctionsMadeApart,
        );
        final picked = made.corrections.last;
        await c.ask(_l.actionKeepOneCorrection);
        await c.cancel(_l.issueCorrectionsMadeApartBody);
        await c.ask(_l.actionKeepOneCorrection);
        await c.choose(picked.date);
        final balance = await c.app.run(
          () => c.devices.phone.ledger.accountBalances(made.account),
        );
        expect(ok(balance).minor['PLN'], picked.correction.targetMinor.toInt());
        expect(c.store.records.list().dataOrNull, hasLength(1));
        expect(find.text(_l.issueCorrectionsMadeApart), findsNothing);
      },
    );

    testWidgets(
      'clear_account_number: only the picked account loses the number',
      (tester) async {
        const number = 'PL00000000000000000000000004';
        final (c, ids) = await _open(tester, _l.issueAccountNumberDuplicate, (
          devices,
        ) async {
          final ledger = devices.phone.ledger;
          final books = await openBooks(ledger);
          final savings = await _account(ledger, 'Savings');
          final store = devices.phone.prudent;
          for (final id in [books.account, savings]) {
            final account = store.accounts.get(id).dataOrNull!;
            ok(
              await store.putAccount(
                account.deepCopy()..accountNumber = number,
              ),
            );
          }
          return [(books.account, 'Wallet'), (savings, 'Savings')]
            ..sort((a, b) => a.$1.compareTo(b.$1));
        });
        await c.ask(_l.actionClearOneAccountNumber);
        await c.cancel(_l.issueAccountNumberDuplicateBody);
        await c.ask(_l.actionClearOneAccountNumber);
        await c.choose(ids.last.$2);
        expect(
          c.store.accounts.get(ids.last.$1).dataOrNull!.hasAccountNumber(),
          isFalse,
        );
        expect(
          c.store.accounts.get(ids.first.$1).dataOrNull!.accountNumber,
          number,
        );
        expect(find.text(_l.issueAccountNumberDuplicate), findsNothing);
      },
    );

    testWidgets(
      'revoke_reset: the picked reset is taken back, the other stays',
      (tester) async {
        final (c, ids) = await _open(tester, _l.issueResetSlotTwice, (
          devices,
        ) async {
          final books = await openBooks(devices.phone.ledger);
          final store = devices.phone.prudent;
          final ids = <String>[];
          for (var i = 0; i < 2; i++) {
            ids.add(
              ok(
                await store.addBudgetReset(
                  BudgetCarryOverReset(
                    id: store.newId(),
                    categoryId: books.category,
                    month: '2026-11',
                    currency: 'PLN',
                    createdBy: store.deviceId,
                    createdAtMs: Int64(1),
                  ),
                ),
              ).id,
            );
          }
          return ids..sort();
        });
        await c.ask(_l.actionRevokeOneReset);
        await c.cancel(_l.issueResetSlotTwiceBody);
        await c.ask(_l.actionRevokeOneReset);
        // Both are named by the slot they share, so they are told apart by their place.
        expect(_options('2026-11, PLN'), findsNWidgets(2));
        await c.choose('2026-11, PLN', index: 1);
        expect(
          c.store.budgetResets.get(ids.last).dataOrNull!.hasRevocation(),
          isTrue,
        );
        expect(
          c.store.budgetResets.get(ids.first).dataOrNull!.hasRevocation(),
          isFalse,
        );
        expect(find.text(_l.issueResetSlotTwice), findsNothing);
      },
    );

    testWidgets(
      'a single candidate is a button that names it and runs at once',
      (tester) async {
        final (c, travel) = await _open(tester, _l.issueRecordCategoryMissing, (
          devices,
        ) async {
          final ledger = devices.phone.ledger;
          final books = await openBooks(ledger);
          await addRecord(ledger, books);
          final travel = await _category(ledger, 'Travel');
          ok(await devices.phone.prudent.deleteCategory(books.category));
          return travel;
        });
        expect(find.text(_l.actionMoveToAnotherCategory), findsNothing);
        await c.app.tapReal(find.text(_l.actionMoveToCategory('Travel')));
        expect(c.store.records.list().dataOrNull!.single.categoryId, travel);
      },
    );

    testWidgets(
      'a single default candidate is a button that says what it does',
      (tester) async {
        final (c, savings) = await _open(
          tester,
          _l.issueDefaultAccountMissing,
          (devices) async {
            final books = await openBooks(devices.phone.ledger);
            final savings = await _account(devices.phone.ledger, 'Savings');
            await _leaveDefaultOn(devices.phone.prudent, books.account);
            return savings;
          },
        );
        expect(find.text(_l.actionChooseAnotherDefault), findsNothing);
        await c.app.tapReal(
          find.text(_l.actionChooseDefaultAccount('Savings')),
        );
        expect(
          c.store.settings
              .get(DerivedIds.settings)
              .dataOrNull!
              .defaultAccountId,
          savings,
        );
        expect(find.text(_l.issueDefaultAccountMissing), findsNothing);
      },
    );
  });

  group('a repair that asks nothing', () {
    testWidgets(
      'delete_record: the button deletes the record, with no prompt',
      (tester) async {
        final (c, _) = await _open(
          tester,
          _l.issueRecordAccountMissing,
          _recordWithoutAccount,
        );
        await c.app.tapReal(find.text(_l.actionDeleteRecord));
        expect(find.text(_s.issueContinue), findsNothing);
        expect(c.store.records.list().dataOrNull, isEmpty);
        expect(find.text(_l.issueRecordAccountMissing), findsNothing);
      },
    );
  });

  group('a name', () {
    testWidgets(
      'recreate_account: cancel and a blank name write nothing; the name is trimmed',
      (tester) async {
        final (c, made) = await _open(
          tester,
          _l.issueRecordAccountMissing,
          _recordWithoutAccount,
        );
        await c.ask(_l.actionRecreateAccount);
        expect(find.text(_l.recreateNameField), findsWidgets);
        expect(_enabled(tester, _s.issueContinue), isFalse);
        await c.cancel(_l.issueRecordAccountMissingBody);

        await c.ask(_l.actionRecreateAccount);
        await tester.enterText(find.byType(ZenTextField), '   ');
        await tester.pump();
        expect(_enabled(tester, _s.issueContinue), isFalse);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await c.app.settle();
        expect(find.text(_s.issueContinue), findsOneWidget);
        expect(c.writes, 0);
        expect(c.store.accounts.get(made.books.account).isSuccess, isFalse);

        await c.name('  Wallet again ');
        expect(
          c.store.accounts.get(made.books.account).dataOrNull!.name,
          'Wallet again',
        );
        expect(find.text(_l.issueRecordAccountMissing), findsNothing);
      },
    );

    testWidgets('recreate_category: the category comes back under its old id', (
      tester,
    ) async {
      final (c, books) = await _open(tester, _l.issueRecordCategoryMissing, (
        devices,
      ) async {
        final books = await openBooks(devices.phone.ledger);
        await addRecord(devices.phone.ledger, books);
        ok(await devices.phone.prudent.deleteCategory(books.category));
        return books;
      });
      await c.ask(_l.actionRecreateCategory);
      await c.name('Groceries');
      expect(
        c.store.categories.get(books.category).dataOrNull!.title,
        'Groceries',
      );
      expect(find.text(_l.issueRecordCategoryMissing), findsNothing);
    });

    testWidgets(
      'an account restored while the name is asked: refused, said, not written over',
      (tester) async {
        final (c, made) = await _open(
          tester,
          _l.issueRecordAccountMissing,
          _recordWithoutAccount,
        );
        await c.ask(_l.actionRecreateAccount);
        await c.app.run(
          () async => ok(
            await c.store.putAccount(
              Account(id: made.books.account, name: 'Restored elsewhere'),
            ),
          ),
        );
        c.watch();
        await c.name('Mine');
        expect(find.textContaining(_s.issueFailed('')), findsOneWidget);
        expect(
          c.store.accounts.get(made.books.account).dataOrNull!.name,
          'Restored elsewhere',
        );
        expect(c.writes, 0);
      },
    );

    testWidgets('the banner on the home screen asks the same way', (
      tester,
    ) async {
      final devices = await twoDevices(tester);
      final made = (await tester.runAsync(
        () => _recordWithoutAccount(devices),
      ))!;
      final app = await LocalAppHarness.pump(tester, devices.phone);
      await app.tapText(_s.reviewButton);
      await app.tapText(_l.issueRecordAccountMissing);
      await app.tapReal(
        find.text(_l.actionRecreateAccount),
        wait: const Duration(milliseconds: 100),
      );
      await tester.enterText(find.byType(ZenTextField), 'Wallet again');
      await tester.pump();
      await app.tapReal(find.text(_s.issueContinue));
      expect(
        devices.phone.prudent.accounts.get(made.books.account).dataOrNull!.name,
        'Wallet again',
      );
    });
  });

  for (final tag in ['en', 'uk', 'pl']) {
    testWidgets('both prompts are in $tag, the framework\'s buttons included', (
      tester,
    ) async {
      final locale = Locale(tag);
      final l = lookupLocalLocalizations(locale);
      final s = tag == 'pl'
          ? PlStoreLocalizations()
          : lookupStoreLocalizations(locale);
      final devices = await twoDevices(tester);
      await tester.runAsync(() => _recordWithoutAccount(devices));
      final app = await LocalAppHarness.pump(
        tester,
        devices.phone,
        locale: locale,
      );
      // Through the banner: it is on the home screen in a phone's layout and a desktop's alike.
      await app.tapText(s.reviewButton);
      await app.tapText(l.issueRecordAccountMissing);

      for (final action in [
        l.actionMoveToAnotherAccount,
        l.actionRecreateAccount,
      ]) {
        await app.tapText(action);
        expect(find.text(s.issueContinue), findsOneWidget);
        expect(find.text(s.cancelButton), findsOneWidget);
        if (action == l.actionRecreateAccount) {
          expect(find.text(l.recreateNameField), findsWidgets);
        }
        if (tag != 'en') {
          expect(find.text(_s.issueContinue), findsNothing);
          expect(find.text(_s.cancelButton), findsNothing);
        }
        await app.tapText(s.cancelButton);
      }
    });
  }
}
