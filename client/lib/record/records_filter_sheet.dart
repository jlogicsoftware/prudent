import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../generated/prudent/v1/categories.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';
import 'record_filter.dart';

/// The records list's filter/search UI (jlogicsoftware/prudent#52). Reads the current
/// [recordFilterProvider] into local editable state and writes a whole new [RecordFilter] back on
/// "Apply" — every criterion here is independently optional, and clearing never touches the
/// underlying records, only which of them are currently shown.
class RecordsFilterSheet extends ConsumerStatefulWidget {
  const RecordsFilterSheet({super.key});

  @override
  ConsumerState<RecordsFilterSheet> createState() => _RecordsFilterSheetState();
}

class _RecordsFilterSheetState extends ConsumerState<RecordsFilterSheet> {
  late final TextEditingController _searchController;
  late final TextEditingController _amountMinController;
  late final TextEditingController _amountMaxController;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _accountId;
  String? _categoryId;
  RecordFilterType? _type;

  @override
  void initState() {
    super.initState();
    final current = ref.read(recordFilterProvider);
    _searchController = TextEditingController(text: current.search ?? '');
    _amountMinController = TextEditingController(
      text: current.amountMin == null ? '' : formatMinorUnits(current.amountMin!),
    );
    _amountMaxController = TextEditingController(
      text: current.amountMax == null ? '' : formatMinorUnits(current.amountMax!),
    );
    _dateFrom = current.dateFrom;
    _dateTo = current.dateTo;
    _accountId = current.accountId;
    _categoryId = current.categoryId;
    _type = current.type;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _amountMinController.dispose();
    _amountMaxController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final initial = (from ? _dateFrom : _dateTo) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
  }

  void _apply() {
    final minAmount = _amountMinController.text.trim().isEmpty
        ? null
        : parseMinorUnits(_amountMinController.text)?.abs();
    final maxAmount = _amountMaxController.text.trim().isEmpty
        ? null
        : parseMinorUnits(_amountMaxController.text)?.abs();

    ref
        .read(recordFilterProvider.notifier)
        .apply(
          RecordFilter(
            dateFrom: _dateFrom,
            dateTo: _dateTo,
            accountId: _accountId,
            categoryId: _categoryId,
            type: _type,
            amountMin: minAmount,
            amountMax: maxAmount,
            search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
          ),
        );
    Navigator.pop(context);
  }

  void _clearAll() {
    ref.read(recordFilterProvider.notifier).clear();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final dateFormat = DateFormat.yMd(locale.toLanguageTag());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.recordsFilterTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(label: Text(t.recordsFilterSearchField)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(from: true),
                    child: Text(_dateFrom == null ? t.recordsFilterDateFrom : dateFormat.format(_dateFrom!)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(from: false),
                    child: Text(_dateTo == null ? t.recordsFilterDateTo : dateFormat.format(_dateTo!)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<RecordFilterType?>(
              segments: [
                ButtonSegment(value: null, label: Text(t.recordsFilterAnyType)),
                ButtonSegment(value: RecordFilterType.expense, label: Text(t.recordsExpense)),
                ButtonSegment(value: RecordFilterType.income, label: Text(t.recordsIncome)),
                ButtonSegment(value: RecordFilterType.transfer, label: Text(t.recordsTransfer)),
              ],
              selected: {_type},
              onSelectionChanged: (selection) => setState(() => _type = selection.first),
            ),
            const SizedBox(height: 16),
            DropdownButton<String?>(
              isExpanded: true,
              value: _accountId,
              hint: Text(t.recordsFilterAnyAccount),
              items: [
                DropdownMenuItem(value: null, child: Text(t.recordsFilterAnyAccount)),
                for (final account in accounts) DropdownMenuItem(value: account.id, child: Text(account.name)),
              ],
              onChanged: (value) => setState(() => _accountId = value),
            ),
            const SizedBox(height: 16),
            DropdownButton<String?>(
              isExpanded: true,
              value: _categoryId,
              hint: Text(t.recordsFilterAnyCategory),
              items: [
                DropdownMenuItem(value: null, child: Text(t.recordsFilterAnyCategory)),
                for (final category in categories)
                  DropdownMenuItem(value: category.id, child: Text(category.title.toUpperCase())),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountMinController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(label: Text(t.recordsFilterAmountMinField)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _amountMaxController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(label: Text(t.recordsFilterAmountMaxField)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(onPressed: _clearAll, child: Text(t.recordsFilterClearAll)),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
                ElevatedButton(onPressed: _apply, child: Text(t.recordsFilterApply)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
