import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import '../generated/prudent_local/v1/imports.pb.dart';
import '../generated/prudent_local/v1/store.pb.dart';
import 'derived_ids.dart';
import 'write_expect.dart';

/// Prudent Local's collections on one open [ZenStore], and the only way to write them.
///
/// The store merges one record across devices field by field and knows nothing else (jZen ADR-065).
/// What makes that merge honest for a ledger is the *shape* of the records (the store messages,
/// ADR-102) and a few structural rules no device may break, enforced here on every write:
///
/// - **Ids.** A record has a random id ([newId]) or, where the server holds a unique index on a
///   natural key, the id derived from that key ([DerivedIds]); a write whose id does not match its
///   key is refused, because it would be a second record for one slot.
/// - **Immutable fields** are written once. A change to one is refused here, so the merge never
///   meets two versions of it.
/// - **Append-only and write-once records** — a transfer, a goal allocation — refuse a second write;
///   an allocation, a carry-over reset and a goal are never deleted, as on the server.
///
/// Rules about *values* (a currency the account holds, a category's kind, an amount's sign) are the
/// ledger's and the budgets' (units 5–6). Rules *across* records, which a merge can break with no
/// device having broken them, are not refused anywhere: `IntegrityRunner` lists them afterwards.
///
/// Reads, conflicts and resolutions go through the collections themselves (and through
/// `zen_ui_store`, which takes a `ZenCollection`). Never `put` or `delete` on a collection directly:
/// that skips every rule above.
final class PrudentLocalStore {
  /// The open store, encrypted on this device and synced by the application's transport.
  final ZenStore zen;

  final ZenCollection<Account> accounts;
  final ZenCollection<AccountCurrency> accountCurrencies;
  final ZenCollection<Category> categories;
  final ZenCollection<Record> records;
  final ZenCollection<Transfer> transfers;
  final ZenCollection<Budget> budgets;
  final ZenCollection<BudgetCarryOverReset> budgetResets;
  final ZenCollection<Goal> goals;
  final ZenCollection<GoalAllocation> goalAllocations;
  final ZenCollection<Plan> plans;
  final ZenCollection<OccurrenceState> occurrences;
  final ZenCollection<Settings> settings;

  /// Statement import sessions (unit 8b, ADR-114): **device-only** (`syncs: false`,
  /// jZenDev/jZen#252). A session holds normalised statement rows for at most 24 hours; they never
  /// reach another device or the sync service, yet `writeAll` saves a session together with the
  /// ledger records its commit writes, as one.
  final ZenCollection<LocalImportSession> importSessions;

  /// Declares every collection on [zen], with the merge policies of [StorePolicies]. Every device
  /// declares the same ones on every launch; the store refuses a collection re-declared differently.
  PrudentLocalStore(this.zen)
    : accounts = zen.collection('accounts', Account.fromBuffer),
      accountCurrencies = zen.collection('account_currencies', AccountCurrency.fromBuffer),
      categories = zen.collection('categories', Category.fromBuffer),
      records = zen.collection('records', Record.fromBuffer),
      transfers = zen.collection('transfers', Transfer.fromBuffer),
      budgets = zen.collection('budgets', Budget.fromBuffer),
      budgetResets = zen.collection(
        'budget_resets',
        BudgetCarryOverReset.fromBuffer,
        mergePolicies: StorePolicies.budgetResets,
      ),
      goals = zen.collection('goals', Goal.fromBuffer, mergePolicies: StorePolicies.goals),
      goalAllocations = zen.collection('goal_allocations', GoalAllocation.fromBuffer),
      plans = zen.collection('plans', Plan.fromBuffer),
      occurrences = zen.collection(
        'occurrences',
        OccurrenceState.fromBuffer,
        mergePolicies: StorePolicies.occurrences,
      ),
      settings = zen.collection('settings', Settings.fromBuffer),
      importSessions = zen.collection(
        'import_sessions',
        LocalImportSession.fromBuffer,
        syncs: false,
        explicitPresence: StorePolicies.importSessionPresence,
      );

