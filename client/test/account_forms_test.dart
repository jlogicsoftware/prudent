// The account forms (jlogicsoftware/prudent#101) on the framework's controls. What is asserted is
// what reaches the form's callback — the request the repository would send — for the input typed,
// not how a control draws itself; that is zen_ui_widgets' own test.
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_ui/account/account_edit.dart';
import 'package:prudent_ui/account/account_new.dart';
import 'package:prudent_ui/account/account_save_error.dart';
import 'package:prudent_ui/account/reconcile_account.dart';
import 'package:prudent_ui/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_transport/zen_transport.dart' as transport;
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
        ...GlobalMaterialLocalizations.delegates,
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

    testWidgets('switch rows use the configured platform and submit their values', (tester) async {
      await open(tester);
      expect(find.byType(ZenSwitchRow), findsNWidgets(5));
      expect(find.byType(CupertinoSwitch), zenIsApplePlatform ? findsNWidgets(5) : findsNothing);
      expect(find.byType(SwitchListTile), zenIsApplePlatform ? findsNothing : findsNWidgets(5));
      await tester.enterText(_field('Account Name'), 'Wallet');
      await tester.tap(find.text('Active'));
      await tester.tap(find.text('Include in total balance'));
      await tester.tap(find.text('Show on overview'));
      await tester.tap(find.text('Add Account'));
      await tester.pumpAndSettle();
      expect(sent!.isActive, isFalse);
      expect(sent!.includeInTotal, isFalse);
      expect(sent!.includeInOverview, isFalse);
    });

    testWidgets('sends the bank account number when one is typed', (tester) async {
      await open(tester);
      await tester.enterText(_field('Account Name'), 'Wallet');
      await tester.enterText(_field('Bank account number (optional)'), ' PL00000000000000000000000001 ');
      await tester.tap(find.text('Add Account'));
      await tester.pumpAndSettle();
      expect(sent!.accountNumber, 'PL00000000000000000000000001');
    });

    testWidgets('sends no number when none is typed', (tester) async {
      await open(tester);
      await tester.enterText(_field('Account Name'), 'Wallet');
      await tester.tap(find.text('Add Account'));
      await tester.pumpAndSettle();
      expect(sent!.hasAccountNumber(), isFalse);
    });

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
    testWidgets('switch changes are saved', (tester) async {
      UpdateAccountRequest? sent;
      await _pump(tester, AccountEdit(account: _account(), onSave: (request) => sent = request));
      expect(find.byType(ZenSwitchRow), findsNWidgets(5));
      expect(find.byType(CupertinoSwitch), zenIsApplePlatform ? findsNWidgets(5) : findsNothing);
      expect(find.byType(SwitchListTile), zenIsApplePlatform ? findsNothing : findsNWidgets(5));
      await tester.tap(find.text('Active'));
      await tester.tap(find.text('Include in total balance'));
      await tester.tap(find.text('Show on overview'));
      await tester.tap(find.text('Save Account'));
      await tester.pumpAndSettle();
      expect(sent!.isActive, isFalse);
      expect(sent!.includeInTotal, isFalse);
      expect(sent!.includeInOverview, isFalse);
    });

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

    testWidgets('resends the stored account number when it is left alone', (tester) async {
      // A PUT is a full replacement: leaving the number out would delete it (ADR-090), so the field
      // starts with the stored number and the form sends whatever it holds.
      UpdateAccountRequest? sent;
      final account = _account()..accountNumber = '00000000000000000000000001';
      await _pump(tester, AccountEdit(account: account, onSave: (request) => sent = request));

      expect(textOf(tester, _field('Bank account number (optional)')), '00000000000000000000000001');
      await tester.enterText(_field('Account Name'), 'Renamed');
      await tester.tap(find.text('Save Account'));
      await tester.pumpAndSettle();

      expect(sent!.accountNumber, '00000000000000000000000001');
    });

    testWidgets('sends an edited number', (tester) async {
      final sent = <UpdateAccountRequest>[];
      final account = _account()..accountNumber = '00000000000000000000000001';
      await _pump(tester, AccountEdit(account: account, onSave: sent.add));

      await tester.enterText(_field('Bank account number (optional)'), ' 00000000000000000000000002 ');
      await tester.tap(find.text('Save Account'));
      await tester.pumpAndSettle();
      expect(sent.single.accountNumber, '00000000000000000000000002');
    });

    testWidgets('an emptied number is sent empty, which clears it', (tester) async {
      final sent = <UpdateAccountRequest>[];
      final account = _account()..accountNumber = '00000000000000000000000001';
      await _pump(tester, AccountEdit(account: account, onSave: sent.add));

      await tester.enterText(_field('Bank account number (optional)'), '');
      await tester.tap(find.text('Save Account'));
      await tester.pumpAndSettle();
      expect(sent.single.accountNumber, '');
    });

    testWidgets('a refused number keeps the form open and says why', (tester) async {
      await _pump(
        tester,
        AccountEdit(
          account: _account(),
          onSave: (request) async => throw transport.ZenTransportError(
            transport.ZenError(code: 'conflict', message: accountNumberTakenMessage),
          ),
        ),
      );

      await tester.enterText(_field('Bank account number (optional)'), '00000000000000000000000002');
      await tester.tap(find.text('Save Account'));
      await tester.pumpAndSettle();

      expect(find.text('Another of your accounts already has this number.'), findsOneWidget);
      // The form is still there, with what was typed, so nothing is lost to a refusal.
      expect(find.text('Save Account'), findsOneWidget);
      expect(textOf(tester, _field('Bank account number (optional)')), '00000000000000000000000002');
    });

    testWidgets('a malformed number is reported as one', (tester) async {
      await _pump(
        tester,
        AccountEdit(
          account: _account(),
          onSave: (request) async => throw transport.ZenTransportError(
            transport.ZenError(
              code: 'invalid',
              message: '$accountNumberInvalidMessage 10 to 34 letters and digits; spaces are ignored.',
            ),
          ),
        ),
      );
      await tester.enterText(_field('Bank account number (optional)'), '!!');
      await tester.tap(find.text('Save Account'));
      await tester.pumpAndSettle();

      expect(find.text('This does not look like an account number.'), findsOneWidget);
      expect(find.textContaining('letters and digits'), findsNothing);
    });

    testWidgets('a 400 about something else is not called an account number', (tester) async {
      await _pump(
        tester,
        AccountEdit(
          account: _account(),
          onSave: (request) async => throw transport.ZenTransportError(
            transport.ZenError(code: 'invalid', message: 'An account needs a name.'),
          ),
        ),
      );
      await tester.tap(find.text('Save Account'));
      await tester.pumpAndSettle();

      expect(find.text('The account was not saved. Try again.'), findsOneWidget);
      expect(find.text('This does not look like an account number.'), findsNothing);
    });

    testWidgets('a failure that is not a server answer ends the spinner and says it was not saved', (tester) async {
      await _pump(
        tester,
        AccountEdit(account: _account(), onSave: (request) async => throw StateError('TEST SECRET TYPED TEXT')),
      );
      await tester.tap(find.text('Save Account'));
      await tester.pumpAndSettle();

      expect(find.text('The account was not saved. Try again.'), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(tester.widget<ZenButton>(find.widgetWithText(ZenButton, 'Save Account')).isLoading, isFalse);
    });

    test('the messages the form recognises are the ones the server sends', () {
      final server = Directory('../server/src/main/java/prudent/account');
      final text = [
        for (final f in server.listSync().whereType<File>().where((f) => f.path.endsWith('.java')))
          f.readAsStringSync().replaceAll(RegExp(r'"\s*\+\s*\n\s*"'), ''),
      ].join('\n');
      expect(text, contains('"$accountNumberTakenMessage"'));
      expect(text, contains('"$accountNumberInvalidMessage 10 to 34 letters'));
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
