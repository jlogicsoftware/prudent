import 'package:zen_core/zen_core.dart' show ZenResult;

import 'generated/prudent/v1/accounts.pb.dart';
import 'generated/prudent/v1/analytics.pb.dart';
import 'generated/prudent/v1/budgets.pb.dart';
import 'generated/prudent/v1/categories.pb.dart';
import 'generated/prudent/v1/goal_allocations.pb.dart';
import 'generated/prudent/v1/goals.pb.dart';
import 'generated/prudent/v1/imports.pb.dart';
import 'generated/prudent/v1/plans.pb.dart';
import 'generated/prudent/v1/privacy.pb.dart';
import 'generated/prudent/v1/records.pb.dart';
import 'generated/prudent/v1/reminders.pb.dart';
import 'generated/prudent/v1/settings.pb.dart';
import 'record/record_filter.dart';

/// Everything a screen, view model or provider asks of Prudent's data: the one seam between the
/// shared UI and where the data lives (jlogicsoftware/prudent#245, ADR-105). Every call returns
/// [ZenResult] — success or an error the caller can render — never a bare value and never a null
/// standing in for "nothing came back" (ADR-004).
///
/// Prudent Server implements it over HTTP (`ServerPrudentRepository`, the only place that knows
/// paths and the transport); a Local implementation will answer from the device. Method contracts
/// below are the server's, which a second implementation must reproduce — refusals included.
abstract interface class PrudentRepository {
  /// [filter] is optional and independently composable per criterion (jlogicsoftware/prudent#52);
  /// omitting it, or passing [RecordFilter.empty], is exactly today's unfiltered call.
  Future<ZenResult<ListRecordsResponse>> listRecords({RecordFilter? filter});

  Future<ZenResult<Record>> createRecord(CreateRecordRequest request);

  Future<ZenResult<Record>> updateRecord(
    String id,
    UpdateRecordRequest request,
  );

  Future<ZenResult<Record>> deleteRecord(String id);

  Future<ZenResult<Transfer>> createTransfer(CreateTransferRequest request);

  Future<ZenResult<Transfer>> deleteTransfer(String transferId);

  Future<ZenResult<Record>> createCorrection(CreateCorrectionRequest request);

  Future<ZenResult<Record>> deleteCorrection(String id);

  Future<ZenResult<ListAccountsResponse>> listAccounts();

  Future<ZenResult<Account>> createAccount(CreateAccountRequest request);

  Future<ZenResult<Account>> updateAccount(
    String id,
    UpdateAccountRequest request,
  );

  /// Deletes an account. By default the server refuses while any record remains; with
  /// [deleteRecords] it deletes every record of the account in the same transaction
  /// (jlogicsoftware/prudent#201) — both legs of a transfer, so another account's balance moves.
  /// Plans still refuse either way.
  Future<ZenResult<Account>> deleteAccount(
    String id, {
    bool deleteRecords = false,
  });

  Future<ZenResult<ListCategoriesResponse>> listCategories();

  Future<ZenResult<Category>> createCategory(CreateCategoryRequest request);

  Future<ZenResult<Category>> updateCategory(
    String id,
    UpdateCategoryRequest request,
  );

  /// Refused (409) while anything — a record, plan, budget or carry-over reset — still points at
  /// the category; [archiveCategory] is how a used category is taken out of use.
  Future<ZenResult<Category>> deleteCategory(String id);

  /// Retires a category (M3, jlogicsoftware/prudent#62): it stays listed and keeps all its history,
  /// and accepts no new record, plan or budget until [restoreCategory]. Refused (409) if it is
  /// already archived.
  Future<ZenResult<Category>> archiveCategory(String id);

  /// Returns an archived category to use. Refused (409) if it is not archived.
  Future<ZenResult<Category>> restoreCategory(String id);

  /// The caller's import sessions, newest first, without rows. [state] narrows the list.
  Future<ZenResult<ListImportSessionsResponse>> listImportSessions({
    ImportSessionState? state,
  });

  /// One session with its held rows (while it is parsed or previewed). Expires a session whose time
  /// has run out, so a stale session reads as EXPIRED rather than lingering.
  Future<ZenResult<ImportSession>> getImportSession(String id);

  /// Parses a statement and opens a session. The server refuses a statement it cannot read as a
  /// whole, with a rule code and row numbers in the message and never the statement's content.
  Future<ZenResult<ImportSession>> createImportSession(
    CreateImportSessionRequest request,
  );

  /// Classifies the rows and fixes the destination account; calling it again with another account is
  /// how the destination is changed without uploading the statement again.
  Future<ZenResult<ImportSession>> previewImportSession(
    String id,
    PreviewImportSessionRequest request,
  );

  /// A decision about one row (category, note, include a duplicate). A POST on purpose: it is a
  /// partial update and PUT in this API means full replacement (ADR-092).
  Future<ZenResult<UpdateImportRowResponse>> updateImportRow(
    String id,
    int rowNumber,
    UpdateImportRowRequest request,
  );

  /// The categories a row with none of its own is written under, by direction. The answer is the
  /// session without its rows.
  Future<ZenResult<ImportSession>> setImportDefaults(
    String id,
    SetImportDefaultsRequest request,
  );