  /// A new random id: 128 bits as 32 lower-case hex characters, minted by this device.
  ///
  /// The server mints every id itself because "an id from an untrusted client is not identity"
  /// (`Ids.java`). Here the device is the only authority over its own store, and two devices must be
  /// able to create records offline without asking anyone, so the device mints them (ADR-111).
  String newId() => zen.newId();

  /// This device's id, which a reset or an allocation records as who made it.
  String get deviceId => zen.deviceId;

  // ── Accounts ────────────────────────────────────────────────────────────────────────────────
  //
  // Every write takes an optional [WriteExpect]: what the caller decided the write against, checked
  // by the store inside the write's turn together with the rules below (ADR-115). A write that
  // edits a record it read passes `WriteExpects.asRead(theRecordItRead)`, so a sync that deleted or
  // changed it in between refuses the write instead of being written over.

  Future<ZenResult<Account>> putAccount(Account value, {WriteExpect<Account>? expect}) =>
      _put(accounts, value, _accountRules, expect);

  Future<ZenResult<Account>> deleteAccount(String id, {WriteExpect<Account>? expect}) =>
      accounts.delete(id, expect: expect);

  Future<ZenResult<AccountCurrency>> putAccountCurrency(
    AccountCurrency value, {
    WriteExpect<AccountCurrency>? expect,
  }) => _put(accountCurrencies, value, _accountCurrencyRules, expect);

  Future<ZenResult<AccountCurrency>> deleteAccountCurrency(
    String id, {
    WriteExpect<AccountCurrency>? expect,
  }) => accountCurrencies.delete(id, expect: expect);

  // ── Categories ──────────────────────────────────────────────────────────────────────────────

  Future<ZenResult<Category>> putCategory(Category value, {WriteExpect<Category>? expect}) =>
      _put(categories, value, _categoryRules, expect);

  Future<ZenResult<Category>> deleteCategory(String id, {WriteExpect<Category>? expect}) =>
      categories.delete(id, expect: expect);

  // ── Records and transfers ───────────────────────────────────────────────────────────────────

  /// An ordinary record or a correction. The correction intent, the plan link and the import key are
  /// immutable, and a correction is never edited at all, only deleted (`RecordResource.java:232`). A
  /// record that confirms an occurrence carries the id derived from it, and an imported record the
  /// id derived from its account, fingerprint and occurrence, so two devices write one record.
  Future<ZenResult<Record>> putRecord(Record value, {WriteExpect<Record>? expect}) =>
      _put(records, value, _recordRules, expect);

  Future<ZenResult<Record>> deleteRecord(String id, {WriteExpect<Record>? expect}) =>
      records.delete(id, expect: expect);

  // ── Import sessions (device-only) ───────────────────────────────────────────────────────────

  /// One import session, whole. [expect] runs inside the write's turn against the session as it
  /// stands then (jZenDev/jZen#251), so a rule checked before the write still holds when it runs.
  Future<ZenResult<LocalImportSession>> putImportSession(
    LocalImportSession value, {
    WriteExpect<LocalImportSession>? expect,
  }) => _put(importSessions, value, _importSessionRules, expect);

  /// A transfer is written once and never edited, only deleted (`RecordResource.java:217`).
  Future<ZenResult<Transfer>> addTransfer(Transfer value, {WriteExpect<Transfer>? expect}) =>
      _put(transfers, value, _transferRules, expect);

  Future<ZenResult<Transfer>> deleteTransfer(String id, {WriteExpect<Transfer>? expect}) =>
      transfers.delete(id, expect: expect);

  // ── Budgets and carry-over resets ───────────────────────────────────────────────────────────
  //
  // Each write below takes an [expect]: the rule the caller checked before writing, run again by the
  // store inside the write's own turn (jZenDev/jZen#251), after anything a sync delivered meanwhile.
  // A refusal it returns is the write's result, so a rule checked against one state never lands on
  // another — above all, an edit never brings back a record a sync just deleted.

  Future<ZenResult<Budget>> putBudget(Budget value, {WriteExpect<Budget>? expect}) =>
      _put(budgets, value, _budgetRules, expect);

