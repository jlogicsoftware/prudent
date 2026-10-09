import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'analytics_content.dart';

/// Spend by month over the trailing [months] months in one [currency] — the analytics screen's
/// "by month" view.
class SpendByMonthView extends ConsumerWidget {
  const SpendByMonthView({super.key, required this.currency, required this.months});

  final String currency;

  /// How many trailing months the chart covers, current month included.
  final int months;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final periodAsync = ref.watch(
      spendByPeriodProvider(
        SpendByPeriodParams(currency: currency, granularity: 'MONTH', count: months),
      ),
    );

    return periodAsync.when(
      loading: () => const Center(child: ZenProgressIndicator()),
      error: (error, _) => Center(child: Text(t.analyticsLoadError(error.toString()))),
      data: (response) => AnalyticsContent(response: response, currency: currency, months: months),
    );
  }
}
