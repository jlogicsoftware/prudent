import 'package:intl/intl.dart';
import 'package:prudent_local_store/prudent_local_store.dart'
    show
        Analytics,
        ImportWorkflow,
        Ledger,
        LedgerBudgets,
        LedgerGoals,
        PlanLedger,
        RecordQuery,
        Settled;
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/analytics.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/budgets.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/goal_allocations.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/privacy.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/reminders.pb.dart';
import 'package:prudent_proto/generated/prudent/v1/settings.pb.dart';
import 'package:prudent_ui/account/settled_accounts.dart';
import 'package:prudent_ui/prudent_repository.dart';
import 'package:prudent_ui/record/record_filter.dart';
import 'package:prudent_ui/settled_figures.dart';
import 'package:zen_core/zen_core.dart';

import 'local_data_export.dart';

/// [PrudentRepository] over this device's store: every shared screen works with no server
/// (ADR-105, ADR-108; plan unit 9).
///
/// Accounts, categories, records, transfers, corrections and settings are the Local [Ledger]'s
/// (ADR-113), which takes and answers the same wire messages the server does, refusals included.
/// The ledger is read from [ledger] on every call, because erasing this device's copy replaces the
/// store under it.
///
/// Statement import is unit 8b's `ImportWorkflow` (ADR-114): sessions in the store's device-only
/// collection, never synced (ADR-100 T12).
///
/// Budgets, carry-over resets, goals and envelopes are unit 6a's ledger extensions (ADR-116); their
/// figures carry what they leave out ([SettledFigures]) like balances do.
///
/// Plans, occurrences and reminders are unit 6b's `PlanLedger` (ADR-119), given the device's clock.
///
/// Analytics is unit 7's `Analytics` (ADR-118); its figures carry what they leave out too. Every part of
/// the interface is answered from the device: there is nothing this build lacks.
///
/// **Balances carry their caveat** (ADR-113): [listAccounts] answers the ledger's `Settled`
/// unchanged, so a balance that leaves out a record two devices disagree about says so beside it.
final class LocalPrudentRepository implements PrudentRepository {
  /// The ledger as it is now; a function because it is replaced when this device's copy is erased.
  final Ledger Function() ledger;

  /// Statement import as it is now (unit 8b, ADR-114); replaced with the ledger.
  final ImportWorkflow Function() imports;

  /// Spend by category and by period as they are now (unit 7, ADR-118); replaced with the ledger.
  final Analytics Function() analytics;

  /// Plans, occurrences and reminders as they are now (unit 6b, ADR-119); replaced with the ledger.
  final PlanLedger Function() plans;

  /// "Now", which every plan operation takes explicitly (ADR-119): a plan's own zone decides its day.
  final DateTime Function() now;

  /// The data copy (the local counterpart of ADR-071's export).
  final LocalDataExport export;

  LocalPrudentRepository({
    required this.ledger,
    required this.imports,
    required this.plans,
    required this.analytics,
    required this.export,
    this.now = DateTime.now,
  });

  static final DateFormat _day = DateFormat('yyyy-MM-dd');

  // ── Records ─────────────────────────────────────────────────────────────────────────────────

  @override
  Future<ZenResult<ListRecordsResponse>> listRecords({RecordFilter? filter}) {
    final f = filter ?? RecordFilter.empty;
    final search = f.search?.trim();
    return ledger().listRecords(
      RecordQuery(
        dateFrom: f.dateFrom == null ? null : _day.format(f.dateFrom!),
        dateTo: f.dateTo == null ? null : _day.format(f.dateTo!),
        accountId: f.accountId,
        categoryId: f.categoryId,
        type: f.type?.wireValue,
        amountMin: f.amountMin?.toInt(),
        amountMax: f.amountMax?.toInt(),
        search: search == null || search.isEmpty ? null : search,
      ),
    );
  }

  @override
  Future<ZenResult<Record>> createRecord(CreateRecordRequest request) =>
      ledger().createRecord(request);

  @override
  Future<ZenResult<Record>> updateRecord(
    String id,
    UpdateRecordRequest request,
  ) => ledger().updateRecord(id, request);

  /// The server answers a delete with no body, which its repository reads as an empty message; so
  /// does this one.
  @override
  Future<ZenResult<Record>> deleteRecord(String id) async =>
      _empty(await ledger().deleteRecord(id), Record.new);

  @override
  Future<ZenResult<Transfer>> createTransfer(CreateTransferRequest request) =>
      ledger().createTransfer(request);

  @override
  Future<ZenResult<Transfer>> deleteTransfer(String transferId) async =>
      _empty(await ledger().deleteTransfer(transferId), Transfer.new);

