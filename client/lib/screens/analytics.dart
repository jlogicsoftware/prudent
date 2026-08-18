import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../chart/bar_chart_painter.dart';
import '../src/generated/prudent/v1/analytics.pb.dart';
import '../src/l10n/generated/prudent_localizations.dart';
import '../src/providers.dart';

/// Spend by month, trailing 12 months — replacing "Detailed analytics will be available soon"
/// (docs/prudent-migration-plan.md Phase 4, new product work).
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  static const int _trailingMonths = 12;

  String? _currency;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final currencies = ref.watch(analyticsCurrenciesProvider);
    if (currencies.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(t.analyticsTitle)),
        body: Center(child: Text(t.chartNoAccounts)),
      );
    }
    _currency ??= currencies.first;
    final currency = currencies.contains(_currency) ? _currency! : currencies.first;

    final periodAsync = ref.watch(
      spendByPeriodProvider(
        SpendByPeriodParams(currency: currency, granularity: 'MONTH', count: _trailingMonths),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(t.analyticsTitle),
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
      body: periodAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(t.analyticsLoadError(error.toString()))),
        data: (response) => _Content(response: response, currency: currency),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.response, required this.currency});

  final SpendByPeriodResponse response;
  final String currency;

  /// Gap-fills the trailing window with zero for any month the server omitted — the API tells
  /// "no data" from "zero spend" apart (analytics.proto), but a bar chart draws them identically,
  /// so the fill happens here rather than the server inventing zero rows it would then have to
  /// distinguish from real ones.
  List<ChartBar> _bars(BuildContext context) {
    final byPeriod = {for (final p in response.periods) p.period: p.amountMinor.toDouble()};
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final bars = <ChartBar>[];
    for (var i = _AnalyticsScreenState._trailingMonths - 1; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i);
      final key =
          '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
      bars.add(ChartBar(label: DateFormat.MMM(locale).format(month), value: byPeriod[key] ?? 0));
    }
    return bars;
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final bars = _bars(context);
    final hasSpend = bars.any((b) => b.value > 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.analyticsSpendByMonth, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        SizedBox(
          height: 240,
          child: CustomPaint(
            painter: BarChartPainter(
              bars: bars,
              barColor: Theme.of(context).colorScheme.primary,
              labelStyle: Theme.of(context).textTheme.labelSmall!,
            ),
          ),
        ),
        if (!hasSpend) ...[const SizedBox(height: 16), Center(child: Text(t.analyticsEmpty))],
      ],
    );
  }
}
