// Two-device rows of ADR-100 that unit 9 answers on screen:
// - T3: a lost device is cut off by replacing the sync key (jZenDev/jZen#237); the other devices
//   stop with "key replaced" until they are paired again, and the page says what it cannot do.
// - T23: a rule a merge breaks across records is listed beside the conflicts in words, with
//   Prudent's actions, and fixed only when the person chooses (jZenDev/jZen#233).
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/app/local_providers.dart';
import 'package:prudent_local_client/l10n/generated/local_localizations.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_sync/zen_store_sync.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import 'support/ledger_setup.dart';
import 'support/local_app_harness.dart';
import 'support/two_local_devices.dart';

void main() {
  final t = lookupPrudentLocalizations(const Locale('en'));
  final l = lookupLocalLocalizations(const Locale('en'));
  final s = lookupStoreLocalizations(const Locale('en'));

  testWidgets(
    'T3: replacing the sync key cuts the old key off, and the page says what it cannot do',
    (tester) async {
      final devices = await twoDevices(tester, TransportKind.sharedFolder);
      await tester.runAsync(() async {
        await openBooks(devices.phone.ledger);
        await devices.sync();
      });
      final oldKey = devices.phone.syncKey;
      final app = await LocalAppHarness.pump(
        tester,
        devices.phone,
        overrides: [
          syncKindProvider.overrideWithValue(ZenSyncKind.sharedFolder),
        ],
      );
      await app.openTab(t.navSettings);
      await app.tapText(l.settingsSync);
      expect(
        find.text(l.syncFolderWarning),
        findsOneWidget,
        reason: 'ADR-100 T6',
      );
      expect(find.text(l.removeDeviceLimits), findsOneWidget);
      expect(find.text(l.syncAddDevice), findsOneWidget);

      await app.tapReal(find.text(l.removeDeviceButton));
      await app.tapReal(find.text(l.removeDeviceButton).last);
      await app.settleUntil(find.text(l.removeDeviceDone));
      expect(devices.phone.syncKey, isNot(oldKey));

      // The laptop still holds the old key: it stops rather than write under it.
      await app.run(() => devices.laptop.transport!.syncNow());
      expect(devices.laptop.transport!.status.issue, ZenSyncIssue.keyReplaced);
    },
  );

  testWidgets(
    'T3 on iCloud: the page says how Apple removes a device, and replaces no key',
    (tester) async {
      final devices = await twoDevices(tester);
      final app = await LocalAppHarness.pump(
        tester,
        devices.phone,
        overrides: [syncKindProvider.overrideWithValue(ZenSyncKind.cloudKit)],
      );
      await app.openTab(t.navSettings);
      await app.tapText(l.settingsSync);
      expect(find.text(l.removeDeviceApple), findsOneWidget);
      expect(find.text(l.removeDeviceButton), findsNothing);
    },
  );

  testWidgets(
    'T23: a record left on an account deleted elsewhere is an issue in words, settled by choice',
    (tester) async {
      final devices = await twoDevices(tester);
      late Books books;
      late String savings;
      await tester.runAsync(() async {
        books = await openBooks(devices.laptop.ledger);
        savings = ok(
          await devices.laptop.ledger.createAccount(
            wire.CreateAccountRequest(
              name: 'Savings',
              type: wire.AccountType.ACCOUNT_TYPE_SAVINGS,
              isActive: true,
              balances: [
                wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(0)),
              ],
            ),
          ),
        ).value.id;
        await devices.sync();
        // Apart: the laptop deletes Wallet; the phone records a purchase on it.
        ok(await devices.laptop.ledger.deleteAccount(books.account));
        await addRecord(devices.phone.ledger, books, title: 'Train');
        await devices.sync();
      });
      final app = await LocalAppHarness.pump(tester, devices.phone);

      // The banner counts it beside the conflicts, on the home screen.
      expect(find.text(s.bannerAttention(1)), findsOneWidget);

      await app.openTab(t.navSettings);
      await app.tapText(l.settingsConflicts);
      expect(find.text(l.issueRecordAccountMissing), findsOneWidget);
      await app.tapText(l.issueRecordAccountMissing);
      expect(find.text(l.issueRecordAccountMissingBody), findsOneWidget);
      expect(find.text(l.actionMoveToAccount('Savings')), findsOneWidget);

      await app.tapReal(find.text(l.actionMoveToAccount('Savings')));
      await app.settle();
      final moved = devices.phone.prudent.records.list().dataOrNull!.single;
      expect(moved.posting.accountId, savings);
      expect(find.text(l.issueRecordAccountMissing), findsNothing);
    },
  );
}
