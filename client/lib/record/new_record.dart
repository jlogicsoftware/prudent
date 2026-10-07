import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../category/selectable_categories.dart';
import '../generated/prudent/v1/categories.pb.dart';
import '../generated/prudent/v1/records.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';

class NewRecord extends ConsumerStatefulWidget {
  const NewRecord({super.key, required this.onSave, this.initialRecord});

  final Record? initialRecord;
  final void Function({
    required String title,
    required String amountInput,
    required String date,
    required String categoryId,
    required String accountId,
    required String currency,
    required String payee,
    required String note,
  })
  onSave;

  @override
  ConsumerState<NewRecord> createState() => _NewRecordState();
}

class _NewRecordState extends ConsumerState<NewRecord> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _payeeController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _selectedDate;
  String? _selectedCategoryId;
  String? _selectedAccountId;
  String _currency = 'PLN';
  // SIGNED (proto/prudent/v1/records.proto, ADR-014): negative is an expense, positive is
  // income. The field only ever holds a magnitude; this toggle supplies the sign.
  bool _isExpense = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecord;
    if (initial != null) {
      _titleController.text = initial.title;
      final amount = initial.amountMinor;
      _isExpense = amount.isNegative;
      _amountController.text = formatMinorUnits(amount.isNegative ? -amount : amount);
      final date = DateTime.tryParse(initial.date);
      _selectedDate = date == null ? null : DateUtils.dateOnly(date);
      _selectedCategoryId = initial.categoryId;
      _selectedAccountId = initial.accountId;
      _currency = initial.currency;
      _payeeController.text = initial.payee;
      _noteController.text = initial.note;
    }
  }

  /// An account with no balances has no currency to offer, so the current one stands.
  void _adoptCurrencyOf(Account account) {
    if (account.balances.isNotEmpty) _currency = account.balances.first.currency;
  }

  void _invalid(String message) {
    final t = PrudentLocalizations.of(context);
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(t.invalidInputTitle),
            content: Text(message),
            actions: [
              ZenButton(
                label: t.okay,
                variant: ZenButtonVariant.text,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
    );
  }

  void _submit() {
    // The field refuses a sign (allowNegative: false) and so only ever holds a magnitude; the
    // toggle is the sole source of the sign that goes on the wire.
    final canonical = normalizeAmount(
      _amountController.text,
      maxFractionDigits: minorUnitDigits,
      allowNegative: false,
    );
    final magnitude = canonical == null ? null : parseMinorUnits(canonical);
    if (_titleController.text.trim().isEmpty ||
        magnitude == null ||
        magnitude <= 0 ||
        _selectedDate == null ||
        _selectedCategoryId == null ||
        _selectedAccountId == null) {
      _invalid(PrudentLocalizations.of(context).recordsInvalidInput);
      return;
    }

    final signed = _isExpense ? -magnitude : magnitude;
    widget.onSave(
      title: _titleController.text.trim(),
      amountInput: formatMinorUnits(signed),
      date: DateFormat('yyyy-MM-dd').format(_selectedDate!),
      categoryId: _selectedCategoryId!,
      accountId: _selectedAccountId!,
      currency: _currency,
      payee: _payeeController.text.trim(),
      note: _noteController.text.trim(),
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _payeeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final categories = selectableCategories(
      ref.watch(categoriesProvider).value ?? const <Category>[],
      keep: widget.initialRecord?.categoryId,
    );
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    _selectedCategoryId ??= categories.isNotEmpty ? categories.first.id : null;
    if (_selectedAccountId == null && accounts.isNotEmpty) {
      // The currency is the account's, so preselecting an account takes its currency with it.
      _selectedAccountId = accounts.first.id;
      _adoptCurrencyOf(accounts.first);
    }
    final today = DateUtils.dateOnly(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: SingleChildScrollView(
        child: Column(
        children: [
          ZenTextField(
            label: t.recordsTitleField,
            controller: _titleController,
            maxLength: 50,
          ),
          const SizedBox(height: 8),
          ZenSegmentedControl<bool>(
            segments: [
              ZenSegment(value: true, label: t.recordsExpense),
              ZenSegment(value: false, label: t.recordsIncome),
            ],
            selected: _isExpense,
            onChanged: (value) => setState(() => _isExpense = value),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ZenAmountField(
                  label: t.recordsAmountField,
                  controller: _amountController,
                  maxFractionDigits: minorUnitDigits,
                  allowNegative: false,
                ),
              ),
              const SizedBox(width: 12),
              // The currency follows the chosen account; it is shown, not chosen, here.
              Padding(padding: const EdgeInsets.only(top: 16), child: Text(_currency)),
            ],
          ),
          const SizedBox(height: 16),
          ZenDateField(
            label: t.recordsDateField,
            value: _selectedDate,
            firstDate: DateTime(today.year - 1, today.month, today.day),
            lastDate: today,
            onChanged: (picked) {
              if (picked != null) setState(() => _selectedDate = picked);
            },
          ),
          const SizedBox(height: 16),
          if (accounts.isNotEmpty)
            ZenSelect<String>(
              label: t.recordsAccountField,
              items: [for (final account in accounts) account.id],
              itemLabel: (id) => accounts.firstWhere((a) => a.id == id).name,
              value: _selectedAccountId,
              onChanged: (value) {
                setState(() {
                  _selectedAccountId = value;
                  _adoptCurrencyOf(accounts.firstWhere((a) => a.id == value));
                });
              },
            ),
          const SizedBox(height: 16),
          if (categories.isNotEmpty)
            ZenSelect<String>(
              label: t.recordsCategoryField,
              items: [for (final category in categories) category.id],
              itemLabel: (id) => categories.firstWhere((c) => c.id == id).title.toUpperCase(),
              value: _selectedCategoryId,
              onChanged: (value) => setState(() => _selectedCategoryId = value),
            ),
          const SizedBox(height: 8),
          ZenTextField(
            label: t.recordsPayeeField,
            controller: _payeeController,
            maxLength: 100,
          ),
          const SizedBox(height: 8),
          ZenTextField(
            label: t.recordsNoteField,
            controller: _noteController,
            maxLength: 280,
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              ZenButton(
                label: t.cancel,
                onPressed: () => Navigator.pop(context),
                variant: ZenButtonVariant.text,
              ),
              ZenButton(
                label: _isExpense ? t.recordsSaveExpense : t.recordsSaveIncome,
                onPressed: _submit,
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}
