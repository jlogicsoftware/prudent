import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/reminders.pb.dart' as wire;
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart' show ZenConflict, ZenStorageError;

import '../../generated/prudent_local/v1/store.pb.dart';
import '../derived_ids.dart';
import '../integrity/checks/category_kind_check.dart';
import '../prudent_local_store.dart';
import '../wire_mapper.dart';
import 'ledger.dart';
import 'ledger_errors.dart';
import 'ledger_view.dart';
import '../write_expect.dart';

/// Prudent Local's plans, their occurrences and their reminders (unit 6b of
/// `docs/implemented-plans/PRUDENT-LOCAL-PLAN.md`, ADR-119): phase-0 §0.3 rows 6.29–6.45 and 6.51–6.53, over
/// [PrudentLocalStore], with the server's `PlanResource`, `OccurrenceResource`, `ReminderResource`
/// and `RecurrenceRule` as the specification. Wire requests in, wire messages out, refusals shaped
/// as the server's, so the parity suite compares one answer against the other and the Local app's
/// repository (unit 9) hands the shared screens — and the existing local-notification scheduler of
/// `packages/prudent_ui` — the messages they already read.
///
/// **Nothing about an occurrence is stored but what a person decided** (ADR-102): which date a rule
/// produces is a pure function of the plan, completed is "the confirming record exists", overdue is
/// "planned and before today". What is stored is an [OccurrenceState] — skipped, or a reminder read —
/// under an id derived from the plan and the date, and only while it differs from the default.
/// Consequences, all stated in ADR-119:
///
/// - Nothing is *generated*: the server materialises a plan's window on every view and keeps the
///   rows; here the window is read from the rule each time. Both look back at most 366 days
///   ([lookbackDays]), and a skipped or completed occurrence outside the current rule is still
///   listed, as the server keeps it.
/// - **Confirmation writes one record** — the plan's amounts as a record, under the id derived from
///   the occurrence — and that is the whole of it: two devices that confirm one occurrence write one
///   record, never two, and deleting the record reopens the occurrence because nothing else said it
///   was done. Deleting a plan deletes its states in one `writeAll`; its records are detached by
///   being read as detached (`Ledger`).
/// - **Time is an argument.** Every operation whose answer depends on the day takes `asOf` (finding
///   F-07) and reckons it in each plan's own zone. Nothing here reads the clock.
/// - **A figure never reads a value two devices disagree about** (ADR-113). A plan in conflict about
///   its amounts, schedule or reminder — or about whether it exists — and an occurrence in conflict
///   about whether it was skipped or paid, has no occurrence in any list and no reminder; the lists
///   answer as [Settled] naming it, planned cash flow (ADR-042) being their sum. Such an occurrence
///   cannot be skipped, restored, confirmed or read until the person settles it.
final class PlanLedger {
  final PrudentLocalStore store;

  PlanLedger(this.store);

  /// How far back the views look for occurrences: a plan opened after a year away shows nothing older
  /// as overdue, "an unresolved commitment is history rather than something to act on"
  /// (`OccurrenceResource.LOOKBACK_DAYS`).
  static const int lookbackDays = 366;

  /// The upcoming window when `days` is omitted (`OccurrenceResource.DEFAULT_UPCOMING_DAYS`).
  static const int defaultUpcomingDays = 30;

  /// The widest upcoming window (`OccurrenceResource.MAX_UPCOMING_DAYS`).
  static const int maxUpcomingDays = 366;

  // ── Plans ───────────────────────────────────────────────────────────────────────────────────

  /// `PlanResource.list`, ordered by start date and then id (row 6.53).
  Future<ZenResult<wire.ListPlansResponse>> listPlans() => _run(() async {
    final view = LedgerView.read(store);
    final plans = view.plans.values.toList()
      ..sort((a, b) {
        final byStart = _rule(a).startDate.compareTo(_rule(b).startDate);
        return byStart != 0 ? byStart : LocalIds.compare(a.id, b.id);
      });
    return wire.ListPlansResponse(plans: [for (final p in plans) _planWire(p)]);
  });

  /// `PlanResource.get`: 404 for an id that is not one or names no plan.
  Future<ZenResult<wire.Plan>> getPlan(String id) => _run(() async {
    return _planWire(_requirePlan(LedgerView.read(store), id));
  });

  /// `PlanResource.create` (rows 6.29–6.32).
  Future<ZenResult<wire.Plan>> createPlan(wire.CreatePlanRequest request) => _run(() async {
    final view = LedgerView.read(store);
    final plan = _plan(
      view,
      null,
      store.newId(),
      title: request.title,
      amountMinor: request.amountMinor.toInt(),
      currency: request.currency,
      accountId: request.accountId,
      categoryId: request.categoryId,
      payee: request.hasPayee() ? request.payee : null,
      note: request.hasNote() ? request.note : null,
      recurrence: request.hasRecurrence() ? request.recurrence : null,
      reminder: request.hasReminder() ? request.reminder : null,
    );
    return _planWire(await _write(store.putPlan(plan, expect: _asRead(null, _noPlan))));
  });

