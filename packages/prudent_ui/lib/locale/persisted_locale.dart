import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zen_core/zen_core.dart';

import '../providers.dart';
import 'shared_preferences_locale_store.dart';

/// The override that makes the chosen language outlive the process. Awaited before `runApp`, so
/// the first frame is already in the right language and never flashes English first.
///
/// An override rather than a read inside the notifier because `build()` is synchronous: a locale
/// is needed to build the first frame, and loading the preferences is the one asynchronous step.
Future<Override> loadPersistedLocale() async {
  final preferences = await SharedPreferences.getInstance();
  return localePreferenceProvider.overrideWithValue(
    ZenLocalePreference(
      supported: prudentSupportedLocales,
      store: SharedPreferencesLocaleStore(preferences),
    ),
  );
}
