import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        data: (response) => AnalyticsContent(response: response, currency: currency, months: _trailingMonths),
      ),
    );
  }
}
