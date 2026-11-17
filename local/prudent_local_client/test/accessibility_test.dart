// Prudent Local's own pages, and the shared screens as Local composes them, against Flutter's
// accessibility guidelines: tap targets labelled and large enough, text with enough contrast.
//
// Tap-target SIZE is a touch rule, so it is checked when the suite is compiled for a phone
// (`zenIsMobile`: run it with ZEN_PLATFORM=android or ios), on a phone-sized screen, against that
// platform's guideline (Apple's 44 pt, Android's 48 dp) — the controls render that platform's sizes.
// Compiled for a desktop (the CI host), the layout is the desktop's at any width, driven by a pointer
// (its sidebar rows are `zen_ui_navigation`'s 38 pt): there labels and contrast are checked.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/l10n/generated/local_localizations.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:zen_core/zen_core.dart' show zenIsApplePlatform, zenIsMobile;

import 'support/ledger_setup.dart';
import 'support/local_app_harness.dart';

void main() {
  final t = lookupPrudentLocalizations(const Locale('en'));
  final l = lookupLocalLocalizations(const Locale('en'));

  // A phone-sized screen only means a phone's layout when the suite is compiled for one; compiled for
  // a desktop (macOS here, Linux in CI) the layout is the desktop's at any width.
  const phone = zenIsMobile ? Size(390, 844) : Size(1280, 900);

  Future<void> meetsAll(WidgetTester tester, {bool touch = true}) async {
    if (touch && zenIsMobile) {
      await expectLater(
        tester,
        meetsGuideline(
          zenIsApplePlatform
              ? iOSTapTargetGuideline
              : androidTapTargetGuideline,
        ),
      );
    }
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  Future<LocalAppHarness> disputedApp(
    WidgetTester tester, {
    Size size = phone,
  }) async {
    final devices = await twoDevices(tester);
    await tester.runAsync(() async {
      final books = await openBooks(devices.laptop.ledger);
      final bread = await addRecord(devices.laptop.ledger, books);
      await devices.sync();
      await editAmount(devices.laptop.ledger, books, bread.id, -1200);
      await editAmount(devices.phone.ledger, books, bread.id, -1500);
      await devices.sync();
    });
    return LocalAppHarness.pump(tester, devices.phone, size: size);
  }

  testWidgets(
    'the overview with a disputed balance and the conflict banner, on a phone',
    (tester) async {
      final handle = tester.ensureSemantics();
      await disputedApp(tester);
      await meetsAll(tester);
      handle.dispose();
    },
  );

  testWidgets('the overview on a wide, pointer-driven screen', (tester) async {
    final handle = tester.ensureSemantics();
    await disputedApp(tester, size: const Size(1280, 900));
    await meetsAll(tester, touch: false);
    handle.dispose();
  });

  for (final page in ['lock', 'sync', 'data']) {
    testWidgets('Settings → $page', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await disputedApp(tester);
      await app.openTab(t.navSettings);
      await app.tapText(switch (page) {
        'lock' => l.settingsSecurity,
        'sync' => l.settingsSync,
        _ => t.settingsPrivacy,
      });
      await meetsAll(tester);
      handle.dispose();
    });
  }

  testWidgets('the first-run notice', (tester) async {
    final handle = tester.ensureSemantics();
    final devices = await twoDevices(tester);
    await LocalAppHarness.pump(
      tester,
      devices.phone,
      firstRunSeen: false,
      size: phone,
    );
    await meetsAll(tester);
    handle.dispose();
  });

  testWidgets('a balance\'s caveat is read out with the balance', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await disputedApp(tester);
    expect(find.bySemanticsLabel(RegExp('Leaves out 1 entry')), findsWidgets);
    handle.dispose();
  });
}
