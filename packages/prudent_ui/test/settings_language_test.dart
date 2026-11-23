// A signed-in person's language choice is told to the server (jlogicsoftware/prudent#291, ADR-130)
// after it has been applied and stored on the device. The device never waits on the server, and a
// refusal is said in a sentence, not thrown at the person.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prudent_ui/content_width.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:prudent_ui/providers.dart';
import 'package:prudent_ui/settings.dart';
import 'package:prudent_ui/settings_session.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

Future<ProviderContainer> pump(
  WidgetTester tester,
  Future<void> Function(String language)? setLanguage,
) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      settingsSessionProvider.overrideWithValue(
        SettingsSession(
          profileBuilder: (_) => const SizedBox(),
          signOut: () async {},
          setLanguage: setLanguage,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // The app's locale is left at English so the sentence below can be found by its words; what
      // is under test is the provider and the call, not the re-render (settings_screen_test).
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
  return container;
}

void choose(WidgetTester tester, String code) =>
    tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>)).onChanged!(code);

void main() {
  testWidgets('the chosen language is told to the server once it is applied', (tester) async {
    final told = <String>[];
    final container = await pump(tester, (language) async => told.add(language));

    choose(tester, 'pl');
    await tester.pumpAndSettle();

    expect(container.read(localeProvider), const Locale('pl'));
    expect(told, ['pl']);
    expect(find.textContaining('could not be told'), findsNothing);
  });

  testWidgets('a refusal keeps the device language and says so', (tester) async {
    final container = await pump(tester, (_) async => throw StateError('refused'));

    choose(tester, 'uk');
    await tester.pumpAndSettle();

    expect(container.read(localeProvider), const Locale('uk'));
    expect(find.textContaining('could not be told'), findsOneWidget);
    // The person sees a sentence, never the exception's text.
    expect(find.textContaining('refused'), findsNothing);
  });

  testWidgets('a session with nothing to tell still switches the language', (tester) async {
    final container = await pump(tester, null);

    choose(tester, 'pl');
    await tester.pumpAndSettle();

    expect(container.read(localeProvider), const Locale('pl'));
    expect(find.textContaining('could not be told'), findsNothing);
  });
}
