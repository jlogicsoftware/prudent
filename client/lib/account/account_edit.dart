import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';

/// Edits an account's name, type and the three flags nothing could previously set
/// (docs/prudent-migration-plan.md Phase 4). `balances` travels through UNCHANGED: a `PUT` is a
/// full replacement (accounts.proto), so this form must resend the currencies it did not touch or
/// the server would read their omission as a request to drop them — and dropping a currency with
/// records is refused at 409 (docs/DECISIONS.md ADR-008), which is not a mistake this form should
/// be able to make silently.
class AccountEdit extends StatefulWidget {
  const AccountEdit({super.key, required this.account, required this.onSave});

  final Account account;
  final void Function(UpdateAccountRequest request) onSave;

  @override
  State<AccountEdit> createState() => _AccountEditState();
}

class _AccountEditState extends State<AccountEdit> {
  late final _nameController = TextEditingController(text: widget.account.name);
  late AccountType _type = widget.account.type;
  late bool _isDefault = widget.account.isDefault;
  late bool _isActive = widget.account.isActive;
  late bool _includeInTotal = widget.account.includeInTotal;
  late bool _includeInOverview = widget.account.includeInOverview;
  late bool _eligibleForGoals = widget.account.eligibleForGoals;

  String _typeLabel(PrudentLocalizations t, AccountType type) => switch (type) {
    AccountType.ACCOUNT_TYPE_CASH => t.accountTypeCash,
    AccountType.ACCOUNT_TYPE_CARD => t.accountTypeCard,
    AccountType.ACCOUNT_TYPE_CHECKING => t.accountTypeChecking,
    AccountType.ACCOUNT_TYPE_SAVINGS => t.accountTypeSavings,
    _ => type.name,
  };

  void _submit() {
    if (_nameController.text.trim().isEmpty) return;
    widget.onSave(
      UpdateAccountRequest(
        name: _nameController.text.trim(),
        type: _type,
        isDefault: _isDefault,
        isActive: _isActive,
        includeInTotal: _includeInTotal,
        includeInOverview: _includeInOverview,
        eligibleForGoals: _eligibleForGoals,
        balances: widget.account.balances,
      ),
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(
        children: [
          ZenTextField(label: t.accountNameField, controller: _nameController),
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
            value: _type,
            onChanged: (value) => setState(() => _type = value),
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
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ZenButton(label: t.accountSave, onPressed: _submit),
              ZenButton(
                label: t.cancel,
                onPressed: () => Navigator.pop(context),
                variant: ZenButtonVariant.text,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