  /// `PlanResource.replace`: a full replacement, so an absent reminder resets it (row 6.33). When the
  /// schedule changed, the plan's still-planned occurrences the new schedule no longer produces go
  /// with it — a stored state of one that was restored or read — in the same write; skipped and
  /// completed ones are the person's decisions and stay (`OccurrenceGenerator.dropStale`, ADR-039).
  Future<ZenResult<wire.Plan>> replacePlan(String id, wire.UpdatePlanRequest request) =>
      _run(() async {
        final view = LedgerView.read(store);
        final current = _requirePlan(view, id);
        final plan = _plan(
          view,
          current,
          current.id,
          title: request.title,
          amountMinor: request.amountMinor.toInt(),
          currency: request.currency,
          accountId: request.accountId,
          categoryId: request.categoryId,
          payee: request.hasPayee() ? request.payee : null,
          note: request.hasNote() ? request.note : null,
          recurrence: request.hasRecurrence() ? request.recurrence : null,
          reminder: request.hasReminder() ? request.reminder : null,
        );
        final batch = StoreBatch(store)..putPlan(plan, expect: _asRead(current, _noPlan));
        final before = _rule(current);
        final after = _rule(plan);
        if (before != after) {
          final states = _States.read(store);
          for (final state in states.byPlan(plan.id)) {
            final date = CivilDate.parse(state.occurrenceDate);
            final confirmed = _confirmed(view, state.id) != null;
            if (!state.skipped && !confirmed && after.occurrencesBetween(date, date).isEmpty) {
              batch.deleteOccurrenceState(state.id, expect: _asRead(state, _changed));
            }
          }
        }
        await _write(store.writeAll(batch), missing: _changed);
        return _planWire(readOrThrow(store.plans.get(plan.id)));
      });

  /// `PlanResource.delete` (row 6.34): the plan and its occurrence states go in one write. Its
  /// records stay in the ledger and read as detached, which is all the server's `detachFromPlan`
  /// does; no balance and no total moves.
  Future<ZenResult<void>> deletePlan(String id) => _run(() async {
    final view = LedgerView.read(store);
    final plan = _requirePlan(view, id);
    final batch = StoreBatch(store)..deletePlan(plan.id, expect: _asRead(plan, _noPlan));
    for (final state in _States.read(store).byPlan(plan.id)) {
      batch.deleteOccurrenceState(state.id, expect: _asRead(state, _changed));
    }
    await _write(store.writeAll(batch), missing: _noPlan);
  });

  // ── Occurrence views ────────────────────────────────────────────────────────────────────────

  /// `OccurrenceResource.upcoming` (row 6.51): every occurrence dated from today, in its plan's
  /// zone, to [days] ahead (default 30, 1–366, else 400), in any state, ordered by date and then by
  /// Java's `UUID.compareTo` of the id (finding F-11). A plan that two devices disagree about has no
  /// occurrence here, and the answer names it ([Settled.unsettled]).
  Future<ZenResult<Settled<wire.ListOccurrencesResponse>>> upcoming({
    int? days,
    required DateTime asOf,
  }) => _run(() async {
    final horizon = days ?? defaultUpcomingDays;
    if (horizon < 1 || horizon > maxUpcomingDays) {
      throw Refusal.invalid('6.51', 'days must be between 1 and $maxUpcomingDays, not $horizon.');
    }
    return _list(asOf, (o, today) {
      final date = o.date;
      return date.compareTo(today) >= 0 && date.compareTo(today.plusDays(horizon)) <= 0;
    }, lookahead: horizon);
  });

  /// `OccurrenceResource.overdue` (row 6.38): the occurrences still planned whose date is before
  /// today in their plan's zone. Skipped and completed ones are resolved and are not listed.
  Future<ZenResult<Settled<wire.ListOccurrencesResponse>>> overdue({required DateTime asOf}) =>
      _run(() async {
        return _list(
          asOf,
          (o, today) => o.open && o.date.compareTo(today) < 0,
          lookahead: 0,
        );
      });

  /// The occurrence of [planId] on [date], or 404 (row 6.35): how a caller that knows a plan and a
  /// date gets the id the other operations take. Looked up in the same window the views read.
  Future<ZenResult<wire.PlanOccurrence>> occurrenceOf(
    String planId,
    String date, {
    required DateTime asOf,
  }) => _run(() async {
    final view = _View.read(store);
    final wanted = CivilDate.tryParse(date);
    final found = wanted == null
        ? null
        : _find(view, DerivedIds.occurrence(_validId(planId), wanted.toString()), asOf);
    if (found == null) throw const Refusal.notFound('6.35', 'No such occurrence.');
    return _occurrenceWire(found);
  });

  /// `OccurrenceResource.skip` (row 6.37): planned or overdue becomes skipped; anything else is 409.
  Future<ZenResult<wire.PlanOccurrence>> skip(String id, {required DateTime asOf}) =>
      _run(() async {
        final view = _View.read(store);
        final occurrence = _require(view, id, asOf);
        _requireSettled(occurrence);
        if (!occurrence.open) {
          throw Refusal.conflict(
            '6.37',
            'An occurrence that is ${occurrence.stateName} cannot become SKIPPED.',
          );
        }
        await _writeState(occurrence, skipped: true);
        return _occurrenceWire(occurrence.with_(skipped: true));
      });

  /// `OccurrenceResource.restore` (row 6.37): skipped becomes planned; anything else is 409.
  Future<ZenResult<wire.PlanOccurrence>> restore(String id, {required DateTime asOf}) =>
      _run(() async {
        final view = _View.read(store);
        final occurrence = _require(view, id, asOf);
        _requireSettled(occurrence);
        if (!occurrence.skipped || occurrence.completed) {
          throw Refusal.conflict(
            '6.37',
            'An occurrence that is ${occurrence.stateName} cannot become PLANNED.',
          );
        }
        await _writeState(occurrence, skipped: false);
        return _occurrenceWire(occurrence.with_(skipped: false));
      });

