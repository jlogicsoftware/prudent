// The monthly budget overview screen (jlogicsoftware/prudent#63): that it shows plan, carry-over,
// actual, remaining and percentage; that overspent and empty months are distinct from an ordinary
// one; that months can be navigated; and that a failure is reported rather than drawn as zeros.
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:prudent/budget/budget_month.dart';
import 'package:prudent/budget/budget_overview_screen.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/generated/prudent/v1/budgets.pb.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';
import 'package:prudent/generated/prudent/v1/settings.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/providers.dart';

Account _account(String id, String currency) => Account(
  id: id,
  name: id,
  type: AccountType.ACCOUNT_TYPE_CASH,
  isActive: true,
  includeInTotal: true,
  includeInOverview: true,
  balances: [CurrencyBalance(currency: currency, amountMinor: Int64(100000))],
);

CategoryBudgetSummary _item(
  String categoryId, {
  required int plan,
  required int actual,
  int carryOver = 0,
  String resetMonth = '',
}) => CategoryBudgetSummary(
  categoryId: categoryId,
  planMinor: Int64(plan),
  actualMinor: Int64(actual),
  carryOverMinor: Int64(carryOver),
  remainingMinor: Int64(carryOver + plan - actual),
  carryOverResetMonth: resetMonth,
);

BudgetSummaryResponse _summary(
  String month,
  String currency,
  List<CategoryBudgetSummary> items,
) => BudgetSummaryResponse(
  month: month,
  currency: currency,
  items: items,
  totalPlanMinor: items.fold<Int64>(Int64.ZERO, (sum, i) => sum + i.planMinor),
  totalActualMinor: items.fold<Int64>(Int64.ZERO, (sum, i) => sum + i.actualMinor),
  totalCarryOverMinor: items.fold<Int64>(Int64.ZERO, (sum, i) => sum + i.carryOverMinor),
  totalRemainingMinor: items.fold<Int64>(Int64.ZERO, (sum, i) => sum + i.remainingMinor),
);

final _food = Category(id: 'food', title: 'Food');
final _rent = Category(id: 'rent', title: 'Rent');