  /// Writes the confirmed session to the ledger in one transaction. Repeating it with the same count
  /// answers with the same result.
  Future<ZenResult<ImportSession>> commitImportSession(
    String id,
    CommitImportSessionRequest request,
  );

  /// Throws the session and its rows away. Nothing is written.
  Future<ZenResult<ImportSession>> discardImportSession(String id);

  /// The user's goals, oldest first, optionally narrowed to one [status]. Archived and completed
  /// goals are listed too: a goal is retired, never deleted.
  Future<ZenResult<ListGoalsResponse>> listGoals({GoalStatus? status});

  Future<ZenResult<Goal>> getGoal(String id);

  /// Creates an active goal. The target must be positive; the currency cannot be changed later.
  Future<ZenResult<Goal>> createGoal(CreateGoalRequest request);

  /// Replaces the goal's name, target amount and target date (an absent date clears it). Refused
  /// (409) while the goal is archived.
  Future<ZenResult<Goal>> updateGoal(String id, UpdateGoalRequest request);

  /// Active → completed. Refused (409) if the goal is not active.
  Future<ZenResult<Goal>> completeGoal(String id);

  /// Active or completed → archived, keeping every bit of history. Refused (409) if already
  /// archived. There is no delete: this is how a goal is retired.
  Future<ZenResult<Goal>> archiveGoal(String id);

  /// Completed or archived → active. Refused (409) if the goal is already active.
  Future<ZenResult<Goal>> reactivateGoal(String id);

  /// How far each goal is, and what to set aside monthly to reach it (M4,
  /// jlogicsoftware/prudent#66, ADR-052): allocated, remaining and a whole percent per goal and, for an
  /// active goal with a target date that has not passed, the monthly contribution and the months it is
  /// spread over. Calculated by the server on every call — the client re-derives none of it. [asOf]
  /// (`YYYY-MM-DD`) is the day to calculate for; omitted, the server uses its UTC date. Never summed
  /// across currencies.
  Future<ZenResult<ListGoalProgressResponse>> getGoalProgress({String? asOf});

  /// Allocates, withdraws or moves money between goal envelopes — one immutable history entry
  /// (ADR-050). [CreateGoalAllocationRequest.kind] decides which goal ids it needs: a target for
  /// an allocation, a source for a withdrawal, both (in one currency) for a move. Refused (404)
  /// for a goal that is not the user's and (409) when the envelope does not hold the amount or a
  /// goal's state does not allow the entry. No account balance moves.
  Future<ZenResult<GoalAllocation>> createGoalAllocation(
    CreateGoalAllocationRequest request,
  );

  /// The envelope history, newest first, optionally narrowed to the entries that put money into or
  /// took it out of one goal. Entries are never edited or deleted.
  Future<ZenResult<ListGoalAllocationsResponse>> listGoalAllocations({
    String? goalId,
  });

  Future<ZenResult<GoalAllocation>> getGoalAllocation(String id);

  /// What each goal's envelope holds right now, one per goal (zero included). Calculated by the
  /// server from the history on every call; it is money set aside, not part of any account balance.
  Future<ZenResult<ListGoalEnvelopesResponse>> listGoalEnvelopes();

  /// What may still be set aside for goals, per currency (ADR-051): the eligible money (active
  /// accounts marked `eligibleForGoals`), what the envelopes already hold, and the difference.
  /// `freeMinor` is negative when the envelopes hold more than the eligible accounts do. Calculated
  /// by the server on every call; an `ALLOCATE` above it is refused with a 409.
  Future<ZenResult<GetFreeMoneyResponse>> getFreeMoney();

  /// The user's budgets, optionally narrowed to one [month] (`YYYY-MM`) and/or one [categoryId].
  Future<ZenResult<ListBudgetsResponse>> listBudgets({
    String? month,
    String? categoryId,
  });

  /// Plan, actual and remaining amount of every category budgeted for [month] (`YYYY-MM`) in
  /// [currency] (M3, jlogicsoftware/prudent#59). Both are required and the currency is never
  /// inferred: a summary is for one month in one currency and is never summed across currencies.
  /// Actual is net spending from posted records, refunds included.
  Future<ZenResult<BudgetSummaryResponse>> getBudgetSummary({
    required String month,
    required String currency,
  });

  /// Sets the budget for one category, [month] (`YYYY-MM`) and [currency], creating it or replacing
  /// its amount — a slot holds at most one. The amount must be positive; to have no budget for the
  /// slot, [deleteBudget].
  Future<ZenResult<Budget>> setBudget({
    required String categoryId,
    required String month,
    required String currency,
    required SetBudgetRequest request,
  });

  /// Removes the budget for one category, [month] and [currency]. Refused (404) if there is none.
  Future<ZenResult<Budget>> deleteBudget({
    required String categoryId,
    required String month,
    required String currency,
  });

