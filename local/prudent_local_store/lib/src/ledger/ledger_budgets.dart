part of 'ledger.dart';

/// Budgets and carry-over resets (unit 6a of `docs/plans/PRUDENT-LOCAL-PLAN.md`): phase-0 §0.3 rows
/// 6.1–6.12, 6.48–6.50, each the server's resource method check for check and in its order
/// (`BudgetResource`, `BudgetCalculator`, `BudgetCarryOverResetResource`; ADR-043 to ADR-046).
///
/// **Every figure is derived on every read**, as on the server: plan, actual, carry-over and
/// remaining are never stored. And, as for balances (ADR-113), **a figure never reads a value two
/// devices disagree about**: a record whose posting, date, category or existence is disputed, a
/// budget whose amount or existence is disputed, and a reset in conflict count in no figure; each is
/// named in the answer's [Settled.unsettled], under the category whose figure left it out.
extension LedgerBudgets on Ledger {
  // ── Slots ───────────────────────────────────────────────────────────────────────────────────

  /// `BudgetResource.list` (row 6.48): optionally one month and one category, ordered by month,
  /// currency, then category id. A malformed month or category id is a 400; a well-formed id that
  /// names nothing matches nothing.
  Future<ZenResult<wire.ListBudgetsResponse>> listBudgets({String? month, String? categoryId}) =>
      Ledger._run(() async {
        final parsedMonth = month == null || javaIsBlank(month) ? null : CivilMonth.parse(month);
        final category = categoryId == null || javaIsBlank(categoryId)
            ? null
            : _idInBody(categoryId, rule: '6.48');
        final view = LedgerView.read(store);
        final budgets =
            view.budgets.values
                .where(
                  (b) =>
                      (parsedMonth == null || b.month == parsedMonth.toString()) &&
                      (category == null || b.categoryId == category),
                )
                .toList()
              ..sort(_slotOrder);
        return wire.ListBudgetsResponse(budgets: [for (final b in budgets) _budgetWire(b)]);
      });

  /// `BudgetResource.get`: 404 for a category that is not one, 400 for the month or currency, 404
  /// for an empty slot.
  Future<ZenResult<wire.Budget>> getBudget(String categoryId, String month, String currency) =>
      Ledger._run(() async {
        final view = LedgerView.read(store);
        final slot = _slot(view, categoryId, month, currency);
        final budget = view.budgets[slot.id];
        if (budget == null) throw const Refusal.notFound('6.1', 'No budget is set for this slot.');
        return _budgetWire(budget);
      });

  /// `BudgetResource.set` (rows 6.1–6.4): the category (404), the month and currency (400), a
  /// positive amount (400), and — for a slot with no budget yet — a category that is not archived
  /// (409). The slot's id is derived from it, so two devices that plan one slot write one record.
  ///
  /// Answers the budget and whether the slot was empty (the server's 201 against 200).
  Future<ZenResult<({wire.Budget budget, bool created})>> setBudget(
    String categoryId,
    String month,
    String currency,
    int amountMinor,
  ) => Ledger._run(() async {
    final view = LedgerView.read(store);
    final slot = _slot(view, categoryId, month, currency);
    if (amountMinor <= 0) {
      throw const Refusal.invalid(
        '6.2',
        'A budget needs a positive amount. To have no budget for a month, delete it.',
      );
    }
    final read = view.budgets[slot.id];
    final existed = read != null;
    _admitSlot(view, slot.categoryId, existed: existed);
    final budget = Budget(
      id: slot.id,
      categoryId: slot.categoryId,
      month: slot.month,
      currency: slot.currency,
      amountMinor: Int64(amountMinor),
    );
    await Ledger._write(
      store.putBudget(
        budget,
        // The slot exactly as read (a plan another device set in between is not written over),
        // and the category's state, again, as they stand when the write runs.
        expect: (current) =>
            _unchanged(read, current, rule: '6.1') ??
            _recheck((now) => _admitSlot(now, slot.categoryId, existed: existed, mustExist: true)),
      ),
    );
    return (budget: _budgetWire(budget), created: !existed);
  });

