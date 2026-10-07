import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import '../popup.dart';
import 'account_list.dart';
import 'account_new.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  static const routeName = '/account';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ZenPageScaffold(
      title: PrudentLocalizations.of(context).accountsTitle,
      actions: [
        Popup(
          icon: Icons.add,
          label: PrudentLocalizations.of(context).addAccountTooltip,
          popupBody: AccountNew(
            onAddAccount:
                (request) =>
                    ref.read(accountsProvider.notifier).addAccount(request),
          ),
        ),
      ],
      body: const AccountList(),
    );
  }
}
