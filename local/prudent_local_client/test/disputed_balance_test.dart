// ADR-113's "Also done when" for unit 9: every balance the screens show from the Local repository
// comes with the `Settled.unsettled` of the ledger answer behind it, and a figure that leaves
// something out says so beside the figure, in all three languages — never a bare number.
//
// Two real devices sync a disputed amount (each edits one record's amount offline), and the app on
// the phone is driven through its real screens: the overview's totals and account, the accounts page
// and the correction form each carry the words.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';

import 'support/ledger_setup.dart';
import 'support/local_app_harness.dart';
import 'support/two_local_devices.dart';

void main() {
  /// A record each device edited to a different amount while apart: the money is disputed.
  Future<TwoLocalDevices> disputed(WidgetTester tester) async {
    final devices = await twoDevices(tester);
    await tester.runAsync(() async {
      final books = await openBooks(devices.laptop.ledger);
      final bread = await addRecord(devices.laptop.ledger, books);
      await devices.sync();
      await editAmount(devices.laptop.ledger, books, bread.id, -1200);
      await editAmount(devices.phone.ledger, books, bread.id, -1500);
      await devices.sync();
    });
    return devices;
  }

  for (final language in ['en', 'uk', 'pl']) {
    testWidgets(
      'a disputed amount is left out and said beside the balance ($language)',
      (tester) async {
        final devices = await disputed(tester);
        final app = await LocalAppHarness.pump(
          tester,
          devices.phone,
          locale: Locale(language),
        );
        final words = lookupPrudentLocalizations(Locale(language))
            .unsettledBalanceNote(1);

        // The overview: the totals and the account, each with the words, and the figure that leaves
        // the disputed record out — the opening PLN 100.00, not either device's guess.
        expect(find.text(words), findsNWidgets(2));
        expect(find.textContaining('100.00 PLN'), findsWidgets);
        expect(find.textContaining('88.00'), findsNothing);
        expect(find.textContaining('85.00'), findsNothing);

        // The laptop says the same: both devices leave out the same record.
        final laptopFigures = ok(
          (await tester.runAsync(() => devices.laptop.ledger.listAccounts()))!,
        );
        expect(laptopFigures.unsettled.values.single, hasLength(1));
        await app.settle();
      },
    );
  }

  testWidgets(
    'once the dispute is settled the words go and the figure counts the record',
    (tester) async {
      final devices = await disputed(tester);
      final app = await LocalAppHarness.pump(tester, devices.phone);
      final words = lookupPrudentLocalizations(const Locale('en'))
          .unsettledBalanceNote(1);
      expect(find.text(words), findsNWidgets(2));

      // Settle it through the store, as the conflict screen's "Keep this version" does.
      await app.run(() async {
        final records = devices.phone.prudent.records;
        final conflict = records.conflicts().dataOrNull!.single;
        final laptopSide = conflict.sides.firstWhere(
          (side) => side.deviceName == 'Laptop',
        );
        await records.resolve(conflict.id, laptopSide.value);
      });

      expect(find.text(words), findsNothing);
      expect(find.textContaining('88.00 PLN'), findsWidgets);
    },
  );

  testWidgets('a settled ledger shows no words at all', (tester) async {
    final devices = await twoDevices(tester);
    await tester.runAsync(() async {
      final books = await openBooks(devices.phone.ledger);
      await addRecord(devices.phone.ledger, books);
    });
    await LocalAppHarness.pump(tester, devices.phone);
    expect(find.textContaining('100.00 PLN'), findsNothing);
    expect(find.textContaining('90.00 PLN'), findsWidgets);
    expect(find.textContaining('disagree'), findsNothing);
  });
}