  /// `BudgetResource.delete`: a hard delete, which changes no balance and no total. 404 for an
  /// unknown category or an empty slot.
  Future<ZenResult<void>> deleteBudget(String categoryId, String month, String currency) =>
      Ledger._run(() async {
        final view = LedgerView.read(store);
        final slot = _slot(view, categoryId, month, currency);
        final read = view.budgets[slot.id];
        if (read == null) throw const Refusal.notFound('6.1', 'No budget is set for this slot.');
        await Ledger._write(
          store.deleteBudget(slot.id, expect: (current) => _unchanged(read, current, rule: '6.1')),
        );
      });

  // ── The summary ─────────────────────────────────────────────────────────────────────────────

  /// `BudgetResource.summary` (rows 6.5–6.7, 6.12, 6.49): for one month and one currency, both
  /// required, each budgeted category's plan, actual (net spending from posted records — refunds
  /// included, transfers and corrections not), carry-over and remaining, and the totals. Items are in
  /// category-id order, as the server's query orders them.
  ///
  /// [Settled.unsettled] is keyed by category id: what that category's figures leave out.
  Future<ZenResult<Settled<wire.BudgetSummaryResponse>>> budgetSummary(
    String month,
    String currency,
  ) => Ledger._run(() async {
    final parsedMonth = CivilMonth.parse(month);
    if (javaIsBlank(currency)) {
      throw const Refusal.invalid(
        '6.49',
        'A currency is required; Prudent never sums a budget across currencies.',
      );
    }
    final normalized = Currencies.parse(currency);
    final view = LedgerView.read(store);
    final figures = _BudgetFigures(view, normalized);
    final budgets = figures.budgetsIn(parsedMonth)
      ..sort((a, b) => a.categoryId.compareTo(b.categoryId));
    final categories = {for (final b in budgets) b.categoryId};
    final carry = figures.carryOverInto(parsedMonth, categories);
    final response = wire.BudgetSummaryResponse(
      month: parsedMonth.toString(),
      currency: normalized,
    );
    var totalPlan = 0;
    var totalActual = 0;
    var totalCarry = 0;
    for (final budget in budgets) {
      final plan = budget.amountMinor.toInt();
      // Spending is money out: the signed net is negated once, here, so a positive actual is net
      // spending and a refund reduces it (`BudgetCalculator.summarize`).
      final actual = negateExact(figures.net(budget.categoryId, parsedMonth));
      final carryOver = carry.amount[budget.categoryId] ?? 0;
      final item = wire.CategoryBudgetSummary(
        categoryId: budget.categoryId,
        planMinor: Int64(plan),
        actualMinor: Int64(actual),
        carryOverMinor: Int64(carryOver),
        remainingMinor: Int64(addExact(carryOver, subtractExact(plan, actual))),
      );
      if (carry.resetMonth[budget.categoryId] case final resetMonth?) {
        item.carryOverResetMonth = resetMonth.toString();
      }
      response.items.add(item);
      totalPlan = addExact(totalPlan, plan);
      totalActual = addExact(totalActual, actual);
      totalCarry = addExact(totalCarry, carryOver);
    }
    response
      ..totalPlanMinor = Int64(totalPlan)
      ..totalActualMinor = Int64(totalActual)
      ..totalCarryOverMinor = Int64(totalCarry)
      ..totalRemainingMinor = Int64(addExact(totalCarry, subtractExact(totalPlan, totalActual)));
    // A category whose only budget this month is disputed has no item, and is named all the same.
    return Settled(
      response,
      figures.unsettledFor(parsedMonth, {...categories, ...figures.disputedSlotsIn(parsedMonth)}),
    );
  });

  // ── Carry-over resets ───────────────────────────────────────────────────────────────────────

