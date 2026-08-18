import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

import 'generated/prudent/v1/accounts.pb.dart';
import 'generated/prudent/v1/categories.pb.dart';
import 'generated/prudent/v1/records.pb.dart';
import 'generated/prudent/v1/settings.pb.dart';
import 'prudent_repository.dart';

/// The server client. Overridden in [ProviderScope] with an instance sharing the session
/// http.Client (see main.dart), so it must be provided by the app.
final prudentRepositoryProvider = Provider<PrudentRepository>((ref) {
  throw UnimplementedError('prudentRepositoryProvider must be overridden');
});

/// The languages Prudent ships — the application's decision (jZen ADR-044), not a ceiling
/// inherited from `ZenLocales.shipped` (`{en, uk}`). Framework screens degrade to English for
/// `pl`, and Prudent supplies its own delegates so its own screens do not have to.
const List<String> prudentSupportedLocales = ['en', 'uk', 'pl'];

/// The current UI locale, one of [prudentSupportedLocales].
///
/// Two jobs, kept on one provider so a language switch is honest end to end: it is
/// `MaterialApp.locale`, so every generated accessor re-renders, and its language tag is what
/// `ZenClient` sends as `Accept-Language` on every request (ADR-007) — including
/// `POST /auth/register`, where the server seeds `users.language`, which is Prudent's only later
/// source for a localized email.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale(ZenLocales.fallback);

  void setLocale(Locale locale) => state = locale;
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

// ---------------------------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------------------------

class RecordsNotifier extends AsyncNotifier<List<Record>> {
  PrudentRepository get _repository => ref.read(prudentRepositoryProvider);

  @override
  Future<List<Record>> build() async {
    final result = await _repository.listRecords();
    return result.fold((response) => response.records, (error) => throw error);
  }

  Future<void> addRecord(CreateRecordRequest request) async {
    final result = await _repository.createRecord(request);
    final record = result.fold((r) => r, (error) => throw error);
    state = AsyncValue.data([...?state.value, record]);
  }

  Future<void> editRecord(String id, UpdateRecordRequest request) async {
    final result = await _repository.updateRecord(id, request);
    final updated = result.fold((r) => r, (error) => throw error);
    state = AsyncValue.data([
      for (final r in state.value ?? const <Record>[]) if (r.id == id) updated else r,
    ]);
  }

  /// Deletes immediately; the caller re-creates on undo (a new server-minted id — there is no
  /// deferred/pending-delete state to keep honest against a server that might already have acted).
  Future<void> removeRecord(String id) async {
    final result = await _repository.deleteRecord(id);
    result.fold((_) => null, (error) => throw error);
    state = AsyncValue.data([
      for (final r in state.value ?? const <Record>[]) if (r.id != id) r,
    ]);
  }
}

final recordsProvider = AsyncNotifierProvider<RecordsNotifier, List<Record>>(RecordsNotifier.new);

// ---------------------------------------------------------------------------------------------
// Accounts
// ---------------------------------------------------------------------------------------------

class AccountsNotifier extends AsyncNotifier<List<Account>> {
  PrudentRepository get _repository => ref.read(prudentRepositoryProvider);

  @override
  Future<List<Account>> build() async {
    final result = await _repository.listAccounts();
    return result.fold((response) => response.accounts, (error) => throw error);
  }

  Future<void> addAccount(CreateAccountRequest request) async {
    final result = await _repository.createAccount(request);
    final account = result.fold((a) => a, (error) => throw error);
    state = AsyncValue.data([...?state.value, account]);
  }

  Future<void> editAccount(String id, UpdateAccountRequest request) async {
    final result = await _repository.updateAccount(id, request);
    final updated = result.fold((a) => a, (error) => throw error);
    state = AsyncValue.data([
      for (final a in state.value ?? const <Account>[]) if (a.id == id) updated else a,
    ]);
  }

  Future<void> removeAccount(String id) async {
    final result = await _repository.deleteAccount(id);
    result.fold((_) => null, (error) => throw error);
    state = AsyncValue.data([
      for (final a in state.value ?? const <Account>[]) if (a.id != id) a,
    ]);
  }
}

final accountsProvider = AsyncNotifierProvider<AccountsNotifier, List<Account>>(
  AccountsNotifier.new,
);

// ---------------------------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------------------------

class CategoriesNotifier extends AsyncNotifier<List<Category>> {
  PrudentRepository get _repository => ref.read(prudentRepositoryProvider);

  @override
  Future<List<Category>> build() async {
    final result = await _repository.listCategories();
    return result.fold((response) => response.categories, (error) => throw error);
  }

  Future<void> addCategory(CreateCategoryRequest request) async {
    final result = await _repository.createCategory(request);
    final category = result.fold((c) => c, (error) => throw error);
    state = AsyncValue.data([...?state.value, category]);
  }

  Future<void> editCategory(String id, UpdateCategoryRequest request) async {
    final result = await _repository.updateCategory(id, request);
    final updated = result.fold((c) => c, (error) => throw error);
    state = AsyncValue.data([
      for (final c in state.value ?? const <Category>[]) if (c.id == id) updated else c,
    ]);
  }

  Future<void> removeCategory(String id) async {
    final result = await _repository.deleteCategory(id);
    result.fold((_) => null, (error) => throw error);
    state = AsyncValue.data([
      for (final c in state.value ?? const <Category>[]) if (c.id != id) c,
    ]);
  }
}

final categoriesProvider = AsyncNotifierProvider<CategoriesNotifier, List<Category>>(
  CategoriesNotifier.new,
);

// ---------------------------------------------------------------------------------------------
// Settings — a singleton, not a collection (settings.proto)
// ---------------------------------------------------------------------------------------------

class SettingsNotifier extends AsyncNotifier<Settings> {
  PrudentRepository get _repository => ref.read(prudentRepositoryProvider);

  @override
  Future<Settings> build() async {
    final result = await _repository.getSettings();
    return result.fold((settings) => settings, (error) => throw error);
  }

  Future<void> updateSettings(UpdateSettingsRequest request) async {
    final result = await _repository.updateSettings(request);
    final settings = result.fold((s) => s, (error) => throw error);
    state = AsyncValue.data(settings);
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);
