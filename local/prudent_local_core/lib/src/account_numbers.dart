import 'package:crypto/crypto.dart';

import 'java_text.dart';
import 'refusal.dart';

/// The normal form of a bank account number and its identity token — the server's
/// `AccountNumbers.java` (ADR-090, rule 3.6), line for line.
///
/// Normal form: every Unicode `White_Space` character removed (no-break spaces and U+0085 included,
/// the byte-order mark and zero-width space not), **ASCII letters only** upper-cased, and a leading
/// `PL` dropped from a 26-digit number; what remains must be 10 to 34 of `A-Z0-9`.
///
/// Two things the plan's one-line summary ("NFC, white space, root-locale upper-casing") says and
/// the server does not do, so Local does not do them either (ADR-107): there is **no NFC** — an
/// `é` written as `e` + U+0301 stays two code points and the shape check refuses it, as does a
/// precomposed `é` — and the upper-casing is **ASCII**, not root-locale, so a dotless `ı` or a `ß`
/// stays what it is and is refused rather than folded into a different number.
///
/// Nothing here puts a number in a refusal: it is personal data.
abstract final class AccountNumbers {
  static final RegExp _shape = RegExp(r'^[A-Z0-9]{10,34}$');
  static final RegExp _polishWithPrefix = RegExp(r'^PL[0-9]{26}$');

  /// `AccountNumbers.normalize`: the normal form, `null` for none (null or blank), or a 400.
  static String? normalize(String? raw) {
    final canonical = AccountNumbers.canonical(raw);
    if (canonical == null) return null;
    final shaped = _shaped(canonical);
    if (shaped == null) {
      throw const Refusal.invalid(
        '3.6',
        'The account number must be 10 to 34 letters and digits; spaces are ignored.',
      );
    }
    return shaped;
  }

  /// `AccountNumbers.normalizeOrNull`: as [normalize], but `null` for a malformed number too.
  static String? normalizeOrNull(String? raw) {
    final canonical = AccountNumbers.canonical(raw);
    return canonical == null ? null : _shaped(canonical);
  }

  /// `AccountNumbers.identityOf`: SHA-256 of [canonical] in Java's UTF-8, lower-case hex. Throws
  /// [ArgumentError] (Java: `IllegalArgumentException`) when nothing is left after normalising.
  static String identityOf(String? raw) {
    final canonical = AccountNumbers.canonical(raw);
    if (canonical == null) {
      throw ArgumentError('an account number is required to derive its identity');
    }
    return sha256.convert(javaUtf8(canonical)).toString();
  }

  /// `AccountNumbers.canonical`: white space removed, ASCII upper-cased, a leading `PL` dropped
  /// from a 26-digit number; `null` when nothing is left. No shape check.
  static String? canonical(String? raw) {
    if (raw == null) return null;
    final compact = StringBuffer();
    for (final rune in raw.runes) {
      if (isUnicodeWhiteSpace(rune)) continue;
      compact.writeCharCode(rune >= 0x61 && rune <= 0x7A ? rune - 0x20 : rune);
    }
    final text = compact.toString();
    if (text.isEmpty) return null;
    return _polishWithPrefix.hasMatch(text) ? text.substring(2) : text;
  }

  static String? _shaped(String canonical) => _shape.hasMatch(canonical) ? canonical : null;
}
