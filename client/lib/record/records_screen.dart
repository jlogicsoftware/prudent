import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

import '../generated/prudent/v1/records.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';
import 'new_record.dart';
import 'records_list.dart';

class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key});

  static const routeName = '/records';

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsState();
}

class _RecordsState extends ConsumerState<RecordsScreen> {
  void _openAddRecordOverlay() {
    final body = NewRecord(
      onSave:
          ({
            required title,
            required amountInput,
            required date,
            required categoryId,
            required accountId,
            required currency,
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
                ),
              ),
    );

    if (zenIsDesktop) {
      showDialog(
        context: context,
        builder:
            (ctx) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              child: SizedBox(width: 400, height: 300, child: Padding(padding: const EdgeInsets.all(16), child: body)),
            ),
      );
    } else {
      showModalBottomSheet(
        isScrollControlled: true,
        useSafeArea: true,
        context: context,
        builder: (ctx) => body,
        constraints: const BoxConstraints.expand(),
      );
    }
  }

  /// Deletes immediately; undo re-creates via a fresh POST, which the server answers with a new
  /// id (docs/prudent-migration-plan.md "delete-with-undo").
  void _removeRecord(Record record) {
    final t = PrudentLocalizations.of(context);
    ref.read(recordsProvider.notifier).removeRecord(record.id);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(t.recordsDeleted),
        action: SnackBarAction(
          label: t.recordsUndo,
          onPressed: () {
            ref.read(recordsProvider.notifier).addRecord(
              CreateRecordRequest(
                title: record.title,
                amountMinor: record.amountMinor,
                date: record.date,
                categoryId: record.categoryId,
                accountId: record.accountId,
                currency: record.currency,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(recordsProvider);
    final t = PrudentLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.appTitle),
        actions: [IconButton(onPressed: _openAddRecordOverlay, icon: const Icon(Icons.add))],
      ),
      body: recordsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(t.recordsLoadError(error.toString()))),
        data: (records) {
          if (records.isEmpty) {
            return Center(child: Text(t.recordsEmpty));
          }
          return RecordsList(records: records, onRemoveRecord: _removeRecord);
        },
      ),
    );
  }
}
