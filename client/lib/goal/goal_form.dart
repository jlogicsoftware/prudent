import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/goals.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../money.dart';
import '../providers.dart';

/// Creates a goal, or edits [goal]'s name, target and date (ADR-049).
///
/// The currency is chosen only at creation — money set aside for a goal is held in it, so it
/// cannot change afterwards — and only from the currencies the user holds accounts in, since an
/// envelope can only be filled from an account. An edit sends the date it shows, so clearing the
/// field clears the date (`UpdateGoalRequest` is a full replacement).
///
/// The form stays open when the server refuses, and says why in the server's words: closing it
/// would throw away what the user typed for a reason they never saw.
class GoalForm extends ConsumerStatefulWidget {
  const GoalForm({super.key, this.goal});

  final Goal? goal;

  @override
  ConsumerState<GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<GoalForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _target;
  String? _currency;
  DateTime? _date;
  String? _targetError;
  String? _failure;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    _name = TextEditingController(text: goal?.name ?? '');
    _target = TextEditingController(
      text: goal == null ? '' : formatMinorUnits(goal.targetAmountMinor),
    );
    _currency = goal?.currency;
    _date = goal != null && goal.hasTargetDate() ? DateTime.tryParse(goal.targetDate) : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _submit(PrudentLocalizations t, String currency) async {
    final canonical = normalizeAmount(_target.text, maxFractionDigits: 2, allowNegative: false);
    final minor = canonical == null ? null : parseMinorUnits(canonical);
    final amountValid = minor != null && minor > Int64.ZERO;
    setState(() => _targetError = amountValid ? null : t.goalAmountInvalid);
    if (!_formKey.currentState!.validate() || !amountValid) return;

    final name = _name.text.trim();
    final date = _date == null ? null : DateFormat('yyyy-MM-dd').format(_date!);
    final goals = ref.read(goalsProvider.notifier);
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final goal = widget.goal;
      if (goal == null) {
        await goals.addGoal(
          CreateGoalRequest(
            name: name,
            currency: currency,
            targetAmountMinor: minor,
            targetDate: date,
          ),
        );
      } else {
        await goals.editGoal(
          goal.id,
          UpdateGoalRequest(name: name, targetAmountMinor: minor, targetDate: date),
        );
      }
      if (mounted) Navigator.pop(context);
    } on ZenError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failure = error.message.isEmpty ? t.goalActionFailed : error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final editing = widget.goal != null;
    final currencies = ref.watch(analyticsCurrenciesProvider);
    final currency =
        editing
            ? widget.goal!.currency
            : (currencies.contains(_currency) ? _currency : null) ??
                (currencies.isEmpty ? null : currencies.first);

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              editing ? t.goalEditTitle : t.goalNew,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (currency == null)
              Text(t.goalNoCurrency, style: Theme.of(context).textTheme.bodyLarge)
            else ...[
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: t.goalNameField,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => (value ?? '').trim().isEmpty ? t.goalNameRequired : null,
              ),
              const SizedBox(height: 16),
              if (!editing && currencies.length > 1) ...[
                ZenSelect<String>(
                  label: t.goalCurrencyField,
                  items: currencies,
                  itemLabel: (c) => c,
                  value: currency,
                  onChanged: (value) => setState(() => _currency = value),
                ),
                const SizedBox(height: 16),
              ],
              ZenAmountField(
                label: '${t.goalTargetField} ($currency)',
                controller: _target,
                maxFractionDigits: 2,
                allowNegative: false,
                errorText: _targetError,
              ),
              const SizedBox(height: 16),
              ZenDateField(
                label: t.goalDateField,
                value: _date,
                clearable: true,
                onChanged: (value) => setState(() => _date = value),
              ),
              if (_failure != null) ...[
                const SizedBox(height: 16),
                Text(_failure!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ZenButton(
                  label: t.cancel,
                  variant: ZenButtonVariant.text,
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                ZenButton(
                  label: t.goalSave,
                  isLoading: _saving,
                  onPressed: currency == null ? null : () => _submit(t, currency),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
