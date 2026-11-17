import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_proto/generated/prudent/v1/analytics.pb.dart' as wire;
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart' show ZenConflict, ZenStorageError;

import '../../generated/prudent_local/v1/store.pb.dart';
import '../ledger/ledger_errors.dart';
import '../ledger/ledger_view.dart' show LedgerReadFailure, Settled, readOrThrow;
import '../prudent_local_store.dart';

/// Prudent Local's analytics (unit 7 of `docs/plans/PRUDENT-LOCAL-PLAN.md`, ADR-118): spend by
/// category and spend by period, computed from the records in the store with `AnalyticsResource`'s
/// semantics, to the cent.
///
/// **What counts as spend** (`RecordEntity.expenseRows`, phase-0 rows 7.1–7.3): an ordinary record
/// whose amount is negative, in the one currency asked for, dated inside the window. Income (a
/// positive amount) and refunds are not netted in — analytics counts expenses only, unlike a
/// budget's actual. A transfer is a record of its own collection locally (ADR-102), so it is not
/// read here at all, as the server's `transfer_id is null`; a correction carries its `correction`
/// message and is skipped, as `is_correction = false`. A category that was deleted or archived
/// still holds its records' spend, by the id they carry.
///
/// **No currency is inferred and none is summed with another** (ADR-008): a missing or invalid
/// currency is a 400, and the answer is one currency's.
///
/// **Order** is the server's promise and nothing more: periods oldest to newest (the label sorts as
/// the calendar does); categories by id — the server's `TreeMap<UUID>` order, which carries no
/// meaning, and which Local reproduces only as "stable" (ids differ between the two, so order is
/// never a parity property; the suite compares categories as a set). A category or period with no
/// spend is absent, not zero, and an empty window is an empty list.
///
/// **A figure never reads a disputed value (ADR-113).** A record two devices disagree about, in a
/// way that changes this figure — its amount, currency or account (one grouped `posting`), its date,
/// its category (for the category figure only), or its very existence — counts in no figure on any
/// device until the person settles it; and the answer is a [Settled] that names it, under the
/// account(s) it touches, so the screen can say that the figure leaves something out. A conflict
/// about a title, payee or note leaves the money agreed and the record is counted.
///
/// Money is exact: a sum that leaves the 64-bit range is an error, never a wrapped figure. (The
/// server's `Long::sum` wraps silently there; that is a defect of the server's, not a rule to
/// reproduce, ADR-118.)
final class Analytics {
  final PrudentLocalStore store;

  /// The clock "the current period" is read from, in UTC like the server's (ADR-014).
  final DateTime Function() _now;