  @override
  Future<ZenResult<Record>> createCorrection(CreateCorrectionRequest request) =>
      ledger().createCorrection(request);

  @override
  Future<ZenResult<Record>> deleteCorrection(String id) async =>
      _empty(await ledger().deleteCorrection(id), Record.new);

  // ── Accounts ────────────────────────────────────────────────────────────────────────────────

  @override
  Future<ZenResult<SettledAccounts>> listAccounts() async =>
      switch (await ledger().listAccounts()) {
        ZenSuccess(:final data) => ZenResult.ok(
          SettledAccounts(data.value.accounts, data.unsettled),
        ),
        ZenFailure(:final error) => ZenResult.err(error),
      };

  @override
  Future<ZenResult<Account>> createAccount(
    CreateAccountRequest request,
  ) async => _value(await ledger().createAccount(request));

  @override
  Future<ZenResult<Account>> updateAccount(
    String id,
    UpdateAccountRequest request,
  ) async => _value(await ledger().updateAccount(id, request));

  @override
  Future<ZenResult<Account>> deleteAccount(
    String id, {
    bool deleteRecords = false,
  }) async => _empty(
    await ledger().deleteAccount(id, deleteRecords: deleteRecords),
    Account.new,
  );

  // ── Categories ──────────────────────────────────────────────────────────────────────────────

  @override
  Future<ZenResult<ListCategoriesResponse>> listCategories() =>
      ledger().listCategories();

  @override
  Future<ZenResult<Category>> createCategory(CreateCategoryRequest request) =>
      ledger().createCategory(request);

  @override
  Future<ZenResult<Category>> updateCategory(
    String id,
    UpdateCategoryRequest request,
  ) => ledger().updateCategory(id, request);

  @override
  Future<ZenResult<Category>> deleteCategory(String id) async =>
      _empty(await ledger().deleteCategory(id), Category.new);

  @override
  Future<ZenResult<Category>> archiveCategory(String id) =>
      ledger().archiveCategory(id);

  @override
  Future<ZenResult<Category>> restoreCategory(String id) =>
      ledger().restoreCategory(id);

  // ── Settings ────────────────────────────────────────────────────────────────────────────────

  @override
  Future<ZenResult<Settings>> getSettings() => ledger().getSettings();

  @override
  Future<ZenResult<Settings>> updateSettings(UpdateSettingsRequest request) =>
      ledger().updateSettings(request);

  // ── The person's data ───────────────────────────────────────────────────────────────────────

  /// Everything this device's store holds, as the server's export document (ADR-071's shape), so a
  /// copy saved here reads like one the server made.
  @override
  Future<ZenResult<DataExport>> exportData() => export.build(ledger());

  /// There is no account to erase: no server, no sign-in. Prudent Local erases this device's copy,
  /// or everything everywhere, from its own Settings page; the server's form is never shown.
  @override
  Future<ZenResult<EraseAccountRequest>> eraseAccount(
    EraseAccountRequest request,
  ) async => const ZenResult.err(
    ZenValidationError(
      'Prudent Local has no account to erase; erase its data under Settings.',
      internalData: {'code': 'invalid'},
    ),
  );

  // ── Statement import (unit 8b, ADR-114) ───────────────────────────────────────────────────

  @override
  Future<ZenResult<ListImportSessionsResponse>> listImportSessions({
    ImportSessionState? state,
  }) {
    final String? name;
    switch (state) {
      case null:
        name = null;
      case ImportSessionState.IMPORT_SESSION_STATE_PARSED:
        name = 'PARSED';
      case ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED:
        name = 'PREVIEWED';
      case ImportSessionState.IMPORT_SESSION_STATE_COMMITTED:
        name = 'COMMITTED';
      case ImportSessionState.IMPORT_SESSION_STATE_DISCARDED:
        name = 'DISCARDED';
      case ImportSessionState.IMPORT_SESSION_STATE_EXPIRED:
        name = 'EXPIRED';
      default:
        return Future.value(
          const ZenResult.err(
            ZenValidationError(
              'Not a session state.',
              internalData: {'code': 'invalid'},
            ),
          ),
        );
    }
    return imports().list(state: name);
  }

  @override
  Future<ZenResult<ImportSession>> getImportSession(String id) =>
      imports().get(id);

  @override
  Future<ZenResult<ImportSession>> createImportSession(
    CreateImportSessionRequest request,
  ) => imports().create(request);

  @override
  Future<ZenResult<ImportSession>> previewImportSession(
    String id,
    PreviewImportSessionRequest request,
  ) => imports().preview(id, request);