  /// Resets one category's carry-over in [currency] from [month] (`YYYY-MM`) onward (M3,
  /// jlogicsoftware/prudent#61): carry-over into that month becomes zero. No budget is deleted and no
  /// earlier month changes. The answer is the audit entry, including what was discarded. Refused
  /// (409) if that slot already has a reset in effect.
  Future<ZenResult<BudgetCarryOverReset>> resetBudgetCarryOver(
    ResetBudgetCarryOverRequest request,
  );

  /// The whole reset history, revoked entries included, newest first, optionally narrowed to one
  /// [categoryId] and/or [currency].
  Future<ZenResult<ListBudgetCarryOverResetsResponse>>
  listBudgetCarryOverResets({String? categoryId, String? currency});

  /// Takes a reset back. The entry stays in the history, marked revoked with who and when, and
  /// the carry-over it bounded is counted in full again. Refused (409) if already revoked.
  Future<ZenResult<BudgetCarryOverReset>> revokeBudgetCarryOverReset(String id);

  Future<ZenResult<ListPlansResponse>> listPlans();

  /// A plan's `reminder` is a setting only (M5, jlogicsoftware/prudent#40): absent means disabled,
  /// one day ahead; a lead time outside the supported set is refused (400), never rounded.
  Future<ZenResult<Plan>> createPlan(CreatePlanRequest request);

  /// A full replacement: a request without a `reminder` resets it to the default, so send back the
  /// one that was read.
  Future<ZenResult<Plan>> updatePlan(String id, UpdatePlanRequest request);

  Future<ZenResult<Plan>> deletePlan(String id);

  /// Occurrences from today (in each plan's time zone) to [days] ahead, in any state, so what was
  /// skipped or confirmed early stays visible. The server defaults to 30 and accepts 1-366.
  Future<ZenResult<ListOccurrencesResponse>> listUpcomingOccurrences({
    int? days,
  });

  /// Occurrences still planned whose date has passed in their plan's time zone.
  Future<ZenResult<ListOccurrencesResponse>> listOverdueOccurrences();

  /// The user decided this occurrence will not happen. Refused (409) unless it is planned.
  Future<ZenResult<PlanOccurrence>> skipOccurrence(String id);

  /// Reopens a skipped occurrence as planned. Refused (409) unless it is skipped.
  Future<ZenResult<PlanOccurrence>> restoreOccurrence(String id);

  /// Says this occurrence happened, and creates the actual transaction (M2,
  /// jlogicsoftware/prudent#57). Every field of [request] is optional and an absent one takes the
  /// plan's own value, so the default request confirms it exactly as planned; what is set replaces
  /// it for this transaction only. Refused (409) unless the occurrence is planned or overdue, so a
  /// double tap cannot post twice. The result carries the completed occurrence and the record.
  Future<ZenResult<ConfirmOccurrenceResponse>> confirmOccurrence(
    String id, [
    ConfirmOccurrenceRequest? request,
  ]);

  /// Every reminder due or overdue now — a still-planned occurrence of a plan whose reminder is on,
  /// within its lead time or past its date — oldest date first, with each one's read state.
  Future<ZenResult<ListRemindersResponse>> listReminders();

  /// Marks one reminder read, addressed by its occurrence's id. Refused (409) for an occurrence
  /// that has no reminder right now, so a client that is behind refetches rather than guesses.
  Future<ZenResult<DueReminder>> markReminderRead(String occurrenceId);

  /// Marks one reminder unread again. Refused (409) like [markReminderRead].
  Future<ZenResult<DueReminder>> markReminderUnread(String occurrenceId);

  /// Marks every current reminder read and answers with the list as it now stands.
  Future<ZenResult<ListRemindersResponse>> markAllRemindersRead();

  Future<ZenResult<Settings>> getSettings();

  Future<ZenResult<Settings>> updateSettings(UpdateSettingsRequest request);

  /// Everything the server stores for the user, as one document: every account, category, record,
  /// plan, occurrence, budget, carry-over reset, goal and envelope entry, in any lifecycle state,
  /// plus the settings and profile. Complete rather than view-shaped; see `privacy.proto`.
  Future<ZenResult<DataExport>> exportData();

  /// Erases every Prudent row the user owns, anonymises their profile and deletes their sign-in
  /// record at the identity provider — IRREVERSIBLE. Refused (400) unless
  /// [EraseAccountRequest.confirmEmail] is the account's sign-in address, and answered 503 when the
  /// sign-in record could not be deleted; in both cases nothing is deleted. The session is not
  /// ended: the caller logs out. The server answers 204, so the empty request message stands in for
  /// the missing body, as [deleteAccount]'s does.
  Future<ZenResult<EraseAccountRequest>> eraseAccount(
    EraseAccountRequest request,
  );

  /// [year] required; [month] optional (1-12) — a single month, or the whole year when omitted.
  Future<ZenResult<SpendByCategoryResponse>> spendByCategory({
    required String currency,
    required int year,
    int? month,
  });

  /// [granularity] is `MONTH` or `YEAR`; [count] is the number of trailing buckets (1-60), ending
  /// at the current period as the server resolves it in UTC.
  Future<ZenResult<SpendByPeriodResponse>> spendByPeriod({
    required String currency,
    required String granularity,
    required int count,
  });
}
