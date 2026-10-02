import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import 'account_tile.dart';

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
              for (final account in cardsAccounts) AccountTile(account),
            ],
            if (otherAccounts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(t.accountsOther, style: Theme.of(context).textTheme.headlineSmall),
              ),
              for (final account in otherAccounts) AccountTile(account),
            ],
          ],
        );
      },
    );
  }
}
