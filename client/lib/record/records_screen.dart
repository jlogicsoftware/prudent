import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

import '../generated/prudent/v1/records.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';
import 'new_record.dart';
import 'new_transfer.dart';
import 'records_filter_sheet.dart';
import 'records_list.dart';

class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key});

  static const routeName = '/records';

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsState();
}

class _RecordsState extends ConsumerState<RecordsScreen> {
  void _presentOverlay(Widget body) {
    if (zenIsDesktop) {
      showDialog(
        context: context,
        builder:
            (ctx) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              child: SizedBox(width: 400, height: 460, child: Padding(padding: const EdgeInsets.all(16), child: body)),
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

  void _openAddRecordOverlay() {
    _presentOverlay(
      NewRecord(
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

  void _openFilterOverlay() {
    _presentOverlay(const RecordsFilterSheet());
  }

  void _openAddTransferOverlay() {
    _presentOverlay(
      NewTransfer(
        onSave:
            ({
              required title,
              required fromAmountInput,
              required fromCurrency,
              required toAmountInput,
              required toCurrency,
              required date,
              required fromAccountId,
              required toAccountId,
            }) => ref
                .read(recordsProvider.notifier)
                .addTransfer(
                  CreateTransferRequest(
                    title: title,
                    fromAmountMinor: parseMinorUnits(fromAmountInput),
                    fromCurrency: fromCurrency,
                    date: date,
                    fromAccountId: fromAccountId,
                    toAccountId: toAccountId,
                    toAmountMinor: parseMinorUnits(toAmountInput),
                    toCurrency: toCurrency,
                  ),
                ),
      ),
    );
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
                payee: record.payee,
                note: record.note,
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
    final filterActive = !ref.watch(recordFilterProvider).isEmpty;
    final t = PrudentLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.appTitle),
        actions: [
          IconButton(
            onPressed: _openFilterOverlay,
            icon: Icon(filterActive ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: filterActive ? t.recordsFilterActiveTooltip : t.recordsFilterTooltip,
          ),
          IconButton(
            onPressed: _openAddTransferOverlay,
            icon: const Icon(Icons.swap_horiz),
            tooltip: t.transfersNewTitle,
          ),
          IconButton(onPressed: _openAddRecordOverlay, icon: const Icon(Icons.add)),
        ],
      ),
      body: recordsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(t.recordsLoadError(error.toString()))),
        data: (records) {
          if (records.isEmpty && filterActive) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.recordsFilterEmpty),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.read(recordFilterProvider.notifier).clear(),
                    child: Text(t.recordsFilterClearAll),
                  ),
                ],
              ),
            );
          }
          if (records.isEmpty) {
            return Center(child: Text(t.recordsEmpty));
          }
          return RecordsList(records: records, onRemoveRecord: _removeRecord);
        },
      ),
    );
  }
}
