/// The handful of Java string operations the server's rules are written in, reproduced exactly.
///
/// Dart's `String.trim()` is **not** Java's `trim()`, and neither is Java's `strip()`: the three
/// remove different characters (a no-break space, a control character, a byte-order mark), and a
/// title or note that the server stores one way must be stored the same way here. Each function
/// names the Java method it reproduces, and `test/golden/text.json` — written by the server's JVM —
/// holds every one of them to it, over every code point where a table is involved.
library;

import 'dart:convert';

/// Java `String.trim()`: removes every UTF-16 unit `<= U+0020` from both ends — the ASCII controls
/// and the space, and nothing else (no no-break space, no em space).
String javaTrim(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && text.codeUnitAt(start) <= 0x20) {
    start++;
  }
  while (end > start && text.codeUnitAt(end - 1) <= 0x20) {
    end--;
  }
  return text.substring(start, end);
}

/// Java `Character.isWhitespace(int)`: a Unicode space, line or paragraph separator that is not a
/// no-break space (U+00A0, U+2007, U+202F), or one of U+0009–U+000D and U+001C–U+001F.
///
/// Spelled out as ranges rather than derived from a Unicode category, because Dart has no
/// `Character.getType`; `test/golden/text.json` carries the JVM's own answer for every code point
/// and the test compares all 1 114 112 of them.
bool isJavaWhitespace(int codePoint) =>
    (codePoint >= 0x09 && codePoint <= 0x0D) ||
    (codePoint >= 0x1C && codePoint <= 0x20) ||
    codePoint == 0x1680 ||
    (codePoint >= 0x2000 && codePoint <= 0x2006) ||
    (codePoint >= 0x2008 && codePoint <= 0x200A) ||
    codePoint == 0x2028 ||
    codePoint == 0x2029 ||
    codePoint == 0x205F ||
    codePoint == 0x3000;

/// Java regex `(?U)\s`, the Unicode `White_Space` property: what `AccountNumbers` removes from a
/// number. Unlike [isJavaWhitespace] it includes the no-break spaces and U+0085; unlike Dart's own
/// `\s` it excludes the byte-order mark U+FEFF.
bool isUnicodeWhiteSpace(int codePoint) =>
    (codePoint >= 0x09 && codePoint <= 0x0D) ||
    codePoint == 0x20 ||
    codePoint == 0x85 ||
    codePoint == 0xA0 ||
    codePoint == 0x1680 ||
    (codePoint >= 0x2000 && codePoint <= 0x200A) ||
    codePoint == 0x2028 ||
    codePoint == 0x2029 ||
    codePoint == 0x202F ||
    codePoint == 0x205F ||
    codePoint == 0x3000;

/// Java `String.strip()`: removes code points for which [isJavaWhitespace] holds from both ends.
String javaStrip(String text) {
  final runes = text.runes.toList();
  var start = 0;
  var end = runes.length;
  while (start < end && isJavaWhitespace(runes[start])) {
    start++;
  }
  while (end > start && isJavaWhitespace(runes[end - 1])) {
    end--;
  }
  return String.fromCharCodes(runes, start, end);
}

/// Java `String.isBlank()`: empty, or only code points for which [isJavaWhitespace] holds.
bool javaIsBlank(String text) => text.runes.every(isJavaWhitespace);

/// Java `String.codePointCount(0, length)`, which is Postgres' `char_length` for the same text:
/// a surrogate pair is one, and a lone surrogate is one as well (finding F-04 — "500 characters" is
/// code points, never Dart's UTF-16 `length`).
int codePointCount(String text) => text.runes.length;

/// Java `String.getBytes(StandardCharsets.UTF_8)`.
///
/// Identical to Dart's `utf8.encode` except for a lone surrogate, which Java replaces with `?`
/// (0x3F) and Dart with U+FFFD. The difference reaches a SHA-256 identity token, so it is
/// reproduced, not approximated.
List<int> javaUtf8(String text) {
  final out = <int>[];
  for (final rune in text.runes) {
    if (rune >= 0xD800 && rune <= 0xDFFF) {
      out.add(0x3F);
    } else {
      out.addAll(utf8.encode(String.fromCharCode(rune)));
    }
  }
  return out;
}
