import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

import '../src/generated/prudent/v1/accounts.pb.dart';
import '../src/l10n/generated/prudent_localizations.dart';
import '../src/money.dart';
import '../src/providers.dart';
import 'account_edit.dart';

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

class _AccountTile extends ConsumerWidget {
  const _AccountTile(this.account);

  final Account account;

  void _openEdit(BuildContext context, WidgetRef ref) {
    final body = AccountEdit(
      account: account,
      onSave: (request) => ref.read(accountsProvider.notifier).editAccount(account.id, request),
    );
    if (zenIsDesktop) {
      showDialog(
        context: context,
        builder:
            (ctx) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              child: SizedBox(width: 400, height: 460, child: body),
            ),
      );
    } else {
      showModalBottomSheet(
        isScrollControlled: true,
        useSafeArea: true,
        context: context,
        builder: (ctx) => body,
        constraints: const BoxConstraints.expand(),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final t = PrudentLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(t.accountDeleteTitle),
            content: Text(t.accountDeleteConfirm(account.name)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.accountDelete)),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(accountsProvider.notifier).removeAccount(account.id);
    } on ZenError catch (error) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(t.accountDeleteTitle),
              // A conflict (records still reference this account) is refused at 409 with a
              // message the resource wrote (AccountResource.delete); every ZenError arriving
              // here carries the server's message the same way, decoded transport-side by
              // ZenTransportError, so there is one path rather than a type check per error kind.
              content: Text(error.message.isEmpty ? t.accountDeleteBlockedGeneric : error.message),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.okay))],
            ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final balances = account.balances
        .map((b) => '${formatMinorUnits(b.amountMinor)} ${b.currency}')
        .join(', ');
    return ListTile(
      onTap: () => _openEdit(context, ref),
      leading: Icon(
        account.type == AccountType.ACCOUNT_TYPE_CARD || account.type == AccountType.ACCOUNT_TYPE_CASH
            ? Icons.account_balance
            : Icons.account_balance_wallet,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(account.name),
      subtitle: Text(balances.isEmpty ? t.accountsNoBalance : balances),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(context, ref),
      ),
    );
  }
}
