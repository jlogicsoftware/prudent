import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'pl_widgets_localizations.dart';

/// Composed BEFORE [zenWidgetsLocaleDelegate] in `MaterialApp.localizationsDelegates`
/// (`lib/app.dart`) — same ordering reason as [PlIdentityDelegate].
class PlWidgetsDelegate extends LocalizationsDelegate<ZenWidgetsLocalizations> {
  const PlWidgetsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'pl';

  @override
  Future<ZenWidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture<ZenWidgetsLocalizations>(PlWidgetsLocalizations());

  @override
  bool shouldReload(PlWidgetsDelegate old) => false;
}

const LocalizationsDelegate<ZenWidgetsLocalizations> prudentPlWidgetsDelegate = PlWidgetsDelegate();
