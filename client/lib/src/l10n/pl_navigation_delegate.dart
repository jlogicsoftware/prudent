import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

import 'pl_navigation_localizations.dart';

/// Composed BEFORE [navigationLocaleDelegate] in `MaterialApp.localizationsDelegates`
/// (`lib/src/app.dart`) — same ordering reason as [PlIdentityDelegate].
class PlNavigationDelegate extends LocalizationsDelegate<NavigationLocalizations> {
  const PlNavigationDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'pl';

  @override
  Future<NavigationLocalizations> load(Locale locale) =>
      SynchronousFuture<NavigationLocalizations>(PlNavigationLocalizations());

  @override
  bool shouldReload(PlNavigationDelegate old) => false;
}

const LocalizationsDelegate<NavigationLocalizations> prudentPlNavigationDelegate =
    PlNavigationDelegate();
