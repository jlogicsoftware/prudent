// Settings in Prudent Local (plan unit 9, ADR-108): no sign-in, so no profile and no log-out; the
// lock, sync and devices, and conflicts pages are added; "Privacy and data" opens Local's own page.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/app/local_providers.dart';
import 'package:prudent_local_client/l10n/generated/local_localizations.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:zen_store_sync/zen_store_sync.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import 'support/local_app_harness.dart';

void main() {
  final t = lookupPrudentLocalizations(const Locale('en'));
  final l = lookupLocalLocalizations(const Locale('en'));

  testWidgets('no profile, no log-out; the Local pages are there', (
    tester,
  ) async {
    final devices = await twoDevices(tester);
    final app = await LocalAppHarness.pump(tester, devices.phone);
    await app.openTab(t.navSettings);
    expect(find.text(t.settingsProfile), findsNothing);
    expect(find.text(t.settingsLogOut), findsNothing);
    for (final entry in [
      l.settingsSecurity,
      l.settingsSync,
      l.settingsConflicts,
      t.settingsPrivacy,
    ]) {
      expect(find.text(entry), findsOneWidget, reason: entry);
    }
  });

  testWidgets(
    'Lock is zen_ui_lock\'s switch, after the warning (ADR-100 T2, T25)',
    (tester) async {
      final devices = await twoDevices(tester);
      final app = await LocalAppHarness.pump(tester, devices.phone);
      await app.openTab(t.navSettings);
      await app.tapText(l.settingsSecurity);
      expect(find.byType(ZenPinLockSwitch), findsOneWidget);
      expect(find.text(l.securityNoPinWarning), findsOneWidget);
      expect(find.text(l.securityPeopleNote), findsOneWidget);
    },
  );

  testWidgets(
    'a device that cannot confirm its owner and has no paired device is warned (T4)',
    (tester) async {
      final devices = await twoDevices(tester);
      final app = await LocalAppHarness.pump(
        tester,
        devices.phone,
        overrides: [
          syncKindProvider.overrideWithValue(ZenSyncKind.sharedFolder),
        ],
      );
      await app.openTab(t.navSettings);
      await app.tapText(l.settingsSecurity);
      expect(find.text(l.securityForgetAlone), findsOneWidget);
    },
  );

  testWidgets('with an owner check, a forgotten PIN is reset by it (T4)', (
    tester,
  ) async {
    final devices = await twoDevices(tester);
    final app = await LocalAppHarness.pump(
      tester,
      devices.phone,
      ownerCheck: true,
    );
    await app.openTab(t.navSettings);
    await app.tapText(l.settingsSecurity);
    expect(find.text(l.securityForgetOwnerCheck), findsOneWidget);
    expect(find.text(l.securityForgetAlone), findsNothing);
  });

  testWidgets(
    'Sync and devices names what nobody can recover (T5) and how to remove a device (T3)',
    (tester) async {
      final devices = await twoDevices(tester);
      final app = await LocalAppHarness.pump(tester, devices.phone);
      await app.openTab(t.navSettings);
      await app.tapText(l.settingsSync);
      // On a phone the list is longer than the screen and builds lazily: scroll to each.
      await tester.scrollUntilVisible(
        find.text(l.removeDeviceTitle),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(l.removeDeviceTitle), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(l.syncLossWarning),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(l.syncLossWarning), findsOneWidget);
    },
  );
}
