part of 'ledger.dart';

/// Goals, their envelopes, free money and progress (unit 6a of `docs/implemented-plans/PRUDENT-LOCAL-PLAN.md`):
/// phase-0 §0.3 rows 6.13–6.28, 6.46, 6.47, 6.54, each the server's resource method check for check
/// and in its order (`GoalResource`, `GoalState`, `GoalAllocationResource`, `FreeMoney`,
/// `GoalProgressCalculator`; ADR-049 to ADR-052).
///
/// **An envelope has no stored amount**: it is the sum of its goal's entries, which are written once
/// and never edited or deleted (append-only, ADR-050), so two devices' entries never conflict and an
/// envelope never reads a disputed value. **Free money and progress** read account balances and goal
/// fields, which two devices can dispute; there, as for balances (ADR-113), a disputed value counts in
/// no figure and is named in the answer's [Settled.unsettled].
///
/// A rule a merge can break afterwards — an envelope below zero after two withdrawals, money left in
/// a goal archived meanwhile — is not refused here but listed by the integrity checks
/// (`EnvelopeCheck`), as ADR-102 D6 decided.
extension LedgerGoals on Ledger {
  // ── Goals ───────────────────────────────────────────────────────────────────────────────────

  /// `GoalResource.list` (row 6.46): optionally one status by its exact constant name (`ACTIVE`,
  /// `COMPLETED`, `ARCHIVED`; anything else is a 400), ordered `created_at, id`.
  Future<ZenResult<wire.ListGoalsResponse>> listGoals({String? status}) => Ledger._run(() async {
    final state = status == null || javaIsBlank(status) ? null : _parseStatus(status);
    final view = LedgerView.read(store);
    return wire.ListGoalsResponse(
      goals: [
        for (final goal in _goalsInOrder(view))
          if (state == null || goal.status == state) WireMapper.goalToWire(goal),
      ],
    );
  });

  /// `GoalResource.get`: 404 for an id that is not one or names nothing.
  Future<ZenResult<wire.Goal>> getGoal(String id) =>
      Ledger._run(() async => WireMapper.goalToWire(_requireGoal(LedgerView.read(store), id)));

  /// `GoalResource.create` (row 6.13): the currency (400), then a name, a positive target and an
  /// optional ISO date (400 each). A new goal is active, and its status time is its creation time.
  Future<ZenResult<wire.Goal>> createGoal(wire.CreateGoalRequest request) => Ledger._run(() async {
    final currency = Currencies.parse(request.currency);
    final now = _clock();
    final goal = Goal(
      id: store.newId(),
      currency: currency,
      status: GoalState.GOAL_STATE_ACTIVE,
      statusChangedAtMs: Int64(now),
      createdAtMs: Int64(now),
    );
    _applyGoal(
      goal,
      name: request.name,
      targetAmountMinor: request.targetAmountMinor.toInt(),
      targetDate: request.hasTargetDate() ? request.targetDate : null,
    );
    return WireMapper.goalToWire(
      await Ledger._write(
        store.putGoal(
          goal,
          expect: (current) =>
              current == null ? null : ZenValidationError('goals/${goal.id} already exists.'),
        ),
      ),
    );
  });

  /// `GoalResource.replace` (rows 6.13, 6.15, 6.18): a full replacement of the name, target and
  /// date — an absent date clears it. An archived goal is read-only (409); its currency never
  /// changes.
  Future<ZenResult<wire.Goal>> updateGoal(String id, wire.UpdateGoalRequest request) =>
      Ledger._run(() async {
        final current = _requireGoal(LedgerView.read(store), id);
        if (current.status == GoalState.GOAL_STATE_ARCHIVED) {
          throw const Refusal.conflict('6.15', 'This goal is archived. Reactivate it to edit it.');
        }
        final next = current.deepCopy();
        _applyGoal(
          next,
          name: request.name,
          targetAmountMinor: request.targetAmountMinor.toInt(),
          targetDate: request.hasTargetDate() ? request.targetDate : null,
        );
        return WireMapper.goalToWire(
          await Ledger._write(
            store.putGoal(
              next,
              // The goal exactly as read: archived meanwhile, or edited on another device, is
              // not written over.
              expect: (now) => LedgerBudgets._unchanged(current, now, rule: '6.15'),
            ),
          ),
        );
      });

