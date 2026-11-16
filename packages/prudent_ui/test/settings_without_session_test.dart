// An app with no sign-in (Prudent Local, ADR-101) leaves settingsSessionProvider unset. Settings
// then has no profile and no log-out: a button that signs out of nothing would be a lie.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prudent_ui/content_width.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:prudent_ui/settings.dart';
import 'package:prudent_ui/settings_session.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

Future<void> pump(WidgetTester tester, {SettingsSession? session}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsSessionProvider.overrideWithValue(session)],
      child: MaterialApp(
        localizationsDelegates: [
          ...PrudentLocalizations.localizationsDelegates,
          ...GlobalMaterialLocalizations.delegates,
          zenWidgetsLocaleDelegate,
        ],
        supportedLocales: PrudentLocalizations.supportedLocales,
        home: const ZenPageWidthScope(
          maxWidth: prudentContentMaxWidth,
          child: SettingsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no session, Settings offers neither Profile nor Log Out', (tester) async {
    await pump(tester);

    expect(find.widgetWithText(ZenButton, 'Profile'), findsNothing);
    expect(find.widgetWithText(ZenButton, 'Log Out'), findsNothing);
    for (final label in ['Accounts', 'Categories', 'Privacy and data']) {
      expect(find.widgetWithText(ZenButton, label), findsOneWidget, reason: label);
    }
  });

  testWidgets('with a session, Log Out calls its signOut', (tester) async {
    var signedOut = 0;
    await pump(
      tester,
      session: SettingsSession(
        profileBuilder: (_) => const SizedBox(),
        signOut: () async => signedOut++,
      ),
    );

    await tester.tap(find.widgetWithText(ZenButton, 'Log Out'));
    await tester.pump();

    expect(signedOut, 1);
    expect(find.widgetWithText(ZenButton, 'Profile'), findsOneWidget);
  });
}
