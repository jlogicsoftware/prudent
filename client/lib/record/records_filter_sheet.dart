import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

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
  static const _anyType = '';
  static const _anyId = '';

  late final TextEditingController _searchController;
  late final TextEditingController _amountMinController;
  late final TextEditingController _amountMaxController;
  final _formKey = GlobalKey<FormState>();
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

  /// What an amount field holds in minor units, or null when it is empty. Both ends are
  /// magnitudes (the server matches the record's absolute amount), so the field refuses a sign.
  Int64? _amount(TextEditingController controller) {
    final canonical = normalizeAmount(
      controller.text,
      maxFractionDigits: minorUnitDigits,
      allowNegative: false,
    );
    return canonical == null ? null : parseMinorUnits(canonical);
  }

  void _apply() {
    // The range fields call out min > max themselves and report it here; the date pickers cannot
    // produce a bad pair. Nothing is applied until the form is valid.
    if (!_formKey.currentState!.validate()) return;
    final minAmount = _amount(_amountMinController);
    final maxAmount = _amount(_amountMaxController);

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
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final today = DateUtils.dateOnly(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
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
              ZenDateRangeField(
                fromLabel: t.recordsFilterDateFrom,
                toLabel: t.recordsFilterDateTo,
                from: _dateFrom,
                to: _dateTo,
                firstDate: DateTime(today.year - 10),
                lastDate: today,
                onChanged: (from, to) => setState(() {
                  _dateFrom = from;
                  _dateTo = to;
                }),
              ),
              const SizedBox(height: 16),
              // "Any type" is the empty string: the control has no null segment, and a wire value
              // is never empty.
              ZenSegmentedControl<String>(
                segments: [
                  ZenSegment(value: _anyType, label: t.recordsFilterAnyType),
                  ZenSegment(value: RecordFilterType.expense.wireValue, label: t.recordsExpense),
                  ZenSegment(value: RecordFilterType.income.wireValue, label: t.recordsIncome),
                  ZenSegment(value: RecordFilterType.transfer.wireValue, label: t.recordsTransfer),
                ],
                selected: _type?.wireValue ?? _anyType,
                onChanged: (value) => setState(
                  () => _type = RecordFilterType.values.where((type) => type.wireValue == value).firstOrNull,
                ),
              ),
              const SizedBox(height: 16),
              // "Any" is the empty id for the same reason: a select with a null value draws its
              // label over the chosen item's text.
              ZenSelect<String>(
                label: t.recordsAccountField,
                items: [_anyId, for (final account in accounts) account.id],
                itemLabel: (id) =>
                    id == _anyId ? t.recordsFilterAnyAccount : accounts.firstWhere((a) => a.id == id).name,
                value: _accountId ?? _anyId,
                onChanged: (value) => setState(() => _accountId = value == _anyId ? null : value),
              ),
              const SizedBox(height: 16),
              ZenSelect<String>(
                label: t.recordsCategoryField,
                items: [_anyId, for (final category in categories) category.id],
                itemLabel: (id) => id == _anyId
                    ? t.recordsFilterAnyCategory
                    : categories.firstWhere((c) => c.id == id).title.toUpperCase(),
                value: _categoryId ?? _anyId,
                onChanged: (value) => setState(() => _categoryId = value == _anyId ? null : value),
              ),
              const SizedBox(height: 16),
              ZenAmountRangeField(
                minLabel: t.recordsFilterAmountMinField,
                maxLabel: t.recordsFilterAmountMaxField,
                minController: _amountMinController,
                maxController: _amountMaxController,
                maxFractionDigits: minorUnitDigits,
                allowNegative: false,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ZenButton(
                    label: t.recordsFilterClearAll,
                    onPressed: _clearAll,
                    variant: ZenButtonVariant.text,
                  ),
                  const Spacer(),
                  ZenButton(
                    label: t.cancel,
                    onPressed: () => Navigator.pop(context),
                    variant: ZenButtonVariant.text,
                  ),
                  ZenButton(label: t.recordsFilterApply, onPressed: _apply),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
