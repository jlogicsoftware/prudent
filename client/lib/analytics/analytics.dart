import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'analytics_content.dart';

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
      return ZenPageScaffold(
        title: t.analyticsTitle,
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
          Expanded(
            child: periodAsync.when(
              loading: () => const Center(child: ZenProgressIndicator()),
              error:
                  (error, _) =>
                      Center(child: Text(t.analyticsLoadError(error.toString()))),
              data:
                  (response) => AnalyticsContent(
                    response: response,
                    currency: currency,
                    months: _trailingMonths,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
