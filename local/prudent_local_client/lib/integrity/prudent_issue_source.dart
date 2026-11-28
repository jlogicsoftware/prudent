import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import '../l10n/generated/local_localizations.dart';

/// The integrity runner's issues (ADR-102 D6, ADR-111) as `zen_ui_store` application issues, beside
/// the store's own conflicts (jZenDev/jZen#233): the banner counts them and the conflict list shows
/// them with Prudent's actions. Nothing is fixed silently (ADR-100 T23).
///
/// [IntegrityIssue] is data; this gives it words in the person's language, chosen by its code, and
/// names records by what the person calls them. What an action needs from the person, a choice among
/// records or a name, is asked by `ZenIssueScreen` itself (jZenDev/jZen#256); cancelling there runs
/// nothing and leaves the issue.
ZenIssueSource prudentIssueSource(
  IntegrityRunner runner,
  LocalLocalizations t,
) => ZenIssueSource(
  issues: () => switch (runner.evaluate()) {
    ZenSuccess(:final data) => [
      for (final issue in data) _issue(issue, runner.store, t),
    ],
    // A store that cannot be read is never reported as "no issues": it is one issue that says so.
    ZenFailure(:final error) => [
      ZenIssue(
        id: 'store.unreadable',
        title: t.issueUnknown(error.runtimeType.toString()),
        description: t.issueUnknownBody,
        actions: [
          // "Try again" writes nothing: `ZenIssueScreen` closes on success and the banner and the list
          // call [issues] again, which reads the store afresh. That re-evaluation is the retry, and the
          // issue stays for as long as the store still cannot be read.
          ZenIssueAction(
            label: t.startFailedRetry,
            run: () async => const ZenResult.ok(null),
          ),
        ],
      ),
    ],
  },
  changes: runner.changes,
);

ZenIssue _issue(
  IntegrityIssue issue,
  PrudentLocalStore store,
  LocalLocalizations t,
) {
  final (title, description) = _words(issue.code, t);
  return ZenIssue(
    id: issue.id,
    title: title,
    description: description,
    actions: [for (final action in issue.actions) _action(action, store, t)],
  );
}

ZenIssueAction _action(
  IntegrityAction action,
  PrudentLocalStore store,
  LocalLocalizations t,
) {
  final choices = action.choices;
  if (choices != null) {
    // One candidate is a button that names it: jZen's choice prompt asserts at least two
    // (jZenDev/jZen#288).
    if (choices case [final only]) {
      return ZenIssueAction(
        label: _onlyChoiceLabel(action.code, _nameOf(store, only), t),
        run: () => action.run(only),
      );
    }
    return ZenIssueAction.choose(
      label: _label(action.code, t),
      choices: [for (final id in choices) (id, _nameOf(store, id))],
      run: action.run,
    );
  }
  if (action.needsText) {
    return ZenIssueAction.text(
      label: _label(action.code, t),
      fieldLabel: t.recreateNameField,
      run: action.run,
    );
  }
  return ZenIssueAction(label: _label(action.code, t), run: action.run);
}

/// What the person calls the record [id]: an account's or category's name, a record's title and
/// date, a carry-over reset's month — never an amount or an account number (ADR-100 T22).
String _nameOf(PrudentLocalStore store, String id) {
  if (store.accounts.get(id).dataOrNull case final a?) return a.name;
  if (store.categories.get(id).dataOrNull case final c?) return c.title;
  if (store.records.get(id).dataOrNull case final r?) {
    return '${r.title}, ${r.date}';
  }
  if (store.budgetResets.get(id).dataOrNull case final reset?) {
    return '${reset.month}, ${reset.currency}';
  }
  return id;
}

String _label(String code, LocalLocalizations t) => switch (code) {
  'delete_record' => t.actionDeleteRecord,
  'delete_transfer' => t.actionDeleteTransfer,
  'delete_plan' => t.actionDeletePlan,
  'delete_budget' => t.actionDeleteBudget,
  'delete_account_currency' => t.actionDeleteAccountCurrency,
  'recreate_account' => t.actionRecreateAccount,
  'recreate_category' => t.actionRecreateCategory,
  'add_currency' => t.actionAddCurrency,
  'category_takes_both' => t.actionCategoryTakesBoth,
  'clear_default_account' => t.actionClearDefaultAccount,
  'allocate_deficit' => t.actionAllocateDeficit,
  'clear_skip' => t.actionClearSkip,
  'undo_overshoot' => t.actionUndoOvershoot,
  'reactivate_goal' => t.actionReactivateGoal,
  'withdraw_all' => t.actionWithdrawAll,
  'move_to_account' => t.actionMoveToAnotherAccount,
  'move_to_category' => t.actionMoveToAnotherCategory,
  'choose_default_account' => t.actionChooseAnotherDefault,
  'delete_correction' => t.actionDeleteOneCorrection,
  'correct_to_target' => t.actionKeepOneCorrection,
  'clear_account_number' => t.actionClearOneAccountNumber,
  'revoke_reset' => t.actionRevokeOneReset,
  _ => t.actionUnknown(code, ''),
};

