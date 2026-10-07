import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/categories.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'chart_content.dart';
import 'donut_chart_painter.dart';

/// Spend by category, one month at a time — replacing "Chart diagram"
/// (docs/prudent-migration-plan.md Phase 4, new product work).
///
/// A `CustomPainter` donut ([DonutChartPainter]), not a charting package: pricing a dependency
/// against a hand-rolled arc chart came out in the painter's favour, and it carries no Wasm-clean
/// risk to prove (ADR-024).
class ChartScreen extends ConsumerStatefulWidget {
  const ChartScreen({super.key});

  static const routName = '/chart';

  @override
  ConsumerState<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends ConsumerState<ChartScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _currency;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final currencies = ref.watch(analyticsCurrenciesProvider);
    if (currencies.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(t.chartTitle)),
        body: Center(child: Text(t.chartNoAccounts)),
      );
    }
    _currency ??= currencies.first;
    final currency = currencies.contains(_currency) ? _currency! : currencies.first;

    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final spendAsync = ref.watch(
      spendByCategoryProvider(
        SpendByCategoryParams(currency: currency, year: _month.year, month: _month.month),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(t.chartTitle)),
      body: Column(
        children: [
          if (currencies.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ZenSelect<String>(
                label: t.analyticsCurrencyField,
                items: currencies,
                itemLabel: (c) => c,
                value: currency,
                onChanged: (value) => setState(() => _currency = value),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                ),
                Text(
                  DateFormat.yMMMM(Localizations.localeOf(context).toLanguageTag()).format(_month),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                ),
              ],
            ),
          ),
          Expanded(
            child: spendAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(t.chartLoadError(error.toString()))),
              data:
                  (response) => ChartContent(response: response, categories: categories, currency: currency),
            ),
          ),
        ],
      ),
    );
  }
}
