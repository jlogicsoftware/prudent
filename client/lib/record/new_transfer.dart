import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';
import 'transfer_leg.dart';

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

  /// What a leg's field holds in minor units, or null if it is empty or not an amount. Both legs
  /// are magnitudes: a transfer's direction is its from/to accounts, never a sign.
  static Int64? _magnitude(TextEditingController controller) {
    final canonical = normalizeAmount(
      controller.text,
      maxFractionDigits: minorUnitDigits,
      allowNegative: false,
    );
    return canonical == null ? null : parseMinorUnits(canonical);
  }

  void _submit() {
    final t = PrudentLocalizations.of(context);
    final fromMagnitude = _magnitude(_fromAmountController);
    final toMagnitude = _magnitude(_toAmountController);
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
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final today = DateUtils.dateOnly(DateTime.now());
    _fromAccountId ??= accounts.isNotEmpty ? accounts.first.id : null;
    _toAccountId ??= accounts.length > 1 ? accounts[1].id : null;

    final fromAccount = _findAccount(accounts, _fromAccountId);
    // The to list leaves the from account out, so a to account that has become the from account is
    // unchosen: a select whose value is not an item fails to build, and the to leg must not keep
    // offering that hidden account's currencies. Submitting it is refused.
    final toAccountId = _toAccountId == _fromAccountId ? null : _toAccountId;
    final toAccount = _findAccount(accounts, toAccountId);
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
      child: SingleChildScrollView(
        child: Column(
          children: [
            Text(t.transfersNewTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ZenTextField(
              label: t.transfersTitleField,
              controller: _titleController,
              inputFormatters: [LengthLimitingTextInputFormatter(50)],
            ),
            const SizedBox(height: 8),
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
            if (accounts.isNotEmpty) ...[
              ZenSelect<String>(
                label: t.transfersFromAccount,
                items: [for (final account in accounts) account.id],
                itemLabel: (id) => _findAccount(accounts, id)!.name,
                value: _fromAccountId,
                onChanged: (value) => setState(() => _fromAccountId = value),
              ),
              const SizedBox(height: 16),
              TransferLeg(
                amountLabel: t.transfersFromAmountField,
                amountController: _fromAmountController,
                currencyLabel: t.transfersFromCurrency,
                currencies: fromCurrencies,
                currency: _fromCurrency,
                onCurrencyChanged: (value) => setState(() => _fromCurrency = value),
              ),
              const SizedBox(height: 16),
              ZenSelect<String>(
                label: t.transfersToAccount,
                items: [
                  for (final account in accounts)
                    if (account.id != _fromAccountId) account.id,
                ],
                itemLabel: (id) => _findAccount(accounts, id)!.name,
                value: toAccountId,
                onChanged: (value) => setState(() => _toAccountId = value),
              ),
              const SizedBox(height: 16),
              TransferLeg(
                amountLabel: t.transfersToAmountField,
                amountController: _toAmountController,
                currencyLabel: t.transfersToCurrency,
                currencies: toCurrencies,
                currency: _toCurrency,
                onCurrencyChanged: (value) => setState(() => _toCurrency = value),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                ZenButton(
                  label: t.cancel,
                  onPressed: () => Navigator.pop(context),
                  variant: ZenButtonVariant.text,
                ),
                ZenButton(label: t.transfersSave, onPressed: _submit),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
