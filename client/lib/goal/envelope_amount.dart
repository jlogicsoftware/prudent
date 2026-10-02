import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/prudent_localizations.dart';
import 'goal_figures.dart';

/// Money set aside in a goal envelope, drawn so it cannot be mistaken for an account balance.
///
/// An envelope is VIRTUAL (ADR-050): the money is still in the user's accounts, and no balance or
/// spending figure reads it. Shown as a plain amount it would sit beside the balances looking like
/// one more pot of money, and a user adding the two would count it twice. So every envelope
/// amount — on a goal card, in the free-money summary, in the history — goes through this one
/// widget: an envelope icon on the tertiary container colour, never the plain text a balance uses,
/// and read out by screen readers as "set aside for goals", so the distinction is not colour alone.
class EnvelopeAmount extends StatelessWidget {
  const EnvelopeAmount(this.amount, this.currency, {super.key, this.signed = false});

  final Int64 amount;
  final String currency;

  /// Writes a leading `+` on a positive amount, for a history entry where the sign is the
  /// direction money moved.
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = '${signed && amount > 0 ? '+' : ''}${formatGoalAmount(amount, currency)}';

    return Semantics(
      container: true,
      label: t.goalEnvelopeSemantics(text),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 16, color: scheme.onTertiaryContainer),
            const SizedBox(width: 4),
            Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: scheme.onTertiaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}