  /// `OccurrenceResource.confirm` (rows 6.39, 6.40): creates exactly one record from a planned or
  /// overdue occurrence — the plan's title, payee, note, amount, account and category unless the
  /// request overrides date, amount, account or category for this record alone — carrying both plan
  /// ids. It is the only thing that completes an occurrence. A skipped or completed one is 409
  /// whatever the request says; a request the record rules refuse is refused and writes nothing.
  ///
  /// The record's id is derived from the occurrence, so a second confirmation — on this device or
  /// another — writes the same record and never a second one.
  Future<ZenResult<wire.ConfirmOccurrenceResponse>> confirm(
    String id,
    wire.ConfirmOccurrenceRequest request, {
    required DateTime asOf,
  }) => _run(() async {
    final view = _View.read(store);
    final occurrence = _require(view, id, asOf);
    _requireSettled(occurrence);
    if (!occurrence.open) {
      throw Refusal.conflict(
        '6.37',
        'An occurrence that is ${occurrence.stateName} cannot become COMPLETED.',
      );
    }
    final plan = occurrence.plan;
    final record =
        Ledger.recordForConfirmation(
            view.ledger,
            DerivedIds.confirmation(occurrence.id),
            title: plan.title,
            amountMinor: request.hasAmountMinor()
                ? request.amountMinor.toInt()
                : plan.posting.amountMinor.toInt(),
            date: request.hasDate() ? request.date : occurrence.date.toString(),
            categoryId: request.hasCategoryId() ? request.categoryId : plan.categoryId,
            accountId: request.hasAccountId() ? request.accountId : plan.posting.accountId,
            currency: plan.posting.currency,
            payee: plan.hasPayee() ? plan.payee : null,
            note: plan.hasNote() ? plan.note : null,
          )
          ..planLink = PlanLink(
            planId: plan.id,
            occurrenceId: occurrence.id,
            occurrenceDate: occurrence.date.toString(),
          );
    // One write: the record, expected still absent (a confirmation that landed meanwhile is a 409,
    // as the server's second confirmation is), and the plan it was decided against, expected
    // unchanged, so a plan a sync deleted or edited in between refuses the whole.
    final batch = StoreBatch(store)
      ..putRecord(record, expect: _asRead(null, _noOccurrence, changed: _alreadyConfirmed))
      ..putPlan(plan, expect: _asRead(plan, _noOccurrence));
    if (occurrence.state case final state?) {
      batch.putOccurrenceState(state, expect: _asRead(state, _changed));
    }
    await _write(store.writeAll(batch), missing: _changed);
    return wire.ConfirmOccurrenceResponse(
      occurrence: _occurrenceWire(occurrence.with_(completed: true)),
      record: WireMapper.recordToWire(record),
    );
  });

  // ── Reminders ───────────────────────────────────────────────────────────────────────────────

  /// `ReminderResource.list` (rows 6.42, 6.52): every still-planned occurrence of a plan whose
  /// reminder is on that is within its lead time or past its date, in the plan's own calendar day,
  /// oldest date first and then by Java's `UUID.compareTo` of the id (finding F-11). Confirmed and
  /// skipped occurrences have no reminder. A plan two devices disagree about has none, and the
  /// answer names it.
  Future<ZenResult<Settled<wire.ListRemindersResponse>>> reminders({required DateTime asOf}) =>
      _run(() async => _reminderList(_View.read(store), asOf));

  /// `ReminderResource.read` (row 6.43): marks one reminder read at [asOf], keeping the first time
  /// when it was already read. 404 for no such occurrence; 409 when it has no reminder right now.
  Future<ZenResult<wire.DueReminder>> markRead(String occurrenceId, {required DateTime asOf}) =>
      _run(() async {
        final view = _View.read(store);
        final due = _requireDue(view, occurrenceId, asOf);
        if (!due.read) await _writeState(due, readAtMs: asOf.millisecondsSinceEpoch);
        return _reminderWire(due.with_(readAtMs: due.read ? null : asOf.millisecondsSinceEpoch));
      });

  /// `ReminderResource.unread` (row 6.43): marks one reminder unread again.
  Future<ZenResult<wire.DueReminder>> markUnread(String occurrenceId, {required DateTime asOf}) =>
      _run(() async {
        final view = _View.read(store);
        final due = _requireDue(view, occurrenceId, asOf);
        await _writeState(due, readAtMs: 0);
        return _reminderWire(due.with_(readAtMs: 0));
      });

  /// `ReminderResource.readAll` (row 6.43): marks every current reminder read at [asOf], keeping the
  /// time of any that was already read, in one write, and answers with the list.
  Future<ZenResult<Settled<wire.ListRemindersResponse>>> markAllRead({required DateTime asOf}) =>
      _run(() async {
        final view = _View.read(store);
        final due = _currentReminders(view, asOf).due;
        final batch = StoreBatch(store);
        final planned = <String>{};
        for (final occurrence in due.where((o) => !o.read)) {
          _stageState(batch, occurrence, readAtMs: asOf.millisecondsSinceEpoch, planned: planned);
        }
        if (batch.length > 0) await _write(store.writeAll(batch), missing: _changed);
        return _reminderList(_View.read(store), asOf);
      });

  // ── Reading ─────────────────────────────────────────────────────────────────────────────────

