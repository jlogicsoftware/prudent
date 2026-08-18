import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../src/generated/prudent/v1/analytics.pb.dart';
import '../src/generated/prudent/v1/categories.pb.dart';
import '../src/l10n/generated/prudent_localizations.dart';
import '../src/money.dart';
import '../src/providers.dart';
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
      return Scaffold(appBar: AppBar(title: Text(t.chartTitle)), body: Center(child: Text(t.chartNoAccounts)));
    }
    _currency ??= currencies.first;
    final currency = currencies.contains(_currency) ? _currency! : currencies.first;

    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final spendAsync = ref.watch(
      spendByCategoryProvider(SpendByCategoryParams(currency: currency, year: _month.year, month: _month.month)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(t.chartTitle),
        actions: [
          if (currencies.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: DropdownButton<String>(
                value: currency,
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (value) => setState(() => _currency = value),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
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
              data: (response) => _Content(response: response, categories: categories, currency: currency),
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.response, required this.categories, required this.currency});

  final SpendByCategoryResponse response;
  final List<Category> categories;
  final String currency;

  Category? _categoryFor(String id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    if (response.items.isEmpty) {
      return Center(child: Text(t.chartEmpty));
    }

    final total = response.items.fold<Int64>(Int64.ZERO, (sum, item) => sum + item.amountMinor);
    final slices = [
      for (final item in response.items)
        DonutSlice(
          value: item.amountMinor.toDouble(),
          color: switch (_categoryFor(item.categoryId)) {
            final c? => Color(c.colorArgb),
            null => Theme.of(context).colorScheme.outline,
          },
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 220,
          child: CustomPaint(
            painter: DonutChartPainter(
              slices: slices,
              trackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Text(
                '${formatMinorUnits(total)} $currency',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        for (final item in response.items)
          _LegendRow(
            color: switch (_categoryFor(item.categoryId)) {
              final c? => Color(c.colorArgb),
              null => Theme.of(context).colorScheme.outline,
            },
            label: _categoryFor(item.categoryId)?.title ?? t.chartUnknownCategory,
            amount: '${formatMinorUnits(item.amountMinor)} $currency',
            percent: total.toInt() == 0 ? 0 : item.amountMinor.toInt() * 100 ~/ total.toInt(),
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label, required this.amount, required this.percent});

  final Color color;
  final String label;
  final String amount;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text('$percent%', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 12),
          Text(amount, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
