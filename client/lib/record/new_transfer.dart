import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';

/// A transfer between two of the user's own accounts, cross-currency included
/// (jlogicsoftware/prudent#32, jlogicsoftware/prudent#50). Each side carries its own amount and
/// currency, entered independently — a same-currency transfer is simply the case where the user
/// happens to enter the same currency on both sides. No exchange rate is ever computed here or on
/// the server: what the user types for each leg is exactly what is persisted.
class NewTransfer extends ConsumerStatefulWidget {
  const NewTransfer({super.key, required this.onSave});

  final void Function({
    required String title,
    required String fromAmountInput,
    required String fromCurrency,
    required String toAmountInput,
    required String toCurrency,
    required String date,
    required String fromAccountId,
    required String toAccountId,
  })
  onSave;

  @override
  ConsumerState<NewTransfer> createState() => _NewTransferState();
}

class _NewTransferState extends ConsumerState<NewTransfer> {
  final _titleController = TextEditingController();
  final _fromAmountController = TextEditingController();
  final _toAmountController = TextEditingController();
  DateTime? _selectedDate;
  String? _fromAccountId;
  String? _toAccountId;
  String? _fromCurrency;
  String? _toCurrency;

  static Account? _findAccount(List<Account> accounts, String? id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  static List<String> _currenciesOf(Account? account) {
    if (account == null) return const [];
    final currencies = account.balances.map((b) => b.currency).toSet().toList()..sort();
    return currencies;
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
    final t = PrudentLocalizations.of(context);
    final fromMagnitude = parseMinorUnits(_fromAmountController.text.trim());
    final toMagnitude = parseMinorUnits(_toAmountController.text.trim());
    if (fromMagnitude == null ||
        fromMagnitude <= 0 ||
        toMagnitude == null ||
        toMagnitude <= 0 ||
        _selectedDate == null ||
        _fromAccountId == null ||
        _toAccountId == null ||
        _fromAccountId == _toAccountId ||
        _fromCurrency == null ||
        _toCurrency == null) {
      _invalid(t.transfersInvalidInput);
      return;
    }

    widget.onSave(
      title: _titleController.text.trim(),
      fromAmountInput: formatMinorUnits(fromMagnitude),
      fromCurrency: _fromCurrency!,
      toAmountInput: formatMinorUnits(toMagnitude),
      toCurrency: _toCurrency!,
      date: DateFormat('yyyy-MM-dd').format(_selectedDate!),
      fromAccountId: _fromAccountId!,
      toAccountId: _toAccountId!,
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _fromAmountController.dispose();
    _toAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    _fromAccountId ??= accounts.isNotEmpty ? accounts.first.id : null;
    _toAccountId ??= accounts.length > 1 ? accounts[1].id : null;

    final fromAccount = _findAccount(accounts, _fromAccountId);
    final toAccount = _findAccount(accounts, _toAccountId);
    final fromCurrencies = _currenciesOf(fromAccount);
    final toCurrencies = _currenciesOf(toAccount);
    if (_fromCurrency == null || !fromCurrencies.contains(_fromCurrency)) {
      _fromCurrency = fromCurrencies.isNotEmpty ? fromCurrencies.first : null;
    }
    if (_toCurrency == null || !toCurrencies.contains(_toCurrency)) {
      _toCurrency = toCurrencies.isNotEmpty ? toCurrencies.first : null;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(
        children: [
          Text(t.transfersNewTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            maxLength: 50,
            decoration: InputDecoration(label: Text(t.transfersTitleField)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedDate == null
                      ? t.recordsNoDateSelected
                      : DateFormat.yMd(locale.toLanguageTag()).format(_selectedDate!),
                ),
              ),
              IconButton(onPressed: _presentDatePicker, icon: const Icon(Icons.calendar_month)),
            ],
          ),
          const SizedBox(height: 16),
          if (accounts.isNotEmpty) ...[
            DropdownButton<String>(
              value: _fromAccountId,
              hint: Text(t.transfersFromAccount),
              items: [
                for (final account in accounts) DropdownMenuItem(value: account.id, child: Text(account.name)),
              ],
              onChanged: (value) => setState(() => _fromAccountId = value),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fromAmountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(label: Text(t.transfersFromAmountField)),
                  ),
                ),
                const SizedBox(width: 16),
                if (fromCurrencies.length > 1)
                  DropdownButton<String>(
                    value: _fromCurrency,
                    items: [
                      for (final currency in fromCurrencies)
                        DropdownMenuItem(value: currency, child: Text(currency)),
                    ],
                    onChanged: (value) => setState(() => _fromCurrency = value),
                  )
                else
                  Text(_fromCurrency ?? ''),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButton<String>(
              value: _toAccountId,
              hint: Text(t.transfersToAccount),
              items: [
                for (final account in accounts)
                  if (account.id != _fromAccountId)
                    DropdownMenuItem(value: account.id, child: Text(account.name)),
              ],
              onChanged: (value) => setState(() => _toAccountId = value),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _toAmountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(label: Text(t.transfersToAmountField)),
                  ),
                ),
                const SizedBox(width: 16),
                if (toCurrencies.length > 1)
                  DropdownButton<String>(
                    value: _toCurrency,
                    items: [
                      for (final currency in toCurrencies)
                        DropdownMenuItem(value: currency, child: Text(currency)),
                    ],
                    onChanged: (value) => setState(() => _toCurrency = value),
                  )
                else
                  Text(_toCurrency ?? ''),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
              ElevatedButton(onPressed: _submit, child: Text(t.transfersSave)),
            ],
          ),
        ],
      ),
    );
  }
}
