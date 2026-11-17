import 'package:fixnum/fixnum.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/budgets.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goal_allocations.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/settings.pb.dart' as wire;
import 'package:protobuf/protobuf.dart';

import '../generated/prudent_local/v1/store.pb.dart';
import 'derived_ids.dart';

/// An account as the store keeps it: the account record, its currencies with their opening amounts,
/// and whether the settings name it the default.
typedef AccountParts = ({Account account, List<AccountCurrency> currencies, bool isDefault});

/// Converts between Prudent Local's store messages and the wire messages of `proto/prudent/v1/` that
/// the shared screens and the parity suite read (ADR-102, ADR-111).
///
/// The store and the wire differ on purpose, and every difference is visible in a signature here:
///
/// - **Derived figures are inputs, never read from the store.** A wire account's `balances` are its
///   *current* balances (`AccountMapper.java:86`, finding F-03), computed by the ledger (unit 5); the
///   store keeps only the opening amounts. An occurrence's status is derived (unit 6b).
/// - **Local-only fields are inputs going in.** A record's import key (F-02) and a correction's
///   intent (D7) are not on the wire, so turning a wire record into a store record asks for them.
/// - **A transfer is one record here and two on the wire** (D4). Its legs get ids derived from it.
/// - **The default account is a setting here** and `Account.is_default` on the wire.
///
/// **Field presence is copied exactly**: a field is set on the output only when it is set on the
/// input. The protobuf runtime serialises a field explicitly set to its default (`note: ''`), and
/// zen_store compares serialised fields, so a mapper that filled in defaults would hand the store
/// edits nobody made — and those can conflict with another device's real change (jZenDev/jZen#245).
/// The round trip is therefore byte-for-byte, which is what `wire_mapper_test` checks.
///
/// A value that cannot be represented the other way is refused with an [ArgumentError], never
/// guessed at: a wire record that is a transfer leg, a leg pair that does not form one transfer,
/// derived balances that do not match the held currencies.
abstract final class WireMapper {
  // ── Accounts ────────────────────────────────────────────────────────────────────────────────

  static const _accountFields = [
    ('id', 'id'),
    ('name', 'name'),
    ('active', 'isActive'),
    ('includeInTotal', 'includeInTotal'),
    ('includeInOverview', 'includeInOverview'),
    ('eligibleForGoals', 'eligibleForGoals'),
    ('accountNumber', 'accountNumber'),
  ];

  /// The wire account. [currencies] are this account's; [balanceMinor] holds the derived current
  /// balance of each of them, and must name exactly those currencies.
  static wire.Account accountToWire(
    Account account, {
    required List<AccountCurrency> currencies,
    required Settings? settings,
    required Map<String, int> balanceMinor,
  }) {
    final ordered = currencies.toList()
      ..sort((a, b) {
        final byPosition = a.position.compareTo(b.position);
        return byPosition != 0 ? byPosition : a.currency.compareTo(b.currency);
      });
    for (final c in ordered) {
      if (c.accountId != account.id) {
        throw ArgumentError.value(c.id, 'currencies', 'belongs to account ${c.accountId}');
      }
    }
    final held = {for (final c in ordered) c.currency};
    if (held.length != balanceMinor.length || !held.containsAll(balanceMinor.keys)) {
      throw ArgumentError.value(
        balanceMinor.keys.toList(),
        'balanceMinor',
        'must name exactly the held currencies $held',
      );
    }
    final out = wire.Account();
    _copy(account, out, _accountFields);
    _copyEnum(account, 'kind', out, 'type', wire.AccountType.valueOf);
    if (settings != null &&
        settings.hasDefaultAccountId() &&
        settings.defaultAccountId == account.id) {
      out.isDefault = true;
    }
    out.balances.addAll([
      for (final c in ordered)
        wire.CurrencyBalance(currency: c.currency, amountMinor: Int64(balanceMinor[c.currency]!)),
    ]);
    return out;
  }

