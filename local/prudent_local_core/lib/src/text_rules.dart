import 'java_text.dart';
import 'refusal.dart';
import 'simple_lower_case.dart';

/// The server's rules for free text (rules 3.7 and 3.8), each named after the server code it
/// reproduces. They are not one rule written four ways by accident: the server really trims with
/// `trim()` in some places and `strip()` in others, and a title the server stores one way must be
/// stored the same way here (`test/golden/text.json` holds the primitives to the JVM).
abstract final class TextRules {
  /// A note is at most 500 **characters** — code points, as Postgres' `char_length` and Java's
  /// `codePointCount` count them, never Dart's UTF-16 `length` (finding F-04). A note of 500 emoji
  /// is 1000 UTF-16 units and is accepted.
  static const int maxNoteCodePoints = 500;

  /// Required text — a record's title, an account's name (`RecordWriter.java:43`,
  /// `AccountResource.java:258`): refused (400) when absent or blank by `isBlank()`, then trimmed by
  /// `trim()`.
  ///
  /// The two methods disagree on purpose-free inputs, and the server's answer is kept: a title of
  /// only U+0001 is not blank (a control is not white space) but trims to the empty string, which
  /// the server stores; a title of only an em space (U+2003) is blank and refused.
  static String requiredTrimmed(String? value, {required String rule}) {
    if (value == null || javaIsBlank(value)) {
      throw Refusal.invalid(rule, 'This text is required.');
    }
    return javaTrim(value);
  }

  /// Optional text — a record's payee or note (`RecordWriter.blankToNull`): trimmed by `trim()`,
  /// and absent when nothing is left, so the field is never an empty string. A lone em space is not
  /// removed by `trim()` and is therefore kept, as on the server.
  static String? optionalTrimmed(String? value) {
    if (value == null) return null;
    final trimmed = javaTrim(value);
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The note of an envelope entry or a carry-over reset (`GoalAllocationResource.java:172`,
  /// `BudgetCarryOverResetResource.java:120`): `strip()`, then at most [maxNoteCodePoints] code
  /// points, else 400. An empty note stays the empty string (the wire field is not optional).
  static String strippedNote(String note) {
    final stripped = javaStrip(note);
    if (codePointCount(stripped) > maxNoteCodePoints) {
      throw const Refusal.invalid('3.8', 'A note may be at most 500 characters.');
    }
    return stripped;
  }

  /// The note of an import row (`ImportWorkflow.java:313`): `trim()`, then at most
  /// [maxNoteCodePoints] code points, else 400; empty becomes absent.
  static String? trimmedOptionalNote(String note) {
    final trimmed = javaTrim(note);
    if (codePointCount(trimmed) > maxNoteCodePoints) {
      throw const Refusal.invalid('3.8', 'A note can be at most 500 characters.');
    }
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// The record search and the order of names (ADR-106): `prudent.text.TextRules` on the server,
/// reproduced code point for code point. Kept beside the free-text rules above because both are the
/// server's rules about text, and named after the Java methods.
///
/// The fold is Unicode's *simple* lower-case mapping, one code point to one
/// (`Character.toLowerCase(int)`), from the server's JVM ([simpleLowerCaseRuns]). Dart's own
/// `String.toLowerCase` is not used: it applies the *full* mapping (U+0130 becomes two code points)
/// and, on the Dart VM, an older Unicode than the JDK's — 437 code points differ (ADR-113).
abstract final class SearchRules {
  static final Map<int, int> _lower = {
    for (final (first, last, step, delta) in simpleLowerCaseRuns)
      for (var cp = first; cp <= last; cp += step) cp: cp + delta,
  };

  /// `TextRules.foldCodePoint`: the simple lower-case mapping of one code point.
  static int foldCodePoint(int codePoint) => _lower[codePoint] ?? codePoint;

  /// `TextRules.fold`: [foldCodePoint] over every code point of [text].
  static String fold(String text) => String.fromCharCodes(text.runes.map(foldCodePoint));

  /// `TextRules.searchTerm`: null when the search is ignored — absent or blank by `isBlank()` —
  /// otherwise `trim()`med and folded.
  ///
  /// Java's `isBlank` and `trim` disagree, and the server's answer is kept: a search of only control
  /// characters (U+0001) is not blank, trims to the empty string, and the empty term is contained in
  /// every title, so it matches every record (`search-vectors.json` t18, m11). A search of only a
  /// no-break space is not blank and is not trimmed either, so it searches for U+00A0. Dart's own
  /// `trim` would remove both, and U+FEFF and U+0085 too; `javaTrim` and `javaIsBlank` do not.
  static String? searchTerm(String? search) {
    if (search == null || javaIsBlank(search)) return null;
    return fold(javaTrim(search));
  }

  /// `TextRules.matchesAny`: whether some non-null field, folded, contains [term] as a plain
  /// substring. `%`, `_` and `\` are ordinary characters; there is no pattern.
  static bool matchesAny(String term, List<String?> fields) =>
      fields.any((field) => field != null && fold(field).contains(term));

  /// `TextRules.compareNames`: folded primary weights, shorter first on a prefix; then the code
  /// points as written; then the id as text (lower-case hex, the server's and Local's id order).
  static int compareNames(String a, String idA, String b, String idB) {
    final keyA = _collationKey(a);
    final keyB = _collationKey(b);
    final byKey = _compareInts(keyA, keyB);
    if (byKey != 0) return byKey;
    final byRaw = _compareInts(a.runes.toList(), b.runes.toList());
    if (byRaw != 0) return byRaw;
    return idA.compareTo(idB);
  }

  static List<int> _collationKey(String name) => fold(name).runes.map(_weight).toList();

  /// Element by element, then the shorter first — `Integer.compare` over Java `int` arrays.
  static int _compareInts(List<int> a, List<int> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
    }
    return a.length == b.length ? 0 : (a.length < b.length ? -1 : 1);
  }

  /// `TextRules.weight`: four times the code point, with the Polish letters right after their base
  /// letter and the Ukrainian letters where a Ukrainian reader looks for them.
  static int _weight(int cp) => switch (cp) {
    0x0105 => 0x61 * 4 + 1, // ą
    0x0107 => 0x63 * 4 + 1, // ć
    0x0119 => 0x65 * 4 + 1, // ę
    0x0142 => 0x6C * 4 + 1, // ł
    0x0144 => 0x6E * 4 + 1, // ń
    0x00F3 => 0x6F * 4 + 1, // ó
    0x015B => 0x73 * 4 + 1, // ś
    0x017A => 0x7A * 4 + 1, // ź
    0x017C => 0x7A * 4 + 2, // ż
    0x0491 => 0x0433 * 4 + 1, // ge with upturn, after ge
    0x0454 => 0x0435 * 4 + 1, // ukrainian ie, after ie
    0x0456 => 0x0438 * 4 + 1, // byelorussian-ukrainian i, after i
    0x0457 => 0x0438 * 4 + 2, // yi, after that
    _ => cp * 4,
  };
}
