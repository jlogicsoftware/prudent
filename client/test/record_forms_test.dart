// The record form, the transfer form and the records filter (jlogicsoftware/prudent#102) on the
// framework's controls. What is asserted is what reaches the form's callback — or the filter
// provider — for the input given, not how a control draws itself; that is zen_ui_widgets' own test.
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';
import 'package:prudent/generated/prudent/v1/records.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/providers.dart';
import 'package:prudent/record/new_record.dart';
import 'package:prudent/record/new_transfer.dart';
import 'package:prudent/record/record_filter.dart';
import 'package:prudent/record/records_filter_sheet.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

final _accounts = [
  Account(
    id: 'bank',
    name: 'Bank',
    balances: [
      CurrencyBalance(currency: 'EUR', amountMinor: Int64(1000)),
      CurrencyBalance(currency: 'PLN', amountMinor: Int64(2500)),
    ],
  ),
  Account(id: 'cash', name: 'Cash', balances: [CurrencyBalance(currency: 'PLN')]),
  Account(id: 'usd', name: 'Dollars', balances: [CurrencyBalance(currency: 'USD')]),
];

final _categories = [Category(id: 'food', title: 'Food'), Category(id: 'fun', title: 'Fun')];

class _Accounts extends AccountsNotifier {
  @override
  Future<List<Account>> build() async => _accounts;
}

class _Categories extends CategoriesNotifier {
  @override
  Future<List<Category>> build() async => _categories;
}

