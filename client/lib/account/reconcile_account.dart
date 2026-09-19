import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';

/// Records an explicit, auditable balance correction against one currency of [account] (M1,
/// jlogicsoftware/prudent#53) — the reconciliation flow the acceptance criterion asks for, instead
/// of silently rewriting the account's opening balance.
///
/// The field the user fills in is the account's TRUE balance as they observe it (e.g. reading a
/// bank statement), never a delta: the server computes the difference against the current derived
/// balance and stores exactly that difference as its own auditable record.
class ReconcileAccount extends StatefulWidget {
  const ReconcileAccount({super.key, required this.account, required this.onSave});

  final Account account;

  final void Function({
    required String currency,
    required String trueBalanceInput,
    required String date,
    required String note,
  })
  onSave;

  @override
  State<ReconcileAccount> createState() => _ReconcileAccountState();
}

class _ReconcileAccountState extends State<ReconcileAccount> {
  final _balanceController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String? _currency;

  List<String> get _currencies =>
      widget.account.balances.map((b) => b.currency).toSet().toList()..sort();

  CurrencyBalance? _selectedBalance() {
    for (final balance in widget.account.balances) {
      if (balance.currency == _currency) return balance;
    }
    return null;
  }

  void _presentDatePicker() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1, now.month, now.day);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
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
    final magnitude = parseMinorUnits(_balanceController.text.trim());
    if (magnitude == null || _currency == null) {
      _invalid(t.correctionsInvalidInput);
      return;
    }

    widget.onSave(
      currency: _currency!,
      trueBalanceInput: formatMinorUnits(magnitude),
      date: DateFormat('yyyy-MM-dd').format(_selectedDate),
      note: _noteController.text.trim(),
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _balanceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    _currency ??= _currencies.isNotEmpty ? _currencies.first : null;
    final currentBalance = _selectedBalance();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.correctionsTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(t.correctionsExplanation, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (_currencies.length > 1)
            DropdownButtonFormField<String>(
              initialValue: _currency,
              items: [
                for (final currency in _currencies)
                  DropdownMenuItem(value: currency, child: Text(currency)),
              ],
              onChanged: (value) => setState(() => _currency = value),
              decoration: InputDecoration(labelText: t.correctionsCurrencyField),
            ),
          if (currentBalance != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                t.correctionsCurrentBalance(
                  formatMinorUnits(currentBalance.amountMinor),
                  currentBalance.currency,
                ),
              ),
            ),
          TextField(
            controller: _balanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(label: Text(t.correctionsTrueBalanceField)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(DateFormat.yMd().format(_selectedDate))),
              IconButton(onPressed: _presentDatePicker, icon: const Icon(Icons.calendar_month)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            maxLength: 200,
            decoration: InputDecoration(label: Text(t.correctionsNoteField)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
              ElevatedButton(onPressed: _submit, child: Text(t.correctionsSave)),
            ],
          ),
        ],
      ),
    );
  }
}
