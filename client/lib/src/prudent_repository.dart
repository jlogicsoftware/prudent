import 'package:zen_core/zen_core.dart' show ZenResult;
import 'package:zen_transport/zen_transport.dart';

import 'generated/prudent/v1/accounts.pb.dart';
import 'generated/prudent/v1/categories.pb.dart';
import 'generated/prudent/v1/records.pb.dart';
import 'generated/prudent/v1/settings.pb.dart';

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
  static const String _accountsPath = '/api/v1/accounts';
  static const String _categoriesPath = '/api/v1/categories';
  static const String _settingsPath = '/api/v1/settings';

  // --- Records --------------------------------------------------------------------------------

  Future<ZenResult<ListRecordsResponse>> listRecords() =>
      _client.get<ListRecordsResponse>(ListRecordsResponse.new, _recordsPath);

  Future<ZenResult<Record>> createRecord(CreateRecordRequest request) =>
      _client.post<Record>(Record.new, _recordsPath, body: request);

  Future<ZenResult<Record>> updateRecord(String id, UpdateRecordRequest request) =>
      _client.put<Record>(Record.new, '$_recordsPath/$id', body: request);

  Future<ZenResult<Record>> deleteRecord(String id) =>
      _client.delete<Record>(Record.new, '$_recordsPath/$id');

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

  // --- Settings -----------------------------------------------------------------------------------

  Future<ZenResult<Settings>> getSettings() =>
      _client.get<Settings>(Settings.new, _settingsPath);

  Future<ZenResult<Settings>> updateSettings(UpdateSettingsRequest request) =>
      _client.put<Settings>(Settings.new, _settingsPath, body: request);
}
