import 'package:material_ui/material_ui.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import 'import_review.dart';

/// The destination account of the session, changeable until the commit. Offers the user's active
/// accounts that hold the statement's currency (the server checks both again, and checks that the
/// statement is the account's own). Changing it classifies the rows again for the new account.
class ImportDestinationField extends StatelessWidget {
  const ImportDestinationField({
    super.key,
    required this.review,
    required this.accounts,
    required this.onChanged,
    this.enabled = true,
  });

  final ImportReview review;
  final List<Account> accounts;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final currency = review.session.currency;
    final current = review.hasDestination ? review.session.accountId : null;
    final offered = [
      for (final a in accounts)
        if (a.id == current || (a.isActive && a.balances.any((b) => b.currency == currency))) a,
    ];
    if (offered.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ZenSelect<String>(
          label: t.importAccountField,
          items: [for (final a in offered) a.id],
          itemLabel: (id) => offered.firstWhere((a) => a.id == id).name,
          value: offered.any((a) => a.id == current) ? current : null,
          onChanged: enabled ? onChanged : null,
          hint: current == null ? t.importNoAccountChosen : null,
        ),
        // The server classifies duplicates per account and starts again when the account changes, so
        // say what a change costs before it is made, not after.
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            t.importDestinationResetHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
