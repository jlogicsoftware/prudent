import 'iso4217.dart';
import 'java_text.dart';
import 'refusal.dart';

/// ISO-4217 currency codes, as the server's `Currencies.java` validates and normalises them
/// (rule 3.2): Java `trim()`, then `toUpperCase(Locale.ROOT)`, then exactly three characters that
/// the JDK's currency table knows.
///
/// Root-locale upper-casing is not ASCII upper-casing: the server accepts `"ınr"` (dotless i) as
/// INR, `"ſek"` (long s) as SEK and `"ßp"` as SSP, because Java folds those letters to ASCII
/// capitals. Local accepts exactly the same inputs; `test/golden/currencies.json` lists every code
/// point that folds that way, from the JVM.
abstract final class Currencies {
  /// The code points other than a–z that `String.toUpperCase(Locale.ROOT)` turns into ASCII
  /// capitals only (the golden file's `rootUpperCaseToAsciiCapitals`, compared in full by the
  /// test). No other character can end in a valid code.
  static const Map<int, String> _foldsToAsciiCapitals = {
    0x00DF: 'SS', // ß
    0x0131: 'I', // ı, dotless i
    0x017F: 'S', // ſ, long s
    0xFB00: 'FF',
    0xFB01: 'FI',
    0xFB02: 'FL',
    0xFB03: 'FFI',
    0xFB04: 'FFL',
    0xFB05: 'ST',
    0xFB06: 'ST',
  };

  /// The server's `Currencies.normalize`, **for every input whose normal form is a valid code**.
  ///
  /// For other input the result may differ from Java's (Java upper-cases the whole of Unicode, this
  /// upper-cases what can matter); it is never stored, because only a valid code is, and the server
  /// quotes the raw input in its refusal, never the normal form. `null` stays `null`.
  static String? normalize(String? code) {
    if (code == null) return null;
    final out = StringBuffer();
    for (final rune in javaTrim(code).runes) {
      if (rune >= 0x61 && rune <= 0x7A) {
        out.writeCharCode(rune - 0x20);
      } else {
        final folded = _foldsToAsciiCapitals[rune];
        if (folded != null) {
          out.write(folded);
        } else {
          out.writeCharCode(rune);
        }
      }
    }
    return out.toString();
  }

  /// The server's `Currencies.isValid`: normalised, three UTF-16 units, and in the JDK's table.
  static bool isValid(String? code) {
    final normalized = normalize(code);
    return normalized != null && normalized.length == 3 && iso4217Codes.contains(normalized);
  }

  /// The canonical code, or a 400 refusal — the server's `parseCurrency` (budgets, goals, resets)
  /// and the currency check every record, account balance and allocation makes.
  static String parse(String? code) {
    final normalized = normalize(code);
    if (normalized == null || !isValid(normalized)) {
      throw const Refusal.invalid('3.2', 'Not an ISO-4217 currency.');
    }
    return normalized;
  }
}
