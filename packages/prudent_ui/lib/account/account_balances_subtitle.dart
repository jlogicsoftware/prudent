import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';
import 'unsettled_balance_note.dart';

/// An account's balances, one per currency, and — beside them, from the same answer — what they
/// leave out while two devices disagree about it (ADR-113).
class AccountBalancesSubtitle extends ConsumerWidget {
  const AccountBalancesSubtitle({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final balances = account.balances
        .map((b) => '${formatMinorUnits(b.amountMinor)} ${b.currency}')
        .join(', ');
    final leftOut = ref.watch(unsettledBalancesProvider)[account.id]?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(balances.isEmpty ? t.accountsNoBalance : balances),
        UnsettledBalanceNote(count: leftOut),
      ],
    );
  }
}