  Settled<wire.ListOccurrencesResponse> _list(
    DateTime asOf,
    bool Function(_Occurrence occurrence, CivilDate today) include, {
    required int lookahead,
  }) {
    final view = _View.read(store);
    final unsettled = <String, Set<String>>{};
    final found = <_Occurrence>[];
    for (final plan in view.ledger.plans.values) {
      if (view.disputes(plan.id) case final ids when ids.isNotEmpty) {
        unsettled.putIfAbsent(plan.id, () => {}).addAll(ids);
        continue;
      }
      final rule = _rule(plan);
      final today = rule.today(asOf);
      for (final occurrence in view.occurrences(plan, rule, today, lookahead: lookahead)) {
        if (occurrence.unsettled.isNotEmpty) {
          unsettled.putIfAbsent(plan.id, () => {}).addAll(occurrence.unsettled);
        } else if (include(occurrence, today)) {
          found.add(occurrence);
        }
      }
    }
    for (final plan in view.disputedPlansWithoutValue()) {
      unsettled.putIfAbsent(plan, () => {}).add(plan);
    }
    found.sort(_byDateThenId);
    return Settled(
      wire.ListOccurrencesResponse(occurrences: [for (final o in found) _occurrenceWire(o)]),
      {
        for (final MapEntry(:key, :value) in unsettled.entries) key: (value.toList()..sort()),
      },
    );
  }

  Settled<wire.ListRemindersResponse> _reminderList(_View view, DateTime asOf) {
    final current = _currentReminders(view, asOf);
    return Settled(
      wire.ListRemindersResponse(reminders: [for (final o in current.due) _reminderWire(o)]),
      current.unsettled,
    );
  }

  ({List<_Occurrence> due, Map<String, List<String>> unsettled}) _currentReminders(
    _View view,
    DateTime asOf,
  ) {
    final unsettled = <String, Set<String>>{};
    final due = <_Occurrence>[];
    for (final plan in view.ledger.plans.values) {
      final reminder = _reminder(plan);
      if (!reminder.enabled) continue;
      if (view.disputes(plan.id) case final ids when ids.isNotEmpty) {
        unsettled.putIfAbsent(plan.id, () => {}).addAll(ids);
        continue;
      }
      final rule = _rule(plan);
      final today = rule.today(asOf);
      for (final occurrence in view.occurrences(
        plan,
        rule,
        today,
        lookahead: reminder.leadDays,
      )) {
        if (occurrence.unsettled.isNotEmpty) {
          unsettled.putIfAbsent(plan.id, () => {}).addAll(occurrence.unsettled);
        } else if (_hasReminder(occurrence, today)) {
          due.add(occurrence);
        }
      }
    }
    due.sort(_byDateThenId);
    return (
      due: due,
      unsettled: {
        for (final MapEntry(:key, :value) in unsettled.entries) key: (value.toList()..sort()),
      },
    );
  }

  /// Whether the occurrence is a reminder as of its plan's [today]: still planned, its plan's
  /// reminder on, and no further ahead than the lead time. Past its date it stays one — overdue
  /// (`ReminderResource.hasReminder`, the single place that says so).
  static bool _hasReminder(_Occurrence occurrence, CivilDate today) {
    final reminder = _reminder(occurrence.plan);
    return reminder.enabled &&
        occurrence.open &&
        occurrence.date.compareTo(today.plusDays(reminder.leadDays)) <= 0;
  }

  static int _byDateThenId(_Occurrence a, _Occurrence b) {
    final byDate = a.date.compareTo(b.date);
    // `Comparator.comparing(date).thenComparing(id)` over java.util.UUID: the signed comparison
    // (finding F-11), where the SQL `order by` of the plan list is byte order.
    return byDate != 0 ? byDate : LocalIds.compareAsJavaUuid(a.id, b.id);
  }

  _Occurrence? _find(_View view, String id, DateTime asOf) {
    if (!LocalIds.isValid(id)) return null;
    for (final plan in view.plansToSearch()) {
      final rule = _rule(plan);
      final today = rule.today(asOf);
      for (final occurrence in view.occurrences(
        plan,
        rule,
        today,
        lookahead: maxUpcomingDays,
      )) {
        if (occurrence.id != id) continue;
        // A plan two devices disagree about leaves all of its occurrences unsettled (`_View.disputes`).
        final disputes = view.disputes(plan.id);
        return disputes.isEmpty
            ? occurrence
            : occurrence.with_(unsettled: [...occurrence.unsettled, ...disputes]);
      }
    }
    return null;
  }

  /// `Ids.parse` then `findOwnedForUpdate`: 404 for an id that is not one or names no occurrence.
  _Occurrence _require(_View view, String id, DateTime asOf) =>
      _find(view, id, asOf) ?? (throw const Refusal.notFound('6.35', 'No such occurrence.'));

  /// An occurrence of a plan or an occurrence state two devices disagree about cannot be changed: the
  /// change would be written over a guess. 409, as every refusal that says "settle this first"
  /// (`Ledger.createCorrection`).
  static void _requireSettled(_Occurrence occurrence) {
    if (occurrence.unsettled.isNotEmpty) {
      throw const Refusal.conflict(
        '6.37',
        'This occurrence has changes from two devices waiting to be settled; settle them first.',
      );
    }
  }

  /// `ReminderResource.findCurrent`: the occurrence, when it has a reminder right now.
  _Occurrence _requireDue(_View view, String id, DateTime asOf) {
    final occurrence = _require(view, id, asOf);
    _requireSettled(occurrence);
    final today = _rule(occurrence.plan).today(asOf);
    if (!_hasReminder(occurrence, today)) {
      throw const Refusal.conflict(
        '6.43',
        'That occurrence has no reminder right now: its plan\'s reminder is off, it is already '
            'confirmed or skipped, or it is not yet within the plan\'s lead time.',
      );
    }
    return occurrence;
  }