  /// The store's parts of a wire account. A wire account's balances are current balances, not
  /// openings (F-03), so the opening of each currency is passed in [openingMinor], which must name
  /// exactly the wire's currencies; their order on the wire becomes their positions.
  static AccountParts accountFromWire(
    wire.Account value, {
    required Map<String, int> openingMinor,
  }) {
    final currencies = value.balances.map((b) => b.currency).toList();
    if (currencies.toSet().length != currencies.length) {
      throw ArgumentError.value(currencies, 'balances', 'name a currency twice');
    }
    if (currencies.length != openingMinor.length || !openingMinor.keys.every(currencies.contains)) {
      throw ArgumentError.value(
        openingMinor.keys.toList(),
        'openingMinor',
        'must name exactly the wire currencies $currencies',
      );
    }
    final account = Account();
    _copy(value, account, [for (final (a, w) in _accountFields) (w, a)]);
    _copyEnum(value, 'type', account, 'kind', AccountKind.valueOf);
    return (
      account: account,
      currencies: [
        for (var i = 0; i < currencies.length; i++)
          _accountCurrency(value.id, currencies[i], openingMinor[currencies[i]]!, i),
      ],
      isDefault: value.isDefault,
    );
  }

  static AccountCurrency _accountCurrency(String accountId, String currency, int opening, int i) {
    final out = AccountCurrency(
      id: DerivedIds.accountCurrency(accountId, currency),
      accountId: accountId,
      currency: currency,
    );
    if (opening != 0) out.openingMinor = Int64(opening);
    if (i != 0) out.position = i;
    return out;
  }

  // ── Categories ──────────────────────────────────────────────────────────────────────────────

  static const _categoryFields = [
    ('id', 'id'),
    ('title', 'title'),
    ('iconKey', 'iconKey'),
    ('description', 'description'),
    ('colorArgb', 'colorArgb'),
    ('archived', 'archived'),
  ];

  static wire.Category categoryToWire(Category value) {
    final out = wire.Category();
    _copy(value, out, _categoryFields);
    _copyEnum(value, 'kind', out, 'kind', wire.CategoryKind.valueOf);
    return out;
  }

  static Category categoryFromWire(wire.Category value) {
    final out = Category();
    _copy(value, out, _categoryFields);
    _copyEnum(value, 'kind', out, 'kind', CategoryDirection.valueOf);
    return out;
  }

  // ── Records ─────────────────────────────────────────────────────────────────────────────────

  static const _recordFields = [
    ('id', 'id'),
    ('title', 'title'),
    ('date', 'date'),
    ('categoryId', 'categoryId'),
    ('payee', 'payee'),
    ('note', 'note'),
  ];

  static wire.Record recordToWire(Record value) {
    final out = wire.Record();
    _copy(value, out, _recordFields);
    _postingToFlat(value, out);
    if (value.hasCorrection()) out.isCorrection = true;
    if (value.hasPlanLink()) {
      out
        ..planId = value.planLink.planId
        ..planOccurrenceId = value.planLink.occurrenceId;
    }
    return out;
  }

  /// The store record of a wire record. A transfer leg is refused: a transfer is one store record
  /// ([transferFromWire]). A correction needs its [correction] intent, which the wire does not carry
  /// (D7); an imported record its [importKey] (F-02).
  static Record recordFromWire(
    wire.Record value, {
    CorrectionIntent? correction,
    ImportKey? importKey,
  }) {
    if (value.hasTransferId()) {
      throw ArgumentError.value(value.id, 'record', 'is a transfer leg; map the transfer instead');
    }
    if (value.isCorrection != (correction != null)) {
      throw ArgumentError.value(
        correction,
        'correction',
        value.isCorrection ? 'is required for a correction' : 'is only for a correction',
      );
    }
    if (value.hasPlanId() != value.hasPlanOccurrenceId()) {
      throw ArgumentError.value(value.id, 'record', 'names a plan without its occurrence, or back');
    }
    final out = Record();
    _copy(value, out, _recordFields);
    out.posting = _flatToPosting(value);
    if (correction != null) out.correction = correction;
    if (value.hasPlanId()) {
      out.planLink = PlanLink(planId: value.planId, occurrenceId: value.planOccurrenceId);
    }
    if (importKey != null) out.importKey = importKey;
    return out;
  }

