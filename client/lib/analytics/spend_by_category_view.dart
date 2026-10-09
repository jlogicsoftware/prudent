import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/categories.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'chart_content.dart';

/// Spend by category, one month at a time, in one [currency] — the analytics screen's "by
/// category" view.
///
/// A `CustomPainter` donut (`DonutChartPainter`), not a charting package: pricing a dependency
/// against a hand-rolled arc chart came out in the painter's favour, and it carries no Wasm-clean
/// risk to prove (ADR-024).
class SpendByCategoryView extends ConsumerStatefulWidget {
  const SpendByCategoryView({super.key, required this.currency});

  final String currency;

  @override
  ConsumerState<SpendByCategoryView> createState() => _SpendByCategoryViewState();
}

class _SpendByCategoryViewState extends ConsumerState<SpendByCategoryView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final spendAsync = ref.watch(
      spendByCategoryProvider(
        SpendByCategoryParams(currency: widget.currency, year: _month.year, month: _month.month),
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ZenIconButton(
                icon: Icons.chevron_left,
                label: t.budgetPreviousMonth,
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Text(
                DateFormat.yMMMM(Localizations.localeOf(context).toLanguageTag()).format(_month),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ZenIconButton(
                icon: Icons.chevron_right,
                label: t.budgetNextMonth,
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ],
          ),
        ),
        Expanded(
          child: spendAsync.when(
            loading: () => const Center(child: ZenProgressIndicator()),
            error: (error, _) => Center(child: Text(t.chartLoadError(error.toString()))),
            data:
                (response) => ChartContent(
                  response: response,
                  categories: categories,
                  currency: widget.currency,
                ),
          ),
        ),
      ],
    );
  }
}
