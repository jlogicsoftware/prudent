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
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  late AccountType _selectedType;
  String _currency = 'USD';

  @override
  void initState() {
    super.initState();
    if (widget.initialAccount != null) {
      _nameController.text = widget.initialAccount!.name;
      _balanceController.text = widget.initialAccount!.balance.toString();
      _selectedType = widget.initialAccount!.type;
      _currency = widget.initialAccount!.currency;
    } else {
      _selectedType = AccountType.card; // Default type
    }
  }

  void _submitAccountData() {
    if (_nameController.text.trim().isEmpty ||
        _balanceController.text.trim().isEmpty) {
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Invalid input'),
              content: const Text('Please fill in all fields.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Okay'),
                ),
              ],
            ),
      );
      return;
    }

    final account = Account(
      name: _nameController.text,
      type: _selectedType,
      balance: double.parse(_balanceController.text),
      currency: _currency,
    );

    widget.onAddAccount(account);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Account Name'),
        ),
        TextField(
          controller: _balanceController,
          decoration: const InputDecoration(labelText: 'Balance'),
          keyboardType: TextInputType.number,
        ),
        DropdownButton<AccountType>(
          value: _selectedType,
          items:
              AccountType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.toString().split('.').last),
                );
              }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedType = value;
              });
            }
          },
        ),
        ElevatedButton(
          onPressed: _submitAccountData,
          child: const Text('Add Account'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