  /// `GoalResource.complete`: active → completed (row 6.14).
  Future<ZenResult<wire.Goal>> completeGoal(String id) =>
      _transition(id, GoalState.GOAL_STATE_COMPLETED);

  /// `GoalResource.archive`: active or completed → archived, refused (409) while the envelope holds
  /// money (rows 6.14, 6.16).
  Future<ZenResult<wire.Goal>> archiveGoal(String id) =>
      _transition(id, GoalState.GOAL_STATE_ARCHIVED);

  /// `GoalResource.reactivate`: completed or archived → active (row 6.14).
  Future<ZenResult<wire.Goal>> reactivateGoal(String id) =>
      _transition(id, GoalState.GOAL_STATE_ACTIVE);

  // ── Envelopes and their history ─────────────────────────────────────────────────────────────

  /// `GoalAllocationResource.history` (row 6.47): every entry, newest first (`created_at desc, id`),
  /// optionally those that put money into or took it out of one goal (a malformed id is a 400).
  Future<ZenResult<wire.ListGoalAllocationsResponse>> listGoalAllocations({String? goalId}) =>
      Ledger._run(() async {
        final goal = goalId == null || javaIsBlank(goalId)
            ? null
            : LedgerBudgets._idInBody(goalId, rule: '6.47');
        final view = LedgerView.read(store);
        final entries =
            view.goalAllocations.values
                .where(
                  (e) =>
                      goal == null ||
                      (e.hasSourceGoalId() && e.sourceGoalId == goal) ||
                      (e.hasTargetGoalId() && e.targetGoalId == goal),
                )
                .toList()
              ..sort((a, b) {
                final byTime = b.createdAtMs.compareTo(a.createdAtMs);
                return byTime != 0 ? byTime : a.id.compareTo(b.id);
              });
        return wire.ListGoalAllocationsResponse(
          allocations: [for (final e in entries) WireMapper.allocationToWire(e)],
        );
      });

  /// `GoalAllocationResource.get`: 404 for an id that is not one or names nothing.
  Future<ZenResult<wire.GoalAllocation>> getGoalAllocation(String id) => Ledger._run(() async {
    final entry = LocalIds.isValid(id) ? LedgerView.read(store).goalAllocations[id] : null;
    if (entry == null) throw const Refusal.notFound('6.22', 'No such goal allocation.');
    return WireMapper.allocationToWire(entry);
  });

  /// `GoalAllocationResource.envelopes`: one envelope per goal in the goals' creation order, a goal
  /// with no entries at zero. Entries never conflict, so an envelope never leaves anything out.
  Future<ZenResult<wire.ListGoalEnvelopesResponse>> listGoalEnvelopes() => Ledger._run(() async {
    final view = LedgerView.read(store);
    final envelopes = _envelopes(view);
    return wire.ListGoalEnvelopesResponse(
      envelopes: [
        for (final goal in _goalsInOrder(view))
          wire.GoalEnvelope(
            goalId: goal.id,
            currency: goal.currency,
            amountMinor: Int64(envelopes[goal.id] ?? 0),
          ),
      ],
    );
  });

  /// `GoalAllocationResource.create` (rows 6.19–6.26), check for check in the server's order: the
  /// kind, a positive amount, the note, the goal ids the kind takes (400 each), the goals (404), one
  /// currency (400), the goals' states (409), the source's envelope (409), the target's room (400),
  /// and for an `ALLOCATE` the currency's free money (409). The entry is written once, with every
  /// one of those checks run again inside the write (jZenDev/jZen#251).
  ///
  /// An `ALLOCATE` is refused (409) while the currency's free money leaves out something two
  /// devices disagree about: the cap must not be a figure nobody agreed on.
  Future<ZenResult<wire.GoalAllocation>> createGoalAllocation(
    wire.CreateGoalAllocationRequest request,
  ) => Ledger._run(() async {
    final view = LedgerView.read(store);
    final entry = _allocation(view, request);
    final written = await Ledger._write(
      store.addGoalAllocation(
        entry,
        expect: (current) => current != null
            ? const ZenValidationError('This entry is already written.')
            : _recheck((now) {
                final again = _allocation(now, request);
                if (again.currency != entry.currency) {
                  throw const Refusal.conflict('6.21', 'The goals changed meanwhile.');
                }
              }),
      ),
    );
    return WireMapper.allocationToWire(written);
  });

  // ── Free money and progress ─────────────────────────────────────────────────────────────────

