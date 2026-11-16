import 'civil_date.dart';
import 'minor_units.dart';

/// The arithmetic of a goal's progress (row 6.28, ADR-052): `GoalProgressCalculator.percent`,
/// `monthsRemaining` and `ceilDiv`, method for method, held to the JVM by `test/golden/
/// goal_progress.json` (unit 6a). The ledger decides which goal gets which guidance; this is only
/// the numbers.
abstract final class GoalArithmetic {
  static final BigInt _hundred = BigInt.from(100);
  static final BigInt _intMin = BigInt.from(-0x80000000);

  /// `allocated × 100 / target` in exact arithmetic, truncated toward zero, at most 100 — so 100
  /// means reached. The server's `BigInteger.intValueExact` throws for a result outside 32 bits
  /// (only an envelope far below zero, which a merge alone can produce): [MoneyOverflow] here.
  static int percent(int allocated, int target) {
    var percent = (BigInt.from(allocated) * _hundred) ~/ BigInt.from(target);
    if (percent > _hundred) percent = _hundred;
    if (percent < _intMin) throw const MoneyOverflow('a goal progress percent');
    return percent.toInt();
  }

  /// The calendar months from [asOf]'s month through [targetDate]'s, both inclusive:
  /// `YearMonth.until(…, MONTHS) + 1`.
  static int monthsRemaining(CivilDate asOf, CivilDate targetDate) =>
      (targetDate.year - asOf.year) * 12 + (targetDate.month - asOf.month) + 1;

  /// [remaining] divided by [months], rounded up — not `(remaining + months - 1) ~/ months`, which
  /// overflows near the top of the range.
  static int ceilDiv(int remaining, int months) =>
      remaining ~/ months + (remaining % months == 0 ? 0 : 1);
}
