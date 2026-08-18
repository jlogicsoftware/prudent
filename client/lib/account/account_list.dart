import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/generated/prudent/v1/accounts.pb.dart';
import '../src/l10n/generated/prudent_localizations.dart';
import '../src/money.dart';
import '../src/providers.dart';

class AccountList extends ConsumerWidget {
  const AccountList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final t = PrudentLocalizations.of(context);

    return accountsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(t.accountsLoadError(error.toString()))),
      data: (accounts) {
        if (accounts.isEmpty) {
          return Center(child: Text(t.accountsEmpty));
        }

        final cardsAccounts =
            accounts
                .where((a) => a.type == AccountType.ACCOUNT_TYPE_CARD || a.type == AccountType.ACCOUNT_TYPE_CASH)
                .toList();
        final otherAccounts =
            accounts
                .where((a) => a.type != AccountType.ACCOUNT_TYPE_CARD && a.type != AccountType.ACCOUNT_TYPE_CASH)
                .toList();

        return ListView(
          children: [
            if (cardsAccounts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(t.accountsBanksAndCards, style: Theme.of(context).textTheme.headlineSmall),
              ),
              for (final account in cardsAccounts) _AccountTile(account),
            ],
            if (otherAccounts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(t.accountsOther, style: Theme.of(context).textTheme.headlineSmall),
              ),
              for (final account in otherAccounts) _AccountTile(account),
            ],
          ],
        );
      },
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile(this.account);

  final Account account;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final balances = account.balances
        .map((b) => '${formatMinorUnits(b.amountMinor)} ${b.currency}')
        .join(', ');
    return ListTile(
      leading: Icon(
        account.type == AccountType.ACCOUNT_TYPE_CARD || account.type == AccountType.ACCOUNT_TYPE_CASH
            ? Icons.account_balance
            : Icons.account_balance_wallet,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(account.name),
      subtitle: Text(balances.isEmpty ? t.accountsNoBalance : balances),
    );
  }
}
