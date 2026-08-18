import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../category/category_icons.dart';
import '../../src/generated/prudent/v1/categories.pb.dart';
import '../../src/generated/prudent/v1/records.pb.dart';
import '../../src/money.dart';

class RecordItem extends StatelessWidget {
  const RecordItem(this.record, {required this.category, super.key});

  final Record record;

  /// Resolved by the caller against the category list it already holds; `null` for an id the
  /// client does not (yet) recognize, which renders the documented fallback rather than throwing.
  final Category? category;

  /// [record.date] is a civil date string (`YYYY-MM-DD`, proto/prudent/v1/records.proto) — parsed
  /// and re-rendered in the ambient locale rather than shown as-is.
  String _formattedDate(BuildContext context) {
    final parsed = DateTime.tryParse(record.date);
    if (parsed == null) return record.date;
    return DateFormat.yMd(Localizations.localeOf(context).toLanguageTag()).format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: category != null ? Color(category!.colorArgb) : Colors.grey,
            foregroundColor: Colors.white,
            child: Icon(category != null ? prudentIconFor(category!.iconKey) : prudentUnknownCategoryIcon),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.title, style: Theme.of(context).textTheme.titleLarge),
                Text(_formattedDate(context), style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          const Spacer(),
          Text(
            // SIGNED (ADR-014): negative is an expense, positive is income. formatMinorUnits
            // already prefixes a negative amount with '-'; a '+' is added here for income so the
            // sign is never ambiguous with an unsigned amount from an earlier product.
            '${record.amountMinor.isNegative ? '' : '+'}${formatMinorUnits(record.amountMinor)} ${record.currency}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color:
                  record.amountMinor.isNegative
                      ? Theme.of(context).colorScheme.error
                      : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.greenAccent
                          : Colors.green.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
