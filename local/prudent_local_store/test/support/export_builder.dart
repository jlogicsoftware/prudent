import 'package:fixnum/fixnum.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/budgets.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goal_allocations.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/privacy.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/settings.pb.dart' as wire;

/// A synthetic privacy export shaped as the server writes it (ADR-088: made-up names and amounts):
/// ids in the server's form (`UUID.toString()`), each account's balances the current ones — the
/// opening given here plus every record — and a transfer as two leg records. The real server's
/// export is moved in by the parity suite's `move_in_test`; this one lets the store's own tests
/// break an export on purpose.
final class ExportBuilder {
  int _next = 0;
  final wire.DataExport _export = wire.DataExport(
    formatVersion: 1,
    exportedAtMs: Int64(1794830400000),
    profile: wire.ExportProfile(email: 'someone@example.com'),
    settings: wire.Settings(mainCurrency: 'PLN'),
  );
  final Map<String, Map<String, int>> _openings = {};
  final Map<String, wire.Account> _accounts = {};

  /// A new id in the server's form, deterministic per builder.
  String id() => '00000000-0000-4000-8000-${(++_next).toString().padLeft(12, '0')}';

  /// The server form of a Local id (8-4-4-4-12).
  static String serverForm(String localId) =>
      '${localId.substring(0, 8)}-${localId.substring(8, 12)}-${localId.substring(12, 16)}-'
      '${localId.substring(16, 20)}-${localId.substring(20)}';

  /// The Local form of a server id.
  static String local(String serverId) => serverId.replaceAll('-', '');

  String account(
    String name,
    Map<String, int> openings, {
    bool isDefault = false,
    bool eligibleForGoals = false,
    String? accountNumber,
    String? id,
  }) {
    final accountId = id ?? this.id();
    final account = wire.Account(
      id: accountId,
      name: name,
      type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
      isActive: true,
      includeInTotal: true,
      includeInOverview: true,
    );
    if (isDefault) account.isDefault = true;
    if (eligibleForGoals) account.eligibleForGoals = true;
    if (accountNumber != null) account.accountNumber = accountNumber;
    _accounts[accountId] = account;
    _openings[accountId] = Map.of(openings);
    _export.accounts.add(account);
    return accountId;
  }

  String category(String title, {wire.CategoryKind? kind, bool archived = false}) {
    final category = wire.Category(id: id(), title: title, iconKey: 'food');
    if (kind != null) category.kind = kind;
    if (archived) category.archived = true;
    _export.categories.add(category);
    return category.id;
  }

  wire.Record record(
    String account,
    String currency,
    int amount, {
    String? category,
    String date = '2026-10-01',
    String title = 'Bread',
  }) {
    final record = wire.Record(
      id: id(),
      title: title,
      amountMinor: Int64(amount),
      currency: currency,
      date: date,
      accountId: account,
    );
    if (category != null) record.categoryId = category;
    _export.records.add(record);
    return record;
  }

  /// A record a statement import wrote, with its key beside it (ADR-110).
  wire.Record imported(
    String account,
    String currency,
    int amount, {
    required String category,
    required String fingerprint,
    required int occurrence,
    String date = '2026-03-10',
  }) {
    final out = record(account, currency, amount, category: category, date: date, title: 'Import');
    _export.recordImportKeys.add(
      wire.ExportImportKey(recordId: out.id, fingerprint: fingerprint, occurrence: occurrence),
    );
    return out;
  }

  wire.Record correction(String account, String currency, int delta, {String date = '2026-10-15'}) {
    final out = record(account, currency, delta, date: date, title: 'Balance correction');
    out.isCorrection = true;
    return out;
  }

  /// A transfer's two legs: [amount] out of [from], [received] (default [amount]) into [to].
  String transfer(
    String from,
    String fromCurrency,
    String to,
    String toCurrency,
    int amount, {
    int? received,
    String date = '2026-10-05',
  }) {
    final transferId = id();
    for (final (account, currency, value) in [
      (from, fromCurrency, -amount),
      (to, toCurrency, received ?? amount),
    ]) {
      _export.records.add(
        wire.Record(
          id: id(),
          title: 'Transfer',
          amountMinor: Int64(value),
          currency: currency,
          date: date,
          accountId: account,
          transferId: transferId,
        ),
      );
    }
    return transferId;
  }