  /// The record that confirms the occurrence whose state id is [occurrenceId], or null.
  static String? _confirmed(LedgerView view, String occurrenceId) {
    final record = DerivedIds.confirmation(occurrenceId);
    return view.records.containsKey(record) || view.recordConflicts.containsKey(record)
        ? record
        : null;
  }

  // ── Writing states ──────────────────────────────────────────────────────────────────────────

  Future<void> _writeState(_Occurrence occurrence, {bool? skipped, int? readAtMs}) async {
    final batch = StoreBatch(store);
    _stageState(batch, occurrence, skipped: skipped, readAtMs: readAtMs);
    if (batch.length > 0) await _write(store.writeAll(batch), missing: _changed);
  }

  /// Stages the state [occurrence] has after the change: stored only while it differs from the
  /// default (skipped, or a reminder read) or while the schedule no longer produces the date — an
  /// occurrence restored after its schedule changed still exists on the server as a planned row, and
  /// here only a state keeps it. [readAtMs] of 0 clears the read time; null leaves it.
  void _stageState(
    StoreBatch batch,
    _Occurrence occurrence, {
    bool? skipped,
    int? readAtMs,
    Set<String>? planned,
  }) {
    planned ??= {};
    final current = occurrence.state;
    final next = (current?.deepCopy() ?? occurrence.newState())
      ..clearSkipped()
      ..clearReminderReadAtMs();
    final isSkipped = skipped ?? current?.skipped ?? false;
    final readAt = readAtMs ?? current?.reminderReadAtMs.toInt() ?? 0;
    if (isSkipped) next.skipped = true;
    if (readAt != 0) next.reminderReadAtMs = Int64(readAt);
    final isDefault = !isSkipped && readAt == 0;
    if (isDefault && occurrence.fromRule) {
      if (current != null) {
        batch.deleteOccurrenceState(current.id, expect: _asRead(current, _changed));
      }
    } else {
      batch.putOccurrenceState(next, expect: _asRead(current, _changed));
    }
    // The plan the change was decided against, expected unchanged and written back as it is: a state
    // for a plan a sync deleted, or whose schedule or reminder it edited, would be an orphan or a guess.
    if (planned.add(occurrence.plan.id)) {
      batch.putPlan(occurrence.plan, expect: _asRead(occurrence.plan, _noOccurrence));
    }
  }

  // ── Plan rules ──────────────────────────────────────────────────────────────────────────────

  /// `PlanResource.apply`, check for check and in its order (rows 6.29–6.32): the reminder, title,
  /// amount, account, category, the category's archived state and kind (when the category or the
  /// direction changes), currency, the account holding it, then the recurrence.
  static Plan _plan(
    LedgerView view,
    Plan? current,
    String id, {
    required String title,
    required int amountMinor,
    required String currency,
    required String accountId,
    required String categoryId,
    required String? payee,
    required String? note,
    required wire.Recurrence? recurrence,
    required wire.Reminder? reminder,
  }) {
    // Evaluated first on the server too: `ReminderSetting.fromProto` runs as an argument.
    final lead = ReminderLeadTimes.parse(
      reminder != null && reminder.hasLeadDays() ? reminder.leadDays : null,
    );
    final enabled = reminder != null && reminder.enabled;

    final trimmed = TextRules.requiredTrimmed(title, rule: '6.29');
    if (amountMinor == 0) {
      throw const Refusal.invalid(
        '6.29',
        'A plan needs a nonzero amount. Negative is planned spending, positive is income.',
      );
    }
    final account = _inBody(view.accounts, accountId, 'account');
    final category = _inBody(view.categories, categoryId, 'category');
    final sameCategory = current != null && current.categoryId == category.id;
    if (!sameCategory && category.archived) {
      throw const Refusal.conflict('6.29', 'This category is archived.');
    }
    final sameDirection =
        current != null && signum(current.posting.amountMinor.toInt()) == signum(amountMinor);
    if ((!sameCategory || !sameDirection) &&
        !CategoryKindCheck.canFile(category.kind, amountMinor)) {
      throw const Refusal.invalid('6.29', 'This category is for the other direction.');
    }
    final normalized = Currencies.parse(currency);
    if (!view.holds(account.id, normalized)) {
      throw const Refusal.invalid('6.29', 'The account does not hold this currency.');
    }
    final rule = _recurrence(recurrence);

    final plan = Plan(
      id: id,
      categoryId: category.id,
      posting: Posting(
        accountId: account.id,
        currency: normalized,
        amountMinor: Int64(amountMinor),
      ),
      schedule: _schedule(rule),
    );
    if (trimmed.isNotEmpty) plan.title = trimmed;
    if (TextRules.optionalTrimmed(payee) case final value?) plan.payee = value;
    if (TextRules.optionalTrimmed(note) case final value?) plan.note = value;
    // Every default is left unset (jZenDev/jZen#245): a reminder that is off at the default lead is no
    // reminder at all, so two devices that set the same state write the same bytes.
    if (enabled || lead != ReminderLeadTimes.defaultDays) {
      plan.reminder = ReminderSetting();
      if (enabled) plan.reminder.enabled = true;
      if (lead != ReminderLeadTimes.defaultDays) plan.reminder.leadDays = lead;
    }
    return plan;
  }

  /// A body-field id (`Ids.parseInBody` + `findOwned`): 400, not 404, for a blank, malformed or
  /// unknown id.
  static T _inBody<T>(Map<String, T> values, String id, String what) {
    if (javaIsBlank(id)) throw Refusal.invalid('6.29', 'A plan needs its $what.');
    final found = LocalIds.isValid(id) ? values[id] : null;
    if (found == null) throw Refusal.invalid('6.29', 'No such $what.');
    return found;
  }

