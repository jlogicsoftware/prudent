import 'dart:convert';

import 'parity_backend.dart';

/// Reads the wire messages both backends answer — the server's canonical proto3 JSON, and Local's
/// wire messages written as proto3 JSON by the same rules — into observations, with one set of
/// functions for both sides, so neither side can observe differently by accident (ADR-113).
///
/// proto3 JSON omits a field at its default: an `int64` of zero, an empty string, `false`, an enum's
/// zero value. Each reader makes those defaults explicit, and turns ids into the names the scenario
/// bound them to (ids differ between the backends and are never compared).
abstract final class ParityReaders {
  /// A plain proto3 `string`: omitted when empty.
  static String string(Map<String, Object?> body, String key) => (body[key] as String?) ?? '';

  /// A proto3 `int64`: a decimal string, omitted when zero.
  static String int64(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value == null) return '0';
    if (value is String) return int.parse(value).toString();
    if (value is int) return value.toString();
    throw StateError('$key is not an int64 in proto3 JSON: $value');
  }

  /// A proto3 `bool`: omitted when false.
  static bool boolean(Map<String, Object?> body, String key) => (body[key] as bool?) ?? false;

  /// A proto3 enum by name: omitted at its zero value [zero].
  static String enumName(Map<String, Object?> body, String key, String zero) =>
      (body[key] as String?) ?? zero;

  /// A proto3 `uint32`: a JSON number, omitted when zero.
  static String uint32(Map<String, Object?> body, String key) =>
      ((body[key] as int?) ?? 0).toString();

  /// An account: every field, its balances in the declared order.
  static Map<String, Object?> account(Map<String, Object?> body) => {
    'name': string(body, 'name'),
    'type': enumName(body, 'type', 'ACCOUNT_TYPE_UNSPECIFIED'),
    'isDefault': boolean(body, 'isDefault'),
    'isActive': boolean(body, 'isActive'),
    'includeInTotal': boolean(body, 'includeInTotal'),
    'includeInOverview': boolean(body, 'includeInOverview'),
    'eligibleForGoals': boolean(body, 'eligibleForGoals'),
    'accountNumber': string(body, 'accountNumber'),
    'balances': [
      for (final b
          in ((body['balances'] as List<Object?>?) ?? const []).cast<Map<String, Object?>>())
        {'currency': string(b, 'currency'), 'amountMinor': int64(b, 'amountMinor')},
    ],
  };

  /// A category: every field but its id.
  static Map<String, Object?> category(Map<String, Object?> body) => {
    'title': string(body, 'title'),
    'iconKey': string(body, 'iconKey'),
    'description': string(body, 'description'),
    'colorArgb': uint32(body, 'colorArgb'),
    'archived': boolean(body, 'archived'),
    'kind': enumName(body, 'kind', 'CATEGORY_KIND_UNSPECIFIED'),
  };

  /// A record or a transfer leg: what it is, where the money is (by bound name), and its text.
  /// `null` for the account or category means "bound to nothing in this scenario".
  static Map<String, Object?> record(Map<String, Object?> body, ParityBindings bindings) => {
    'kind': body['transferId'] != null
        ? 'transfer'
        : (boolean(body, 'isCorrection') ? 'correction' : 'record'),
    'account': bindings.nameOf(body['accountId'] as String?),
    'category': bindings.nameOf(body['categoryId'] as String?),
    'amountMinor': int64(body, 'amountMinor'),
    'currency': string(body, 'currency'),
    'date': string(body, 'date'),
    'title': string(body, 'title'),
    'payee': body['payee'] as String?,
    'note': body['note'] as String?,
    'planLinked': body['planId'] != null,
  };

  /// A transfer: its two legs, source first.
  static Map<String, Object?> transfer(Map<String, Object?> body, ParityBindings bindings) => {
    'from': record(body['fromRecord']! as Map<String, Object?>, bindings),
    'to': record(body['toRecord']! as Map<String, Object?>, bindings),
  };

  /// The record list (rows 5.46–5.50), compared as the phase-0 inventory says: rows of accounts this
  /// scenario bound (the server's user is shared by the whole run), grouped by date **in the order
  /// the backend answered**, so a date out of `date desc` order shows as a different grouping; within
  /// one date, as a set — the two backends mint different ids, so the `id` tie-break is not a parity
  /// property. That each backend did order one date by its own ids, ascending, is observed as a
  /// fact of its own (`idOrder`), which both must state.
  static Map<String, Object?> recordList(List<Object?> rows, ParityBindings bindings) {
    final days = <Map<String, Object?>>[];
    var ascending = true;
    String? lastDate;
    String? lastId;
    for (final row in rows.cast<Map<String, Object?>>()) {
      final read = record(row, bindings);
      if (read['account'] == null) continue;
      final date = read['date']! as String;
      final id = string(row, 'id');
      if (date != lastDate) {
        days.add({'date': date, 'rows': <Map<String, Object?>>[]});
        lastDate = date;
      } else if (lastId != null && id.compareTo(lastId) <= 0) {
        ascending = false;
      }
      lastId = id;
      (days.last['rows']! as List<Map<String, Object?>>).add(read);
    }
    for (final day in days) {
      (day['rows']! as List<Map<String, Object?>>).sort(
        (a, b) => jsonEncode(a).compareTo(jsonEncode(b)),
      );
    }
    return {'days': days, 'idOrder': ascending ? 'ascending' : 'not ascending'};
  }

  /// The names this scenario bound, in the order the backend listed them; rows of other scenarios
  /// are left out.
  static List<String> boundNames(List<Object?> rows, ParityBindings bindings) => [
    for (final row in rows.cast<Map<String, Object?>>()) ?bindings.nameOf(row['id'] as String?),
  ];

  // ── Unit 6a: budgets, resets, goals, allocations ───────────────────────────────────────────

  /// A list of [rows] narrowed to those whose [key] names something this scenario bound, each read
  /// by [read], **in the order the backend answered**.
  static List<Map<String, Object?>> boundRows(
    List<Object?> rows,
    ParityBindings bindings,
    String key,
    Map<String, Object?> Function(Map<String, Object?> row) read,
  ) => [
    for (final row in rows.cast<Map<String, Object?>>())
      if (bindings.nameOf(row[key] as String?) != null) read(row),
  ];

  /// A budget slot: its category by bound name, month, currency and amount.
  static Map<String, Object?> budget(Map<String, Object?> body, ParityBindings bindings) => {
    'category': bindings.nameOf(body['categoryId'] as String?),
    'month': string(body, 'month'),
    'currency': string(body, 'currency'),
    'amountMinor': int64(body, 'amountMinor'),
  };

  /// The budget summary (rows 6.5–6.7, 6.12): every figure, the items of bound categories as a set
  /// ordered by name (the server orders them by category id, and ids differ between the backends),
  /// and whether the backend did answer them in ascending id order (`idOrder`), which both must.
  static Map<String, Object?> budgetSummary(Map<String, Object?> body, ParityBindings bindings) {
    final rows = ((body['items'] as List<Object?>?) ?? const []).cast<Map<String, Object?>>();
    var ascending = true;
    for (var i = 1; i < rows.length; i++) {
      if (string(rows[i], 'categoryId').compareTo(string(rows[i - 1], 'categoryId')) <= 0) {
        ascending = false;
      }
    }
    final items = [
      for (final row in rows)
        if (bindings.nameOf(row['categoryId'] as String?) case final name?)
          {
            'category': name,
            'planMinor': int64(row, 'planMinor'),
            'actualMinor': int64(row, 'actualMinor'),
            'carryOverMinor': int64(row, 'carryOverMinor'),
            'remainingMinor': int64(row, 'remainingMinor'),
            'carryOverResetMonth': string(row, 'carryOverResetMonth'),
          },
    ]..sort((a, b) => a['category']!.compareTo(b['category']!));
    return {
      'month': string(body, 'month'),
      'currency': string(body, 'currency'),
      'items': items,
      'totalPlanMinor': int64(body, 'totalPlanMinor'),
      'totalActualMinor': int64(body, 'totalActualMinor'),
      'totalCarryOverMinor': int64(body, 'totalCarryOverMinor'),
      'totalRemainingMinor': int64(body, 'totalRemainingMinor'),
      'idOrder': ascending ? 'ascending' : 'not ascending',
    };
  }

  /// A carry-over reset: what it bounds and discards, its note, and whether it is revoked (who and
  /// when are a user on the server and a device locally, and a clock, so they are not compared).
  static Map<String, Object?> reset(Map<String, Object?> body, ParityBindings bindings) => {
    'category': bindings.nameOf(body['categoryId'] as String?),
    'month': string(body, 'month'),
    'currency': string(body, 'currency'),
    'discardedMinor': int64(body, 'discardedMinor'),
    'note': string(body, 'note'),
    'revoked': body['revokedAtMs'] != null,
  };

  /// A goal: every field but its id and its two times.
  static Map<String, Object?> goal(Map<String, Object?> body) => {
    'name': string(body, 'name'),
    'currency': string(body, 'currency'),
    'targetAmountMinor': int64(body, 'targetAmountMinor'),
    'targetDate': body['targetDate'] as String?,
    'status': enumName(body, 'status', 'GOAL_STATUS_UNSPECIFIED'),
  };

  /// An envelope entry: its kind, its goals by bound name, currency, amount and note.
  static Map<String, Object?> allocation(Map<String, Object?> body, ParityBindings bindings) => {
    'kind': enumName(body, 'kind', 'GOAL_ALLOCATION_KIND_UNSPECIFIED'),
    'source': bindings.nameOf(body['sourceGoalId'] as String?),
    'target': bindings.nameOf(body['targetGoalId'] as String?),
    'currency': string(body, 'currency'),
    'amountMinor': int64(body, 'amountMinor'),
    'note': string(body, 'note'),
  };

  /// An envelope: its goal by bound name, currency and amount.
  static Map<String, Object?> envelope(Map<String, Object?> body, ParityBindings bindings) => {
    'goal': bindings.nameOf(body['goalId'] as String?),
    'currency': string(body, 'currency'),
    'amountMinor': int64(body, 'amountMinor'),
  };

  /// Free money in one [currency] (rows 6.26, 6.27, 6.54), or `{'listed': false}` when the answer
  /// has no entry for it. The server's figures are the whole user's (ADR-107), so a scenario that
  /// reads free money owns its currency; the contributing accounts are the bound ones, in the order
  /// the backend listed them.
  static Map<String, Object?> freeMoney(
    Map<String, Object?> body,
    String currency,
    ParityBindings bindings,
  ) {
    for (final row
        in ((body['currencies'] as List<Object?>?) ?? const []).cast<Map<String, Object?>>()) {
      if (string(row, 'currency') != currency) continue;
      return {
        'listed': true,
        'eligibleMinor': int64(row, 'eligibleMinor'),
        'allocatedMinor': int64(row, 'allocatedMinor'),
        'freeMinor': int64(row, 'freeMinor'),
        'accounts': [
          for (final id in ((row['eligibleAccountIds'] as List<Object?>?) ?? const []))
            ?bindings.nameOf(id as String?),
        ],
      };
    }
    return {'listed': false};
  }

  /// One goal's progress (row 6.28): every figure and the guidance; an absent contribution is null.
  static Map<String, Object?> goalProgress(Map<String, Object?> body, ParityBindings bindings) => {
    'goal': bindings.nameOf(body['goalId'] as String?),
    'currency': string(body, 'currency'),
    'allocatedMinor': int64(body, 'allocatedMinor'),
    'targetAmountMinor': int64(body, 'targetAmountMinor'),
    'remainingMinor': int64(body, 'remainingMinor'),
    'progressPercent': (body['progressPercent'] as int?) ?? 0,
    'guidance': enumName(body, 'guidance', 'GOAL_GUIDANCE_UNSPECIFIED'),
    'monthlyContributionMinor': body.containsKey('monthlyContributionMinor')
        ? int64(body, 'monthlyContributionMinor')
        : null,
    'monthsRemaining': body['monthsRemaining'] as int?,
  };
}