/// The button of a choice that has one candidate. The other choices are made only for two or more
/// records (two corrections, two accounts with one number, two resets), so they have no wording here.
String _onlyChoiceLabel(String code, String name, LocalLocalizations t) =>
    switch (code) {
      'move_to_account' => t.actionMoveToAccount(name),
      'move_to_category' => t.actionMoveToCategory(name),
      'choose_default_account' => t.actionChooseDefaultAccount(name),
      _ => t.actionUnknown(code, name),
    };

/// The title and the description of an issue, by its code. A code this build has no words for (a
/// check a later unit adds) is still shown, named by its code, with its actions.
(String, String) _words(String code, LocalLocalizations t) => switch (code) {
  'reference.record_account_missing' => (
    t.issueRecordAccountMissing,
    t.issueRecordAccountMissingBody,
  ),
  'reference.record_category_missing' => (
    t.issueRecordCategoryMissing,
    t.issueRecordCategoryMissingBody,
  ),
  'reference.transfer_account_missing' => (
    t.issueTransferAccountMissing,
    t.issueTransferAccountMissingBody,
  ),
  'reference.currency_account_missing' => (
    t.issueCurrencyAccountMissing,
    t.issueCurrencyAccountMissingBody,
  ),
  'reference.plan_account_missing' => (
    t.issuePlanAccountMissing,
    t.issuePlanAccountMissingBody,
  ),
  'reference.plan_category_missing' => (
    t.issuePlanCategoryMissing,
    t.issuePlanCategoryMissingBody,
  ),
  'reference.budget_category_missing' => (
    t.issueBudgetCategoryMissing,
    t.issueBudgetCategoryMissingBody,
  ),
  'reference.reset_category_missing' => (
    t.issueResetCategoryMissing,
    t.issueResetCategoryMissingBody,
  ),
  'reference.default_account_missing' => (
    t.issueDefaultAccountMissing,
    t.issueDefaultAccountMissingBody,
  ),
  'currency.record_not_held' => (
    t.issueRecordNotHeld,
    t.issueRecordNotHeldBody,
  ),
  'currency.transfer_not_held' => (
    t.issueTransferNotHeld,
    t.issueTransferNotHeldBody,
  ),
  'currency.plan_not_held' => (t.issuePlanNotHeld, t.issuePlanNotHeldBody),
  'category.kind_refuses_sign' => (
    t.issueCategoryKind,
    t.issueCategoryKindBody,
  ),
  'account.number_duplicate' => (
    t.issueAccountNumberDuplicate,
    t.issueAccountNumberDuplicateBody,
  ),
  'budget.reset_slot_twice' => (
    t.issueResetSlotTwice,
    t.issueResetSlotTwiceBody,
  ),
  'correction.made_apart' => (
    t.issueCorrectionsMadeApart,
    t.issueCorrectionsMadeApartBody,
  ),
  'goal.envelope_below_zero' => (
    t.issueEnvelopeBelowZero,
    t.issueEnvelopeBelowZeroBody,
  ),
  'goal.archived_holds_money' => (
    t.issueArchivedGoalHoldsMoney,
    t.issueArchivedGoalHoldsMoneyBody,
  ),
  'occurrence.skipped_and_paid' => (
    t.issueSkippedAndPaid,
    t.issueSkippedAndPaidBody,
  ),
  'goal.repairs_made_apart' => (
    t.issueRepairsMadeApart,
    t.issueRepairsMadeApartBody,
  ),
  _ => (t.issueUnknown(code), t.issueUnknownBody),
};

/// Every issue code this build has words for; a test holds it to the checks the runner has.
const Set<String> wordedIssueCodes = {
  'reference.record_account_missing',
  'reference.record_category_missing',
  'reference.transfer_account_missing',
  'reference.currency_account_missing',
  'reference.plan_account_missing',
  'reference.plan_category_missing',
  'reference.budget_category_missing',
  'reference.reset_category_missing',
  'reference.default_account_missing',
  'currency.record_not_held',
  'currency.transfer_not_held',
  'currency.plan_not_held',
  'category.kind_refuses_sign',
  'account.number_duplicate',
  'budget.reset_slot_twice',
  'correction.made_apart',
  'goal.envelope_below_zero',
  'goal.archived_holds_money',
  'occurrence.skipped_and_paid',
  'goal.repairs_made_apart',
};
