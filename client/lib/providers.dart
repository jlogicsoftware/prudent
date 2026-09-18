import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

import 'generated/prudent/v1/accounts.pb.dart';
import 'generated/prudent/v1/analytics.pb.dart';
import 'generated/prudent/v1/categories.pb.dart';
import 'generated/prudent/v1/records.pb.dart';
import 'generated/prudent/v1/settings.pb.dart';
import 'prudent_repository.dart';
import 'record/record_filter.dart';

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

/// The records list's active filter (jlogicsoftware/prudent#52). A plain [Notifier] rather than a
/// bare [StateProvider] only so [clear] reads as a named action at call sites (the records filter
/// sheet's "Clear all").
class RecordFilterNotifier extends Notifier<RecordFilter> {
  @override
  RecordFilter build() => RecordFilter.empty;

  void apply(RecordFilter filter) => state = filter;

  /// Resets every criterion. Re-fetching with no filter restores the full list — nothing is
  /// mutated or deleted, so no data is lost by clearing.
  void clear() => state = RecordFilter.empty;
}

final recordFilterProvider = NotifierProvider<RecordFilterNotifier, RecordFilter>(
  RecordFilterNotifier.new,
);

class RecordsNotifier extends AsyncNotifier<List<Record>> {
  PrudentRepository get _repository => ref.read(prudentRepositoryProvider);

  @override
  Future<List<Record>> build() async {
    final filter = ref.watch(recordFilterProvider);
    final result = await _repository.listRecords(filter: filter);
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

  /// Creates a same-currency transfer (jlogicsoftware/prudent#32) and adds both legs to state.
  ///
  /// Also invalidates [accountsProvider]: a transfer moves two accounts' DERIVED balances
  /// (ADR-014) without ever touching an Account row, so re-fetching accounts is the only way the
  /// balance shown anywhere picks up the move.
  Future<Transfer> addTransfer(CreateTransferRequest request) async {
    final result = await _repository.createTransfer(request);
    final transfer = result.fold((t) => t, (error) => throw error);
    state = AsyncValue.data([...?state.value, transfer.fromRecord, transfer.toRecord]);
    ref.invalidate(accountsProvider);
    return transfer;
  }

  /// Deletes both legs of a transfer by their shared id.
  Future<void> removeTransfer(String transferId) async {
    final result = await _repository.deleteTransfer(transferId);
    result.fold((_) => null, (error) => throw error);
    state = AsyncValue.data([
      for (final r in state.value ?? const <Record>[]) if (r.transferId != transferId) r,
    ]);
    ref.invalidate(accountsProvider);
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

// ---------------------------------------------------------------------------------------------
// Analytics — read-only, always scoped to one currency (analytics.proto, ADR-014)
// ---------------------------------------------------------------------------------------------

/// The set of currencies across every account the user holds, main currency first when it is one
/// of them — the options a currency picker on the chart/analytics screens offers. Never a blended
/// list that pretends currencies can be summed; this is only ever used to pick ONE to view.
final analyticsCurrenciesProvider = Provider<List<String>>((ref) {
  final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
  final mainCurrency = ref.watch(settingsProvider).value?.mainCurrency;
  final currencies = <String>{
    for (final account in accounts)
      for (final balance in account.balances) balance.currency,
  };
  final ordered = currencies.toList()..sort();
  if (mainCurrency != null && ordered.remove(mainCurrency)) {
    ordered.insert(0, mainCurrency);
  }
  return ordered;
});

@immutable
class SpendByCategoryParams {
  const SpendByCategoryParams({required this.currency, required this.year, this.month});

  final String currency;
  final int year;
  final int? month;

  @override
  bool operator ==(Object other) =>
      other is SpendByCategoryParams &&
      other.currency == currency &&
      other.year == year &&
      other.month == month;

  @override
  int get hashCode => Object.hash(currency, year, month);
}

final spendByCategoryProvider =
    FutureProvider.autoDispose.family<SpendByCategoryResponse, SpendByCategoryParams>((
      ref,
      params,
    ) async {
      final repository = ref.watch(prudentRepositoryProvider);
      final result = await repository.spendByCategory(
        currency: params.currency,
        year: params.year,
        month: params.month,
      );
      return result.fold((response) => response, (error) => throw error);
    });

@immutable
class SpendByPeriodParams {
  const SpendByPeriodParams({required this.currency, required this.granularity, required this.count});

  final String currency;
  final String granularity;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is SpendByPeriodParams &&
      other.currency == currency &&
      other.granularity == granularity &&
      other.count == count;

  @override
  int get hashCode => Object.hash(currency, granularity, count);
}

final spendByPeriodProvider =
    FutureProvider.autoDispose.family<SpendByPeriodResponse, SpendByPeriodParams>((
      ref,
      params,
    ) async {
      final repository = ref.watch(prudentRepositoryProvider);
      final result = await repository.spendByPeriod(
        currency: params.currency,
        granularity: params.granularity,
        count: params.count,
      );
      return result.fold((response) => response, (error) => throw error);
    });
