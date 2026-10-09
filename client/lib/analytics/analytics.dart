import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'analytics_view.dart';
import 'spend_by_category_view.dart';
import 'spend_by_month_view.dart';

/// Where spending is looked at: by month over the trailing year, or by category for one month.
/// The two share a currency and a screen, so the donut that used to be a pushed screen of its own
/// (ADR-062) is a segment here and the navigation sidebar stays on screen.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  static const int _trailingMonths = 12;

  String? _currency;
  AnalyticsView _view = AnalyticsView.byMonth;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final currencies = ref.watch(analyticsCurrenciesProvider);
    if (currencies.isEmpty) {
      return ZenPageScaffold(title: t.analyticsTitle, body: Center(child: Text(t.chartNoAccounts)));
    }
    _currency ??= currencies.first;
    final currency = currencies.contains(_currency) ? _currency! : currencies.first;

    return ZenPageScaffold(
      title: t.analyticsTitle,
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ZenSegmentedControl<AnalyticsView>(
              segments: [
                ZenSegment(value: AnalyticsView.byMonth, label: t.analyticsSpendByMonth),
                ZenSegment(value: AnalyticsView.byCategory, label: t.analyticsSpendByCategory),
              ],
              selected: _view,
              onChanged: (view) => setState(() => _view = view),
            ),
          ),
          Expanded(
            child: switch (_view) {
              AnalyticsView.byMonth => SpendByMonthView(
                currency: currency,
                months: _trailingMonths,
              ),
              AnalyticsView.byCategory => SpendByCategoryView(currency: currency),
            },
          ),
        ],
      ),
    );
  }
}