  // ── Transfers ───────────────────────────────────────────────────────────────────────────────

  /// The wire transfer: two leg records, the source leg negative, as the server writes them
  /// (`TransferResource.java:127–145`), with ids derived from the transfer's.
  static wire.Transfer transferToWire(Transfer value) {
    wire.Record leg(Posting posting, {required bool source}) {
      final out = wire.Record(
        id: DerivedIds.transferLeg(value.id, source: source),
        transferId: value.id,
      );
      _copy(value, out, const [('title', 'title'), ('date', 'date')]);
      _postingToFlat(Record(posting: posting), out);
      if (source && out.hasAmountMinor()) out.amountMinor = -out.amountMinor;
      return out;
    }

    return wire.Transfer(
      id: value.id,
      fromRecord: leg(value.source, source: true),
      toRecord: leg(value.destination, source: false),
    );
  }

  /// One store transfer from the wire's two legs, refused unless they are one transfer: both legs
  /// name it, share its title and date, carry no category, plan or correction, and the source is
  /// negative and the destination positive.
  static Transfer transferFromWire(wire.Transfer value) {
    final from = value.fromRecord;
    final to = value.toRecord;
    String? problem;
    if (from.transferId != value.id || to.transferId != value.id) {
      problem = 'a leg does not name the transfer';
    } else if (from.title != to.title || from.date != to.date) {
      problem = 'the legs differ in title or date';
    } else if (from.amountMinor >= 0 || to.amountMinor <= 0) {
      problem = 'the source leg must be negative and the destination positive';
    } else if ([
      from,
      to,
    ].any((r) => r.hasCategoryId() || r.hasPlanId() || r.hasPlanOccurrenceId() || r.isCorrection)) {
      problem = 'a leg carries a category, a plan or a correction';
    }
    if (problem != null) throw ArgumentError.value(value.id, 'transfer', problem);
    final out = Transfer(id: value.id);
    _copy(from, out, const [('title', 'title'), ('date', 'date')]);
    out
      ..source = (_flatToPosting(from)..amountMinor = -from.amountMinor)
      ..destination = _flatToPosting(to);
    return out;
  }

  // ── Budgets and resets ──────────────────────────────────────────────────────────────────────

  static const _budgetFields = [
    ('categoryId', 'categoryId'),
    ('month', 'month'),
    ('currency', 'currency'),
    ('amountMinor', 'amountMinor'),
  ];

  static wire.Budget budgetToWire(Budget value) {
    final out = wire.Budget();
    _copy(value, out, _budgetFields);
    return out;
  }

  static Budget budgetFromWire(wire.Budget value) {
    final out = Budget(id: DerivedIds.budget(value.categoryId, value.month, value.currency));
    _copy(value, out, _budgetFields);
    return out;
  }

  static const _resetFields = [
    ('id', 'id'),
    ('categoryId', 'categoryId'),
    ('month', 'month'),
    ('currency', 'currency'),
    ('discardedMinor', 'discardedMinor'),
    ('note', 'note'),
    ('createdBy', 'createdBy'),
    ('createdAtMs', 'createdAtMs'),
  ];

  static wire.BudgetCarryOverReset resetToWire(BudgetCarryOverReset value) {
    final out = wire.BudgetCarryOverReset();
    _copy(value, out, _resetFields);
    if (value.hasRevocation()) {
      out
        ..revokedBy = value.revocation.by
        ..revokedAtMs = value.revocation.atMs;
    }
    return out;
  }

  static BudgetCarryOverReset resetFromWire(wire.BudgetCarryOverReset value) {
    final revoked = value.revokedBy.isNotEmpty || value.revokedAtMs != Int64.ZERO;
    if (revoked && (value.revokedBy.isEmpty || value.revokedAtMs == Int64.ZERO)) {
      throw ArgumentError.value(value.id, 'reset', 'is revoked without both who and when');
    }
    final out = BudgetCarryOverReset();
    _copy(value, out, _resetFields);
    if (revoked) out.revocation = Revocation(by: value.revokedBy, atMs: value.revokedAtMs);
    return out;
  }