  @override
  Future<ZenResult<UpdateImportRowResponse>> updateImportRow(
    String id,
    int rowNumber,
    UpdateImportRowRequest request,
  ) => imports().updateRow(id, rowNumber, request);

  @override
  Future<ZenResult<ImportSession>> setImportDefaults(
    String id,
    SetImportDefaultsRequest request,
  ) => imports().setDefaults(id, request);

  @override
  Future<ZenResult<ImportSession>> commitImportSession(
    String id,
    CommitImportSessionRequest request,
  ) => imports().commit(id, request);

  @override
  Future<ZenResult<ImportSession>> discardImportSession(String id) =>
      imports().discard(id);

  // ── Goals and envelopes (unit 6a, ADR-116) ──────────────────────────────────────────────────

  @override
  Future<ZenResult<ListGoalsResponse>> listGoals({GoalStatus? status}) async {
    final String? name;
    switch (status) {
      case null:
        name = null;
      case GoalStatus.GOAL_STATUS_ACTIVE:
        name = 'ACTIVE';
      case GoalStatus.GOAL_STATUS_COMPLETED:
        name = 'COMPLETED';
      case GoalStatus.GOAL_STATUS_ARCHIVED:
        name = 'ARCHIVED';
      default:
        return const ZenResult.err(
          ZenValidationError(
            'Not a goal status.',
            internalData: {'code': 'invalid'},
          ),
        );
    }
    return ledger().listGoals(status: name);
  }

  @override
  Future<ZenResult<Goal>> getGoal(String id) => ledger().getGoal(id);

  @override
  Future<ZenResult<Goal>> createGoal(CreateGoalRequest request) =>
      ledger().createGoal(request);

  @override
  Future<ZenResult<Goal>> updateGoal(String id, UpdateGoalRequest request) =>
      ledger().updateGoal(id, request);

  @override
  Future<ZenResult<Goal>> completeGoal(String id) => ledger().completeGoal(id);

  @override
  Future<ZenResult<Goal>> archiveGoal(String id) => ledger().archiveGoal(id);

  @override
  Future<ZenResult<Goal>> reactivateGoal(String id) =>
      ledger().reactivateGoal(id);

  /// What the progress leaves out (a goal two devices disagree about) travels with it (ADR-116).
  @override
  Future<ZenResult<SettledFigures<ListGoalProgressResponse>>> getGoalProgress({
    String? asOf,
  }) async => _figures(await ledger().goalProgress(asOf: asOf));

  @override
  Future<ZenResult<GoalAllocation>> createGoalAllocation(
    CreateGoalAllocationRequest request,
  ) => ledger().createGoalAllocation(request);

  @override
  Future<ZenResult<ListGoalAllocationsResponse>> listGoalAllocations({
    String? goalId,
  }) => ledger().listGoalAllocations(goalId: goalId);

  @override
  Future<ZenResult<GoalAllocation>> getGoalAllocation(String id) =>
      ledger().getGoalAllocation(id);

  @override
  Future<ZenResult<ListGoalEnvelopesResponse>> listGoalEnvelopes() =>
      ledger().listGoalEnvelopes();

  @override
  Future<ZenResult<SettledFigures<GetFreeMoneyResponse>>>
  getFreeMoney() async => _figures(await ledger().freeMoney());

  // ── Budgets and carry-over resets (unit 6a, ADR-116) ────────────────────────────────────────

  @override
  Future<ZenResult<ListBudgetsResponse>> listBudgets({
    String? month,
    String? categoryId,
  }) => ledger().listBudgets(month: month, categoryId: categoryId);

  @override
  Future<ZenResult<SettledFigures<BudgetSummaryResponse>>> getBudgetSummary({
    required String month,
    required String currency,
  }) async => _figures(await ledger().budgetSummary(month, currency));

  @override
  Future<ZenResult<Budget>> setBudget({
    required String categoryId,
    required String month,
    required String currency,
    required SetBudgetRequest request,
  }) async => switch (await ledger().setBudget(
    categoryId,
    month,
    currency,
    request.amountMinor.toInt(),
  )) {
    ZenSuccess(:final data) => ZenResult.ok(data.budget),
    ZenFailure(:final error) => ZenResult.err(error),
  };

  @override
  Future<ZenResult<Budget>> deleteBudget({
    required String categoryId,
    required String month,
    required String currency,
  }) async => _empty(
    await ledger().deleteBudget(categoryId, month, currency),
    Budget.new,
  );

  @override
  Future<ZenResult<BudgetCarryOverReset>> resetBudgetCarryOver(
    ResetBudgetCarryOverRequest request,
  ) => ledger().resetBudgetCarryOver(request);

