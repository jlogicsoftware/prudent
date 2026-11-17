// The budget and goal figures (unit 6a, ADR-116) carry what they leave out, like balances do, and
// follow the store while their screen is open: a dispute that arrives by sync while the Budgets or
// Goals tab is mounted shows its note there, in the person's language, and settling it removes the
// note — without leaving the tab (review of jlogicsoftware/prudent#269, findings 1 and 2).
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart' as wire;
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:prudent_local_store/prudent_local_store.dart'
    show LedgerBudgets, LedgerGoals;

import 'support/ledger_setup.dart';
import 'support/local_app_harness.dart';
import 'support/two_local_devices.dart';

void main() {
  final t = lookupPrudentLocalizations(const Locale('en'));
  final note = t.unsettledBalanceNote(1);

  /// Both devices edit [id]'s amount apart, then sync: the money is disputed.
  Future<void> dispute(
    TwoLocalDevices devices,
    Books books,
    String id, {
    String date = '2026-11-02',
  }) async {
    await editAmount(devices.laptop.ledger, books, id, -1200, date: date);
    await editAmount(devices.phone.ledger, books, id, -1500, date: date);
    await devices.sync();
  }

  /// Keeps the laptop's version, as "Keep this version" on the conflict screen does.
  Future<void> settle(TwoLocalDevices devices) async {
    final records = devices.phone.prudent.records;
    final conflict = records.conflicts().dataOrNull!.single;
    await records.resolve(
      conflict.id,
      conflict.sides.firstWhere((side) => side.deviceName == 'Laptop').value,
    );
  }

  testWidgets(
    'a dispute synced while Budgets is open is said beside the summary, and goes when settled',
    (tester) async {
      final devices = await twoDevices(tester);
      late Books books;
      late String bread;
      final month = DateTime.now();
      final monthText =
          '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final day = '$monthText-01';
      await tester.runAsync(() async {
        books = await openBooks(devices.laptop.ledger);
        bread = (await addRecord(devices.laptop.ledger, books, date: day)).id;
        ok(
          await devices.laptop.ledger.setBudget(
            books.category,
            monthText,
            'PLN',
            5000,
          ),
        );
        await devices.sync();
      });
      final app = await LocalAppHarness.pump(tester, devices.phone);
      await app.openTab(t.navBudgets);
      expect(find.text(note), findsNothing);

      // The dispute arrives while the tab is open: the summary is read again and says so.
      await app.run(() => dispute(devices, books, bread, date: day));
      expect(find.text(note), findsWidgets);

      await app.run(() => settle(devices));
      expect(find.text(note), findsNothing);
    },
  );

  testWidgets(
    'a dispute synced while Goals is open is said beside free money, and goes when settled',
    (tester) async {
      final devices = await twoDevices(tester);
      late Books books;
      late String bread;
      await tester.runAsync(() async {
        books = await openBooks(devices.laptop.ledger);
        // Free money reads only accounts marked eligible for goals (ADR-051).
        final wallet = ok(await devices.laptop.ledger.getAccount(books.account))
            .value;
        ok(
          await devices.laptop.ledger.updateAccount(
            books.account,
            wire.UpdateAccountRequest(
              name: wallet.name,
              type: wallet.type,
              isActive: true,
              includeInTotal: true,
              includeInOverview: true,
              eligibleForGoals: true,
              balances: wallet.balances
                  .map(
                    (b) => wire.CurrencyBalance(
                      currency: b.currency,
                      amountMinor: Int64(10000),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
        bread = (await addRecord(devices.laptop.ledger, books)).id;
        ok(
          await devices.laptop.ledger.createGoal(
            wire.CreateGoalRequest(
              name: 'Bike',
              currency: 'PLN',
              targetAmountMinor: Int64(20000),
            ),
          ),
        );
        await devices.sync();
      });
      final app = await LocalAppHarness.pump(tester, devices.phone);
      await app.openTab(t.navGoals);
      expect(find.text('Bike'), findsWidgets);
      expect(find.text(note), findsNothing);

      await app.run(() => dispute(devices, books, bread));
      expect(find.text(note), findsWidgets);

      await app.run(() => settle(devices));
      expect(find.text(note), findsNothing);
    },
  );
}
