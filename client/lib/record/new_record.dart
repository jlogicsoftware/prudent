import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../src/generated/prudent/v1/accounts.pb.dart';
import '../src/generated/prudent/v1/categories.pb.dart';
import '../src/generated/prudent/v1/records.pb.dart';
import '../src/l10n/generated/prudent_localizations.dart';
import '../src/money.dart';
import '../src/providers.dart';

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
  })
  onSave;

  @override
  ConsumerState<NewRecord> createState() => _NewRecordState();
}

class _NewRecordState extends ConsumerState<NewRecord> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
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
      _selectedDate = DateTime.tryParse(initial.date);
      _selectedCategoryId = initial.categoryId;
      _selectedAccountId = initial.accountId;
      _currency = initial.currency;
    }
  }

  void _presentDatePicker() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1, now.month, now.day);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: firstDate,
      lastDate: now,
    );
    if (pickedDate != null) setState(() => _selectedDate = pickedDate);
  }

  void _invalid(String message) {
    final t = PrudentLocalizations.of(context);
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(t.invalidInputTitle),
            content: Text(message),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.okay))],
          ),
    );
  }

  void _submit() {
    final raw = _amountController.text.trim();
    // The field only ever holds a magnitude, regardless of what the user typed; the toggle is the
    // sole source of the sign that goes on the wire.
    final magnitude = parseMinorUnits(raw.startsWith('-') ? raw.substring(1) : raw);
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
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    _selectedCategoryId ??= categories.isNotEmpty ? categories.first.id : null;
    _selectedAccountId ??= accounts.isNotEmpty ? accounts.first.id : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(
        children: [
          TextField(
            controller: _titleController,
            maxLength: 50,
            decoration: InputDecoration(label: Text(t.recordsTitleField)),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(t.recordsExpense)),
              ButtonSegment(value: false, label: Text(t.recordsIncome)),
            ],
            selected: {_isExpense},
            onSelectionChanged: (selection) => setState(() => _isExpense = selection.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(suffix: Text(_currency), label: Text(t.recordsAmountField)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _selectedDate == null
                          ? t.recordsNoDateSelected
                          : DateFormat.yMd(locale.toLanguageTag()).format(_selectedDate!),
                    ),
                    IconButton(onPressed: _presentDatePicker, icon: const Icon(Icons.calendar_month)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (accounts.isNotEmpty)
            DropdownButton<String>(
              value: _selectedAccountId,
              items: [
                for (final account in accounts) DropdownMenuItem(value: account.id, child: Text(account.name)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedAccountId = value;
                  final account = accounts.firstWhere((a) => a.id == value);
                  if (account.balances.isNotEmpty) _currency = account.balances.first.currency;
                });
              },
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (categories.isNotEmpty)
                DropdownButton<String>(
                  value: _selectedCategoryId,
                  items: [
                    for (final category in categories)
                      DropdownMenuItem(value: category.id, child: Text(category.title.toUpperCase())),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedCategoryId = value);
                  },
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
              ElevatedButton(
                onPressed: _submit,
                child: Text(_isExpense ? t.recordsSaveExpense : t.recordsSaveIncome),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
