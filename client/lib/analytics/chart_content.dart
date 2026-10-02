import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';

import '../generated/prudent/v1/analytics.pb.dart';
import '../generated/prudent/v1/categories.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import 'donut_chart_painter.dart';
import 'legend_row.dart';

/// The chart screen's body once one month's spend by category has loaded: the donut with its
/// total, and a legend row per category.
class ChartContent extends StatelessWidget {
  const ChartContent({super.key, required this.response, required this.categories, required this.currency});

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
          LegendRow(
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
