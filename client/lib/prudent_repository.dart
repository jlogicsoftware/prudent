import 'package:zen_core/zen_core.dart' show ZenResult;
import 'package:zen_transport/zen_transport.dart';

import 'generated/prudent/v1/accounts.pb.dart';
import 'generated/prudent/v1/analytics.pb.dart';
import 'generated/prudent/v1/budgets.pb.dart';
import 'generated/prudent/v1/categories.pb.dart';
import 'generated/prudent/v1/plans.pb.dart';
import 'generated/prudent/v1/records.pb.dart';
import 'generated/prudent/v1/settings.pb.dart';
import 'record/record_filter.dart';

/// Prudent's server surface, typed over [ZenClient]. Every call returns [ZenResult] — success or
/// a [ZenError] the caller can render — never a bare value and never a null standing in for
/// "the server said nothing" (docs/DECISIONS.md ADR-004, "the client talks to one server").
///
/// One [ZenClient] is enough here: unlike the demo, Prudent never forces a transport mode per
/// call, so the client negotiates its own default rather than the app pinning JSON/Protobuf
/// instances side by side.
class PrudentRepository {
  PrudentRepository({required ZenClient client}) : _client = client;

  final ZenClient _client;

  static const String _recordsPath = '/api/v1/records';
  static const String _transfersPath = '/api/v1/transfers';
  static const String _correctionsPath = '/api/v1/corrections';
  static const String _accountsPath = '/api/v1/accounts';
  static const String _categoriesPath = '/api/v1/categories';
  static const String _settingsPath = '/api/v1/settings';
  static const String _budgetsPath = '/api/v1/budgets';
  static const String _carryOverResetsPath = '/api/v1/budget-carry-over-resets';
  static const String _plansPath = '/api/v1/plans';
  static const String _occurrencesPath = '/api/v1/occurrences';
  static const String _spendByCategoryPath =
      '/api/v1/analytics/spend-by-category';
  static const String _spendByPeriodPath = '/api/v1/analytics/spend-by-period';

  // --- Records --------------------------------------------------------------------------------

  /// [filter] is optional and independently composable per criterion (jlogicsoftware/prudent#52);
  /// omitting it, or passing [RecordFilter.empty], is exactly today's unfiltered call.
  Future<ZenResult<ListRecordsResponse>> listRecords({RecordFilter? filter}) {
    final query = filter?.toQueryParameters() ?? const <String, String>{};
    final path =
        query.isEmpty ? _recordsPath : '$_recordsPath?${_encodeQuery(query)}';
    return _client.get<ListRecordsResponse>(ListRecordsResponse.new, path);
  }

  Future<ZenResult<Record>> createRecord(CreateRecordRequest request) =>
      _client.post<Record>(Record.new, _recordsPath, body: request);

  Future<ZenResult<Record>> updateRecord(
    String id,
    UpdateRecordRequest request,
  ) => _client.put<Record>(Record.new, '$_recordsPath/$id', body: request);

  Future<ZenResult<Record>> deleteRecord(String id) =>
      _client.delete<Record>(Record.new, '$_recordsPath/$id');

  // --- Transfers (same currency only, jlogicsoftware/prudent#32) ------------------------------

  Future<ZenResult<Transfer>> createTransfer(CreateTransferRequest request) =>
      _client.post<Transfer>(Transfer.new, _transfersPath, body: request);

  Future<ZenResult<Transfer>> deleteTransfer(String transferId) =>
      _client.delete<Transfer>(Transfer.new, '$_transfersPath/$transferId');

  // --- Balance corrections (M1, jlogicsoftware/prudent#53) -------------------------------------

  Future<ZenResult<Record>> createCorrection(CreateCorrectionRequest request) =>
      _client.post<Record>(Record.new, _correctionsPath, body: request);

  Future<ZenResult<Record>> deleteCorrection(String id) =>
      _client.delete<Record>(Record.new, '$_correctionsPath/$id');

  // --- Accounts ---------------------------------------------------------------------------------

  Future<ZenResult<ListAccountsResponse>> listAccounts() => _client
      .get<ListAccountsResponse>(ListAccountsResponse.new, _accountsPath);

  Future<ZenResult<Account>> createAccount(CreateAccountRequest request) =>
      _client.post<Account>(Account.new, _accountsPath, body: request);

  Future<ZenResult<Account>> updateAccount(
    String id,
    UpdateAccountRequest request,
  ) => _client.put<Account>(Account.new, '$_accountsPath/$id', body: request);

  Future<ZenResult<Account>> deleteAccount(String id) =>
      _client.delete<Account>(Account.new, '$_accountsPath/$id');

  // --- Categories -------------------------------------------------------------------------------

  Future<ZenResult<ListCategoriesResponse>> listCategories() => _client
      .get<ListCategoriesResponse>(ListCategoriesResponse.new, _categoriesPath);

  Future<ZenResult<Category>> createCategory(CreateCategoryRequest request) =>
      _client.post<Category>(Category.new, _categoriesPath, body: request);