  Future<ZenResult<Budget>> deleteBudget(String id, {WriteExpect<Budget>? expect}) =>
      budgets.delete(id, expect: expect);

  /// Records a reset, unrevoked. It is an audit entry: never edited, never deleted (ADR-046).
  Future<ZenResult<BudgetCarryOverReset>> addBudgetReset(
    BudgetCarryOverReset value, {
    WriteExpect<BudgetCarryOverReset>? expect,
  }) {
    if (value.hasRevocation()) {
      return _refuse('A carry-over reset is recorded unrevoked; revoke it with revokeBudgetReset.');
    }
    return _put(
      budgetResets,
      value,
      _Rules<BudgetCarryOverReset>(id: _randomId, writeOnce: true),
      expect,
    );
  }

  /// Marks the reset [id] revoked by this device at [atMs]. The only change a reset ever takes, and
  /// only once: the store refuses it inside the write's turn if the reset was revoked meanwhile (a
  /// revocation that arrived by sync included) or is gone, besides whatever [expect] refuses.
  ///
  /// Two devices that revoke one reset offline merge without a question: the revocation is a group
  /// (who and when) and jZen's `earliestBy` policy (jZenDev/jZen#244) keeps the earlier one whole
  /// ([StorePolicies.budgetResets]).
  Future<ZenResult<BudgetCarryOverReset>> revokeBudgetReset(
    String id, {
    required int atMs,
    ZenError? Function(BudgetCarryOverReset current)? expect,
  }) {
    final current = budgetResets.get(id);
    switch (current) {
      case ZenFailure(:final error):
        return Future.value(ZenResult.err(error));
      case ZenSuccess(:final data):
        if (data.hasRevocation()) return _refuse('budget_resets/$id is already revoked.');
        final next = data.deepCopy()..revocation = Revocation(by: deviceId, atMs: Int64(atMs));
        return _put(budgetResets, next, _resetRevocationRules, (now) {
          if (now == null) return ZenNotFoundError('budget_resets/$id does not exist.');
          if (now.hasRevocation()) {
            return ZenValidationError('budget_resets/$id is already revoked.');
          }
          return expect?.call(now);
        });
    }
  }

  static final _budgetRules = _Rules<Budget>(
    id: (v) => _derivedId(v.id, () => DerivedIds.budget(v.categoryId, v.month, v.currency)),
    immutable: const ['categoryId', 'month', 'currency'],
  );

  static final _resetRevocationRules = _Rules<BudgetCarryOverReset>(
    id: _randomId,
    immutable: const [
      'categoryId',
      'month',
      'currency',
      'discardedMinor',
      'note',
      'createdBy',
      'createdAtMs',
    ],
  );

  // ── Goals and allocations ───────────────────────────────────────────────────────────────────

  /// A goal is retired, never deleted (ADR-049); its currency and creation time never change.
  Future<ZenResult<Goal>> putGoal(Goal value, {WriteExpect<Goal>? expect}) =>
      _put(goals, value, _goalRules, expect);

  /// Append-only, as on the server (ADR-050): written once, never edited or deleted.
  Future<ZenResult<GoalAllocation>> addGoalAllocation(
    GoalAllocation value, {
    WriteExpect<GoalAllocation>? expect,
  }) =>
      _put(goalAllocations, value, _Rules<GoalAllocation>(id: _randomId, writeOnce: true), expect);

  static final _goalRules = _Rules<Goal>(
    id: _randomId,
    immutable: const ['currency', 'createdAtMs'],
  );

  // ── Plans and occurrences ───────────────────────────────────────────────────────────────────

  Future<ZenResult<Plan>> putPlan(Plan value, {WriteExpect<Plan>? expect}) =>
      _put(plans, value, _planRules, expect);

  Future<ZenResult<Plan>> deletePlan(String id, {WriteExpect<Plan>? expect}) =>
      plans.delete(id, expect: expect);

