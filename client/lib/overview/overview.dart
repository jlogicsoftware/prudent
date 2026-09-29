import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../account/account_screen.dart';
import '../generated/prudent/v1/accounts.pb.dart';
import '../analytics/chart_screen.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import 'overview_totals.dart';
import 'planned_cash_flow.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(t.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.pie_chart_outline),
            onPressed:
                () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const ChartScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed:
                () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const AccountScreen())),
          ),
        ],
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(t.accountsLoadError(error.toString()))),
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
                Text(t.overviewTotalsTitle, style: Theme.of(context).textTheme.headlineSmall),
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
                Text(t.overviewAccountsTitle, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                for (final account in overviewAccounts)
                  Card(
                    child: ListTile(
                      title: Text(account.name),
                      subtitle: Text(
                        account.balances.isEmpty
                            ? t.accountsNoBalance
                            : account.balances
                                .map((b) => '${formatMinorUnits(b.amountMinor)} ${b.currency}')
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
              if (showPlanned) PlannedCashFlowSection(accounts: accounts, mainCurrency: mainCurrency),
            ],
          );
        },
      ),
    );
  }
}

/// The planned section: per currency, expected income and spending kept apart, then their net.
/// A failed load is reported inside the section — the balances above it are unaffected and stay
/// readable.
class PlannedCashFlowSection extends ConsumerWidget {
  const PlannedCashFlowSection({super.key, required this.accounts, required this.mainCurrency});

  final List<Account> accounts;
  final String? mainCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final planned = ref.watch(plannedOccurrencesProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.plannedCashFlowTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          planned.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text(t.plannedCashFlowLoadError(error.toString())),
            data: (occurrences) {
              final flows = plannedCashFlowByCurrency(occurrences, accounts, mainCurrency);
              if (flows.isEmpty) return Text(t.plannedCashFlowEmpty(plannedCashFlowDays));
              return Column(
                children: [
                  for (final entry in flows.entries)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.key, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            _FlowRow(t.plannedCashFlowIncome, entry.value.income, entry.key),
                            _FlowRow(t.plannedCashFlowSpending, entry.value.spending, entry.key),
                            const Divider(),
                            _FlowRow(t.plannedCashFlowNet, entry.value.net, entry.key, emphasis: true),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow(this.label, this.amount, this.currency, {this.emphasis = false});

  final String label;
  final Int64 amount;
  final String currency;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final style =
        emphasis ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: style)),
          Text('${formatMinorUnits(amount)} $currency', style: style),
        ],
      ),
    );
  }
}