  /// `BudgetCarryOverResetResource.history` (row 6.50): every reset, revoked ones included, newest
  /// first (`created_at desc, id`), optionally one category (a malformed id is a 400) and one
  /// currency (400 when not ISO-4217).
  Future<ZenResult<wire.ListBudgetCarryOverResetsResponse>> listBudgetResets({
    String? categoryId,
    String? currency,
  }) => Ledger._run(() async {
    final category = categoryId == null || javaIsBlank(categoryId)
        ? null
        : _idInBody(categoryId, rule: '6.50');
    final parsedCurrency = currency == null || javaIsBlank(currency)
        ? null
        : Currencies.parse(currency);
    final view = LedgerView.read(store);
    final resets =
        view.budgetResets.values
            .where(
              (r) =>
                  (category == null || r.categoryId == category) &&
                  (parsedCurrency == null || r.currency == parsedCurrency),
            )
            .toList()
          ..sort((a, b) {
            final byTime = b.createdAtMs.compareTo(a.createdAtMs);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
    return wire.ListBudgetCarryOverResetsResponse(
      resets: [for (final r in resets) WireMapper.resetToWire(r)],
    );
  });

  /// `BudgetCarryOverResetResource.reset` (rows 6.8, 6.9, 6.12): the category (400 malformed, 404
  /// unknown), month, currency, a note of at most 500 characters; then one live reset per slot
  /// (409). The entry records the carry-over it discards — the summary's own figure, so the person's
  /// number, not a second derivation of it. A figure two devices disagree about is not a number
  /// anyone saw, so a reset is refused (409) while that carry-over leaves something out.
  Future<ZenResult<wire.BudgetCarryOverReset>> resetBudgetCarryOver(
    wire.ResetBudgetCarryOverRequest request,
  ) => Ledger._run(() async {
    final view = LedgerView.read(store);
    final category = _idInBody(request.categoryId, rule: '6.8');
    if (!view.categories.containsKey(category)) {
      throw const Refusal.notFound('6.8', 'No such category.');
    }
    final month = CivilMonth.parse(request.month);
    final currency = Currencies.parse(request.currency);
    final note = TextRules.strippedNote(request.note);
    final discarded = _discarded(view, category, month, currency);
    _admitReset(view, category, month, currency);
    final reset = BudgetCarryOverReset(
      id: store.newId(),
      categoryId: category,
      month: month.toString(),
      currency: currency,
      createdBy: store.deviceId,
      createdAtMs: Int64(_now()),
    );
    if (discarded != 0) reset.discardedMinor = Int64(discarded);
    if (note.isNotEmpty) reset.note = note;
    final written = await Ledger._write(
      store.addBudgetReset(
        reset,
        expect: (_) => _recheck((now) {
          if (!now.categories.containsKey(category)) {
            throw const Refusal.notFound('6.8', 'No such category.');
          }
          _admitReset(now, category, month, currency);
          if (_discarded(now, category, month, currency) != discarded) {
            throw const Refusal.conflict(
              '6.12',
              'The carry-over changed while the reset was being written. Look at it again.',
            );
          }
        }),
      ),
    );
    return WireMapper.resetToWire(written);
  });

  /// `BudgetCarryOverResetResource.revoke` (rows 6.10, 6.11): 404 for an id that is not one or names
  /// nothing, 409 when it is already revoked. It is marked revoked by this device, never deleted.
  Future<ZenResult<wire.BudgetCarryOverReset>> revokeBudgetReset(String id) =>
      Ledger._run(() async {
        final view = LedgerView.read(store);
        final reset = LocalIds.isValid(id) ? view.budgetResets[id] : null;
        if (reset == null) throw const Refusal.notFound('6.10', 'No such carry-over reset.');
        if (reset.hasRevocation()) {
          throw const Refusal.conflict('6.10', 'This reset was already revoked.');
        }
        final written = await Ledger._write(store.revokeBudgetReset(reset.id, atMs: _now()));
        return WireMapper.resetToWire(written);
      });

  // ── Rules ───────────────────────────────────────────────────────────────────────────────────

  /// The slot a path names, in the server's order: the category (404, `Ids.parse`), the month and
  /// the currency (400).
  _Slot _slot(LedgerView view, String categoryId, String month, String currency) {
    final category = LocalIds.isValid(categoryId) ? view.categories[categoryId] : null;
    if (category == null) throw const Refusal.notFound('6.1', 'No such category.');
    final parsedMonth = CivilMonth.parse(month).toString();
    final normalized = Currencies.parse(currency);
    return _Slot(
      DerivedIds.budget(category.id, parsedMonth, normalized),
      category.id,
      parsedMonth,
      normalized,
    );
  }

  /// Row 6.4 (ADR-047): an archived category takes no budget in a slot that has none; a slot that
  /// holds one can still be corrected. [mustExist] is the recheck inside the write, where a category
  /// a sync deleted meanwhile is a 404 like any other.
  static void _admitSlot(
    LedgerView view,
    String categoryId, {
    required bool existed,
    bool mustExist = false,
  }) {
    final category = view.categories[categoryId];
    if (category == null) {
      if (mustExist) throw const Refusal.notFound('6.1', 'No such category.');
      return;
    }
    if (!existed && category.archived) {
      throw const Refusal.conflict('6.4', 'This category is archived.');
    }
  }

  /// Row 6.9: one live reset per slot — read on every side of every reset's conflict, so a reset
  /// another device holds live still occupies the slot.
  static void _admitReset(LedgerView view, String category, CivilMonth month, String currency) {
    final taken = view.resetValues().any(
      (r) =>
          !r.hasRevocation() &&
          r.categoryId == category &&
          r.month == month.toString() &&
          r.currency == currency,
    );
    if (taken) {
      throw Refusal.conflict(
        '6.9',
        'The carry-over of this category is already reset from $month in $currency.',
      );
    }
  }

  /// What a reset of [category] from [month] would discard: the carry-over into that month, refused
  /// (409) while it leaves out something two devices disagree about.
  static int _discarded(LedgerView view, String category, CivilMonth month, String currency) {
    final figures = _BudgetFigures(view, currency);
    final carry = figures.carryOverInto(month, {category});
    if (figures.unsettledFor(month, {category}).isNotEmpty) {
      throw const Refusal.conflict(
        '6.12',
        'This carry-over leaves out a change two devices disagree about. Settle it first.',
      );
    }
    return carry.amount[category] ?? 0;
  }

  /// [rule] run against the store as it stands inside a write's turn: null when it holds, else the
  /// ledger's refusal (or the store's read error) as the write's result (jZenDev/jZen#251).
  ZenError? _recheck(void Function(LedgerView view) rule) {
    try {
      rule(LedgerView.read(store));
      return null;
    } on Refusal catch (refusal) {
      return LedgerErrors.of(refusal);
    } on LedgerReadFailure catch (failure) {
      return failure.error;
    } on MoneyOverflow catch (overflow) {
      return ZenUnknownError('A figure left the range of minor units ($overflow).');
    }
  }

  int _now() => _clock();

  /// The precondition of an edit or a delete: the record must still be exactly the version [read]
  /// (the same bytes, which is what the store merges by), or still absent when [read] is null. A
  /// write puts a whole message and the store counts every field that differs from the stored record
  /// as this device's edit, so a field another device changed in between would otherwise be written
  /// back to the value read — a last writer winning. Refused instead: 404 when it is gone, 409 when
  /// it changed; the person looks again.
  static ZenError? _unchanged(
    GeneratedMessage? read,
    GeneratedMessage? current, {
    required String rule,
  }) => WriteExpects.asRead<GeneratedMessage>(
    read,
    gone: () =>
        LedgerErrors.of(Refusal.notFound(rule, 'This was deleted on another device meanwhile.')),
    changed: () => LedgerErrors.of(
      Refusal.conflict(rule, 'This changed on another device meanwhile. Look at it again.'),
    ),
  )(current);

  static int _slotOrder(Budget a, Budget b) {
    final byMonth = a.month.compareTo(b.month);
    if (byMonth != 0) return byMonth;
    final byCurrency = a.currency.compareTo(b.currency);
    return byCurrency != 0 ? byCurrency : a.categoryId.compareTo(b.categoryId);
  }

  static wire.Budget _budgetWire(Budget budget) => WireMapper.budgetToWire(budget);

  /// An id in a request body or a query (`Ids.parseInBody`): blank or malformed is a 400.
  static String _idInBody(String id, {required String rule}) {
    if (javaIsBlank(id) || !LocalIds.isValid(id)) throw Refusal.invalid(rule, 'Not a valid id.');
    return id;
  }
}

/// One budget slot a path names, its id derived from it.
final class _Slot {
  final String id;
  final String categoryId;
  final String month;
  final String currency;

  const _Slot(this.id, this.categoryId, this.month, this.currency);
}

/// The carry-over of some categories into a month: the amount per category and the live reset
/// month that bounded it, if any.
final class _CarryOver {
  final Map<String, int> amount;
  final Map<String, CivilMonth> resetMonth;

  const _CarryOver(this.amount, this.resetMonth);
}

/// The budget figures of one currency over one [LedgerView]: what `BudgetCalculator` computes from
/// its queries, from settled values only.
final class _BudgetFigures {
  final LedgerView view;
  final String currency;

  /// Net of settled records per category and month (`RecordEntity.netByCategory*`): ordinary
  /// records with a category, in [currency]; never a transfer (its own store record) or a correction.
  final Map<String, Map<(int, int), int>> _net = {};

  /// Per category, the records, budgets and resets a figure of it leaves out, with the months they
  /// would count in (a reset: from its month on).
  final Map<String, List<(String, CivilDate?, CivilMonth?)>> _disputed = {};

  _BudgetFigures(this.view, this.currency) {
    for (final record in view.records.values) {
      if (LedgerView.disputes(view.recordConflicts[record.id], _recordTags)) continue;
      if (!_counts(record)) continue;
      final date = Ledger._storedDate('records', record.id, record.date);
      final byMonth = _net.putIfAbsent(record.categoryId, () => {});
      final key = (date.year, date.month);
      byMonth[key] = addExact(byMonth[key] ?? 0, record.posting.amountMinor.toInt());
    }
    for (final conflict in view.recordConflicts.values) {
      if (!LedgerView.disputes(conflict, _recordTags)) continue;
      for (final side in [?view.records[conflict.id], for (final s in conflict.sides) ?s.value]) {
        if (!_counts(side)) continue;
        _disputed.putIfAbsent(side.categoryId, () => []).add((
          conflict.id,
          CivilDate.tryParse(side.date),
          null,
        ));
      }
    }
    for (final conflict in view.budgetConflicts.values) {
      if (!LedgerView.disputes(conflict, _budgetTags)) continue;
      for (final side in [?view.budgets[conflict.id], for (final s in conflict.sides) ?s.value]) {
        if (side.currency != currency) continue;
        _disputed.putIfAbsent(side.categoryId, () => []).add((
          conflict.id,
          CivilMonth.tryParse(side.month)?.firstDay,
          null,
        ));
      }
    }
    for (final conflict in view.resetConflicts.values) {
      for (final side in [
        ?view.budgetResets[conflict.id],
        for (final s in conflict.sides) ?s.value,
      ]) {
        if (side.currency != currency) continue;
        _disputed.putIfAbsent(side.categoryId, () => []).add((
          conflict.id,
          null,
          CivilMonth.tryParse(side.month),
        ));
      }
    }
  }

  static final Set<int> _recordTags = {
    for (final name in const ['posting', 'date', 'categoryId'])
      Record().info_.byName[name]!.tagNumber,
  };
  static final Set<int> _budgetTags = {Budget().info_.byName['amountMinor']!.tagNumber};

  bool _counts(Record record) =>
      record.hasCategoryId() && !record.hasCorrection() && record.posting.currency == currency;

  /// The settled budgets of [month] in this currency.
  List<Budget> budgetsIn(CivilMonth month) => [
    for (final b in view.budgets.values)
      if (b.month == month.toString() &&
          b.currency == currency &&
          !LedgerView.disputes(view.budgetConflicts[b.id], _budgetTags))
        b,
  ];

  /// The categories with a budget in [month] and this currency that two devices disagree about.
  Set<String> disputedSlotsIn(CivilMonth month) => {
    for (final conflict in view.budgetConflicts.values)
      if (LedgerView.disputes(conflict, _budgetTags))
        for (final side in [?view.budgets[conflict.id], for (final s in conflict.sides) ?s.value])
          if (side.month == month.toString() && side.currency == currency) side.categoryId,
  };

  /// The signed net of [categoryId]'s settled records in [month].
  int net(String categoryId, CivilMonth month) => _net[categoryId]?[(month.year, month.month)] ?? 0;

  /// `BudgetResource.carryOverInto`: per category, Σ (plan + net) over its settled budgets of the
  /// months before [month] in this currency, from its latest live reset at or before [month] on
  /// (ADR-045, ADR-046). A month with no budget adds nothing and passes the sum on unchanged.
  _CarryOver carryOverInto(CivilMonth month, Set<String> categories) {
    final resetMonth = <String, CivilMonth>{};
    for (final reset in view.budgetResets.values) {
      if (view.resetConflicts.containsKey(reset.id)) continue;
      if (reset.hasRevocation() || reset.currency != currency) continue;
      if (!categories.contains(reset.categoryId)) continue;
      final at = CivilMonth.tryParse(reset.month);
      if (at == null || at.compareTo(month) > 0) continue;
      final latest = resetMonth[reset.categoryId];
      if (latest == null || at.compareTo(latest) > 0) resetMonth[reset.categoryId] = at;
    }
    final amount = <String, int>{};
    for (final budget in view.budgets.values) {
      if (budget.currency != currency || !categories.contains(budget.categoryId)) continue;
      if (LedgerView.disputes(view.budgetConflicts[budget.id], _budgetTags)) continue;
      final at = CivilMonth.tryParse(budget.month);
      if (at == null || at.compareTo(month) >= 0) continue;
      final reset = resetMonth[budget.categoryId];
      if (reset != null && at.compareTo(reset) < 0) continue;
      amount[budget.categoryId] = addExact(
        amount[budget.categoryId] ?? 0,
        addExact(budget.amountMinor.toInt(), net(budget.categoryId, at)),
      );
    }
    return _CarryOver(amount, resetMonth);
  }

  /// By category of [categories], what their figures for [month] leave out: a disputed record,
  /// budget or reset in this currency that would count in the month or before it. Sorted.
  Map<String, List<String>> unsettledFor(CivilMonth month, Set<String> categories) {
    final end = (month.year, month.month);
    final out = <String, List<String>>{};
    for (final category in categories) {
      final ids = <String>{
        for (final (id, date, resetAt)
            in _disputed[category] ?? const <(String, CivilDate?, CivilMonth?)>[])
          if (resetAt != null
              ? resetAt.compareTo(month) <= 0
              : date == null || _compareMonths((date.year, date.month), end) <= 0)
            id,
      };
      if (ids.isNotEmpty) out[category] = ids.toList()..sort();
    }
    return out;
  }
}

/// Orders two (year, month) pairs.
int _compareMonths((int, int) a, (int, int) b) =>
    a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2);