  static RecurrenceRule _recurrence(wire.Recurrence? recurrence) {
    if (recurrence == null) throw const Refusal.invalid('6.30', 'A plan needs a recurrence.');
    return RecurrenceRule.parse(
      frequency: switch (recurrence.frequency) {
        wire.RecurrenceFrequency.RECURRENCE_FREQUENCY_ONCE => PlanFrequency.once,
        wire.RecurrenceFrequency.RECURRENCE_FREQUENCY_DAILY => PlanFrequency.daily,
        wire.RecurrenceFrequency.RECURRENCE_FREQUENCY_WEEKLY => PlanFrequency.weekly,
        wire.RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY => PlanFrequency.monthly,
        wire.RecurrenceFrequency.RECURRENCE_FREQUENCY_YEARLY => PlanFrequency.yearly,
        _ => null,
      },
      interval: recurrence.interval,
      startDate: recurrence.startDate,
      timeZone: recurrence.timeZone,
      untilDate: recurrence.whichEnd() == wire.Recurrence_End.untilDate
          ? recurrence.untilDate
          : null,
      occurrenceCount: recurrence.whichEnd() == wire.Recurrence_End.occurrenceCount
          ? recurrence.occurrenceCount
          : null,
    );
  }

  static Schedule _schedule(RecurrenceRule rule) {
    final schedule = Schedule(
      frequency: switch (rule.frequency) {
        PlanFrequency.once => Frequency.FREQUENCY_ONCE,
        PlanFrequency.daily => Frequency.FREQUENCY_DAILY,
        PlanFrequency.weekly => Frequency.FREQUENCY_WEEKLY,
        PlanFrequency.monthly => Frequency.FREQUENCY_MONTHLY,
        PlanFrequency.yearly => Frequency.FREQUENCY_YEARLY,
      },
      interval: rule.interval,
      startDate: rule.startDate.toString(),
      timeZone: rule.timeZone,
    );
    if (rule.untilDate != null) schedule.untilDate = rule.untilDate.toString();
    if (rule.occurrenceCount != null) schedule.occurrenceCount = rule.occurrenceCount!;
    return schedule;
  }

  /// The rule of a stored plan. Every write path validated it, so one that does not parse was not
  /// written by this ledger: a storage failure naming the plan, never a 400 for the caller.
  static RecurrenceRule _rule(Plan plan) {
    try {
      final s = plan.schedule;
      return RecurrenceRule.parse(
        frequency: switch (s.frequency) {
          Frequency.FREQUENCY_ONCE => PlanFrequency.once,
          Frequency.FREQUENCY_DAILY => PlanFrequency.daily,
          Frequency.FREQUENCY_WEEKLY => PlanFrequency.weekly,
          Frequency.FREQUENCY_MONTHLY => PlanFrequency.monthly,
          Frequency.FREQUENCY_YEARLY => PlanFrequency.yearly,
          _ => null,
        },
        interval: s.interval,
        startDate: s.startDate,
        timeZone: s.timeZone,
        untilDate: s.whichEnd() == Schedule_End.untilDate ? s.untilDate : null,
        occurrenceCount: s.whichEnd() == Schedule_End.occurrenceCount ? s.occurrenceCount : null,
      );
    } on Refusal {
      throw LedgerReadFailure(ZenStorageError('plans/${plan.id} holds a schedule that is not valid.'));
    }
  }

  /// The rule of a stored plan's schedule (see [_rule]); how `Ledger.deleteRecord` knows whether the
  /// schedule still produces the date a deleted confirmation reopens.
  static RecurrenceRule ruleOf(Plan plan) => _rule(plan);

  static ({bool enabled, int leadDays}) _reminder(Plan plan) => (
    enabled: plan.hasReminder() && plan.reminder.enabled,
    leadDays: plan.hasReminder() && plan.reminder.hasLeadDays()
        ? plan.reminder.leadDays
        : ReminderLeadTimes.defaultDays,
  );

  static String _validId(String id) =>
      LocalIds.isValid(id) ? id : throw const Refusal.notFound('6.35', 'No such plan.');

  /// `PlanResource.require`: 404 for an id that is not one or names no plan.
  static Plan _requirePlan(LedgerView view, String id) {
    final plan = LocalIds.isValid(id) ? view.plans[id] : null;
    if (plan == null) throw const Refusal.notFound('6.33', 'No such plan.');
    return plan;
  }

  // ── Wire ────────────────────────────────────────────────────────────────────────────────────

  /// A plan as the wire carries it: the server always answers a reminder, at its default when none
  /// was set.
  static wire.Plan _planWire(Plan plan) {
    final out = WireMapper.planToWire(plan);
    final reminder = _reminder(plan);
    out.reminder = wire.Reminder(enabled: reminder.enabled, leadDays: reminder.leadDays);
    return out;
  }

  static wire.PlanOccurrence _occurrenceWire(_Occurrence o) => WireMapper.occurrenceToWire(
    plan: o.plan,
    date: o.date.toString(),
    status: o.status,
    state: o.state,
  );

  static wire.DueReminder _reminderWire(_Occurrence o) {
    final lead = _reminder(o.plan).leadDays;
    return wire.DueReminder(
      occurrence: _occurrenceWire(o),
      remindOn: o.date.plusDays(-lead).toString(),
      leadDays: lead,
      read: o.read,
    );
  }

