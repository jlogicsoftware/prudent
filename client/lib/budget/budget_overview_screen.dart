import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/categories.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'budget_month.dart';
import 'budget_month_bar.dart';
import 'budget_summary_view.dart';

/// The monthly budget overview (M3, jlogicsoftware/prudent#63): move between months and see, per
/// budgeted category and in total, the plan, what was carried in, what was spent, what remains and
/// the percentage used — with overspent and empty months stated distinctly.
///
/// ONE MONTH IN ONE CURRENCY AT A TIME (ADR-009, ADR-044): the currency is picked, never summed
/// across. The month and currency are view state, not settings — they change what this screen
/// asks for, not what any figure means — so they live here and start at the current month and the
/// main (first) currency every time the tab is opened.
class BudgetOverviewScreen extends ConsumerStatefulWidget {
  const BudgetOverviewScreen({super.key});

  @override
  ConsumerState<BudgetOverviewScreen> createState() => _BudgetOverviewScreenState();
}

class _BudgetOverviewScreenState extends ConsumerState<BudgetOverviewScreen> {
  BudgetMonth _month = BudgetMonth.of(DateTime.now());
  String? _currency;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final currencies = ref.watch(analyticsCurrenciesProvider);

    if (currencies.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(t.budgetsTitle)),
        body: Center(child: Text(t.budgetNoAccounts)),
      );
    }
    final currency = currencies.contains(_currency) ? _currency! : currencies.first;

    final summaryAsync = ref.watch(
      budgetSummaryProvider(BudgetSummaryParams(month: _month.wire, currency: currency)),
    );
    final categories = {
      for (final category in ref.watch(categoriesProvider).value ?? const <Category>[])
        category.id: category,
    };

    return Scaffold(
      appBar: AppBar(title: Text(t.budgetsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: BudgetMonthBar(
              month: _month,
              isCurrent: _month == BudgetMonth.of(DateTime.now()),
              onPrevious: () => setState(() => _month = _month.previous),
              onNext: () => setState(() => _month = _month.next),
              onCurrent: () => setState(() => _month = BudgetMonth.of(DateTime.now())),
            ),
          ),
          if (currencies.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ZenSelect<String>(
                label: t.budgetCurrency,
                items: currencies,
                itemLabel: (c) => c,
                value: currency,
                onChanged: (value) => setState(() => _currency = value),
              ),
            ),
          Expanded(
            child: summaryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(t.budgetLoadError(error.toString()))),
              data:
                  (summary) =>
                      BudgetSummaryView(summary: summary, month: _month, categories: categories),
            ),
          ),
        ],
      ),
    );
  }
}