  Future<ZenResult<OccurrenceState>> putOccurrenceState(
    OccurrenceState value, {
    WriteExpect<OccurrenceState>? expect,
  }) => _put(occurrences, value, _occurrenceRules, expect);

  Future<ZenResult<OccurrenceState>> deleteOccurrenceState(
    String id, {
    WriteExpect<OccurrenceState>? expect,
  }) => occurrences.delete(id, expect: expect);

  // ── Settings ────────────────────────────────────────────────────────────────────────────────

  /// The one settings record. It is created, edited, never deleted.
  Future<ZenResult<Settings>> putSettings(Settings value, {WriteExpect<Settings>? expect}) =>
      _put(settings, value, _settingsRules, expect);

  // ── Several records as one ──────────────────────────────────────────────────────────────────

  /// Writes every operation of [batch] as one, through jZen's `ZenStore.writeAll`
  /// (jZenDev/jZen#232): all of it reaches the disk, or none of it does, even if the device loses
  /// power half way. Each operation is held to exactly the rules its single-record method applies —
  /// the id, the immutable fields, write-once, and its [WriteExpect] — against the records as they
  /// stand when the batch takes its turn, and if any one is refused, nothing is written.
  ///
  /// Atomic on this device only: another device receives the records one by one (a sync is per
  /// record), so a screen there can briefly show part of a batch. Every batch Prudent writes is
  /// therefore one whose parts are each a valid state on their own, or whose half-arrived state the
  /// integrity checks name (an account deleted before its records arrive deleted is a dangling
  /// reference for one sync).
  Future<ZenResult<void>> writeAll(StoreBatch batch) {
    final zenBatch = ZenBatch();
    for (final step in batch._steps) {
      if (step(zenBatch) case final error?) return Future.value(ZenResult.err(error));
    }
    return zen.writeAll(zenBatch);
  }

  // ── The rules ───────────────────────────────────────────────────────────────────────────────

  static String? _randomId(GeneratedMessage value) {
    final id = value.getField(_idTag) as String;
    return LocalIds.isValid(id) ? null : '"$id" is not a local id (32 lower-case hex characters).';
  }

  static String? _derivedId(String id, String Function() derive) {
    final String expected;
    try {
      expected = derive();
    } on ArgumentError catch (e) {
      return 'The natural key of "$id" is not canonical: ${e.message} (${e.invalidValue}).';
    }
    return id == expected ? null : '"$id" is not the id its natural key derives ($expected).';
  }

  static const int _idTag = 1;

  static final _accountRules = _Rules<Account>(id: _randomId);

  static final _accountCurrencyRules = _Rules<AccountCurrency>(
    id: (v) => _derivedId(v.id, () => DerivedIds.accountCurrency(v.accountId, v.currency)),
    immutable: const ['accountId', 'currency'],
  );

  static final _categoryRules = _Rules<Category>(id: _randomId);

  static final _planRules = _Rules<Plan>(id: _randomId);

  /// Stored only when it differs from the default (skipped, or a reminder read); the id is derived
  /// from the plan and the date, so two devices that skip one occurrence write one record.
  static final _occurrenceRules = _Rules<OccurrenceState>(
    id: (v) => _derivedId(v.id, () => DerivedIds.occurrence(v.planId, v.occurrenceDate)),
    immutable: const ['planId', 'occurrenceDate'],
  );

