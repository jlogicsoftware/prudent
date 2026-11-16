import 'java_text.dart';
import 'refusal.dart';

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
