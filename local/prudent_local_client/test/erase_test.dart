// Erasure (plan unit 9; ADR-100 T24, jZenDev/jZen#239).
//
// - On screen: "Erase this device's copy" says what remains before it is pressed and asks first;
//   "Erase everywhere" asks twice; a device whose data was erased everywhere says so and starts
//   again only when the person asks.
// - Across two real devices: erasing here leaves the other device's copy and comes back at the next
//   sync; erasing everywhere reaches the other device through the shared folder; starting again
//   makes a new, empty store and forgets the erased key.
//
// The erasing itself closes and reopens the store, which waits on file I/O a widget test's fake
// clock never finishes; so the semantics are proven on the real event loop (as jZen's own Local
// tests do), and the whole flow through the buttons in integration_test/app_test.dart on macOS.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:prudent_local_client/l10n/generated/local_localizations.dart';
import 'package:prudent_local_client/screens/erased_everywhere_screen.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';

import 'support/ledger_setup.dart';
import 'support/local_app_harness.dart';
import 'support/two_local_devices.dart';

void main() {
  final t = lookupPrudentLocalizations(const Locale('en'));
  final l = lookupLocalLocalizations(const Locale('en'));

  group('on screen', () {
    testWidgets(
      'erasing this device\'s copy says what remains and asks first',
      (tester) async {
        final devices = await twoDevices(tester);
        await tester.runAsync(() => openBooks(devices.phone.ledger));
        final app = await LocalAppHarness.pump(tester, devices.phone);
        await app.openTab(t.navSettings);
        await app.tapText(t.settingsPrivacy);
        expect(find.text(l.dataEraseHint), findsOneWidget);
        // The heading and the button read alike; the button is the second.
        await app.tapFinder(find.text(l.dataEraseButton).last);
        expect(find.text(l.dataEraseConfirm), findsOneWidget);
        await app.tapText(l.cancel);
        expect(devices.phone.prudent.accounts.list().dataOrNull, hasLength(1));
      },
    );

    testWidgets('erasing everywhere says it cannot be undone and asks twice', (
      tester,
    ) async {
      final devices = await twoDevices(tester);
      await tester.runAsync(() => openBooks(devices.phone.ledger));
      final app = await LocalAppHarness.pump(tester, devices.phone);
      await app.openTab(t.navSettings);
      await app.tapText(t.settingsPrivacy);
      await app.tapFinder(find.text(l.dataEverywhereButton).last);
      expect(find.text(l.dataEverywhereHint), findsWidgets);
      await app.tapText(l.confirm);
      expect(find.text(l.dataEverywhereConfirm), findsOneWidget);
      await app.tapText(l.cancel);
      expect(devices.phone.erasedEverywhere, isFalse);
      expect(devices.phone.prudent.accounts.list().dataOrNull, hasLength(1));
    });

    testWidgets(
      'the app follows a new store after this device\'s copy is erased, without a build error',
      (tester) async {
        final devices = await twoDevices(tester);
        await tester.runAsync(() async {
          await openBooks(devices.laptop.ledger);
          await devices.sync();
        });
        final app = await LocalAppHarness.pump(tester, devices.phone);
        expect(find.text('Wallet'), findsOneWidget);
        // The store is replaced under the mounted app; every read follows it once the frame is
        // built (refreshing during the build would modify a provider while the tree builds).
        final before = devices.phone.generation;
        await app.run(devices.phone.eraseThisDevice);
        expect(tester.takeException(), isNull);
        expect(devices.phone.generation, greaterThan(before));
        // The new store syncs the folder's copy back in, and the screen shows it.
        await app.run(devices.sync);
        expect(find.text('Wallet'), findsOneWidget);
      },
    );

    testWidgets(
      'a device whose data another device erased everywhere says so',
      (tester) async {
        final devices = await twoDevices(tester, TransportKind.sharedFolder);
        await tester.runAsync(() async {
          await openBooks(devices.laptop.ledger);
          await devices.sync();
          await devices.laptop.eraseEverywhere();
          await TwoLocalDevices.syncAndRest(devices.phone);
        });
        await LocalAppHarness.pump(tester, devices.phone);
        expect(find.byType(ErasedEverywhereScreen), findsOneWidget);
        expect(find.text(l.erasedBody), findsOneWidget);
        expect(find.text(l.erasedStart), findsOneWidget);
      },
    );
  });

  group('across two devices', () {
    late TwoLocalDevices devices;
    tearDown(() async => devices.dispose());

    test(
      'erasing this device\'s copy leaves the other\'s, and it comes back',
      () async {
        devices = await TwoLocalDevices.create();
        final books = await openBooks(devices.laptop.ledger);
        await addRecord(devices.laptop.ledger, books);
        await devices.sync();
        expect(await devices.phone.eraseThisDevice(), isA<ZenSuccess<void>>());
        expect(devices.phone.prudent.accounts.list().dataOrNull, isEmpty);
        expect(devices.laptop.prudent.accounts.list().dataOrNull, hasLength(1));
        await devices.sync();
        expect(devices.phone.prudent.accounts.list().dataOrNull, hasLength(1));
        expect(
          ok(await devices.phone.ledger.listRecords()).records,
          hasLength(1),
        );
      },
    );

    test('erasing everywhere reaches the other device; starting again is a new, empty store', () async {
      devices = await TwoLocalDevices.create(TransportKind.sharedFolder);
      final books = await openBooks(devices.laptop.ledger);
      await addRecord(devices.laptop.ledger, books);
      await devices.sync();

      expect(await devices.phone.eraseEverywhere(), isA<ZenSuccess<void>>());
      expect(devices.phone.erasedEverywhere, isTrue);
      await TwoLocalDevices.syncAndRest(devices.laptop);
      expect(devices.laptop.erasedEverywhere, isTrue);
      expect(devices.laptop.prudent.accounts.list().dataOrNull, isEmpty);

      expect(await devices.phone.startAfresh(), isA<ZenSuccess<void>>());
      expect(devices.phone.erasedEverywhere, isFalse);
      expect(
        devices.phone.hasSyncKey,
        isFalse,
        reason: 'an erased key is never reused',
      );
      expect(devices.phone.prudent.accounts.list().dataOrNull, isEmpty);
      await openBooks(devices.phone.ledger);
      expect(devices.phone.prudent.accounts.list().dataOrNull, hasLength(1));
    });
  });
}
