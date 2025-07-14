import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent/account/account.dart';

import 'account_provider.dart';

class AccountList extends ConsumerWidget {
  const AccountList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountProvider);

    final cardsAccounts =
        accounts
            .where(
              (account) =>
                  account.type == AccountType.card ||
                  account.type == AccountType.cash,
            )
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Banks and Cards',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        // List of accounts
        Expanded(
          child: ListView.builder(
            itemCount: cardsAccounts.length,
            itemBuilder: (context, index) {
              final account = cardsAccounts[index];
              return ListTile(
                leading: Icon(Icons.account_balance),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                title: Text(account.name),
                subtitle: Text(
                  'Balance: \$${account.balance.toStringAsFixed(2)}',
                ),
                onTap: () {
                  // Handle account tap
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Other Accounts',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        // List of other accounts
        Expanded(
          child: ListView.builder(
            itemCount: accounts.length - cardsAccounts.length,
            itemBuilder: (context, index) {
              final account =
                  accounts
                      .where(
                        (account) =>
                            account.type != AccountType.card &&
                            account.type != AccountType.cash,
                      )
                      .toList()[index];
              return ListTile(
                leading: Icon(Icons.account_balance_wallet),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                title: Text(account.name),
                subtitle: Text(
                  'Balance: \$${account.balance.toStringAsFixed(2)}',
                ),
                onTap: () {
                  // Handle account tap
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