  /// An ordinary record or a correction. The correction intent, the plan link and the import key are
  /// immutable, and a correction is never edited at all, only deleted (`RecordResource.java:232`). A
  /// record that confirms an occurrence carries the id derived from it, and an imported record the
  /// id derived from its account, fingerprint and occurrence, so two devices write one record.
  static final _recordRules = _Rules<Record>(
    id: (v) {
      if (v.hasPlanLink()) {
        // The link's date, when it carries one, is the date the occurrence id derives from (unit
        // 6b): a record that names a date its occurrence id does not belong to would complete a
        // different day than it says.
        final link = v.planLink;
        if (link.occurrenceDate.isNotEmpty &&
            _derivedId(
                  link.occurrenceId,
                  () => DerivedIds.occurrence(link.planId, link.occurrenceDate),
                ) !=
                null) {
          return 'The plan link of records/${v.id} names an occurrence that is not its plan\'s on '
              '${link.occurrenceDate}.';
        }
        return _derivedId(v.id, () => DerivedIds.confirmation(link.occurrenceId));
      }
      if (v.hasImportKey()) {
        return _derivedId(
          v.id,
          () => DerivedIds.imported(
            v.posting.accountId,
            v.importKey.fingerprint,
            v.importKey.occurrence,
          ),
        );
      }
      return _randomId(v);
    },
    immutable: const ['correction', 'planLink', 'importKey'],
    onUpdate: (current, next) => current.hasCorrection()
        ? 'records/${next.id} is a correction, which is never edited: delete it and correct again.'
        : null,
  );

  static final _importSessionRules = _Rules<LocalImportSession>(
    id: _randomId,
    immutable: const ['formatId', 'currency', 'createdAtMs'],
  );

  /// A transfer is written once and never edited, only deleted (`RecordResource.java:217`).
  static final _transferRules = _Rules<Transfer>(id: _randomId, writeOnce: true);

  /// The one settings record. It is created, edited, never deleted.
  static final _settingsRules = _Rules<Settings>(
    id: (v) => v.id == DerivedIds.settings
        ? null
        : 'The settings record has the id "${DerivedIds.settings}", not "${v.id}".',
  );

  Future<ZenResult<T>> _put<T extends GeneratedMessage>(
    ZenCollection<T> collection,
    T value,
    _Rules<T> rules,
    WriteExpect<T>? expect,
  ) {
    if (rules.id(value) case final problem?) {
      return Future.value(ZenResult.err(ZenValidationError(problem)));
    }
    return collection.put(
      value.getField(_idTag) as String,
      value,
      expect: _admitting(collection, value, rules, expect),
    );
  }

  /// The precondition the store runs inside the write's turn: the caller's [expect] first, then
  /// [rules] — write-once, the immutable fields, a further refusal of an update — against the record
  /// as it stands *then*. Checked any earlier, a sync's receive queued before the write could change
  /// the record in between, and the rule would hold only for a version that is no longer there.
  ///
  /// A stored record whose bytes no longer decode never reaches this: the store answers its decode
  /// failure for it, so a write never goes past exactly the record nobody can read.
  static WriteExpect<T> _admitting<T extends GeneratedMessage>(
    ZenCollection<T> collection,
    T value,
    _Rules<T> rules,
    WriteExpect<T>? expect,
  ) => (current) {
    if (expect?.call(current) case final error?) return error;
    if (current == null) return null;
    final id = value.getField(_idTag) as String;
    if (rules.writeOnce) {
      return ZenValidationError('${collection.name}/$id is written once and never edited.');
    }
    for (final name in rules.immutable) {
      if (!_sameField(current, value, name)) {
        return ZenValidationError(
          '${collection.name}/$id: "$name" is written once and never changed.',
        );
      }
    }
    if (rules.onUpdate?.call(current, value) case final problem?) {
      return ZenValidationError(problem);
    }
    return null;
  };

