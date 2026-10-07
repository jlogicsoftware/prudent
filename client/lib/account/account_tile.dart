import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../generated/prudent/v1/records.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';
import 'account_edit.dart';
import 'reconcile_account.dart';

/// One account in the accounts list: its balances per currency, and the edit, reconcile and delete
/// actions on it.
class AccountTile extends ConsumerWidget {
  const AccountTile(this.account, {super.key});

  final Account account;

  void _openEdit(BuildContext context, WidgetRef ref) {
    final body = AccountEdit(
      account: account,
      onSave: (request) => ref.read(accountsProvider.notifier).editAccount(account.id, request),
    );
    showAdaptivePresentation<void>(context, builder: (_) => body);
  }

  void _openReconcile(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final body = ReconcileAccount(
      account: account,
      onSave: ({
        required currency,
        required trueBalanceInput,
        required date,
        required note,
      }) async {
        try {
          await ref
              .read(recordsProvider.notifier)
              .addCorrection(
                CreateCorrectionRequest(
                  accountId: account.id,
                  currency: currency,
                  balanceMinor: parseMinorUnits(trueBalanceInput)!,
                  date: date,
                  note: note.isEmpty ? null : note,
                ),
              );
        } on ZenError catch (error) {
          if (!context.mounted) return;
          showDialog(
            context: context,
            builder:
                (ctx) => AlertDialog(
                  title: Text(t.correctionsTitle),
                  content: Text(
                    error.message.isEmpty ? t.correctionsAlreadyBalanced : error.message,
                  ),
                  actions: [
                    ZenButton(
                      label: t.okay,
                      variant: ZenButtonVariant.text,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
          );
        }
      },
    );
    showAdaptivePresentation<void>(context, builder: (_) => body);
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
              ZenButton(
                label: t.cancel,
                variant: ZenButtonVariant.text,
                onPressed: () => Navigator.pop(ctx, false),
              ),
              ZenButton(
                label: t.accountDelete,
                variant: ZenButtonVariant.text,
                onPressed: () => Navigator.pop(ctx, true),
              ),
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
              actions: [
                ZenButton(
                  label: t.okay,
                  variant: ZenButtonVariant.text,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZenIconButton(
            icon: Icons.balance,
            label: t.accountReconcile,
            onPressed: () => _openReconcile(context, ref),
          ),
          ZenIconButton(
            icon: Icons.delete_outline,
            label: t.accountDelete,
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }
}