void main() {
  final requests = <BudgetSummaryParams>[];

  setUp(requests.clear);

  Future<void> pump(
    WidgetTester tester, {
    required Future<BudgetSummaryResponse> Function(BudgetSummaryParams params) summary,
    List<Account>? accounts,
    List<Category>? categories,
  }) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsProvider.overrideWith(() => _FixedAccounts(accounts ?? [_account('a', 'PLN')])),
          settingsProvider.overrideWith(() => _FixedSettings()),
          categoriesProvider.overrideWith(() => _FixedCategories(categories ?? [_food, _rent])),
          budgetSummaryProvider.overrideWith((ref, params) {
            requests.add(params);
            return summary(params);
          }),
        ],
        child: const MaterialApp(
          localizationsDelegates: PrudentLocalizations.localizationsDelegates,
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: BudgetOverviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final thisMonth = BudgetMonth.of(DateTime.now());
  String label(BudgetMonth month) => DateFormat.yMMMM('en').format(month.firstDay);

  testWidgets('shows plan, carry-over, actual, remaining and percentage per category and in total', (
    tester,
  ) async {
    await pump(
      tester,
      summary:
          (params) async => _summary(params.month, params.currency, [
            _item('rent', plan: 50000, actual: 25000, carryOver: 10000),
            _item('food', plan: 30000, actual: 12000),
          ]),
    );

    expect(requests.single.month, thisMonth.wire);
    expect(requests.single.currency, 'PLN');
    expect(find.text(label(thisMonth)), findsOneWidget);

    // Totals first, then the categories by title (Food before Rent although the server sent Rent first).
    final total = tester.getTopLeft(find.text('Total')).dy;
    final food = tester.getTopLeft(find.text('Food')).dy;
    final rent = tester.getTopLeft(find.text('Rent')).dy;
    expect(total, lessThan(food));
    expect(food, lessThan(rent));

    expect(find.text('Plan'), findsNWidgets(3));
    expect(find.text('Carried over'), findsNWidgets(3));
    expect(find.text('Spent'), findsNWidgets(3));
    expect(find.text('Remaining'), findsNWidgets(3));

    // Food: 120 of 300. Rent: 250 of 500 + 100 carried in. Total: 370 of 800 + 100.
    expect(find.text('300.00 PLN'), findsOneWidget);
    expect(find.text('120.00 PLN'), findsOneWidget);
    expect(find.text('180.00 PLN'), findsOneWidget);
    expect(find.text('40% used'), findsOneWidget);
    expect(find.text('500.00 PLN'), findsOneWidget);
    expect(find.text('100.00 PLN'), findsNWidgets(2)); // Rent's and the total's carry-over.
    expect(find.text('250.00 PLN'), findsOneWidget);
    expect(find.text('350.00 PLN'), findsOneWidget);
    expect(find.text('800.00 PLN'), findsOneWidget);
    expect(find.text('370.00 PLN'), findsOneWidget);
    expect(find.text('530.00 PLN'), findsOneWidget);
    // Rent: 250 of 600 available; total: 370 of 900 — both round down to 41.
    expect(find.text('41% used'), findsNWidgets(2));

    expect(find.textContaining('Overspent'), findsNothing);
  });

  testWidgets('states an overspent category in words, and leaves the others alone', (tester) async {
    await pump(
      tester,
      summary:
          (params) async => _summary(params.month, params.currency, [
            _item('food', plan: 30000, actual: 12000),
            _item('rent', plan: 50000, actual: 62550),
          ]),
    );

    // Only Rent is over; the total (800 vs 745.50) is not.
    expect(find.text('Overspent by 125.50 PLN'), findsOneWidget);
    expect(find.text('-125.50 PLN'), findsOneWidget);
    expect(find.text('125% used'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('54.50 PLN'), findsOneWidget);
  });

  testWidgets('an overspend carried in is overspent even with nothing spent, and has no percentage', (
    tester,
  ) async {
    await pump(
      tester,
      summary:
          (params) async => _summary(params.month, params.currency, [
            _item('food', plan: 10000, actual: 0, carryOver: -15000),
          ]),
    );

    // The category and the total are both over by 50.00.
    expect(find.text('Overspent by 50.00 PLN'), findsNWidgets(2));
    expect(find.textContaining('% used'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a month with no budgets is an empty state, not a card of zeros', (tester) async {
    await pump(tester, summary: (params) async => _summary(params.month, params.currency, const []));

    expect(find.text('No budgets for ${label(thisMonth)} in PLN.'), findsOneWidget);
    expect(find.text('Total'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('navigates to the previous and next month and back to this one', (tester) async {
    await pump(tester, summary: (params) async => _summary(params.month, params.currency, const []));
    expect(find.text('This month'), findsNothing);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(requests.last.month, thisMonth.previous.wire);
    expect(find.text(label(thisMonth.previous)), findsOneWidget);
    expect(find.text('No budgets for ${label(thisMonth.previous)} in PLN.'), findsOneWidget);

    await tester.tap(find.byTooltip('Next month'));
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(requests.last.month, thisMonth.next.wire);
    expect(find.text(label(thisMonth.next)), findsOneWidget);

    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();
    expect(requests.last.month, thisMonth.wire);
    expect(find.text('This month'), findsNothing);
  });

  testWidgets('asks for one currency at a time, the main one first', (tester) async {
    await pump(
      tester,
      accounts: [_account('a', 'PLN'), _account('b', 'EUR')],
      summary: (params) async => _summary(params.month, params.currency, const []),
    );

    expect(requests.map((r) => r.currency).toSet(), {'PLN'});
    expect(find.text('Currency'), findsOneWidget);
  });

  testWidgets('labels an archived category and a reset, and names a category it cannot find', (
    tester,
  ) async {
    await pump(
      tester,
      categories: [Category(id: 'food', title: 'Food', archived: true)],
      summary:
          (params) async => _summary(params.month, params.currency, [
            _item('food', plan: 30000, actual: 1000, resetMonth: '2026-02'),
            _item('gone', plan: 1000, actual: 0),
          ]),
    );

    expect(find.text('Archived'), findsOneWidget);
    expect(
      find.text('Carry-over reset from ${label(BudgetMonth(2026, 2))}'),
      findsOneWidget,
    );
    expect(find.text('Unknown category'), findsOneWidget);
  });

  testWidgets('reports a failed load rather than drawing zeros', (tester) async {
    await pump(tester, summary: (params) async => throw StateError('boom'));

    expect(find.textContaining('Could not load budgets'), findsOneWidget);
    expect(find.text('Total'), findsNothing);
  });

  testWidgets('asks for an account first when there is no currency to budget in', (tester) async {
    await pump(
      tester,
      accounts: const [],
      summary: (params) async => _summary(params.month, params.currency, const []),
    );

    expect(find.text('Add an account to start budgeting.'), findsOneWidget);
    expect(requests, isEmpty);
  });
}

class _FixedAccounts extends AccountsNotifier {
  _FixedAccounts(this._accounts);
  final List<Account> _accounts;

  @override
  Future<List<Account>> build() async => _accounts;
}

class _FixedCategories extends CategoriesNotifier {
  _FixedCategories(this._categories);
  final List<Category> _categories;

  @override
  Future<List<Category>> build() async => _categories;
}

class _FixedSettings extends SettingsNotifier {
  @override
  Future<Settings> build() async => Settings(mainCurrency: 'PLN');
}
