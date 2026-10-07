import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/plans.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';
import 'occurrence_figure_row.dart';
import 'reminder_figures.dart';

/// One planned occurrence, and what the user can do about it: confirm it as planned, skip it, or
/// restore a skipped one (M2, ADR-039, ADR-040). This is where a reminder leads (M5, ADR-055).
///
/// The occurrence shown is the last one the server answered with — the one passed in, then each
/// action's own response — so the status drawn is the stored one. What each status offers follows
/// the server's rules: a planned or overdue occurrence can be confirmed or skipped, a skipped one
/// restored, a completed one nothing. Offering only that is a convenience; the server still
/// decides, and a refusal is shown in its words.
///
/// Confirming here writes the record exactly as the plan has it. Changing the date, amount, account
/// or category for one transaction is not offered on this screen; the server takes it
/// ([ConfirmOccurrenceRequest]), and a screen for it is its own piece of work.
class OccurrenceDetailScreen extends ConsumerStatefulWidget {
  const OccurrenceDetailScreen({super.key, required this.occurrence});

  final PlanOccurrence occurrence;

  @override
  ConsumerState<OccurrenceDetailScreen> createState() => _OccurrenceDetailScreenState();
}

class _OccurrenceDetailScreenState extends ConsumerState<OccurrenceDetailScreen> {
  late PlanOccurrence _occurrence = widget.occurrence;
  bool _busy = false;

  Future<void> _act(Future<PlanOccurrence> Function(OccurrenceActions actions) action) async {
    final t = PrudentLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final updated = await action(ref.read(occurrenceActionsProvider));
      if (mounted) setState(() => _occurrence = updated);
    } on ZenError catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(_occurrence.title),
              content: Text(error.message.isEmpty ? t.occurrenceActionFailed : error.message),
              actions: [
                ZenButton(
                  label: t.okay,
                  variant: ZenButtonVariant.text,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final account = accounts.where((a) => a.id == _occurrence.accountId).firstOrNull;
    final category = categories.where((c) => c.id == _occurrence.categoryId).firstOrNull;
    final open =
        _occurrence.status == OccurrenceStatus.OCCURRENCE_STATUS_PLANNED ||
        _occurrence.status == OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE;
    final skipped = _occurrence.status == OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED;

    return Scaffold(
      appBar: AppBar(title: Text(t.occurrenceTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_occurrence.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          OccurrenceFigureRow(
            t.occurrenceDate,
            formatReminderDate(_occurrence.occurrenceDate, locale),
          ),
          OccurrenceFigureRow(
            t.occurrenceAmount,
            '${formatMinorUnits(_occurrence.amountMinor)} ${_occurrence.currency}',
          ),
          OccurrenceFigureRow(t.occurrenceAccount, account?.name ?? t.occurrenceUnknownAccount),
          OccurrenceFigureRow(
            t.occurrenceCategory,
            category?.title ?? t.occurrenceUnknownCategory,
          ),
          OccurrenceFigureRow(t.occurrenceStatus, _statusLabel(t, _occurrence.status)),
          const SizedBox(height: 24),
          if (open) ...[
            Text(t.occurrenceConfirmHint, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ZenButton(
                  label: t.occurrenceConfirm,
                  icon: Icons.check,
                  isLoading: _busy,
                  onPressed: () => _act((actions) => actions.confirm(_occurrence.id)),
                ),
                ZenButton(
                  label: t.occurrenceSkip,
                  icon: Icons.skip_next,
                  variant: ZenButtonVariant.secondary,
                  onPressed: _busy ? null : () => _act((actions) => actions.skip(_occurrence.id)),
                ),
              ],
            ),
          ] else if (skipped)
            ZenButton(
              label: t.occurrenceRestore,
              icon: Icons.restore,
              variant: ZenButtonVariant.secondary,
              isLoading: _busy,
              onPressed: () => _act((actions) => actions.restore(_occurrence.id)),
            )
          else
            Text(t.occurrenceNotPlannedHint, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  static String _statusLabel(PrudentLocalizations t, OccurrenceStatus status) => switch (status) {
    OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE => t.occurrenceStatusOverdue,
    OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED => t.occurrenceStatusCompleted,
    OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED => t.occurrenceStatusSkipped,
    _ => t.occurrenceStatusPlanned,
  };
}
