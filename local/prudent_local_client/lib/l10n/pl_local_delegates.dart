import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import 'pl_lock_localizations.dart';
import 'pl_store_localizations.dart';

/// Composed BEFORE `lockLocaleDelegate`: `Localizations` takes the first delegate per type that
/// supports the locale, so Prudent's Polish wins over the framework's degrading English fallback.
class PlLockDelegate extends LocalizationsDelegate<LockLocalizations> {
  const PlLockDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'pl';

  @override
  Future<LockLocalizations> load(Locale locale) =>
      SynchronousFuture<LockLocalizations>(PlLockLocalizations());

  @override
  bool shouldReload(PlLockDelegate old) => false;
}

/// Composed BEFORE `storeLocaleDelegate`, for the same reason as [PlLockDelegate].
class PlStoreDelegate extends LocalizationsDelegate<StoreLocalizations> {
  const PlStoreDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'pl';

  @override
  Future<StoreLocalizations> load(Locale locale) =>
      SynchronousFuture<StoreLocalizations>(PlStoreLocalizations());

  @override
  bool shouldReload(PlStoreDelegate old) => false;
}