  // ── Shared ──────────────────────────────────────────────────────────────────────────────────

  // ── Write preconditions ─────────────────────────────────────────────────────────────────────

  /// The record must still be [basis] — the version this operation's rules were checked against, or
  /// absent when [basis] is null — when the store runs the write (ADR-115, ADR-122). Gone since:
  /// [gone], the 404 the server gives. Changed since: [changed], 409 under §0.3 X.7 unless the
  /// caller says what that change means.
  static WriteExpect<T> _asRead<T extends GeneratedMessage>(
    T? basis,
    Refusal gone, {
    Refusal changed = _changed,
  }) => WriteExpects.asRead(
    basis,
    gone: () => LedgerErrors.of(gone),
    changed: () => LedgerErrors.of(changed),
  );

  static const _changed = Refusal.conflict(
    'X.7',
    'This changed on another device while it was being saved. Look at it again.',
  );
  static const _noPlan = Refusal.notFound('6.33', 'No such plan.');
  static const _noOccurrence = Refusal.notFound('6.35', 'No such occurrence.');

  /// A confirmation that landed on another device while this one was being made: the occurrence is
  /// completed, which the server answers 409 (`OccurrenceState.successors`).
  static const _alreadyConfirmed = Refusal.conflict(
    '6.37',
    'An occurrence that is COMPLETED cannot become COMPLETED.',
  );

  /// The value of a store write, or a [LedgerReadFailure] with the store's own error. [missing] is
  /// the refusal for a **delete** whose record a sync removed between the check and the write: jZen
  /// answers that itself with a bare not-found before any precondition runs, so it is mapped here
  /// (see `Ledger._write`).
  static Future<T> _write<T>(Future<ZenResult<T>> write, {Refusal? missing}) async {
    final result = await write;
    if (result case ZenFailure(:final error)
        when missing != null && error is ZenNotFoundError && LedgerErrors.statusOf(error) == null) {
      throw missing;
    }
    return readOrThrow(result);
  }

  /// Runs one operation: a rule's [Refusal] becomes the server-shaped error, the store's errors are
  /// returned as they are, and a date outside the calendar is an error, never a wrapped value.
  static Future<ZenResult<T>> _run<T>(Future<T> Function() body) async {
    try {
      return ZenResult.ok(await body());
    } on Refusal catch (refusal) {
      return ZenResult.err(LedgerErrors.of(refusal));
    } on LedgerReadFailure catch (failure) {
      return ZenResult.err(failure.error);
    } on CalendarOverflow {
      return ZenResult.err(ZenUnknownError('A date left the range the calendar can hold.'));
    }
  }
}

/// The plans' read of the store: the ledger's, and the occurrence states with what is in conflict.
final class _View {
  final LedgerView ledger;
  final _States states;

  _View._(this.ledger, this.states);

  factory _View.read(PrudentLocalStore store) =>
      _View._(LedgerView.read(store), _States.read(store));

  static final int _postingTag = Plan().info_.byName['posting']!.tagNumber;
  static final int _categoryTag = Plan().info_.byName['categoryId']!.tagNumber;
  static final int _scheduleTag = Plan().info_.byName['schedule']!.tagNumber;
  static final int _reminderTag = Plan().info_.byName['reminder']!.tagNumber;
  static final int _skippedTag = OccurrenceState().info_.byName['skipped']!.tagNumber;

  /// What about [planId] two devices disagree about, as the ids that name it: its existence or a
  /// field every occurrence reads (amount, account, currency, category, schedule, reminder). A
  /// conflict about a title, payee or note leaves every figure agreed.
  List<String> disputes(String planId) {
    final conflict = ledger.planConflicts[planId];
    if (conflict == null) return const [];
    final touches =
        conflict.isDeleteConflict ||
        conflict.fields.any(
          {_postingTag, _categoryTag, _scheduleTag, _reminderTag}.contains,
        );
    return touches ? [planId] : const [];
  }

  /// Plans that exist only as the sides of a delete conflict, so the plan list does not hold them.
  Iterable<String> disputedPlansWithoutValue() sync* {
    for (final conflict in ledger.planConflicts.values) {
      if (conflict.isDeleteConflict && !ledger.plans.containsKey(conflict.id)) yield conflict.id;
    }
  }

  /// The plans an occurrence id is looked for in: the plan list, and a plan that is only the side of
  /// a conflict, so that its occurrence is refused as unsettled and not reported as missing.
  Iterable<Plan> plansToSearch() sync* {
    yield* ledger.plans.values;
    for (final conflict in ledger.planConflicts.values) {
      if (ledger.plans.containsKey(conflict.id)) continue;
      final side = conflict.sides.map((s) => s.value).whereType<Plan>().firstOrNull;
      if (side != null) yield side;
    }
  }

