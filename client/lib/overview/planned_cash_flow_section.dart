import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'planned_cash_flow.dart';
import 'planned_cash_flow_row.dart';

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
            loading: () => const Center(child: ZenProgressIndicator()),
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
                            PlannedCashFlowRow(
                              t.plannedCashFlowIncome,
                              entry.value.income,
                              entry.key,
                            ),
                            PlannedCashFlowRow(
                              t.plannedCashFlowSpending,
                              entry.value.spending,
                              entry.key,
                            ),
                            const Divider(),
                            PlannedCashFlowRow(
                              t.plannedCashFlowNet,
                              entry.value.net,
                              entry.key,
                              emphasis: true,
                            ),
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