  // ── Goals and allocations ───────────────────────────────────────────────────────────────────

  static const _goalFields = [
    ('id', 'id'),
    ('name', 'name'),
    ('currency', 'currency'),
    ('targetAmountMinor', 'targetAmountMinor'),
    ('targetDate', 'targetDate'),
    ('statusChangedAtMs', 'statusChangedAtMs'),
    ('createdAtMs', 'createdAtMs'),
  ];

  static wire.Goal goalToWire(Goal value) {
    final out = wire.Goal();
    _copy(value, out, _goalFields);
    _copyEnum(value, 'status', out, 'status', wire.GoalStatus.valueOf);
    return out;
  }

  static Goal goalFromWire(wire.Goal value) {
    final out = Goal();
    _copy(value, out, _goalFields);
    _copyEnum(value, 'status', out, 'status', GoalState.valueOf);
    return out;
  }

  static const _allocationFields = [
    ('id', 'id'),
    ('sourceGoalId', 'sourceGoalId'),
    ('targetGoalId', 'targetGoalId'),
    ('currency', 'currency'),
    ('amountMinor', 'amountMinor'),
    ('note', 'note'),
    ('createdAtMs', 'createdAtMs'),
    ('createdBy', 'createdBy'),
  ];

  static wire.GoalAllocation allocationToWire(GoalAllocation value) {
    final out = wire.GoalAllocation();
    _copy(value, out, _allocationFields);
    _copyEnum(value, 'kind', out, 'kind', wire.GoalAllocationKind.valueOf);
    return out;
  }

  /// [compensates] is local-only (a repair's compensated entries, ADR-120), so it is an input.
  static GoalAllocation allocationFromWire(
    wire.GoalAllocation value, {
    List<String> compensates = const [],
  }) {
    final out = GoalAllocation();
    _copy(value, out, _allocationFields);
    _copyEnum(value, 'kind', out, 'kind', AllocationKind.valueOf);
    out.compensates.addAll(compensates);
    return out;
  }

  // ── Plans and occurrences ───────────────────────────────────────────────────────────────────

  static const _planFields = [
    ('id', 'id'),
    ('title', 'title'),
    ('categoryId', 'categoryId'),
    ('payee', 'payee'),
    ('note', 'note'),
  ];

  static const _scheduleFields = [
    ('interval', 'interval'),
    ('startDate', 'startDate'),
    ('timeZone', 'timeZone'),
    ('untilDate', 'untilDate'),
    ('occurrenceCount', 'occurrenceCount'),
  ];

  static const _reminderFields = [('enabled', 'enabled'), ('leadDays', 'leadDays')];

  static wire.Plan planToWire(Plan value) {
    final out = wire.Plan();
    _copy(value, out, _planFields);
    _postingToFlat(Record(posting: value.posting), out);
    if (value.hasSchedule()) {
      final recurrence = wire.Recurrence();
      _copy(value.schedule, recurrence, _scheduleFields);
      _copyEnum(
        value.schedule,
        'frequency',
        recurrence,
        'frequency',
        wire.RecurrenceFrequency.valueOf,
      );
      out.recurrence = recurrence;
    }
    if (value.hasReminder()) {
      out.reminder = wire.Reminder();
      _copy(value.reminder, out.reminder, _reminderFields);
    }
    return out;
  }

  static Plan planFromWire(wire.Plan value) {
    final out = Plan();
    _copy(value, out, _planFields);
    out.posting = _flatToPosting(value);
    if (value.hasRecurrence()) {
      final schedule = Schedule();
      _copy(value.recurrence, schedule, _scheduleFields);
      _copyEnum(value.recurrence, 'frequency', schedule, 'frequency', Frequency.valueOf);
      out.schedule = schedule;
    }
    if (value.hasReminder()) {
      out.reminder = ReminderSetting();
      _copy(value.reminder, out.reminder, _reminderFields);
    }
    return out;
  }

