// Every tab of the shared shell loads from the device (plan unit 9): the ledger (unit 5), budgets and
// goals (6a), plans and reminders (6b), analytics (7) and the import (8b) are all wired, so no screen
// shows a load error and nothing is faked.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';

import 'support/ledger_setup.dart';
import 'support/local_app_harness.dart';

void main() {
  final t = lookupPrudentLocalizations(const Locale('en'));

  Future<LocalAppHarness> app(WidgetTester tester) async {
    final devices = await twoDevices(tester);
    await tester.runAsync(() async {
      final books = await openBooks(devices.phone.ledger);
      await addRecord(devices.phone.ledger, books);
    });
    return LocalAppHarness.pump(tester, devices.phone);
  }

  testWidgets(
    'the overview shows the balance and the planned cash flow loads beside it',
    (tester) async {
      await app(tester);
      expect(find.textContaining('90.00 PLN'), findsWidgets);
      expect(find.text(t.plannedCashFlowLoadError), findsNothing);
      expect(find.text(t.loadErrorRetry), findsNothing);
    },
  );

  testWidgets('Records lists what the ledger holds', (tester) async {
    final harness = await app(tester);
    await harness.openTab(t.navRecords);
    expect(find.text('Bread'), findsOneWidget);
  });

  testWidgets('Budgets loads', (tester) async {
    final harness = await app(tester);
    await harness.openTab(t.navBudgets);
    expect(find.text(t.budgetLoadError), findsNothing);
    expect(find.text(t.loadErrorRetry), findsNothing);
  });

  testWidgets('Goals loads, free money included', (tester) async {
    final harness = await app(tester);
    await harness.openTab(t.navGoals);
    expect(find.text(t.goalsLoadError), findsNothing);
    expect(find.text(t.goalFreeMoneyLoadError), findsNothing);
  });

  testWidgets('Analytics loads', (tester) async {
    final harness = await app(tester);
    await harness.openTab(t.navAnalytics);
    expect(find.text(t.analyticsLoadError), findsNothing);
    expect(find.text(t.loadErrorRetry), findsNothing);
  });
}