  /// `GoalAllocationResource.freeMoney` (rows 6.26, 6.27, 6.54): per currency, ordered by code, the
  /// eligible money (current balances of the active accounts marked eligible for goals, listed in
  /// name order), what the envelopes hold, and the difference, which may be negative after a later
  /// spend (ADR-051).
  ///
  /// [Settled.unsettled] is keyed by currency: an account whose `active` or `eligible_for_goals`
  /// flag (or existence) two devices disagree about counts in no currency and is named under each
  /// currency it holds; a record, transfer or opening its balance leaves out is named under its
  /// currency.
  Future<ZenResult<Settled<wire.GetFreeMoneyResponse>>> freeMoney() => Ledger._run(() async {
    final view = LedgerView.read(store);
    final positions = _FreeMoney(view);
    return Settled(
      wire.GetFreeMoneyResponse(
        currencies: [
          for (final currency in positions.currencies)
            wire.CurrencyFreeMoney(
              currency: currency,
              eligibleMinor: Int64(positions.eligible[currency] ?? 0),
              allocatedMinor: Int64(positions.allocated[currency] ?? 0),
              freeMinor: Int64(positions.free(currency)),
              eligibleAccountIds: positions.sources[currency] ?? const [],
            ),
        ],
      ),
      positions.unsettled,
    );
  });

  /// `GoalResource.progress` (rows 6.28, 6.45): for each goal in creation order, what is allocated,
  /// the target, what remains (never negative), the whole percent rounded down, and the guidance —
  /// with, for an active goal with money left and a target date not yet passed, the monthly
  /// contribution rounded up over the calendar months from [asOf]'s through the target's, both
  /// inclusive. [asOf] defaults to today in UTC, as the server's does; the parity suite pins it
  /// (finding F-07).
  ///
  /// A goal whose target, date or status two devices disagree about has no progress anyone agreed
  /// on: it is left out of the list and named in [Settled.unsettled], keyed by its id.
  Future<ZenResult<Settled<wire.ListGoalProgressResponse>>> goalProgress({String? asOf}) =>
      Ledger._run(() async {
        final day = asOf == null || javaIsBlank(asOf)
            ? _todayUtc()
            : Ledger._date(asOf, rule: '6.45');
        final view = LedgerView.read(store);
        final envelopes = _envelopes(view);
        final response = wire.ListGoalProgressResponse(asOf: day.toString());
        final unsettled = <String, List<String>>{};
        for (final goal in _goalsInOrder(view)) {
          if (LedgerView.disputes(view.goalConflicts[goal.id], _progressTags)) {
            unsettled[goal.id] = [goal.id];
            continue;
          }
          response.goals.add(_progress(goal, envelopes[goal.id] ?? 0, day));
        }
        return Settled(response, unsettled);
      });

  // ── Rules ───────────────────────────────────────────────────────────────────────────────────

  /// `GoalResource.transition` (rows 6.14, 6.16): 404, then — for an archive the state allows — an
  /// envelope that still holds money (409), then a move the state does not allow (409). The status
  /// time is this device's clock; two devices that reach one status keep the earlier time
  /// (`ZenMergePolicy.earliest`, jZenDev/jZen#235).
  Future<ZenResult<wire.Goal>> _transition(String id, GoalState target) => Ledger._run(() async {
    final view = LedgerView.read(store);
    final goal = _requireGoal(view, id);
    _admitTransition(view, goal, target);
    final next = goal.deepCopy()
      ..status = target
      ..statusChangedAtMs = Int64(_clock());
    return WireMapper.goalToWire(
      await Ledger._write(
        store.putGoal(
          next,
          // The goal exactly as read, and the envelope, as they stand when the write runs.
          expect: (current) =>
              LedgerBudgets._unchanged(goal, current, rule: '6.14') ??
              _recheck((now) => _admitTransition(now, goal, target)),
        ),
      ),
    );
  });

  static void _admitTransition(LedgerView view, Goal goal, GoalState target) {
    final allowed = _successors[goal.status] ?? const <GoalState>{};
    if (target == GoalState.GOAL_STATE_ARCHIVED &&
        allowed.contains(target) &&
        (_envelopes(view)[goal.id] ?? 0) != 0) {
      throw const Refusal.conflict(
        '6.16',
        'This goal still holds money. Withdraw it or move it to another goal first.',
      );
    }
    if (!allowed.contains(target)) {
      throw Refusal.conflict(
        '6.14',
        'A goal cannot move from ${_stateName(goal.status)} to ${_stateName(target)}.',
      );
    }
  }

