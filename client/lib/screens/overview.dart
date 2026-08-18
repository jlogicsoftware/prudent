import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_screen.dart';
import '../chart/chart_screen.dart';
import '../src/l10n/generated/prudent_localizations.dart';
import '../src/money.dart';
import '../src/overview_totals.dart';
import '../src/providers.dart';

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
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final accountsAsync = ref.watch(accountsProvider);
    final mainCurrency = ref.watch(settingsProvider).value?.mainCurrency;

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
              ],
            ],
          );
        },
      ),
    );
  }
}
