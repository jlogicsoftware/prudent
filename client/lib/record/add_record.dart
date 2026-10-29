import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/records.pb.dart';
import '../money.dart';
import '../providers.dart';
import 'new_record.dart';

void showAddRecord(BuildContext context, WidgetRef ref) {
  showAdaptivePresentation<void>(
    context,
    builder:
        (_) => NewRecord(
          onSave:
              ({
                required title,
                required amountInput,
                required date,
                required categoryId,
                required accountId,
                required currency,
                required payee,
                required note,
              }) => ref
                  .read(recordsProvider.notifier)
                  .addRecord(
                    CreateRecordRequest(
                      title: title,
                      amountMinor: parseMinorUnits(amountInput),
                      date: date,
                      categoryId: categoryId,
                      accountId: accountId,
                      currency: currency,
                      payee: payee,
                      note: note,
                    ),
                  ),
        ),
  );
}