  Future<ZenResult<Category>> updateCategory(
    String id,
    UpdateCategoryRequest request,
  ) => _client.put<Category>(
    Category.new,
    '$_categoriesPath/$id',
    body: request,
  );

  /// Refused (409) while anything — a record, plan, budget or carry-over reset — still points at
  /// the category; [archiveCategory] is how a used category is taken out of use.
  Future<ZenResult<Category>> deleteCategory(String id) =>
      _client.delete<Category>(Category.new, '$_categoriesPath/$id');

  /// Retires a category (M3, jlogicsoftware/prudent#62): it stays listed and keeps all its history,
  /// and accepts no new record, plan or budget until [restoreCategory]. Refused (409) if it is
  /// already archived.
  Future<ZenResult<Category>> archiveCategory(String id) =>
      _client.post<Category>(Category.new, '$_categoriesPath/$id/archive');

  /// Returns an archived category to use. Refused (409) if it is not archived.
  Future<ZenResult<Category>> restoreCategory(String id) =>
      _client.post<Category>(Category.new, '$_categoriesPath/$id/restore');

  // --- Budgets (M3, jlogicsoftware/prudent#36) — the amount that may be spent, never a transaction

  /// The user's budgets, optionally narrowed to one [month] (`YYYY-MM`) and/or one [categoryId].
  Future<ZenResult<ListBudgetsResponse>> listBudgets({
    String? month,
    String? categoryId,
  }) {
    final query = <String, String>{
      if (month != null) 'month': month,
      if (categoryId != null) 'categoryId': categoryId,
    };
    final path =
        query.isEmpty ? _budgetsPath : '$_budgetsPath?${_encodeQuery(query)}';
    return _client.get<ListBudgetsResponse>(ListBudgetsResponse.new, path);
  }

  /// Plan, actual and remaining amount of every category budgeted for [month] (`YYYY-MM`) in
  /// [currency] (M3, jlogicsoftware/prudent#59). Both are required and the currency is never
  /// inferred: a summary is for one month in one currency and is never summed across currencies.
  /// Actual is net spending from posted records, refunds included.
  Future<ZenResult<BudgetSummaryResponse>> getBudgetSummary({
    required String month,
    required String currency,
  }) => _client.get<BudgetSummaryResponse>(
    BudgetSummaryResponse.new,
    '$_budgetsPath/summary?${_encodeQuery({'month': month, 'currency': currency})}',
  );

  /// Sets the budget for one category, [month] (`YYYY-MM`) and [currency], creating it or replacing
  /// its amount — a slot holds at most one. The amount must be positive; to have no budget for the
  /// slot, [deleteBudget].
  Future<ZenResult<Budget>> setBudget({
    required String categoryId,
    required String month,
    required String currency,
    required SetBudgetRequest request,
  }) => _client.put<Budget>(
    Budget.new,
    _budgetPath(categoryId, month, currency),
    body: request,
  );

  /// Removes the budget for one category, [month] and [currency]. Refused (404) if there is none.
  Future<ZenResult<Budget>> deleteBudget({
    required String categoryId,
    required String month,
    required String currency,
  }) => _client.delete<Budget>(
    Budget.new,
    _budgetPath(categoryId, month, currency),
  );

  /// Resets one category's carry-over in [currency] from [month] (`YYYY-MM`) onward (M3,
  /// jlogicsoftware/prudent#61): carry-over into that month becomes zero. No budget is deleted and no
  /// earlier month changes. The answer is the audit entry, including what was discarded. Refused
  /// (409) if that slot already has a reset in effect.
  Future<ZenResult<BudgetCarryOverReset>> resetBudgetCarryOver(
    ResetBudgetCarryOverRequest request,
  ) => _client.post<BudgetCarryOverReset>(
    BudgetCarryOverReset.new,
    _carryOverResetsPath,
    body: request,
  );

  /// The whole reset history, revoked entries included, newest first, optionally narrowed to one
  /// [categoryId] and/or [currency].
  Future<ZenResult<ListBudgetCarryOverResetsResponse>>
  listBudgetCarryOverResets({String? categoryId, String? currency}) {
    final query = <String, String>{
      if (categoryId != null) 'categoryId': categoryId,
      if (currency != null) 'currency': currency,
    };
    final path =
        query.isEmpty
            ? _carryOverResetsPath
            : '$_carryOverResetsPath?${_encodeQuery(query)}';
    return _client.get<ListBudgetCarryOverResetsResponse>(
      ListBudgetCarryOverResetsResponse.new,
      path,
    );
  }

  /// Takes a reset back. The entry stays in the history, marked revoked with who and when, and
  /// the carry-over it bounded is counted in full again. Refused (409) if already revoked.
  Future<ZenResult<BudgetCarryOverReset>> revokeBudgetCarryOverReset(
    String id,
  ) => _client.post<BudgetCarryOverReset>(
    BudgetCarryOverReset.new,
    '$_carryOverResetsPath/${Uri.encodeComponent(id)}/revoke',
  );