  /// `GoalState.successors`.
  static const _successors = {
    GoalState.GOAL_STATE_ACTIVE: {GoalState.GOAL_STATE_COMPLETED, GoalState.GOAL_STATE_ARCHIVED},
    GoalState.GOAL_STATE_COMPLETED: {GoalState.GOAL_STATE_ACTIVE, GoalState.GOAL_STATE_ARCHIVED},
    GoalState.GOAL_STATE_ARCHIVED: {GoalState.GOAL_STATE_ACTIVE},
  };

  /// `GoalResource.apply`: a name that is not blank (stripped), a positive target, an optional date.
  static void _applyGoal(
    Goal goal, {
    required String name,
    required int targetAmountMinor,
    required String? targetDate,
  }) {
    if (javaIsBlank(name)) throw const Refusal.invalid('6.13', 'A goal needs a name.');
    if (targetAmountMinor <= 0) {
      throw const Refusal.invalid('6.13', 'A goal needs a positive target amount.');
    }
    final date = targetDate == null ? null : Ledger._date(targetDate, rule: '6.13');
    goal
      ..name = javaStrip(name)
      ..targetAmountMinor = Int64(targetAmountMinor);
    if (date == null) {
      goal.clearTargetDate();
    } else {
      goal.targetDate = date.toString();
    }
  }

  /// `GoalResource.parseStatus`: the exact constant name.
  static GoalState _parseStatus(String status) => switch (status) {
    'ACTIVE' => GoalState.GOAL_STATE_ACTIVE,
    'COMPLETED' => GoalState.GOAL_STATE_COMPLETED,
    'ARCHIVED' => GoalState.GOAL_STATE_ARCHIVED,
    _ => throw const Refusal.invalid('6.46', 'Unknown goal status.'),
  };

  static String _stateName(GoalState state) => switch (state) {
    GoalState.GOAL_STATE_ACTIVE => 'ACTIVE',
    GoalState.GOAL_STATE_COMPLETED => 'COMPLETED',
    GoalState.GOAL_STATE_ARCHIVED => 'ARCHIVED',
    _ => 'UNKNOWN',
  };

  /// A goal named in a path (`Ids.parse`): 404 for an id that is not one or names nothing.
  static Goal _requireGoal(LedgerView view, String id) {
    final goal = LocalIds.isValid(id) ? view.goals[id] : null;
    if (goal == null) throw const Refusal.notFound('6.13', 'No such goal.');
    return goal;
  }