  String plan(String account, String currency, int amount, String category, String startDate) {
    final plan = wire.Plan(
      id: id(),
      title: 'Rent',
      amountMinor: Int64(amount),
      currency: currency,
      accountId: account,
      categoryId: category,
      recurrence: wire.Recurrence(
        frequency: wire.RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY,
        interval: 1,
        startDate: startDate,
        timeZone: 'Europe/Warsaw',
      ),
    );
    _export.plans.add(plan);
    return plan.id;
  }

  wire.PlanOccurrence occurrence(String plan, String date, wire.OccurrenceStatus status) {
    final source = _export.plans.firstWhere((p) => p.id == plan);
    final out = wire.PlanOccurrence(
      id: id(),
      planId: plan,
      occurrenceDate: date,
      status: status,
      title: source.title,
      amountMinor: source.amountMinor,
      currency: source.currency,
      accountId: source.accountId,
      categoryId: source.categoryId,
    );
    _export.occurrences.add(out);
    return out;
  }

  /// The record that confirmed [occurrence], as the server writes it.
  wire.Record confirmation(wire.PlanOccurrence occurrence) {
    final out = record(
      occurrence.accountId,
      occurrence.currency,
      occurrence.amountMinor.toInt(),
      category: occurrence.categoryId,
      date: occurrence.occurrenceDate,
      title: occurrence.title,
    );
    out
      ..planId = occurrence.planId
      ..planOccurrenceId = occurrence.id;
    return out;
  }

  void budget(String category, String month, String currency, int amount) => _export.budgets.add(
    wire.Budget(categoryId: category, month: month, currency: currency, amountMinor: Int64(amount)),
  );

  String reset(String category, String month, String currency, {bool revoked = false}) {
    final reset = wire.BudgetCarryOverReset(
      id: id(),
      categoryId: category,
      month: month,
      currency: currency,
      discardedMinor: Int64(1200),
      note: 'Fresh start',
      createdBy: '00000000-0000-4000-9000-000000000001',
      createdAtMs: Int64(1790000000000),
    );
    if (revoked) {
      reset
        ..revokedBy = '00000000-0000-4000-9000-000000000001'
        ..revokedAtMs = Int64(1790000500000);
    }
    _export.carryOverResets.add(reset);
    return reset.id;
  }

  String goal(String name, String currency, int target, {String? targetDate}) {
    final goal = wire.Goal(
      id: id(),
      name: name,
      currency: currency,
      targetAmountMinor: Int64(target),
      status: wire.GoalStatus.GOAL_STATUS_ACTIVE,
      statusChangedAtMs: Int64(1790000000000),
      createdAtMs: Int64(1790000000000),
    );
    if (targetDate != null) goal.targetDate = targetDate;
    _export.goals.add(goal);
    return goal.id;
  }

  void allocation(
    wire.GoalAllocationKind kind,
    String currency,
    int amount, {
    String? source,
    String? target,
    int atMs = 1790000100000,
  }) {
    final entry = wire.GoalAllocation(
      id: id(),
      kind: kind,
      currency: currency,
      amountMinor: Int64(amount),
      note: '',
      createdAtMs: Int64(atMs),
      createdBy: '00000000-0000-4000-9000-000000000001',
    );
    if (source != null) entry.sourceGoalId = source;
    if (target != null) entry.targetGoalId = target;
    _export.goalAllocations.add(entry);
  }

  /// An open import session, which a move leaves behind (ADR-114).
  void openImportSession() =>
      _export.importSessions.add(wire.ImportSession(id: id(), formatId: 'erste-pl-csv'));

  /// The export, each account's balances the openings plus every record on it.
  wire.DataExport build() {
    final out = _export.deepCopy();
    final sums = <(String, String), int>{};
    for (final r in out.records) {
      final key = (r.accountId, r.currency);
      sums[key] = (sums[key] ?? 0) + r.amountMinor.toInt();
    }
    for (final account in out.accounts) {
      account.balances.clear();
      for (final MapEntry(key: currency, value: opening) in _openings[account.id]!.entries) {
        account.balances.add(
          wire.CurrencyBalance(
            currency: currency,
            amountMinor: Int64(opening + (sums[(account.id, currency)] ?? 0)),
          ),
        );
      }
    }
    return out;
  }
}