  /// The wire occurrence of [plan] on [date]. Its [status] is derived — completed from a live
  /// confirming record, overdue from the date (unit 6b) — and its title, amount, currency, account
  /// and category are copied from the plan, as the server does. [state] is the stored part, if any.
  static wire.PlanOccurrence occurrenceToWire({
    required Plan plan,
    required String date,
    required wire.OccurrenceStatus status,
    OccurrenceState? state,
  }) {
    final id = DerivedIds.occurrence(plan.id, date);
    if (state != null &&
        (state.id != id || state.planId != plan.id || state.occurrenceDate != date)) {
      throw ArgumentError.value(state.id, 'state', 'is not the state of ${plan.id} on $date');
    }
    final out = wire.PlanOccurrence(id: id, planId: plan.id, occurrenceDate: date, status: status);
    _copy(plan, out, const [('title', 'title'), ('categoryId', 'categoryId')]);
    _postingToFlat(Record(posting: plan.posting), out);
    return out;
  }

  /// The stored state of a wire occurrence: skipped when its status says so, and the reminder-read
  /// time, which the wire does not carry ([reminderReadAtMs]; null for unread).
  static OccurrenceState occurrenceFromWire(wire.PlanOccurrence value, {int? reminderReadAtMs}) {
    final out = OccurrenceState(
      id: DerivedIds.occurrence(value.planId, value.occurrenceDate),
      planId: value.planId,
      occurrenceDate: value.occurrenceDate,
    );
    if (value.status == wire.OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED) out.skipped = true;
    if (reminderReadAtMs != null) out.reminderReadAtMs = Int64(reminderReadAtMs);
    return out;
  }

  // ── Settings ────────────────────────────────────────────────────────────────────────────────

  static wire.Settings settingsToWire(Settings value) {
    final out = wire.Settings();
    _copy(value, out, const [('mainCurrency', 'mainCurrency')]);
    return out;
  }

  /// The settings record, with the default account the wire carries on the account instead.
  static Settings settingsFromWire(wire.Settings value, {String? defaultAccountId}) {
    final out = Settings(id: DerivedIds.settings);
    _copy(value, out, const [('mainCurrency', 'mainCurrency')]);
    if (defaultAccountId != null) out.defaultAccountId = defaultAccountId;
    return out;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────────────────────

  static const _postingFields = [
    ('accountId', 'accountId'),
    ('currency', 'currency'),
    ('amountMinor', 'amountMinor'),
  ];

  /// Copies a record's (or plan's) posting into the flat account, currency and amount fields of a
  /// wire message [out].
  static void _postingToFlat(Record from, GeneratedMessage out) {
    if (from.hasPosting()) _copy(from.posting, out, _postingFields);
  }

  /// The posting of a wire message's flat account, currency and amount fields.
  static Posting _flatToPosting(GeneratedMessage from) {
    final out = Posting();
    _copy(from, out, _postingFields);
    return out;
  }

  /// Copies each named field from [from] to [to] **only when it is set on [from]**, so field presence
  /// survives the trip (see the class comment).
  static void _copy(GeneratedMessage from, GeneratedMessage to, List<(String, String)> names) {
    for (final (fromName, toName) in names) {
      final fromTag = from.info_.byName[fromName]!.tagNumber;
      if (!from.hasField(fromTag)) continue;
      to.setField(to.info_.byName[toName]!.tagNumber, from.getField(fromTag) as Object);
    }
  }

  /// Copies an enum field to the other side's enum with the same number, when it is set. The two
  /// enums are kept value for value (`wire_mapper_test` proves the names match); a number without a
  /// counterpart is refused.
  static void _copyEnum<T extends ProtobufEnum>(
    GeneratedMessage from,
    String fromName,
    GeneratedMessage to,
    String toName,
    T? Function(int value) valueOf,
  ) {
    final fromTag = from.info_.byName[fromName]!.tagNumber;
    if (!from.hasField(fromTag)) return;
    final value = from.getField(fromTag) as ProtobufEnum;
    final counterpart =
        valueOf(value.value) ??
        (throw ArgumentError.value(value.value, fromName, 'has no counterpart in $toName'));
    to.setField(to.info_.byName[toName]!.tagNumber, counterpart);
  }
}
