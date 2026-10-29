import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/categories.pb.dart';
import '../generated/prudent/v1/records.pb.dart';
import '../money.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'new_record.dart';
import 'record_item.dart';

class RecordsList extends ConsumerWidget {
  const RecordsList({
    super.key,
    required this.records,
    required this.onRemoveRecord,
  });

  final List<Record> records;
  final void Function(Record record) onRemoveRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    Category? categoryFor(String id) {
      for (final c in categories) {
        if (c.id == id) return c;
      }
      return null;
    }

    final t = PrudentLocalizations.of(context);

    void edit(Record record) {
      showAdaptivePresentation<void>(
        context,
        builder:
            (_) => NewRecord(
              initialRecord: record,
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
                      .editRecord(
                        record.id,
                        UpdateRecordRequest(
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

    Future<void> remove(Record record) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(t.recordsDeleteTitle),
              content: Text(t.recordsDeleteConfirm),
              actions: [
                ZenButton(
                  label: t.cancel,
                  variant: ZenButtonVariant.text,
                  onPressed: () => Navigator.pop(dialogContext, false),
                ),
                ZenButton(
                  label: t.recordsDelete,
                  variant: ZenButtonVariant.text,
                  onPressed: () => Navigator.pop(dialogContext, true),
                ),
              ],
            ),
      );
      if (confirmed == true && context.mounted) onRemoveRecord(record);
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.separated(
          itemCount: records.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, index) {
            final record = records[index];
            return ZenListItemActions(
              key: ValueKey(record.id),
              showActionsLabel: t.recordsShowActions,
              hideActionsLabel: t.recordsHideActions,
              actions: [
                ZenListItemAction(
                  icon: Icons.edit,
                  label: t.recordsEdit,
                  onPressed: () => edit(record),
                ),
                ZenListItemAction(
                  icon: Icons.delete,
                  variant: ZenListItemActionVariant.destructive,
                  label: t.recordsDelete,
                  onPressed: () => remove(record),
                ),
              ],
              child: RecordItem(
                record,
                category: categoryFor(record.categoryId),
              ),
            );
          },
        ),
      ),
    );
  }
}
