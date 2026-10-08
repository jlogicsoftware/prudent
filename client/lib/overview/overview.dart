import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../account/account_screen.dart';
import '../analytics/chart_screen.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../reminder/reminder_bell.dart';
import 'overview_totals.dart';
import 'planned_cash_flow.dart';
import 'planned_cash_flow_section.dart';
import '../providers.dart';

/// Real totals, replacing the two placeholder `Text` widgets this screen shipped with
/// (docs/prudent-migration-plan.md, Phase 4 — new product work, not a port).
///
/// Honours the three account flags nothing could previously set: `isActive` gates both sections
/// below (an inactive account is kept for its history, not shown here); `includeInOverview`
/// controls the account list; `includeInTotal` controls which accounts feed the totals. The two
/// are independent, so a savings account can be visible without counting toward spendable funds.
///
/// PER-CURRENCY, NEVER BLENDED (docs/DECISIONS.md ADR-009): Prudent does no FX, so there is no
/// single "total balance" number. Each currency gets its own row, main currency first.
///
/// PLANNED CASH FLOW (jlogicsoftware/prudent#58) is a section of its own beneath the balances and
/// is never added to them: it is money still expected, not money that moved, so no figure above it
/// changes when it is shown or hidden. The switch is the user's include/hide control.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final accountsAsync = ref.watch(accountsProvider);
    final mainCurrency = ref.watch(settingsProvider).value?.mainCurrency;
    final showPlanned = ref.watch(plannedCashFlowVisibleProvider);

    return ZenPageScaffold(
      title: t.appTitle,
      actions: [
        const ReminderBell(),
        ZenIconButton(
          icon: Icons.pie_chart_outline,
          label: t.chartTitle,
          onPressed:
              () => Navigator.of(
                context,
              ).push(ZenPageRoute(builder: (ctx) => const ChartScreen())),
        ),
        ZenIconButton(
          icon: Icons.list,
          label: t.accountsTitle,
          onPressed:
              () => Navigator.of(
                context,
              ).push(ZenPageRoute(builder: (ctx) => const AccountScreen())),
        ),
      ],
      body: accountsAsync.when(
        loading: () => const Center(child: ZenProgressIndicator()),
        error:
            (error, _) =>
                Center(child: Text(t.accountsLoadError(error.toString()))),
        data: (accounts) {
          final overviewAccounts = accountsForOverview(accounts);
          final totals = totalsByCurrency(accounts, mainCurrency);

          if (overviewAccounts.isEmpty && totals.isEmpty) {
            return Center(child: Text(t.overviewEmpty));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (totals.isNotEmpty) ...[
                Text(
                  t.overviewTotalsTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                for (final entry in totals.entries)
                  Card(
                    child: ListTile(
                      title: Text(entry.key),
                      trailing: Text(
                        '${formatMinorUnits(entry.value)} ${entry.key}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
              if (overviewAccounts.isNotEmpty) ...[
                Text(
                  t.overviewAccountsTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                for (final account in overviewAccounts)
                  Card(
                    child: ListTile(
                      title: Text(account.name),
                      subtitle: Text(
                        account.balances.isEmpty
                            ? t.accountsNoBalance
                            : account.balances
                                .map(
                                  (b) =>
                                      '${formatMinorUnits(b.amountMinor)} ${b.currency}',
                                )
                                .join(', '),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
              ZenSwitchRow(
                label: t.plannedCashFlowToggle,
                subtitle: t.plannedCashFlowToggleHint(plannedCashFlowDays),
                value: showPlanned,
                onChanged: ref.read(plannedCashFlowVisibleProvider.notifier).set,
              ),
              if (showPlanned)
                PlannedCashFlowSection(
                  accounts: accounts,
                  mainCurrency: mainCurrency,
                ),
            ],
          );
        },
      ),
    );
  }
}
