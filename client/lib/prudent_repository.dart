import 'package:zen_core/zen_core.dart' show ZenResult;
import 'package:zen_transport/zen_transport.dart';

import 'generated/prudent/v1/accounts.pb.dart';
import 'generated/prudent/v1/analytics.pb.dart';
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
  static const String _plansPath = '/api/v1/plans';
  static const String _occurrencesPath = '/api/v1/occurrences';
  static const String _spendByCategoryPath = '/api/v1/analytics/spend-by-category';
  static const String _spendByPeriodPath = '/api/v1/analytics/spend-by-period';

  // --- Records --------------------------------------------------------------------------------

  /// [filter] is optional and independently composable per criterion (jlogicsoftware/prudent#52);
  /// omitting it, or passing [RecordFilter.empty], is exactly today's unfiltered call.
  Future<ZenResult<ListRecordsResponse>> listRecords({RecordFilter? filter}) {
    final query = filter?.toQueryParameters() ?? const <String, String>{};
    final path = query.isEmpty ? _recordsPath : '$_recordsPath?${_encodeQuery(query)}';
    return _client.get<ListRecordsResponse>(ListRecordsResponse.new, path);
  }

  Future<ZenResult<Record>> createRecord(CreateRecordRequest request) =>
      _client.post<Record>(Record.new, _recordsPath, body: request);

  Future<ZenResult<Record>> updateRecord(String id, UpdateRecordRequest request) =>
      _client.put<Record>(Record.new, '$_recordsPath/$id', body: request);

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

  Future<ZenResult<ListAccountsResponse>> listAccounts() =>
      _client.get<ListAccountsResponse>(ListAccountsResponse.new, _accountsPath);

  Future<ZenResult<Account>> createAccount(CreateAccountRequest request) =>
      _client.post<Account>(Account.new, _accountsPath, body: request);

  Future<ZenResult<Account>> updateAccount(String id, UpdateAccountRequest request) =>
      _client.put<Account>(Account.new, '$_accountsPath/$id', body: request);

  Future<ZenResult<Account>> deleteAccount(String id) =>
      _client.delete<Account>(Account.new, '$_accountsPath/$id');

  // --- Categories -------------------------------------------------------------------------------

  Future<ZenResult<ListCategoriesResponse>> listCategories() =>
      _client.get<ListCategoriesResponse>(ListCategoriesResponse.new, _categoriesPath);

  Future<ZenResult<Category>> createCategory(CreateCategoryRequest request) =>
      _client.post<Category>(Category.new, _categoriesPath, body: request);

  Future<ZenResult<Category>> updateCategory(String id, UpdateCategoryRequest request) =>
      _client.put<Category>(Category.new, '$_categoriesPath/$id', body: request);

  Future<ZenResult<Category>> deleteCategory(String id) =>
      _client.delete<Category>(Category.new, '$_categoriesPath/$id');

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
  Future<ZenResult<ListOccurrencesResponse>> listUpcomingOccurrences({int? days}) {
    final path = days == null
        ? '$_occurrencesPath/upcoming'
        : '$_occurrencesPath/upcoming?${_encodeQuery({'days': '$days'})}';
    return _client.get<ListOccurrencesResponse>(ListOccurrencesResponse.new, path);
  }

  /// Occurrences still planned whose date has passed in their plan's time zone.
  Future<ZenResult<ListOccurrencesResponse>> listOverdueOccurrences() =>
      _client.get<ListOccurrencesResponse>(
        ListOccurrencesResponse.new,
        '$_occurrencesPath/overdue',
      );

  /// The user decided this occurrence will not happen. Refused (409) unless it is planned.
  Future<ZenResult<PlanOccurrence>> skipOccurrence(String id) =>
      _client.post<PlanOccurrence>(PlanOccurrence.new, '$_occurrencesPath/$id/skip');

  /// Reopens a skipped occurrence as planned. Refused (409) unless it is skipped.
  Future<ZenResult<PlanOccurrence>> restoreOccurrence(String id) =>
      _client.post<PlanOccurrence>(PlanOccurrence.new, '$_occurrencesPath/$id/restore');

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
    final query = {'currency': currency, 'granularity': granularity, 'count': '$count'};
    return _client.get<SpendByPeriodResponse>(
      SpendByPeriodResponse.new,
      '$_spendByPeriodPath?${_encodeQuery(query)}',
    );
  }

  static String _encodeQuery(Map<String, String> query) => query.entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
}