  Analytics(this.store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final int _postingTag = Record().info_.byName['posting']!.tagNumber;
  static final int _dateTag = Record().info_.byName['date']!.tagNumber;
  static final int _categoryTag = Record().info_.byName['categoryId']!.tagNumber;

  /// `GET /api/v1/analytics/spend-by-category`: the checks of the server in its order — currency,
  /// then year, then month.
  Future<ZenResult<Settled<wire.SpendByCategoryResponse>>> spendByCategory({
    required String? currency,
    required int? year,
    int? month,
  }) => _run(() {
    final code = _requireCurrency(currency);
    final window = SpendWindow.ofYearOrMonth(year: year, month: month);
    final scan = _scan(code, window, readsCategory: true);
    final totals = <String, int>{};
    for (final spend in scan.spends) {
      final category = spend.categoryId;
      if (category == null) {
        throw LedgerReadFailure(
          ZenStorageError('records/${spend.recordId} is an expense with no category.'),
        );
      }
      totals[category] = addExact(totals[category] ?? 0, spend.amount);
    }
    final ordered = totals.keys.toList()..sort(LocalIds.compare);
    return Settled(
      wire.SpendByCategoryResponse(
        currency: code,
        items: [
          for (final id in ordered)
            wire.CategorySpend(categoryId: id, amountMinor: Int64(totals[id]!)),
        ],
      ),
      scan.unsettled,
    );
  });

  /// `GET /api/v1/analytics/spend-by-period`: the checks of the server in its order — currency, then
  /// granularity, then count. [granularity] is `MONTH` or `YEAR` in any case; the window ends at the
  /// current period in UTC.
  Future<ZenResult<Settled<wire.SpendByPeriodResponse>>> spendByPeriod({
    required String? currency,
    required String? granularity,
    required int? count,
  }) => _run(() {
    final code = _requireCurrency(currency);
    final kind = SpendWindow.parseGranularity(granularity);
    final anchor = _now().toUtc();
    final window = SpendWindow.trailing(
      granularity: kind,
      count: count,
      anchorYear: anchor.year,
      anchorMonth: anchor.month,
    );
    final scan = _scan(code, window, readsCategory: false);
    final totals = <String, int>{};
    for (final spend in scan.spends) {
      final period = SpendWindow.label(kind, spend.year, spend.month);
      totals[period] = addExact(totals[period] ?? 0, spend.amount);
    }
    // "2026-08" and "2026" sort as the calendar does, which is the order the contract promises.
    final ordered = totals.keys.toList()..sort();
    return Settled(
      wire.SpendByPeriodResponse(
        currency: code,
        granularity: kind == SpendGranularity.month
            ? wire.Granularity.GRANULARITY_MONTH
            : wire.Granularity.GRANULARITY_YEAR,
        periods: [
          for (final period in ordered)
            wire.PeriodSpend(period: period, amountMinor: Int64(totals[period]!)),
        ],
      ),
      scan.unsettled,
    );
  });

  /// The server's `requireCurrency`: normalised, and a valid ISO-4217 code, or a 400.
  static String _requireCurrency(String? currency) {
    final normalized = Currencies.normalize(currency);
    if (normalized == null || !Currencies.isValid(normalized)) {
      throw const Refusal.invalid(
        '7.1',
        'A currency is required and must be ISO-4217; Prudent never sums analytics across currencies.',
      );
    }
    return normalized;
  }

  /// One pass over the records: the spends of [currency] inside [window] that are settled, and what
  /// was left out because two devices disagree about it.
  _Scan _scan(String currency, SpendWindow window, {required bool readsCategory}) {
    final conflicts = {
      for (final conflict in readOrThrow(store.records.conflicts())) conflict.id: conflict,
    };
    final all = readOrThrow(store.records.list());
    final spends = <_Spend>[];
    for (final record in all) {
      final conflict = conflicts[record.id];
      if (conflict != null && _disputes(conflict, readsCategory)) continue;
      if (record.hasCorrection()) continue;
      final amount = record.posting.amountMinor.toInt();
      if (amount >= 0 || record.posting.currency != currency) continue;
      final date = CivilDate.tryParse(record.date);
      if (date == null) {
        throw LedgerReadFailure(
          ZenStorageError('records/${record.id} holds a date that is not one.'),
        );
      }
      if (!window.contains(date.year, date.month)) continue;
      spends.add(
        _Spend(
          recordId: record.id,
          categoryId: record.hasCategoryId() ? record.categoryId : null,
          year: date.year,
          month: date.month,
          amount: negateExact(amount),
        ),
      );
    }

    final unsettled = <String, Set<String>>{};
    final shown = conflicts.isEmpty
        ? const <String, Record>{}
        : {
            for (final record in all)
              if (conflicts.containsKey(record.id)) record.id: record,
          };
    for (final conflict in conflicts.values) {
      if (!_disputes(conflict, readsCategory)) continue;
      // Every value any device holds, the one shown included; the deleting side has none.
      final values = <Record>[?shown[conflict.id], for (final side in conflict.sides) ?side.value];
      for (final value in values) {
        if (_couldCount(value, currency, window)) {
          unsettled.putIfAbsent(value.posting.accountId, () => {}).add(conflict.id);
        }
      }
    }
    return _Scan(spends, {
      for (final MapEntry(:key, :value) in unsettled.entries) key: value.toList()..sort(),
    });
  }

  /// Whether the conflict is about something this figure reads (see the class comment).
  static bool _disputes(ZenConflict<Record> conflict, bool readsCategory) =>
      conflict.isDeleteConflict ||
      conflict.fields.contains(_postingTag) ||
      conflict.fields.contains(_dateTag) ||
      (readsCategory && conflict.fields.contains(_categoryTag));

  /// Whether [value], read as one device holds it, would have been spend in this figure — so a
  /// disputed record that is nowhere near it does not make the figure say it left something out.
  static bool _couldCount(Record value, String currency, SpendWindow window) {
    if (value.hasCorrection()) return false;
    if (value.posting.amountMinor >= Int64.ZERO || value.posting.currency != currency) return false;
    final date = CivilDate.tryParse(value.date);
    // A date that cannot be read cannot be shown to be outside: name the record.
    return date == null || window.contains(date.year, date.month);
  }

  /// A rule's [Refusal] becomes the server-shaped error, the store's errors are returned as they
  /// are, and a figure that leaves the 64-bit range is an error, never a value (as the ledger does).
  static Future<ZenResult<T>> _run<T>(T Function() body) async {
    try {
      return ZenResult.ok(body());
    } on Refusal catch (refusal) {
      return ZenResult.err(LedgerErrors.of(refusal));
    } on LedgerReadFailure catch (failure) {
      return ZenResult.err(failure.error);
    } on MoneyOverflow catch (overflow) {
      return ZenResult.err(ZenUnknownError('A figure left the range of minor units ($overflow).'));
    }
  }
}

final class _Spend {
  final String recordId;
  final String? categoryId;
  final int year;
  final int month;

  /// The magnitude of the expense: positive.
  final int amount;

  const _Spend({
    required this.recordId,
    required this.categoryId,
    required this.year,
    required this.month,
    required this.amount,
  });
}

final class _Scan {
  final List<_Spend> spends;
  final Map<String, List<String>> unsettled;

  const _Scan(this.spends, this.unsettled);
}
