import 'currencies.dart';
import 'java_text.dart';
import 'refusal.dart';

/// The record list's `type` filter (`RecordType.java`, phase-0 §0.3 row 5.47).
enum RecordType { income, expense, transfer, correction }

/// `RecordType.parse`: absent or blank (`isBlank`) is no filter; otherwise `trim()`, upper-cased, and
/// one of the four names, or a 400.
///
/// The server upper-cases with `String.toUpperCase()`, so a dotless `ı` or a long `ſ` becomes an
/// ASCII capital and `"ıncome"` is INCOME. [Currencies.normalize] is exactly that fold (Java `trim()`
/// and upper-casing, for every input that can end in ASCII capitals), so it is reused rather than
/// written twice.
abstract final class RecordTypes {
  static RecordType? parse(String? value) {
    if (value == null || javaIsBlank(value)) return null;
    return switch (Currencies.normalize(value)) {
      'INCOME' => RecordType.income,
      'EXPENSE' => RecordType.expense,
      'TRANSFER' => RecordType.transfer,
      'CORRECTION' => RecordType.correction,
      _ => throw const Refusal.invalid(
        '5.47',
        'Not a record type. Expected income, expense, transfer, or correction.',
      ),
    };
  }
}
