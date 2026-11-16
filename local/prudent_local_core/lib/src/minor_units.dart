/// Money as the server holds it (rule 3.1): a signed 64-bit count of minor units, never a float.
///
/// **The one fixed wire scale.** Every currency is counted in hundredths on the wire
/// (`amount_minor`, `proto/prudent/v1/accounts.proto`), whatever ISO-4217 says about its minor
/// unit: JPY 100 is `10000`. [wireMinorUnitDigits] is that scale. The server-connected client keeps
/// the same constant as `minorUnitDigits` in `client/lib/money.dart`; when that file moves into the
/// shared package (unit 2) it should read this one, so that there is one constant, not two
/// (ADR-107).
///
/// **Overflow is an error, not a wrap.** Dart's `int` wraps silently at 2^63 on the VM; the server
/// sums with `Math.addExact` and friends (`BudgetCalculator`, `FreeMoney`), which throw. A balance
/// that wrapped would be a figure that differs from the server's by 2^64 minor units without a word,
/// so every sum here goes through [addExact], [subtractExact] or [negateExact], and they throw
/// [MoneyOverflow] exactly where Java throws `ArithmeticException` (`test/golden/money.json`).
///
/// This package runs on the Dart VM and native AOT only: Prudent Local has no web build (jZen
/// ADR-073), and on the web `int` is a double. `test/money_test.dart` fails if `int` is not 64-bit.
library;

/// How many fraction digits an amount carries on the wire, for every currency.
const int wireMinorUnitDigits = 2;

/// The largest amount the wire can carry: Java's `Long.MAX_VALUE`.
const int maxMinorUnits = 0x7FFFFFFFFFFFFFFF;

/// The smallest amount the wire can carry: Java's `Long.MIN_VALUE`.
const int minMinorUnits = -0x8000000000000000;

/// An exact sum or difference of minor units left the 64-bit range — Java's `ArithmeticException`
/// from `Math.addExact`. Never caught to produce a figure.
class MoneyOverflow implements Exception {
  const MoneyOverflow(this.operation);

  final String operation;

  @override
  String toString() => 'MoneyOverflow: $operation left the 64-bit range of minor units';
}

/// Java's `Math.addExact(long, long)`.
int addExact(int a, int b) {
  final result = a + b;
  // Overflow happened iff both operands have the sign opposite to the result's.
  if (((a ^ result) & (b ^ result)) < 0) throw const MoneyOverflow('addExact');
  return result;
}

/// Java's `Math.subtractExact(long, long)`.
int subtractExact(int a, int b) {
  final result = a - b;
  // Overflow happened iff the operands have different signs and the result's differs from a's.
  if (((a ^ b) & (a ^ result)) < 0) throw const MoneyOverflow('subtractExact');
  return result;
}

/// Java's `Math.negateExact(long)`: only `Long.MIN_VALUE` has no negation.
int negateExact(int a) {
  if (a == minMinorUnits) throw const MoneyOverflow('negateExact');
  return -a;
}

/// Java's `Long.signum(long)`: the direction of a signed amount (negative is an expense, positive is
/// income, records.proto).
int signum(int a) => a > 0 ? 1 : (a < 0 ? -1 : 0);

/// The exact sum of [amounts], starting from zero.
int sumExact(Iterable<int> amounts) => amounts.fold(0, addExact);

/// `Long.toString(long)`: the canonical decimal text of an amount, as proto3 JSON carries an int64
/// and as the import fingerprint writes it (`RowFingerprints.java`).
String minorUnitsToString(int amount) => amount.toString();
