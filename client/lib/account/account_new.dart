import 'package:flutter/material.dart';

import '../src/generated/prudent/v1/accounts.pb.dart';
import '../src/l10n/generated/prudent_localizations.dart';
import '../src/money.dart';

/// Opens an account with a single starting currency and balance. An account can hold several
/// currencies at once (docs/DECISIONS.md ADR-008); adding a second one is an edit, not part of
/// creation.
class AccountNew extends StatefulWidget {
  final void Function(CreateAccountRequest request) onAddAccount;

  const AccountNew({super.key, required this.onAddAccount});

  @override
  State<AccountNew> createState() => _AccountNewState();
}

class _AccountNewState extends State<AccountNew> {
  final _formKey = GlobalKey<FormState>();
  var _name = '';
  var _balanceInput = '0';
  var _currency = 'PLN';
  var _selectedType = AccountType.ACCOUNT_TYPE_CARD;
  var _isDefault = false;
  var _isActive = true;
  var _includeInTotal = true;
  var _includeInOverview = true;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final minor = parseMinorUnits(_balanceInput);
    if (minor == null) return;

    widget.onAddAccount(
      CreateAccountRequest(
        name: _name,
        type: _selectedType,
        isDefault: _isDefault,
        isActive: _isActive,
        includeInTotal: _includeInTotal,
        includeInOverview: _includeInOverview,
        balances: [CurrencyBalance(currency: _currency, amountMinor: minor)],
      ),
    );
    Navigator.pop(context);
  }

  String _typeLabel(PrudentLocalizations t, AccountType type) => switch (type) {
    AccountType.ACCOUNT_TYPE_CASH => t.accountTypeCash,
    AccountType.ACCOUNT_TYPE_CARD => t.accountTypeCard,
    AccountType.ACCOUNT_TYPE_CHECKING => t.accountTypeChecking,
    AccountType.ACCOUNT_TYPE_SAVINGS => t.accountTypeSavings,
    _ => type.name,
  };

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
        child: Column(
          children: [
            TextFormField(
              decoration: InputDecoration(labelText: t.accountNameField),
              validator: (value) => value == null || value.isEmpty ? t.accountNameRequired : null,
              onSaved: (newValue) => _name = newValue ?? '',
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _balanceInput,
                    decoration: InputDecoration(labelText: t.accountOpeningBalanceField),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) => parseMinorUnits(value ?? '') == null ? t.accountAmountInvalid : null,
                    onSaved: (newValue) => _balanceInput = newValue ?? '0',
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: _currency,
                    decoration: InputDecoration(labelText: t.accountCurrencyField),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 3,
                    onSaved: (newValue) => _currency = (newValue ?? 'PLN').toUpperCase(),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<AccountType>(
              items: [
                for (final type in AccountType.values.where((v) => v != AccountType.ACCOUNT_TYPE_UNSPECIFIED))
                  DropdownMenuItem(value: type, child: Text(_typeLabel(t, type))),
              ],
              initialValue: _selectedType,
              onChanged: (value) {
                if (value != null) setState(() => _selectedType = value);
              },
              decoration: InputDecoration(labelText: t.accountTypeField),
              validator: (value) => value == null ? t.accountTypeRequired : null,
            ),
            SwitchListTile(
              title: Text(t.accountIsDefault),
              value: _isDefault,
              onChanged: (value) => setState(() => _isDefault = value),
            ),
            SwitchListTile(
              title: Text(t.accountIsActive),
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
            SwitchListTile(
              title: Text(t.accountIncludeInTotal),
              value: _includeInTotal,
              onChanged: (value) => setState(() => _includeInTotal = value),
            ),
            SwitchListTile(
              title: Text(t.accountIncludeInOverview),
              value: _includeInOverview,
              onChanged: (value) => setState(() => _includeInOverview = value),
            ),
            const SizedBox(height: 32.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(onPressed: _submit, child: Text(t.accountAdd)),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
