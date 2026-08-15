import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account.dart';

class AccountNew extends ConsumerStatefulWidget {
  final Account? initialAccount;
  final void Function(Account) onAddAccount;

  const AccountNew({
    super.key,
    required this.onAddAccount,
    this.initialAccount,
  });

  @override
  ConsumerState<AccountNew> createState() => _AccountNewState();
}

class _AccountNewState extends ConsumerState<AccountNew> {
  final _formKey = GlobalKey<FormState>();
  var _name = '';
  var _balance = 0.0;
  late AccountType _selectedType;
  String _currency = 'USD';

  @override
  void initState() {
    super.initState();
    if (widget.initialAccount != null) {
      _selectedType = widget.initialAccount!.type;
      _currency = widget.initialAccount!.currency;
    } else {
      _selectedType = AccountType.card; // Default type
    }
  }

  void _submitAccountData() {
    if (!_formKey.currentState!.validate()) {
      return; // If the form is not valid, exit
    }

    _formKey.currentState!.save(); // Save the form data
    final account = Account(
      name: _name,
      type: _selectedType,
      balance: _balance,
      currency: _currency,
    );

    widget.onAddAccount(account);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
        child: Column(
          children: [
            TextFormField(
              decoration: const InputDecoration(labelText: 'Account Name'),
              validator:
                  (value) => value!.isEmpty ? 'Please enter a name' : null,
              onSaved: (newValue) => _name = newValue ?? '',
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Balance'),
              // initialValue: '0.00',
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onSaved:
                  (newValue) =>
                      _balance =
                          double.tryParse(
                            newValue?.replaceAll(',', '.') ?? '',
                          ) ??
                          0.0,
            ),
            DropdownButtonFormField<AccountType>(
              items:
              [
                for (var type in AccountType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(type.toString().split('.').last),
                  ),
              ],
              initialValue: _selectedType,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedType = value;
                  });
                }
              },
              decoration: const InputDecoration(labelText: 'Account Type'),
              validator:
                  (value) => value == null ? 'Please select a type' : null,
            ),
            const SizedBox(height: 32.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: _submitAccountData,
                  child: const Text('Add Account'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