Future<ProviderContainer> _pump(WidgetTester tester, Widget form, {RecordFilter? filter}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      accountsProvider.overrideWith(_Accounts.new),
      categoriesProvider.overrideWith(_Categories.new),
    ],
  );
  addTearDown(container.dispose);
  if (filter != null) container.read(recordFilterProvider.notifier).apply(filter);
  // Loaded before the first frame, as they are by the time a screen opens a form: a select whose
  // value is not yet among its items does not build.
  await container.read(accountsProvider.future);
  await container.read(categoriesProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: [
          ...PrudentLocalizations.localizationsDelegates,
          zenWidgetsLocaleDelegate,
        ],
        supportedLocales: PrudentLocalizations.supportedLocales,
        home: Scaffold(body: form),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _field(String label) => find.widgetWithText(TextField, label);

/// Picks the first of the current month in the Material calendar the date field opens. Always a
/// selectable day: the form's last date is today.
Future<void> _pickFirstOfMonth(WidgetTester tester, Finder field) async {
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text('1'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

String _firstOfThisMonth() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
}

typedef _Saved =
    ({
      String title,
      String amount,
      String date,
      String categoryId,
      String accountId,
      String currency,
    });

void main() {
  group('NewRecord', () {
    _Saved? saved;

    Future<void> open(WidgetTester tester, {Record? initial}) async {
      saved = null;
      await _pump(
        tester,
        NewRecord(
          initialRecord: initial,
          onSave:
              ({
                required title,
                required amountInput,
                required date,
                required categoryId,
                required accountId,
                required currency,
                required payee,
                required note,
              }) =>
                  saved = (
                    title: title,
                    amount: amountInput,
                    date: date,
                    categoryId: categoryId,
                    accountId: accountId,
                    currency: currency,
                  ),
        ),
      );
    }

    Future<void> fill(WidgetTester tester, {String amount = '12,5'}) async {
      await tester.enterText(_field('Title'), 'Lunch');
      await tester.enterText(_field('Amount'), amount);
      await _pickFirstOfMonth(tester, find.text('Select a date'));
    }

    testWidgets('an expense reaches the wire negative, in exact minor units', (tester) async {
      await open(tester);
      await fill(tester);
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.amount, '-12.50');
      expect(saved!.date, _firstOfThisMonth());
      expect(saved!.accountId, 'bank');
      expect(saved!.categoryId, 'food');
    });

    testWidgets('the toggle alone turns it into income', (tester) async {
      await open(tester);
      await fill(tester);
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Income'));
      await tester.pumpAndSettle();

      expect(saved!.amount, '12.50');
    });

    testWidgets('the field does not take a sign; the toggle is the only source of it', (
      tester,
    ) async {
      await open(tester);
      await fill(tester, amount: '-12');
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      // The refused "-" leaves the field empty, which is not an amount: nothing is saved.
      expect(saved, isNull);
      expect(find.text('Invalid input'), findsOneWidget);
    });

    testWidgets('refuses a third fraction digit rather than rounding it', (tester) async {
      await open(tester);
      await fill(tester, amount: '1.234');
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      // The field refuses the over-long entry outright, so nothing is saved and the user is told
      // — never a rounded guess at the digit that was refused.
      expect(saved, isNull);
      expect(find.text('Invalid input'), findsOneWidget);
    });

    testWidgets('refuses a missing date', (tester) async {
      await open(tester);
      await tester.enterText(_field('Title'), 'Lunch');
      await tester.enterText(_field('Amount'), '5');
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      expect(find.text('Invalid input'), findsOneWidget);
    });

    testWidgets('refuses a zero amount', (tester) async {
      await open(tester);
      await fill(tester, amount: '0');
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
    });

    testWidgets('the currency follows the chosen account, the category the chosen category', (
      tester,
    ) async {
      await open(tester);
      await fill(tester);
      // Driven through onChanged: opening a select is the control's own business and differs by
      // platform; the wiring to the callback is Prudent's.
      final selects = find.byType(ZenSelect<String>);
      tester.widget<ZenSelect<String>>(selects.at(0)).onChanged!('usd');
      await tester.pumpAndSettle();
      tester.widget<ZenSelect<String>>(selects.at(1)).onChanged!('fun');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      expect(saved!.accountId, 'usd');
      expect(saved!.currency, 'USD');
      expect(saved!.categoryId, 'fun');
    });

    testWidgets('editing shows the stored magnitude, date and sign, and resends them', (
      tester,
    ) async {
      await open(
        tester,
        initial: Record(
          id: 'r',
          title: 'Rent',
          amountMinor: Int64(-123456),
          date: '2026-03-04',
          categoryId: 'fun',
          accountId: 'cash',
          currency: 'PLN',
        ),
      );

      expect(tester.widget<TextField>(_field('Amount')).controller!.text, '1234.56');
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      expect(saved!.amount, '-1234.56');
      expect(saved!.date, '2026-03-04');
      expect(saved!.accountId, 'cash');
      expect(saved!.categoryId, 'fun');
    });
  });

  group('NewTransfer', () {
    ({
      String fromAmount,
      String fromCurrency,
      String toAmount,
      String toCurrency,
      String from,
      String to,
      String date,
    })?
    saved;

    Future<void> open(WidgetTester tester) async {
      saved = null;
      await _pump(
        tester,
        NewTransfer(
          onSave:
              ({
                required title,
                required fromAmountInput,
                required fromCurrency,
                required toAmountInput,
                required toCurrency,
                required date,
                required fromAccountId,
                required toAccountId,
              }) =>
                  saved = (
                    fromAmount: fromAmountInput,
                    fromCurrency: fromCurrency,
                    toAmount: toAmountInput,
                    toCurrency: toCurrency,
                    from: fromAccountId,
                    to: toAccountId,
                    date: date,
                  ),
        ),
      );
    }

    Future<void> fill(WidgetTester tester) async {
      await tester.enterText(_field('Amount sent'), '10');
      await tester.enterText(_field('Amount received'), '42,5');
      await _pickFirstOfMonth(tester, find.text('Select a date'));
    }

    testWidgets('each leg keeps its own amount and the first currency of its account', (
      tester,
    ) async {
      await open(tester);
      await fill(tester);
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.from, 'bank');
      expect(saved!.fromCurrency, 'EUR');
      expect(saved!.fromAmount, '10.00');
      expect(saved!.to, 'cash');
      expect(saved!.toCurrency, 'PLN');
      expect(saved!.toAmount, '42.50');
      expect(saved!.date, _firstOfThisMonth());
    });

    testWidgets('only an account that holds several currencies offers a choice', (tester) async {
      await open(tester);

      // Bank holds two; Cash holds one, so its currency is shown, not chosen.
      expect(find.text('PLN'), findsOneWidget);
      final selects = find.byType(ZenSelect<String>);
      expect(selects, findsNWidgets(3));
    });

    testWidgets('the currency picked for a leg is the one sent', (tester) async {
      await open(tester);
      await fill(tester);
      tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>).at(1)).onChanged!('PLN');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      expect(saved!.fromCurrency, 'PLN');
    });

    testWidgets('the currencies follow a changed account, each side apart', (tester) async {
      await open(tester);
      await fill(tester);
      // To account -> Dollars: its currency replaces PLN; the from side is untouched.
      tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>).last).onChanged!('usd');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      expect(saved!.to, 'usd');
      expect(saved!.toCurrency, 'USD');
      expect(saved!.fromCurrency, 'EUR');
    });

    testWidgets('choosing the to account as the from account does not break the form', (
      tester,
    ) async {
      await open(tester);
      await fill(tester);
      // Bank (two currencies) on both sides: from Cash first, then to Bank, then from Bank.
      Future<void> choose(int select, String id) async {
        tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>).at(select)).onChanged!(id);
        await tester.pumpAndSettle();
      }

      await choose(0, 'cash');
      await choose(1, 'bank');
      // From account, to account, and the to leg's currency (Bank holds two).
      expect(find.byType(ZenSelect<String>), findsNWidgets(3));
      await choose(0, 'bank');

      // The to account is unchosen, so its leg offers no currency choice any more; the from leg
      // (Bank, two currencies) does. A stale to leg would make four.
      expect(tester.takeException(), isNull);
      expect(find.byType(ZenSelect<String>), findsNWidgets(3));

      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      // Same account on both sides is refused, never sent.
      expect(saved, isNull);
      expect(find.text('Invalid input'), findsOneWidget);
    });

    testWidgets('refuses a negative or empty amount on either leg', (tester) async {
      await open(tester);
      await tester.enterText(_field('Amount sent'), '-10');
      await tester.enterText(_field('Amount received'), '5');
      await _pickFirstOfMonth(tester, find.text('Select a date'));
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      expect(find.text('Invalid input'), findsOneWidget);
    });

    testWidgets('refuses a missing date', (tester) async {
      await open(tester);
      await tester.enterText(_field('Amount sent'), '10');
      await tester.enterText(_field('Amount received'), '10');
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
    });
  });

  group('RecordsFilterSheet', () {
    late ProviderContainer container;

    Future<void> open(WidgetTester tester) async {
      container = await _pump(tester, const RecordsFilterSheet());
    }

    RecordFilter current() => container.read(recordFilterProvider);

    testWidgets('applies every criterion, amounts in minor units', (tester) async {
      await open(tester);
      await tester.enterText(_field('Search'), ' coffee ');
      await tester.enterText(_field('Min amount'), '1,5');
      await tester.enterText(_field('Max amount'), '20');
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      final selects = find.byType(ZenSelect<String>);
      tester.widget<ZenSelect<String>>(selects.at(0)).onChanged!('cash');
      tester.widget<ZenSelect<String>>(selects.at(1)).onChanged!('fun');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(current().search, 'coffee');
      expect(current().amountMin, Int64(150));
      expect(current().amountMax, Int64(2000));
      expect(current().type, RecordFilterType.expense);
      expect(current().accountId, 'cash');
      expect(current().categoryId, 'fun');
    });

    testWidgets('an untouched sheet applies the empty filter', (tester) async {
      await open(tester);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(current(), RecordFilter.empty);
    });

    testWidgets('either end of an amount range can stand alone', (tester) async {
      await open(tester);
      await tester.enterText(_field('Max amount'), '7');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(current().amountMin, isNull);
      expect(current().amountMax, Int64(700));
    });

    testWidgets('a minimum above the maximum is called out and not applied', (tester) async {
      await open(tester);
      await tester.enterText(_field('Min amount'), '50');
      await tester.enterText(_field('Max amount'), '10');
      await tester.pumpAndSettle();

      expect(find.text('The minimum must not be greater than the maximum'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // The sheet is still open and nothing was written.
      expect(find.text('Apply'), findsOneWidget);
      expect(current(), RecordFilter.empty);

      await tester.enterText(_field('Max amount'), '60');
      await tester.pumpAndSettle();
      expect(find.text('The minimum must not be greater than the maximum'), findsNothing);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(current().amountMin, Int64(5000));
      expect(current().amountMax, Int64(6000));
    });

    testWidgets('the date range applies both ends', (tester) async {
      await open(tester);
      final range = tester.widget<ZenDateRangeField>(find.byType(ZenDateRangeField));
      range.onChanged!(DateTime(2026, 3, 1), DateTime(2026, 3, 31));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(current().dateFrom, DateTime(2026, 3, 1));
      expect(current().dateTo, DateTime(2026, 3, 31));
    });

    testWidgets('starts from the filter already applied, and Any clears a criterion', (
      tester,
    ) async {
      container = await _pump(
        tester,
        const RecordsFilterSheet(),
        filter: RecordFilter(
          accountId: 'cash',
          amountMin: Int64(250),
          type: RecordFilterType.income,
        ),
      );
      expect(tester.widget<TextField>(_field('Min amount')).controller!.text, '2.50');
      tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>).at(0)).onChanged!('');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(current().accountId, isNull);
      expect(current().amountMin, Int64(250));
      expect(current().type, RecordFilterType.income);
    });

    testWidgets('Clear all empties the filter', (tester) async {
      await open(tester);
      container.read(recordFilterProvider.notifier).apply(RecordFilter(accountId: 'cash'));
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();

      expect(current(), RecordFilter.empty);
    });
  });
}
