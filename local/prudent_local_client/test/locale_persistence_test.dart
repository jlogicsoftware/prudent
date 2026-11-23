// The language picked in Settings must outlive the process in Prudent Local too
// (jlogicsoftware/prudent#289): the same provider and override as the server-connected app's,
// over the same storage. A "restart" is a new ProviderContainer, so nothing of the old one survives.
// Only what was written to the device does.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_ui/locale/persisted_locale.dart';
import 'package:prudent_ui/locale/shared_preferences_locale_store.dart';
import 'package:prudent_ui/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> launch({
    List<String> device = const ['en-US'],
  }) async {
    final container = ProviderContainer(
      overrides: [
        deviceLanguagesProvider.overrideWithValue(device),
        await loadPersistedLocale(),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a language chosen in Settings is still chosen after a restart', () async {
    final first = await launch();
    expect(first.read(localeProvider), const Locale('en'));

    await first.read(localeProvider.notifier).setLocale(const Locale('pl'));
    expect(first.read(localeProvider), const Locale('pl'));

    final second = await launch();
    expect(second.read(localeProvider), const Locale('pl'));
    // ZenClient reads this per request, so a restored language is sent from the first one.
    expect(second.read(localeProvider).languageCode, 'pl');
  });

  test('first launch starts in a supported device language', () async {
    final container = await launch(device: const ['de-DE', 'uk-UA']);
    expect(container.read(localeProvider), const Locale('uk'));
  });

  test('first launch with an unsupported device language starts in English', () async {
    final container = await launch(device: const ['de-DE', 'fr']);
    expect(container.read(localeProvider), const Locale('en'));
  });

  test('a stored choice wins over the device language', () async {
    SharedPreferences.setMockInitialValues({SharedPreferencesLocaleStore.key: 'en'});
    final container = await launch(device: const ['uk']);
    expect(container.read(localeProvider), const Locale('en'));
  });

  test('a stored tag that is no longer supported falls back instead of failing', () async {
    SharedPreferences.setMockInitialValues({SharedPreferencesLocaleStore.key: 'de'});
    expect((await launch(device: const ['uk'])).read(localeProvider), const Locale('uk'));

    SharedPreferences.setMockInitialValues({SharedPreferencesLocaleStore.key: 'xx-garbage'});
    expect((await launch()).read(localeProvider), const Locale('en'));
  });

  test('an unsupported language is refused, not stored', () async {
    final container = await launch();
    await expectLater(
      container.read(localeProvider.notifier).setLocale(const Locale('de')),
      throwsArgumentError,
    );
    expect(container.read(localeProvider), const Locale('en'));
    expect((await SharedPreferences.getInstance()).getString(SharedPreferencesLocaleStore.key), isNull);
  });
}