  /// Whether field [name] serialises to the same bytes in [a] and [b] — exactly what the store
  /// compares when it merges, so "unchanged" here means "no version of it to merge".
  static bool _sameField(GeneratedMessage a, GeneratedMessage b, String name) {
    final tag = a.info_.byName[name]!.tagNumber;
    List<int> only(GeneratedMessage m) {
      final copy = m.deepCopy();
      for (final other in copy.info_.fieldInfo.keys) {
        if (other != tag) copy.clearField(other);
      }
      return copy.writeToBuffer();
    }

    final left = only(a);
    final right = only(b);
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static Future<ZenResult<T>> _refuse<T>(String message) =>
      Future.value(ZenResult.err(ZenValidationError(message)));
}

/// The field-level merge policies (jZenDev/jZen#235, consumed from jZen PR #241), by proto field
/// number read from the generated message's own descriptor, so a renumbered field cannot leave a
/// policy on the wrong one.
///
/// Only the same-intent times of ADR-102 have one: when two devices reached the *same* state at two
/// moments, the earlier moment is kept. That is not last-writer-wins — it is a pure function of the
/// two values, the same on every device whatever arrived first. Every other field keeps the store's
/// default: two different values are a conflict for the person.
///
/// A carry-over reset's revocation is a same-intent field that is a *group* — who and when. It
/// merges by its time with jZen's group policy (`ZenMergePolicy.earliestBy`, jZenDev/jZen#244,
/// consumed in ADR-114), which keeps the whole earlier version, so the author is never taken from
/// the other device than the time beside it.
abstract final class StorePolicies {
  /// `Goal.status_changed_at_ms`: completing (or archiving) one goal on two devices keeps the first
  /// moment. The status itself stays a plain field, so completing on one device and archiving on
  /// another is still a question.
  static final Map<int, ZenMergePolicy> goals = {
    _tag(Goal(), 'statusChangedAtMs'): ZenMergePolicy.earliest,
  };

  /// `OccurrenceState.reminder_read_at_ms`: a reminder read on two devices keeps the first moment.
  static final Map<int, ZenMergePolicy> occurrences = {
    _tag(OccurrenceState(), 'reminderReadAtMs'): ZenMergePolicy.earliest,
  };

  /// `BudgetCarryOverReset.revocation`: a reset revoked on two devices keeps the first revocation,
  /// who and when together, ordered by `Revocation.at_ms`. Revoking on one device against no
  /// revocation on the other is not a disagreement (the revocation is only ever added), so nothing
  /// else changes. Field numbers pinned by merge_table_test.
  static final Map<int, ZenMergePolicy> budgetResets = {
    _tag(BudgetCarryOverReset(), 'revocation'): ZenMergePolicy.earliestBy(
      _tag(Revocation(), 'atMs'),
    ),
  };

  /// The `optional` fields of an import session, whose default is a value and not "unset"
  /// (jZenDev/jZen#245): above all `committed_written` = 0, a commit that wrote nothing.
  static final Set<int> importSessionPresence = {
    for (final name in const [
      'accountId',
      'committedWritten',
      'committedAlreadyImported',
      'defaultExpenseCategoryId',
      'defaultIncomeCategoryId',
      'statementIdentity',
    ])
      _tag(LocalImportSession(), name),
  };

  static int _tag(GeneratedMessage message, String name) => message.info_.byName[name]!.tagNumber;
}

final class _Rules<T extends GeneratedMessage> {
  /// Null when the value's id is right for it; otherwise why not.
  final String? Function(T value) id;

  /// Fields (by Dart name) that may never change once written.
  final List<String> immutable;

  /// A record that exists is never written again.
  final bool writeOnce;

  /// A further refusal of an update, given the stored record; null to allow.
  final String? Function(T current, T next)? onUpdate;

  const _Rules({
    required this.id,
    this.immutable = const [],
    this.writeOnce = false,
    this.onUpdate,
  });
}

/// Writes and deletes for [PrudentLocalStore.writeAll], named like the store's own methods and held
/// to the same rules. Nothing is checked or written until `writeAll` runs it.
///
/// Only the collections written together are here (unit 5: an account with its currencies and the
/// default setting, an account deleted with its records; unit 6b: a plan with its occurrence states,
/// a confirmation). A later unit that writes several
/// records as one adds its own methods, each delegating to the single-record rules.
final class StoreBatch {
  final PrudentLocalStore _store;
  final List<ZenError? Function(ZenBatch)> _steps = [];

  /// A batch for [store]; run it with [PrudentLocalStore.writeAll] on the same store.
  StoreBatch(this._store);

  /// How many operations the batch holds.
  int get length => _steps.length;

  void putAccount(Account value, {WriteExpect<Account>? expect}) =>
      _put(_store.accounts, value, PrudentLocalStore._accountRules, expect);

  void deleteAccount(String id, {WriteExpect<Account>? expect}) =>
      _delete(_store.accounts, id, expect);

