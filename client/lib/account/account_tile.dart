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
import 'delete_account_form.dart';
import 'reconcile_account.dart';

/// One account in the accounts list: its balances per currency, and the edit, reconcile and delete
/// actions on it.
class AccountTile extends ConsumerWidget {
  const AccountTile(this.account, {super.key});

  final Account account;

  void _openEdit(BuildContext context, WidgetRef ref) {
    final body = AccountEdit(
      account: account,
      onSave:
          (request) => ref
              .read(accountsProvider.notifier)
              .editAccount(account.id, request),
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
                    error.message.isEmpty
                        ? t.correctionsAlreadyBalanced
                        : error.message,
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

  /// Two steps (jlogicsoftware/prudent#201): this warning, then [DeleteAccountForm], which asks for
  /// a typed phrase before anything is deleted. Cancelling either deletes nothing.
  Future<void> _confirmDelete(BuildContext context) async {
    final t = PrudentLocalizations.of(context);
    final proceed = await showDialog<bool>(
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
                label: t.accountDeleteContinue,
                variant: ZenButtonVariant.text,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
    );
    if (proceed != true || !context.mounted) return;
    await showAdaptivePresentation<void>(
      context,
      builder: (_) => DeleteAccountForm(account: account),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final balances = account.balances
        .map((b) => '${formatMinorUnits(b.amountMinor)} ${b.currency}')
        .join(', ');
    return ZenListItemActions(
      showActionsLabel: t.accountShowActions,
      hideActionsLabel: t.accountHideActions,
      actions: [
        ZenListItemAction(
          icon: Icons.balance,
          label: t.accountReconcile,
          onPressed: () => _openReconcile(context, ref),
        ),
        ZenListItemAction(
          icon: Icons.delete_outline,
          label: t.accountDelete,
          variant: ZenListItemActionVariant.destructive,
          onPressed: () => _confirmDelete(context),
        ),
      ],
      child: ZenListRow(
        onTap: () => _openEdit(context, ref),
        leading: Icon(
          account.type == AccountType.ACCOUNT_TYPE_CARD ||
                  account.type == AccountType.ACCOUNT_TYPE_CASH
              ? Icons.account_balance
              : Icons.account_balance_wallet,
        ),
        title: account.name,
        subtitle: balances.isEmpty ? t.accountsNoBalance : balances,
      ),
    );
  }
}
