import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';

/// A same-currency transfer between two of the user's own accounts (jlogicsoftware/prudent#32).
/// Cross-currency transfers (two user-entered amounts, no FX) are a separate, later issue.
class NewTransfer extends ConsumerStatefulWidget {
  const NewTransfer({super.key, required this.onSave});

  final void Function({
    required String title,
    required String amountInput,
    required String date,
    required String fromAccountId,
    required String toAccountId,
    required String currency,
  })
  onSave;

  @override
  ConsumerState<NewTransfer> createState() => _NewTransferState();
}

class _NewTransferState extends ConsumerState<NewTransfer> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime? _selectedDate;
  String? _fromAccountId;
  String? _toAccountId;
  String? _currency;

  /// The currencies [from] and [to] both hold — the only currencies a same-currency transfer
  /// between them can move. Empty when the pair shares none.
  List<String> _sharedCurrencies(Account? from, Account? to) {
    if (from == null || to == null) return const [];
    final fromCurrencies = from.balances.map((b) => b.currency).toSet();
    final toCurrencies = to.balances.map((b) => b.currency).toSet();
    final shared = fromCurrencies.intersection(toCurrencies).toList()..sort();
    return shared;
  }

  static Account? _findAccount(List<Account> accounts, String? id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
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

  void _submit(List<String> sharedCurrencies) {
    final t = PrudentLocalizations.of(context);
    final magnitude = parseMinorUnits(_amountController.text.trim());
    if (magnitude == null ||
        magnitude <= 0 ||
        _selectedDate == null ||
        _fromAccountId == null ||
        _toAccountId == null ||
        _fromAccountId == _toAccountId) {
      _invalid(t.transfersInvalidInput);
      return;
    }
    if (sharedCurrencies.isEmpty) {
      _invalid(t.transfersNoSharedCurrency);
      return;
    }
    final currency = _currency ?? sharedCurrencies.first;

    widget.onSave(
      title: _titleController.text.trim(),
      amountInput: formatMinorUnits(magnitude),
      date: DateFormat('yyyy-MM-dd').format(_selectedDate!),
      fromAccountId: _fromAccountId!,
      toAccountId: _toAccountId!,
      currency: currency,
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
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    _fromAccountId ??= accounts.isNotEmpty ? accounts.first.id : null;
    _toAccountId ??= accounts.length > 1 ? accounts[1].id : null;

    final fromAccount = _findAccount(accounts, _fromAccountId);
    final toAccount = _findAccount(accounts, _toAccountId);
    final sharedCurrencies = _sharedCurrencies(fromAccount, toAccount);
    if (_currency == null || !sharedCurrencies.contains(_currency)) {
      _currency = sharedCurrencies.isNotEmpty ? sharedCurrencies.first : null;
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
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    suffix: Text(_currency ?? ''),
                    label: Text(t.transfersAmountField),
                  ),
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
          ],
          if (sharedCurrencies.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: _currency,
              items: [
                for (final currency in sharedCurrencies) DropdownMenuItem(value: currency, child: Text(currency)),
              ],
              onChanged: (value) => setState(() => _currency = value),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
              ElevatedButton(
                onPressed: () => _submit(sharedCurrencies),
                child: Text(t.transfersSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
