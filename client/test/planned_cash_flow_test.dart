// Planned cash flow on the overview (jlogicsoftware/prudent#58): which occurrences count, that
// income and spending stay apart, and that the section is separate from — and hideable without
// touching — the actual balances.
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/generated/prudent/v1/plans.pb.dart';
import 'package:prudent/generated/prudent/v1/settings.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/overview/overview.dart';
import 'package:prudent/overview/planned_cash_flow.dart';
import 'package:prudent/providers.dart';

Account _account(
  String id, {
  bool isActive = true,
  bool includeInTotal = true,
  int balance = 100000,
  String currency = 'PLN',
}) => Account(
  id: id,
  name: id,
  type: AccountType.ACCOUNT_TYPE_CASH,
  isActive: isActive,
  includeInTotal: includeInTotal,
  includeInOverview: true,
  balances: [CurrencyBalance(currency: currency, amountMinor: Int64(balance))],
);

PlanOccurrence _occurrence(
  int amountMinor, {
  String account = 'a',
  String currency = 'PLN',
  OccurrenceStatus status = OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
}) => PlanOccurrence(
  id: '$amountMinor-$account-$currency-${status.value}',
  amountMinor: Int64(amountMinor),
  currency: currency,
  accountId: account,
  status: status,
);

void main() {
  group('plannedCashFlowByCurrency', () {
    test('keeps income and spending apart and nets them', () {
      final flows = plannedCashFlowByCurrency(
        [_occurrence(500000), _occurrence(-120000), _occurrence(-30000)],
        [_account('a')],
        null,
      );
      expect(flows['PLN']!.income, Int64(500000));
      expect(flows['PLN']!.spending, Int64(-150000));
      expect(flows['PLN']!.net, Int64(350000));
    });

    test('counts planned and overdue, never completed or skipped', () {
      final flows = plannedCashFlowByCurrency(
        [
          _occurrence(-100),
          _occurrence(-200, status: OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE),
          _occurrence(-400, status: OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED),
          _occurrence(-800, status: OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED),
        ],
        [_account('a')],
        null,
      );
      expect(flows['PLN']!.spending, Int64(-300));
    });

    test('never blends currencies, and lists the main currency first', () {
      final flows = plannedCashFlowByCurrency(
        [_occurrence(100, currency: 'EUR'), _occurrence(-50), _occurrence(70, currency: 'USD')],
        [_account('a'), _account('b')],
        'USD',
      );
      // No account "b" occurrences, and every currency is its own entry.
      expect(flows.keys.toList(), ['USD', 'EUR', 'PLN']);
      expect(flows['EUR']!.net, Int64(100));
      expect(flows['PLN']!.net, Int64(-50));
    });

    test('drops occurrences on an inactive, untotalled or unknown account', () {
      final flows = plannedCashFlowByCurrency(
        [
          _occurrence(-100),
          _occurrence(-200, account: 'inactive'),
          _occurrence(-400, account: 'hidden'),
          _occurrence(-800, account: 'deleted'),
        ],
        [_account('a'), _account('inactive', isActive: false), _account('hidden', includeInTotal: false)],
        null,
      );
      expect(flows['PLN']!.spending, Int64(-100));
    });

    test('is empty when nothing is expected', () {
      expect(plannedCashFlowByCurrency(const [], [_account('a')], null), isEmpty);
    });
  });

  group('OverviewScreen planned section', () {
    Future<void> pump(WidgetTester tester, {Future<List<PlanOccurrence>> Function()? planned}) {
      return tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountsProvider.overrideWith(() => _FixedAccounts([_account('a')])),
            settingsProvider.overrideWith(() => _FixedSettings()),
            plannedOccurrencesProvider.overrideWith(
              (ref) => (planned ?? () async => [_occurrence(500000), _occurrence(-120000)])(),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: PrudentLocalizations.localizationsDelegates,
            supportedLocales: PrudentLocalizations.supportedLocales,
            home: OverviewScreen(),
          ),
        ),
      );
    }

    testWidgets('shows planned money apart from the balance, and the switch hides it', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('Planned cash flow'), findsOneWidget);
      expect(find.text('5000.00 PLN'), findsOneWidget);
      expect(find.text('-1200.00 PLN'), findsOneWidget);
      expect(find.text('3800.00 PLN'), findsOneWidget);
      // The actual balance is untouched by the planned money (it appears as the total and on the
      // account row).
      expect(find.text('1000.00 PLN'), findsNWidgets(2));

      await tester.scrollUntilVisible(find.text('Include planned cash flow'), 200);
      await tester.tap(find.text('Include planned cash flow'));
      await tester.pumpAndSettle();

      expect(find.text('Planned cash flow'), findsNothing);
      expect(find.text('3800.00 PLN'), findsNothing);
      expect(find.text('1000.00 PLN'), findsNWidgets(2));
    });

    testWidgets('a failed load is reported in the section and leaves the balances readable', (
      tester,
    ) async {
      await pump(tester, planned: () async => throw StateError('boom'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not load planned cash flow'), findsOneWidget);
      expect(find.text('1000.00 PLN'), findsNWidgets(2));
    });

    testWidgets('says so when nothing is planned', (tester) async {
      await pump(tester, planned: () async => const []);
      await tester.pumpAndSettle();

      expect(find.text('Nothing planned in the next 30 days.'), findsOneWidget);
    });
  });
}

class _FixedAccounts extends AccountsNotifier {
  _FixedAccounts(this._accounts);
  final List<Account> _accounts;

  @override
  Future<List<Account>> build() async => _accounts;
}

class _FixedSettings extends SettingsNotifier {
  @override
  Future<Settings> build() async => Settings(mainCurrency: 'PLN');
}