  /// Every occurrence of [plan] a view could list at [today]: the dates its rule produces from 366
  /// days back (never before its start) to [lookahead] days ahead, and those it no longer produces
  /// but a person decided — skipped, or confirmed — or restored.
  List<_Occurrence> occurrences(
    Plan plan,
    RecurrenceRule rule,
    CivilDate today, {
    required int lookahead,
  }) {
    // Not clipped at the plan's start: the rule produces nothing earlier by itself, and an
    // occurrence a person decided under an earlier schedule can fall before the new one starts.
    final from = today.plusDays(-PlanLedger.lookbackDays);
    final to = today.plusDays(lookahead);
    final byDate = <String, _Occurrence>{};
    void add(CivilDate date, {required bool fromRule}) {
      if (date.compareTo(from) < 0 || date.compareTo(to) > 0) return;
      byDate.putIfAbsent(
        date.toString(),
        () => _build(plan, rule, date, today, fromRule: fromRule),
      );
    }

    if (to.compareTo(from) >= 0) {
      for (final date in rule.occurrencesBetween(from, to)) {
        add(date, fromRule: true);
      }
    }
    for (final state in states.byPlan(plan.id)) {
      add(CivilDate.parse(state.occurrenceDate), fromRule: false);
    }
    for (final conflict in states.conflictsOfPlan(plan.id)) {
      add(CivilDate.parse(conflict.date), fromRule: false);
    }
    for (final record in _confirmingRecords(plan.id)) {
      add(CivilDate.parse(record.planLink.occurrenceDate), fromRule: false);
    }
    return byDate.values.toList();
  }

  Iterable<Record> _confirmingRecords(String planId) sync* {
    for (final record in ledger.recordValues()) {
      if (record.hasPlanLink() &&
          record.planLink.planId == planId &&
          record.planLink.occurrenceDate.isNotEmpty) {
        yield record;
      }
    }
  }

  _Occurrence _build(
    Plan plan,
    RecurrenceRule rule,
    CivilDate date,
    CivilDate today, {
    required bool fromRule,
  }) {
    final id = DerivedIds.occurrence(plan.id, date.toString());
    final state = states.states[id];
    final unsettled = <String>{};
    final stateConflict = states.conflicts[id];
    if (stateConflict != null &&
        (stateConflict.isDeleteConflict || stateConflict.fields.contains(_skippedTag))) {
      unsettled.add(id);
    }
    final confirming = DerivedIds.confirmation(id);
    final completed = ledger.records.containsKey(confirming);
    final recordConflict = ledger.recordConflicts[confirming];
    if (recordConflict != null && recordConflict.isDeleteConflict) unsettled.add(confirming);
    return _Occurrence(
      plan: plan,
      date: date,
      id: id,
      today: today,
      state: state,
      completed: completed || recordConflict != null,
      skipped: state?.skipped ?? false,
      fromRule: fromRule || rule.occurrencesBetween(date, date).isNotEmpty,
      unsettled: unsettled.toList()..sort(),
    );
  }
}

/// The stored occurrence states, and the ones two devices disagree about.
final class _States {
  final Map<String, OccurrenceState> states;
  final Map<String, ZenConflict<OccurrenceState>> conflicts;

  _States(this.states, this.conflicts);

  factory _States.read(PrudentLocalStore store) => _States(
    {for (final s in readOrThrow(store.occurrences.list())) s.id: s},
    {for (final c in readOrThrow(store.occurrences.conflicts())) c.id: c},
  );

  Iterable<OccurrenceState> byPlan(String planId) => states.values.where((s) => s.planId == planId);

  /// The conflicts about an occurrence of [planId], by the date either side names.
  Iterable<({String id, String date})> conflictsOfPlan(String planId) sync* {
    for (final conflict in conflicts.values) {
      for (final side in conflict.sides) {
        final value = side.value;
        if (value != null && value.planId == planId) {
          yield (id: conflict.id, date: value.occurrenceDate);
          break;
        }
      }
    }
  }
}

/// One occurrence of a plan, derived: its status from the confirming record and the stored state,
/// its overdue-ness from its date and its plan's today.
final class _Occurrence {
  final Plan plan;
  final CivilDate date;
  final String id;
  final CivilDate today;
  final OccurrenceState? state;
  final bool completed;
  final bool skipped;

  /// Whether the plan's schedule produces this date (as against a skipped, completed or restored
  /// occurrence of an earlier schedule).
  final bool fromRule;

  /// The ids of what two devices disagree about that decides this occurrence's state; empty when it
  /// is settled.
  final List<String> unsettled;

  /// A reminder-read time set by the operation that built this value, before it is stored.
  final int? pendingReadAtMs;

  _Occurrence({
    required this.plan,
    required this.date,
    required this.id,
    required this.today,
    required this.state,
    required this.completed,
    required this.skipped,
    required this.fromRule,
    required this.unsettled,
    this.pendingReadAtMs,
  });

  /// Completed wins over skipped: money moved. Two devices that skipped and paid one occurrence end
  /// here, and the `occurrence.skipped_and_paid` check lists it.
  bool get open => !completed && !skipped;

  String get stateName => completed
      ? 'COMPLETED'
      : skipped
      ? 'SKIPPED'
      : 'PLANNED';

  wire.OccurrenceStatus get status => completed
      ? wire.OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED
      : skipped
      ? wire.OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED
      : date.compareTo(today) < 0
      ? wire.OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE
      : wire.OccurrenceStatus.OCCURRENCE_STATUS_PLANNED;

  /// Whether the reminder has been read: a stored read time, or one this operation just set.
  bool get read => (pendingReadAtMs ?? state?.reminderReadAtMs.toInt() ?? 0) != 0;

  OccurrenceState newState() =>
      OccurrenceState(id: id, planId: plan.id, occurrenceDate: date.toString());

  _Occurrence with_({
    bool? skipped,
    bool? completed,
    int? readAtMs,
    List<String>? unsettled,
  }) => _Occurrence(
    plan: plan,
    date: date,
    id: id,
    today: today,
    state: state,
    completed: completed ?? this.completed,
    skipped: skipped ?? this.skipped,
    fromRule: fromRule,
    unsettled: unsettled ?? this.unsettled,
    pendingReadAtMs: readAtMs ?? pendingReadAtMs,
  );
}
