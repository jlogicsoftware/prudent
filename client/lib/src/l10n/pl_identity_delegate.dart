import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'pl_identity_localizations.dart';

/// Composed BEFORE [identityLocaleDelegate] in `MaterialApp.localizationsDelegates`
/// (`lib/src/app.dart`): `Localizations` takes the first delegate per type that supports the
/// locale, so ordering is what makes Prudent's Polish win over the framework's English fallback
/// rather than the reverse.
///
/// [load] returns a [SynchronousFuture], like every generated delegate. An `async` load would
/// leave `IdentityLocalizations` unresolved for a frame during which
/// [identityLocaleDelegate] — composed second — answers in its place, which defeats the ordering
/// silently rather than loudly.
class PlIdentityDelegate extends LocalizationsDelegate<IdentityLocalizations> {
  const PlIdentityDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'pl';

  @override
  Future<IdentityLocalizations> load(Locale locale) =>
      SynchronousFuture<IdentityLocalizations>(PlIdentityLocalizations());

  @override
  bool shouldReload(PlIdentityDelegate old) => false;
}

const LocalizationsDelegate<IdentityLocalizations> prudentPlIdentityDelegate =
    PlIdentityDelegate();