  /// Goals in the server's `created_at, id` order.
  static List<Goal> _goalsInOrder(LedgerView view) => view.goals.values.toList()
    ..sort((a, b) {
      final byTime = a.createdAtMs.compareTo(b.createdAtMs);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  static Map<String, int> _envelopes(LedgerView view) => goalEnvelopes(view.goalAllocations.values);

  /// The entry [request] asks for, or the server's refusal of it, in `GoalAllocationResource.create`'s
  /// order.
  GoalAllocation _allocation(LedgerView view, wire.CreateGoalAllocationRequest request) {
    final kind = switch (request.kind) {
      wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE =>
        AllocationKind.ALLOCATION_KIND_ALLOCATE,
      wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW =>
        AllocationKind.ALLOCATION_KIND_WITHDRAW,
      wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE => AllocationKind.ALLOCATION_KIND_MOVE,
      _ => throw const Refusal.invalid(
        '6.19',
        'An envelope entry needs a kind: ALLOCATE, WITHDRAW or MOVE.',
      ),
    };
    final amount = request.amountMinor.toInt();
    if (amount <= 0) {
      throw const Refusal.invalid('6.20', 'An envelope entry needs a positive amount.');
    }
    final note = TextRules.strippedNote(request.note);
    final hasSource = kind != AllocationKind.ALLOCATION_KIND_ALLOCATE;
    final hasTarget = kind != AllocationKind.ALLOCATION_KIND_WITHDRAW;
    final sourceId = _goalIdFor(
      used: hasSource,
      present: request.hasSourceGoalId(),
      value: request.sourceGoalId,
    );
    final targetId = _goalIdFor(
      used: hasTarget,
      present: request.hasTargetGoalId(),
      value: request.targetGoalId,
    );
    if (sourceId != null && sourceId == targetId) {
      throw const Refusal.invalid('6.19', 'Money cannot be moved to the goal it already is in.');
    }
    // `currencyOfOwned` for an ALLOCATE, then `lockGoals`: each goal named must exist (404).
    for (final id in [?sourceId, ?targetId]) {
      if (!view.goals.containsKey(id)) throw const Refusal.notFound('6.19', 'No such goal.');
    }
    final source = sourceId == null ? null : view.goals[sourceId];
    final target = targetId == null ? null : view.goals[targetId];
    if (source != null && target != null && source.currency != target.currency) {
      throw const Refusal.invalid(
        '6.21',
        'Money cannot be moved between goals in different currencies.',
      );
    }
    // A goal's state is read on every side of its conflict: money moves only where every side
    // allows it (`GoalState.releasesMoney`, `acceptsMoney`).
    if (source != null &&
        view.goalSides(source.id).any((g) => g.status == GoalState.GOAL_STATE_ARCHIVED)) {
      throw const Refusal.conflict(
        '6.23',
        'This goal is archived, so money cannot be taken out of it. Reactivate it first.',
      );
    }
    if (target != null &&
        view.goalSides(target.id).any((g) => g.status != GoalState.GOAL_STATE_ACTIVE)) {
      throw const Refusal.conflict(
        '6.23',
        'This goal is not active, so money cannot be put into it.',
      );
    }
    final envelopes = _envelopes(view);
    if (source != null && (envelopes[source.id] ?? 0) < amount) {
      throw const Refusal.conflict(
        '6.24',
        "This goal's envelope holds less than the amount requested.",
      );
    }
    if (target != null) {
      try {
        addExact(envelopes[target.id] ?? 0, amount);
      } on MoneyOverflow {
        throw const Refusal.invalid('6.25', 'That amount would be more than an envelope can hold.');
      }
    }
    if (kind == AllocationKind.ALLOCATION_KIND_ALLOCATE) {
      final money = _FreeMoney(view);
      if (money.unsettled.containsKey(target!.currency)) {
        throw const Refusal.conflict(
          '6.26',
          'The free money in this currency leaves out a change two devices disagree about. '
              'Settle it first.',
        );
      }
      if (amount > money.free(target.currency)) {
        throw Refusal.conflict(
          '6.26',
          'That is more than the free money in ${target.currency} '
              '(free: ${money.free(target.currency)}, requested: $amount, in minor units).',
        );
      }
    }
    final entry = GoalAllocation(
      id: store.newId(),
      kind: kind,
      currency: (source ?? target)!.currency,
      amountMinor: Int64(amount),
      createdAtMs: Int64(_clock()),
      createdBy: store.deviceId,
    );
    if (sourceId != null) entry.sourceGoalId = sourceId;
    if (targetId != null) entry.targetGoalId = targetId;
    if (note.isNotEmpty) entry.note = note;
    return entry;
  }

  /// `GoalAllocationResource.goalIdFor`: a goal id the kind does not take, or lacks, is a 400, and
  /// so is a malformed one (`Ids.parseInBody`).
  static String? _goalIdFor({required bool used, required bool present, required String value}) {
    if (!used) {
      if (present) {
        throw const Refusal.invalid('6.19', 'This kind of entry does not take that goal.');
      }
      return null;
    }
    if (!present) throw const Refusal.invalid('6.19', 'This kind of entry needs that goal.');
    return LedgerBudgets._idInBody(value, rule: '6.19');
  }

  /// `GoalProgressCalculator.progress`.
  static wire.GoalProgress _progress(Goal goal, int allocated, CivilDate asOf) {
    final target = goal.targetAmountMinor.toInt();
    // `Math.max(0L, target - allocated)`: a plain long subtraction on the server, so the same here
    // (a Dart VM int is the same 64-bit two's-complement value).
    final remaining = math.max(0, target - allocated);
    final progress = wire.GoalProgress(
      goalId: goal.id,
      currency: goal.currency,
      allocatedMinor: Int64(allocated),
      targetAmountMinor: Int64(target),
      remainingMinor: Int64(remaining),
      progressPercent: GoalArithmetic.percent(allocated, target),
    );
    if (goal.status != GoalState.GOAL_STATE_ACTIVE) {
      return progress..guidance = wire.GoalGuidance.GOAL_GUIDANCE_NOT_ACTIVE;
    }
    if (remaining == 0) return progress..guidance = wire.GoalGuidance.GOAL_GUIDANCE_REACHED;
    if (!goal.hasTargetDate()) {
      return progress..guidance = wire.GoalGuidance.GOAL_GUIDANCE_NO_TARGET_DATE;
    }
    final targetDate = Ledger._storedDate('goals', goal.id, goal.targetDate);
    if (targetDate.compareTo(asOf) < 0) {
      return progress..guidance = wire.GoalGuidance.GOAL_GUIDANCE_OVERDUE;
    }
    final months = GoalArithmetic.monthsRemaining(asOf, targetDate);
    final contribution = GoalArithmetic.ceilDiv(remaining, months);
    return progress
      ..guidance = wire.GoalGuidance.GOAL_GUIDANCE_CONTRIBUTION
      ..monthsRemaining = months
      ..monthlyContributionMinor = Int64(contribution);
  }

  static final Set<int> _progressTags = {
    for (final name in const ['targetAmountMinor', 'targetDate', 'status'])
      Goal().info_.byName[name]!.tagNumber,
  };

  CivilDate _todayUtc() {
    final now = DateTime.fromMillisecondsSinceEpoch(_clock(), isUtc: true);
    return CivilDate.parse(
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}',
    );
  }
}

/// `FreeMoney.calculate` over one [LedgerView], from settled values only.
final class _FreeMoney {
  /// Per currency, the current balances of the accounts that fund goals.
  final Map<String, int> eligible = {};

