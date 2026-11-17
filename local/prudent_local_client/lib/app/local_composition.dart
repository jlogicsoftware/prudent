import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:prudent_ui/providers.dart';
import 'package:prudent_ui/settings_entries.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';

import '../core/local_session.dart';
import '../l10n/generated/local_localizations.dart';
import '../repository/local_data_export.dart';
import '../repository/local_prudent_repository.dart';
import '../screens/local_data_screen.dart';
import '../screens/prudent_conflicts_page.dart';
import '../screens/security_screen.dart';
import '../screens/sync_screen.dart';
import 'local_providers.dart';

/// Prudent Local's composition: the shared screens' repository is the Local one, Settings gains the
/// lock, sync and devices, and conflicts pages, and "Privacy and data" opens Local's own page. There
/// is no `SettingsSession`: no sign-in, so no profile entry and no log-out (ADR-108).
///
/// One list, used by `main` and by every test that pumps the whole app, so a test runs exactly the
/// composition a device does.
List<Override> localOverrides({
  required LocalSession session,
  required ZenPinLock lock,
  required ZenLockStorage storage,
  LocalDataExport export = const LocalDataExport(),
}) => [
  localSessionProvider.overrideWithValue(session),
  pinLockProvider.overrideWithValue(lock),
  lockStorageProvider.overrideWithValue(storage),
  prudentRepositoryProvider.overrideWithValue(
    LocalPrudentRepository(
      ledger: () => session.ledger,
      imports: () => session.imports,
      plans: () => session.plans,
      analytics: () => session.analytics,
      export: export,
    ),
  ),
  privacyScreenProvider.overrideWithValue((_) => const LocalDataScreen()),
  settingsEntriesProvider.overrideWith(
    (ref) => [
      SettingsEntry(
        label: (context) => LocalLocalizations.of(context).settingsSecurity,
        builder: (_) => const SecurityScreen(),
      ),
      SettingsEntry(
        label: (context) => LocalLocalizations.of(context).settingsSync,
        builder: (_) => const SyncScreen(),
      ),
      SettingsEntry(
        label: (context) => LocalLocalizations.of(context).settingsConflicts,
        builder: (_) => const PrudentConflictsPage(),
      ),
    ],
  ),
];