  void putAccountCurrency(AccountCurrency value, {WriteExpect<AccountCurrency>? expect}) =>
      _put(_store.accountCurrencies, value, PrudentLocalStore._accountCurrencyRules, expect);

  void deleteAccountCurrency(String id, {WriteExpect<AccountCurrency>? expect}) =>
      _delete(_store.accountCurrencies, id, expect);

  void putCategory(Category value, {WriteExpect<Category>? expect}) =>
      _put(_store.categories, value, PrudentLocalStore._categoryRules, expect);

  void putRecord(Record value, {WriteExpect<Record>? expect}) =>
      _put(_store.records, value, PrudentLocalStore._recordRules, expect);

  void putImportSession(LocalImportSession value, {WriteExpect<LocalImportSession>? expect}) =>
      _put(_store.importSessions, value, PrudentLocalStore._importSessionRules, expect);

  void putPlan(Plan value, {WriteExpect<Plan>? expect}) =>
      _put(_store.plans, value, PrudentLocalStore._planRules, expect);

  void deletePlan(String id, {WriteExpect<Plan>? expect}) => _delete(_store.plans, id, expect);

  void putOccurrenceState(OccurrenceState value, {WriteExpect<OccurrenceState>? expect}) =>
      _put(_store.occurrences, value, PrudentLocalStore._occurrenceRules, expect);

  void deleteOccurrenceState(String id, {WriteExpect<OccurrenceState>? expect}) =>
      _delete(_store.occurrences, id, expect);

  void deleteRecord(String id, {WriteExpect<Record>? expect}) =>
      _delete(_store.records, id, expect);

  void deleteTransfer(String id, {WriteExpect<Transfer>? expect}) =>
      _delete(_store.transfers, id, expect);

  void putSettings(Settings value, {WriteExpect<Settings>? expect}) =>
      _put(_store.settings, value, PrudentLocalStore._settingsRules, expect);

  // Unit 10b (ADR-123): a move into an empty store writes every collection as one.

  void addTransfer(Transfer value, {WriteExpect<Transfer>? expect}) =>
      _put(_store.transfers, value, PrudentLocalStore._transferRules, expect);

  void putBudget(Budget value, {WriteExpect<Budget>? expect}) =>
      _put(_store.budgets, value, PrudentLocalStore._budgetRules, expect);

  /// A carry-over reset as the server's export holds it, **revoked or not**: the one place a reset
  /// is written with its revocation already in it, because a move copies a history that happened
  /// elsewhere (ADR-123). Written once, never edited, like [PrudentLocalStore.addBudgetReset].
  void addMovedBudgetReset(BudgetCarryOverReset value, {WriteExpect<BudgetCarryOverReset>? expect}) =>
      _put(
        _store.budgetResets,
        value,
        _Rules<BudgetCarryOverReset>(id: PrudentLocalStore._randomId, writeOnce: true),
        expect,
      );

  void putGoal(Goal value, {WriteExpect<Goal>? expect}) =>
      _put(_store.goals, value, PrudentLocalStore._goalRules, expect);

  void addGoalAllocation(GoalAllocation value, {WriteExpect<GoalAllocation>? expect}) => _put(
    _store.goalAllocations,
    value,
    _Rules<GoalAllocation>(id: PrudentLocalStore._randomId, writeOnce: true),
    expect,
  );

  void _put<T extends GeneratedMessage>(
    ZenCollection<T> collection,
    T value,
    _Rules<T> rules,
    WriteExpect<T>? expect,
  ) => _steps.add((batch) {
    if (rules.id(value) case final problem?) return ZenValidationError(problem);
    batch.put(
      collection,
      value.getField(PrudentLocalStore._idTag) as String,
      value,
      expect: PrudentLocalStore._admitting(collection, value, rules, expect),
    );
    return null;
  });

  void _delete<T extends GeneratedMessage>(
    ZenCollection<T> collection,
    String id,
    WriteExpect<T>? expect,
  ) => _steps.add((batch) {
    batch.delete(collection, id, expect: expect);
    return null;
  });
}
