import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

import 'record/records_screen.dart';
import 'analytics/analytics.dart';
import 'budget/budget_overview_screen.dart';
import 'goal/goals_screen.dart';
import 'notification/notification_providers.dart';
import 'overview/overview.dart';
import 'settings.dart';
import 'l10n/generated/prudent_localizations.dart';

/// The authenticated shell: the reused `ZenNavigation` adaptive layout hosting Prudent's six
/// tabs (docs/prudent-migration-plan.md §2.4). `lib/navigation/` is deleted, not adapted.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);

    // Schedules the device notifications for the plans' reminders on sign-in. Listened to rather
    // than watched so its result never rebuilds the shell; the listener is what keeps the
    // auto-disposed pass alive until it finishes.
    ref.listen(reminderNotificationSyncProvider, (_, _) {});

    final items = [
      ZenNavigationItem(
        id: 'overview',
        label: t.navOverview,
        icon: Icons.home,
        builder: (context) => const OverviewScreen(),
      ),
      ZenNavigationItem(
        id: 'records',
        label: t.navRecords,
        icon: Icons.swap_vert_outlined,
        builder: (context) => const RecordsScreen(),
      ),
      ZenNavigationItem(
        id: 'budgets',
        label: t.navBudgets,
        icon: Icons.savings_outlined,
        builder: (context) => const BudgetOverviewScreen(),
      ),
      ZenNavigationItem(
        id: 'goals',
        label: t.navGoals,
        icon: Icons.flag_outlined,
        builder: (context) => const GoalsScreen(),
      ),
      ZenNavigationItem(
        id: 'analytics',
        label: t.navAnalytics,
        icon: Icons.analytics_outlined,
        builder: (context) => const AnalyticsScreen(),
      ),
      ZenNavigationItem(
        id: 'settings',
        label: t.navSettings,
        icon: Icons.settings,
        builder: (context) => const SettingsScreen(),
      ),
    ];

    return ZenNavigation(
      items: items,
      selectedIndex: _index,
      onItemSelected: (index) => setState(() => _index = index),
    );
  }
}