  @override
  Future<ZenResult<ListBudgetCarryOverResetsResponse>>
  listBudgetCarryOverResets({String? categoryId, String? currency}) =>
      ledger().listBudgetResets(categoryId: categoryId, currency: currency);

  @override
  Future<ZenResult<BudgetCarryOverReset>> revokeBudgetCarryOverReset(
    String id,
  ) => ledger().revokeBudgetReset(id);

  // ── Plans, occurrences and reminders (unit 6b, ADR-119) ────────────────────────────────────
  //
  // An occurrence list leaves out a plan two devices disagree about (`Settled.unsettled`); the conflict
  // banner names it. The planned cash flow is expected money, not a balance, and does not yet carry
  // the count beside it (ADR-121, "Not verified").

  @override
  Future<ZenResult<ListPlansResponse>> listPlans() => plans().listPlans();

  @override
  Future<ZenResult<Plan>> createPlan(CreatePlanRequest request) =>
      plans().createPlan(request);

  @override
  Future<ZenResult<Plan>> updatePlan(String id, UpdatePlanRequest request) =>
      plans().replacePlan(id, request);

  @override
  Future<ZenResult<Plan>> deletePlan(String id) async =>
      _empty(await plans().deletePlan(id), Plan.new);

  @override
  Future<ZenResult<ListOccurrencesResponse>> listUpcomingOccurrences({
    int? days,
  }) async => _value(await plans().upcoming(days: days, asOf: now()));

  @override
  Future<ZenResult<ListOccurrencesResponse>> listOverdueOccurrences() async =>
      _value(await plans().overdue(asOf: now()));

  @override
  Future<ZenResult<PlanOccurrence>> skipOccurrence(String id) =>
      plans().skip(id, asOf: now());

  @override
  Future<ZenResult<PlanOccurrence>> restoreOccurrence(String id) =>
      plans().restore(id, asOf: now());

  @override
  Future<ZenResult<ConfirmOccurrenceResponse>> confirmOccurrence(
    String id, [
    ConfirmOccurrenceRequest? request,
  ]) => plans().confirm(id, request ?? ConfirmOccurrenceRequest(), asOf: now());

  @override
  Future<ZenResult<ListRemindersResponse>> listReminders() async =>
      _value(await plans().reminders(asOf: now()));

  @override
  Future<ZenResult<DueReminder>> markReminderRead(String occurrenceId) =>
      plans().markRead(occurrenceId, asOf: now());

  @override
  Future<ZenResult<DueReminder>> markReminderUnread(String occurrenceId) =>
      plans().markUnread(occurrenceId, asOf: now());

  @override
  Future<ZenResult<ListRemindersResponse>> markAllRemindersRead() async =>
      _value(await plans().markAllRead(asOf: now()));

  // ── Analytics (unit 7, ADR-118) ─────────────────────────────────────────────────────────────

  /// What the chart leaves out (a record two devices disagree about) travels with it (ADR-118).
  @override
  Future<ZenResult<SettledFigures<SpendByCategoryResponse>>> spendByCategory({
    required String currency,
    required int year,
    int? month,
  }) async => _figures(
    await analytics().spendByCategory(
      currency: currency,
      year: year,
      month: month,
    ),
  );

  @override
  Future<ZenResult<SettledFigures<SpendByPeriodResponse>>> spendByPeriod({
    required String currency,
    required String granularity,
    required int count,
  }) async => _figures(
    await analytics().spendByPeriod(
      currency: currency,
      granularity: granularity,
      count: count,
    ),
  );

  // ── Helpers ─────────────────────────────────────────────────────────────────────────────────

  /// A ledger figure with what it leaves out, as the screens read it: the count of distinct entries.
  static ZenResult<SettledFigures<T>> _figures<T>(
    ZenResult<Settled<T>> result,
  ) => switch (result) {
    ZenSuccess(:final data) => ZenResult.ok(
      SettledFigures(
        data.value,
        {for (final ids in data.unsettled.values) ...ids}.length,
      ),
    ),
    ZenFailure(:final error) => ZenResult.err(error),
  };

  static ZenResult<T> _value<T>(ZenResult<Settled<T>> result) =>
      switch (result) {
        ZenSuccess(:final data) => ZenResult.ok(data.value),
        ZenFailure(:final error) => ZenResult.err(error),
      };

  static ZenResult<T> _empty<T>(ZenResult<void> result, T Function() empty) =>
      switch (result) {
        ZenSuccess() => ZenResult.ok(empty()),
        ZenFailure(:final error) => ZenResult.err(error),
      };
}
