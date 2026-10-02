import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'bar_chart_painter.dart';
import '../generated/prudent/v1/analytics.pb.dart';
import '../l10n/generated/prudent_localizations.dart';

/// The analytics screen's body once spend by month has loaded: a bar per month of the trailing
/// window, gap-filled with zero, and an empty note when nothing was spent.
class AnalyticsContent extends StatelessWidget {
  const AnalyticsContent({
    super.key,
    required this.response,
    required this.currency,
    required this.months,
  });

  final SpendByPeriodResponse response;
  final String currency;

  /// How many trailing months the chart covers, current month included.
  final int months;

  /// Gap-fills the trailing window with zero for any month the server omitted — the API tells
  /// "no data" from "zero spend" apart (analytics.proto), but a bar chart draws them identically,
  /// so the fill happens here rather than the server inventing zero rows it would then have to
  /// distinguish from real ones.
  List<ChartBar> _bars(BuildContext context) {
    final byPeriod = {for (final p in response.periods) p.period: p.amountMinor.toDouble()};
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final bars = <ChartBar>[];
    for (var i = months - 1; i >= 0; i--) {
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