  /// Per currency, those accounts' ids in name order (`TextRules.compareNames`, row 6.54).
  final Map<String, List<String>> sources = {};

  /// Per currency, what every goal's envelope in it holds — every goal, archived included, so a
  /// goal's currency is listed even at zero.
  final Map<String, int> allocated = {};

  /// Per currency, what [eligible] leaves out (sorted).
  final Map<String, List<String>> unsettled;

  _FreeMoney._(this.unsettled);

  factory _FreeMoney(LedgerView view) {
    final unsettled = <String, Set<String>>{};
    final money = _FreeMoney._({});
    final accounts = view.accounts.values.toList()
      ..sort((a, b) => SearchRules.compareNames(a.name, a.id, b.name, b.id));
    for (final account in accounts) {
      final held = view.currenciesOf(account.id);
      if (LedgerView.disputes(view.accountConflicts[account.id], _accountTags)) {
        for (final c in held) {
          unsettled.putIfAbsent(c.currency, () => {}).add(account.id);
        }
        continue;
      }
      if (!account.eligibleForGoals || !account.active) continue;
      final balances = view.balancesOf(account.id).minor;
      for (final c in held) {
        money.eligible[c.currency] = addExact(
          money.eligible[c.currency] ?? 0,
          balances[c.currency] ?? 0,
        );
        money.sources.putIfAbsent(c.currency, () => []).add(account.id);
        for (final id in view.unsettledIn(account.id, c.currency)) {
          unsettled.putIfAbsent(c.currency, () => {}).add(id);
        }
      }
    }
    // An account deleted on one device and edited on another is not listed by the store; whether it
    // funds goals is exactly what the two devices disagree about.
    for (final conflict in view.accountConflicts.values) {
      if (view.accounts.containsKey(conflict.id)) continue;
      for (final c in view.currenciesOf(conflict.id)) {
        unsettled.putIfAbsent(c.currency, () => {}).add(conflict.id);
      }
    }
    final envelopes = LedgerGoals._envelopes(view);
    for (final goal in view.goals.values) {
      money.allocated[goal.currency] = addExact(
        money.allocated[goal.currency] ?? 0,
        envelopes[goal.id] ?? 0,
      );
    }
    money.unsettled.addAll({
      for (final MapEntry(:key, :value) in unsettled.entries) key: value.toList()..sort(),
    });
    return money;
  }

  static final Set<int> _accountTags = {
    for (final name in const ['active', 'eligibleForGoals'])
      Account().info_.byName[name]!.tagNumber,
  };

  /// Every currency with eligible money or a goal, in code order.
  List<String> get currencies => {...eligible.keys, ...allocated.keys}.toList()..sort();

  /// `Position.freeMinor`: eligible less allocated, possibly negative.
  int free(String currency) => subtractExact(eligible[currency] ?? 0, allocated[currency] ?? 0);
}