  static String _budgetPath(String categoryId, String month, String currency) =>
      '$_budgetsPath/${Uri.encodeComponent(categoryId)}/${Uri.encodeComponent(month)}'
      '/${Uri.encodeComponent(currency)}';

  // --- Plans (M2, jlogicsoftware/prudent#34) — expected money, never a transaction ------------

  Future<ZenResult<ListPlansResponse>> listPlans() =>
      _client.get<ListPlansResponse>(ListPlansResponse.new, _plansPath);

  Future<ZenResult<Plan>> createPlan(CreatePlanRequest request) =>
      _client.post<Plan>(Plan.new, _plansPath, body: request);

  Future<ZenResult<Plan>> updatePlan(String id, UpdatePlanRequest request) =>
      _client.put<Plan>(Plan.new, '$_plansPath/$id', body: request);

  Future<ZenResult<Plan>> deletePlan(String id) =>
      _client.delete<Plan>(Plan.new, '$_plansPath/$id');

  // --- Planned occurrences (M2, jlogicsoftware/prudent#56) — expected, not yet a transaction ---

  /// Occurrences from today (in each plan's time zone) to [days] ahead, in any state, so what was
  /// skipped or confirmed early stays visible. The server defaults to 30 and accepts 1-366.
  Future<ZenResult<ListOccurrencesResponse>> listUpcomingOccurrences({
    int? days,
  }) {
    final path =
        days == null
            ? '$_occurrencesPath/upcoming'
            : '$_occurrencesPath/upcoming?${_encodeQuery({'days': '$days'})}';
    return _client.get<ListOccurrencesResponse>(
      ListOccurrencesResponse.new,
      path,
    );
  }

  /// Occurrences still planned whose date has passed in their plan's time zone.
  Future<ZenResult<ListOccurrencesResponse>> listOverdueOccurrences() =>
      _client.get<ListOccurrencesResponse>(
        ListOccurrencesResponse.new,
        '$_occurrencesPath/overdue',
      );

  /// The user decided this occurrence will not happen. Refused (409) unless it is planned.
  Future<ZenResult<PlanOccurrence>> skipOccurrence(String id) => _client
      .post<PlanOccurrence>(PlanOccurrence.new, '$_occurrencesPath/$id/skip');

  /// Reopens a skipped occurrence as planned. Refused (409) unless it is skipped.
  Future<ZenResult<PlanOccurrence>> restoreOccurrence(String id) =>
      _client.post<PlanOccurrence>(
        PlanOccurrence.new,
        '$_occurrencesPath/$id/restore',
      );

  /// Says this occurrence happened, and creates the actual transaction (M2,
  /// jlogicsoftware/prudent#57). Every field of [request] is optional and an absent one takes the
  /// plan's own value, so the default request confirms it exactly as planned; what is set replaces
  /// it for this transaction only. Refused (409) unless the occurrence is planned or overdue, so a
  /// double tap cannot post twice. The result carries the completed occurrence and the record.
  Future<ZenResult<ConfirmOccurrenceResponse>> confirmOccurrence(
    String id, [
    ConfirmOccurrenceRequest? request,
  ]) => _client.post<ConfirmOccurrenceResponse>(
    ConfirmOccurrenceResponse.new,
    '$_occurrencesPath/$id/confirm',
    body: request ?? ConfirmOccurrenceRequest(),
  );

  // --- Settings -----------------------------------------------------------------------------------

  Future<ZenResult<Settings>> getSettings() =>
      _client.get<Settings>(Settings.new, _settingsPath);

  Future<ZenResult<Settings>> updateSettings(UpdateSettingsRequest request) =>
      _client.put<Settings>(Settings.new, _settingsPath, body: request);

  // --- Analytics — read-only, always scoped to one currency (analytics.proto) --------------------

  /// [year] required; [month] optional (1-12) — a single month, or the whole year when omitted.
  Future<ZenResult<SpendByCategoryResponse>> spendByCategory({
    required String currency,
    required int year,
    int? month,
  }) {
    final query = {
      'currency': currency,
      'year': '$year',
      if (month != null) 'month': '$month',
    };
    return _client.get<SpendByCategoryResponse>(
      SpendByCategoryResponse.new,
      '$_spendByCategoryPath?${_encodeQuery(query)}',
    );
  }

  /// [granularity] is `MONTH` or `YEAR`; [count] is the number of trailing buckets (1-60), ending
  /// at the current period as the server resolves it in UTC.
  Future<ZenResult<SpendByPeriodResponse>> spendByPeriod({
    required String currency,
    required String granularity,
    required int count,
  }) {
    final query = {
      'currency': currency,
      'granularity': granularity,
      'count': '$count',
    };
    return _client.get<SpendByPeriodResponse>(
      SpendByPeriodResponse.new,
      '$_spendByPeriodPath?${_encodeQuery(query)}',
    );
  }

  static String _encodeQuery(Map<String, String> query) => query.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');
}
