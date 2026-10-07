// The account forms (jlogicsoftware/prudent#101) on the framework's controls. What is asserted is
// what reaches the form's callback — the request the repository would send — for the input typed,
// not how a control draws itself; that is zen_ui_widgets' own test.
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/account/account_edit.dart';
import 'package:prudent/account/account_new.dart';
import 'package:prudent/account/reconcile_account.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';
import 'zen_fields.dart';

Future<void> _pump(WidgetTester tester, Widget form) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: [
        ...PrudentLocalizations.localizationsDelegates,
        zenWidgetsLocaleDelegate,
      ],
      supportedLocales: PrudentLocalizations.supportedLocales,
      home: Scaffold(body: form),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => textInput(label);

Account _account() => Account(
  id: 'acc',
  name: 'Bank',
  type: AccountType.ACCOUNT_TYPE_CARD,
  isActive: true,
  includeInTotal: true,
  includeInOverview: true,
  balances: [
    CurrencyBalance(currency: 'EUR', amountMinor: Int64(1000)),
    CurrencyBalance(currency: 'PLN', amountMinor: Int64(2500)),
  ],
);

void main() {
  group('AccountNew', () {
    CreateAccountRequest? sent;

    Future<void> open(WidgetTester tester) async {
      sent = null;
      await _pump(tester, AccountNew(onAddAccount: (request) => sent = request));
    }

    testWidgets('sends the typed name and the balance in minor units', (tester) async {
      await open(tester);
      await tester.enterText(_field('Account Name'), 'Wallet');
      await tester.enterText(_field('Opening balance'), '12,5');
      await tester.tap(find.text('Add Account'));
      await tester.pumpAndSettle();

      expect(sent, isNotNull);
      expect(sent!.name, 'Wallet');
      expect(sent!.type, AccountType.ACCOUNT_TYPE_CARD);
      expect(sent!.balances.single.currency, 'PLN');
      expect(sent!.balances.single.amountMinor, Int64(1250));
    });

    testWidgets('keeps a negative opening balance', (tester) async {
      await open(tester);
      await tester.enterText(_field('Account Name'), 'Overdraft');
      await tester.enterText(_field('Opening balance'), '-3');
      await tester.tap(find.text('Add Account'));
      await tester.pumpAndSettle();

      expect(sent!.balances.single.amountMinor, Int64(-300));
    });

    testWidgets('refuses an empty amount and says so', (tester) async {
      await open(tester);
      await tester.enterText(_field('Account Name'), 'Wallet');
      await tester.enterText(_field('Opening balance'), '');
      await tester.tap(find.text('Add Account'));
      await tester.pumpAndSettle();

      expect(sent, isNull);
      expect(find.text('Enter a valid amount'), findsOneWidget);

      await tester.enterText(_field('Opening balance'), '5');
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid amount'), findsNothing);
    });

    testWidgets('refuses a missing name', (tester) async {
      await open(tester);
      await tester.tap(find.text('Add Account'));
      await tester.pumpAndSettle();

      expect(sent, isNull);
      expect(find.text('Please enter a name'), findsOneWidget);
    });

    testWidgets('sends the type picked in the select', (tester) async {
      await open(tester);
      await tester.enterText(_field('Account Name'), 'Rainy day');
      // Driven through onChanged: opening the select is the control's own business and differs
      // by platform (a wheel on iOS, a menu elsewhere); the wiring to the request is Prudent's.
      tester.widget<ZenSelect<AccountType>>(find.byType(ZenSelect<AccountType>)).onChanged!(
        AccountType.ACCOUNT_TYPE_SAVINGS,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Account'));
      await tester.pumpAndSettle();

      expect(sent!.type, AccountType.ACCOUNT_TYPE_SAVINGS);
    });
  });

  group('AccountEdit', () {
    testWidgets('resends the balances it did not touch', (tester) async {
      UpdateAccountRequest? sent;
      await _pump(tester, AccountEdit(account: _account(), onSave: (request) => sent = request));

      await tester.enterText(_field('Account Name'), '  Renamed ');
      await tester.tap(find.text('Save Account'));
      await tester.pumpAndSettle();

      expect(sent!.name, 'Renamed');
      expect(sent!.type, AccountType.ACCOUNT_TYPE_CARD);
      expect(sent!.balances, _account().balances);
    });

    testWidgets('does not save without a name', (tester) async {
      UpdateAccountRequest? sent;
      await _pump(tester, AccountEdit(account: _account(), onSave: (request) => sent = request));

      await tester.enterText(_field('Account Name'), '  ');
      await tester.tap(find.text('Save Account'));
      await tester.pumpAndSettle();

      expect(sent, isNull);
    });
  });

  group('ReconcileAccount', () {
    ({String currency, String balance, String date, String note})? sent;

    Future<void> open(WidgetTester tester, Account account) async {
      sent = null;
      await _pump(
        tester,
        ReconcileAccount(
          account: account,
          onSave:
              ({required currency, required trueBalanceInput, required date, required note}) =>
                  sent = (currency: currency, balance: trueBalanceInput, date: date, note: note),
        ),
      );
    }

    testWidgets('sends the true balance as exact decimal text for the first currency', (
      tester,
    ) async {
      await open(tester, _account());
      await tester.enterText(_field('True balance'), '250,5');
      await tester.enterText(_field('Note (optional)'), 'statement');
      await tester.tap(find.text('Reconcile'));
      await tester.pumpAndSettle();

      expect(sent, isNotNull);
      expect(sent!.currency, 'EUR');
      expect(sent!.balance, '250.50');
      expect(sent!.note, 'statement');
      final today = DateUtils.dateOnly(DateTime.now());
      expect(sent!.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(sent!.date, '${today.year}-${_two(today.month)}-${_two(today.day)}');
    });

    testWidgets('sends the currency picked in the select', (tester) async {
      await open(tester, _account());
      tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>)).onChanged!('PLN');
      await tester.pumpAndSettle();
      await tester.enterText(_field('True balance'), '1');
      await tester.tap(find.text('Reconcile'));
      await tester.pumpAndSettle();

      expect(sent!.currency, 'PLN');
    });

    testWidgets('has no currency select for a single-currency account', (tester) async {
      await open(
        tester,
        Account(id: 'a', name: 'One', balances: [CurrencyBalance(currency: 'PLN')]),
      );

      expect(find.byType(ZenSelect<String>), findsNothing);
    });

    testWidgets('refuses an empty amount with the invalid-input dialog', (tester) async {
      await open(tester, _account());
      await tester.tap(find.text('Reconcile'));
      await tester.pumpAndSettle();

      expect(sent, isNull);
      expect(find.text('Please enter a valid balance and choose a currency.'), findsOneWidget);
    });

    testWidgets('refuses more fraction digits than a minor unit holds', (tester) async {
      await open(tester, _account());
      await tester.enterText(_field('True balance'), '1.234');
      await tester.tap(find.text('Reconcile'));
      await tester.pumpAndSettle();

      // The field refuses the over-long entry outright, so nothing is submitted and the user is
      // told — never a rounded guess at the digit that was refused.
      expect(sent, isNull);
      expect(find.text('Please enter a valid balance and choose a currency.'), findsOneWidget);
    });
  });
}

String _two(int n) => n.toString().padLeft(2, '0');
