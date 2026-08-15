import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent/account/account_list.dart';
import 'package:prudent/account/account_new.dart';
import 'package:prudent/account/account_provider.dart';
import 'package:prudent/widgets/popup/popup.dart';

import 'account.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  static const routeName = '/account';

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late final List<Account> accounts = ref.watch(accountProvider);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          Popup(
            popupLeading: const Icon(Icons.add),
            popupBody: AccountNew(
              onAddAccount:
                  (account) =>
                      ref.read(accountProvider.notifier).addAccount(account),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child:
                accounts.isEmpty
                    ? const Center(child: Text('No accounts added yet.'))
                    : AccountList(),
          ),
        ],
      ),
    );
  }
}
