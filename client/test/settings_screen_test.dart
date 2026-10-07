// The settings screen (jlogicsoftware/prudent#103) on the framework's controls: its four
// navigation/session actions are ZenButtons and the language choice is a ZenSelect whose options
// are each language's own name. Which widget draws a control is zen_ui_widgets' test; what is
// asserted here is that the screen offers the right ones and that choosing a language takes effect.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/providers.dart';
import 'package:prudent/settings.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder:
              (context, ref, _) => MaterialApp(
                locale: ref.watch(localeProvider),
                localizationsDelegates: [
                  ...PrudentLocalizations.localizationsDelegates,
                  zenWidgetsLocaleDelegate,
                ],
                supportedLocales: PrudentLocalizations.supportedLocales,
                home: const SettingsScreen(),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers its four actions as framework buttons', (tester) async {
    await pump(tester);

    for (final label in ['Accounts', 'Categories', 'Profile', 'Log Out']) {
      expect(find.widgetWithText(ZenButton, label), findsOneWidget, reason: label);
    }
    expect(find.byType(ZenButton), findsNWidgets(4));
  });

  testWidgets('the language select names each language in itself and shows the current one', (tester) async {
    await pump(tester);

    final select = tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>));
    expect(select.label, 'Language');
    expect(select.value, 'en');
    expect(select.items.map(select.itemLabel), ['English', 'Українська', 'Polski']);
  });

  testWidgets('choosing a language switches the app to it', (tester) async {
    await pump(tester);

    tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>)).onChanged!('pl');
    await tester.pumpAndSettle();

    expect(container.read(localeProvider), const Locale('pl'));
    // The screen re-renders in the chosen language, and the select now shows it.
    expect(find.text('Ustawienia'), findsOneWidget);
    expect(tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>)).value, 'pl');
  });
}
