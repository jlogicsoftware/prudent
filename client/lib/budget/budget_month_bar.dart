import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/prudent_localizations.dart';
import 'budget_month.dart';

/// The month being viewed, with the controls to move through months. "This month" appears only
/// away from the current month, so the way back is always one tap and never clutters the bar.
class BudgetMonthBar extends StatelessWidget {
  const BudgetMonthBar({
    super.key,
    required this.month,
    required this.isCurrent,
    required this.onPrevious,
    required this.onNext,
    required this.onCurrent,
  });

  final BudgetMonth month;
  final bool isCurrent;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onCurrent;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: t.budgetPreviousMonth,
          onPressed: onPrevious,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                DateFormat.yMMMM(locale).format(month.firstDay),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (!isCurrent) TextButton(onPressed: onCurrent, child: Text(t.budgetThisMonth)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: t.budgetNextMonth,
          onPressed: onNext,
        ),
      ],
    );
  }
}
