import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../upper_case_formatter.dart';

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
  final _nameController = TextEditingController();
  final _balance = TextEditingController(text: '0');
  var _balanceInvalid = false;
  final _currencyController = TextEditingController(text: 'PLN');
  var _selectedType = AccountType.ACCOUNT_TYPE_CARD;
  var _isDefault = false;
  var _isActive = true;
  var _includeInTotal = true;
  var _includeInOverview = true;
  var _eligibleForGoals = false;

  @override
  void dispose() {
    _nameController.dispose();
    _currencyController.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _submit() {
    final formValid = _formKey.currentState!.validate();
    // The field's canonical text is read through normalizeAmount; what it means in minor units is
    // money.dart's. An empty or malformed amount is refused here, not left to parse as zero.
    final canonical = normalizeAmount(_balance.text, maxFractionDigits: minorUnitDigits);
    final minor = canonical == null ? null : parseMinorUnits(canonical);
    setState(() => _balanceInvalid = minor == null);
    if (!formValid || minor == null) return;
    widget.onAddAccount(
      CreateAccountRequest(
        name: _nameController.text,
        type: _selectedType,
        isDefault: _isDefault,
        isActive: _isActive,
        includeInTotal: _includeInTotal,
        includeInOverview: _includeInOverview,
        eligibleForGoals: _eligibleForGoals,
        balances: [CurrencyBalance(currency: _currencyController.text.toUpperCase(), amountMinor: minor)],
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
            ZenTextField(
              label: t.accountNameField,
              controller: _nameController,
              validator: (value) => value == null || value.isEmpty ? t.accountNameRequired : null,
            ),
            Row(
              children: [
                Expanded(
                  child: ZenAmountField(
                    label: t.accountOpeningBalanceField,
                    controller: _balance,
                    maxFractionDigits: minorUnitDigits,
                    errorText: _balanceInvalid ? t.accountAmountInvalid : null,
                    onChanged: (_) {
                      if (_balanceInvalid) setState(() => _balanceInvalid = false);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 80,
                  child: ZenTextField(
                    label: t.accountCurrencyField,
                    controller: _currencyController,
                    inputFormatters: [const UpperCaseTextFormatter(), LengthLimitingTextInputFormatter(3)],
                  ),
                ),
              ],
            ),
            // Room for the balance field's error line and the select's floating label.
            const SizedBox(height: 16),
            ZenSelect<AccountType>(
              label: t.accountTypeField,
              items: [
                for (final type in AccountType.values.where(
                  (v) => v != AccountType.ACCOUNT_TYPE_UNSPECIFIED,
                ))
                  type,
              ],
              itemLabel: (type) => _typeLabel(t, type),
              value: _selectedType,
              onChanged: (value) => setState(() => _selectedType = value),
            ),
            ZenSwitchRow(
              label: t.accountIsDefault,
              value: _isDefault,
              onChanged: (value) => setState(() => _isDefault = value),
            ),
            ZenSwitchRow(
              label: t.accountIsActive,
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
            ZenSwitchRow(
              label: t.accountIncludeInTotal,
              value: _includeInTotal,
              onChanged: (value) => setState(() => _includeInTotal = value),
            ),
            ZenSwitchRow(
              label: t.accountIncludeInOverview,
              value: _includeInOverview,
              onChanged: (value) => setState(() => _includeInOverview = value),
            ),
            ZenSwitchRow(
              label: t.accountEligibleForGoals,
              subtitle: t.accountEligibleForGoalsHint,
              value: _eligibleForGoals,
              onChanged: (value) => setState(() => _eligibleForGoals = value),
            ),
            const SizedBox(height: 32.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ZenButton(label: t.accountAdd, onPressed: _submit),
                ZenButton(
                  label: t.cancel,
                  onPressed: () => Navigator.pop(context),
                  variant: ZenButtonVariant.text,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
