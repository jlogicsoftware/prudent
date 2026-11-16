import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../civil_date.dart';
import '../java_text.dart';

part 'java_root_upper_case.dart';

/// What identifies one statement row inside one account (ADR-091) — the server's `RowKey`: a
/// digest of what the row says, and which of the rows with that digest in its statement it is.
final class RowKey {
  RowKey(this.fingerprint, this.occurrence) {
    if (!RowFingerprints.keyShape.hasMatch(fingerprint)) {
      throw ArgumentError("A row key's fingerprint has the wrong shape.");
    }
    if (occurrence < 1) throw ArgumentError("A row key's occurrence is 1 or more.");
  }

  /// A scheme prefix, a colon and 64 lower-case hex characters; never statement text.
  final String fingerprint;

  /// 1-based: the n-th row of the statement with this fingerprint.
  final int occurrence;

  @override
  bool operator ==(Object other) =>
      other is RowKey && other.fingerprint == fingerprint && other.occurrence == occurrence;

  @override
  int get hashCode => Object.hash(fingerprint, occurrence);

  @override
  String toString() => 'RowKey($fingerprint, $occurrence)';
}

/// The fields of a row the fingerprint reads, as the importer normalised them.
final class FingerprintFields {
  const FingerprintFields({
    required this.transactionDate,
    required this.amountMinor,
    this.description,
    this.counterparty,
    this.counterpartyAccount,
  });

  final CivilDate transactionDate;
  final int amountMinor;
  final String? description;
  final String? counterparty;
  final String? counterpartyAccount;
}

/// How a statement row is recognised the next time it is imported — the server's
/// `RowFingerprints.java` (ADR-091), byte for byte, held to it by
/// `test/golden/import_fingerprints.json` and by the fingerprint of every accepted row in
/// `test/golden/erste_import.json`.
///
/// **The `v1` scheme:** SHA-256 over a scheme tag, the destination account's id, the format id,
/// the currency, the transaction date, the signed amount in minor units and the [normalise]d
/// description, counterparty and counterparty account, each written as its UTF-8 length, a colon,
/// its bytes and a newline. Left out on purpose: the bank's sequence number, the booking date and
/// the balance. Rows with one fingerprint in one statement are told apart by [keys]' occurrence
/// number.
///
/// **The account id is written as the server writes it** (`UUID.toString()`: lower-case,
/// 8-4-4-4-12), whichever form it is given in. A Local id is the server's id without its dashes
/// (ADR-103), so an account moved in from the server keeps the fingerprints the server stored for
/// it (ADR-110) and a statement imported before the move is recognised after it.
///
/// The digest is not secret (ADR-091): it is personal data, never logged and never shown.
abstract final class RowFingerprints {
  /// The scheme prefix of a content fingerprint. A change to the scheme is a new prefix.
  static const fingerprintPrefix = 'v1';

  /// The scheme prefix of a key built from a bank identifier believed stable.
  static const stableIdPrefix = 'e1';

  /// The shape of every key, as the server's database CHECK constraints require.
  static final RegExp keyShape = RegExp(r'^[a-z][0-9]+:[0-9a-f]{64}$');

  static final RegExp _localId = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _serverId = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// The fingerprint of one row in one destination account. [accountId] is a Local id or the
  /// server's form of one; anything else is an [ArgumentError].
  static String fingerprint(
    String accountId,
    String formatId,
    String currency,
    FingerprintFields row,
  ) {
    final out = <int>[];
    _put(out, 'prudent.import.row.$fingerprintPrefix');
    _put(out, _serverFormOf(accountId));
    _put(out, formatId);
    _put(out, currency);
    _put(out, row.transactionDate.toString());
    _put(out, row.amountMinor.toString());
    _put(out, normalise(row.description));
    _put(out, normalise(row.counterparty));
    _put(out, normalise(row.counterpartyAccount));
    return '$fingerprintPrefix:${sha256.convert(out)}';
  }

  /// The key of a row identified by a bank identifier trusted to be stable; occurrence 1. No format
  /// declares one today (`ErsteStatementImporter.stableExternalId` is false).
  static RowKey stableIdKey(String accountId, String formatId, String? externalId) {
    if (externalId == null || javaIsBlank(externalId)) {
      throw ArgumentError('A stable identifier is required to key a row by it.');
    }
    final out = <int>[];
    _put(out, 'prudent.import.id.$stableIdPrefix');
    _put(out, _serverFormOf(accountId));
    _put(out, formatId);
    _put(out, javaStrip(externalId));
    return RowKey('$stableIdPrefix:${sha256.convert(out)}', 1);
  }

  /// The keys of a statement's rows, in the order given: the n-th row with a fingerprint gets
  /// occurrence n.
  static List<RowKey> keys(List<String> fingerprints) {
    final seen = <String, int>{};
    return [
      for (final fingerprint in fingerprints)
        RowKey(fingerprint, seen.update(fingerprint, (n) => n + 1, ifAbsent: () => 1)),
    ];
  }

  /// One normal form for the text a bank writes — the server's `normalise`: Unicode NFC, every run
  /// of Unicode white space (a no-break space included) one space, Java `strip()`, root-locale
  /// upper-casing, and NFC again (upper-casing can decompose); `null` is empty.
  ///
  /// Every step is Java's, not Dart's: `(?U)\s` is [isUnicodeWhiteSpace] (Dart's `\s` also takes a
  /// byte-order mark), `strip()` is [javaStrip], and root upper-casing is the JDK's table
  /// (`java_root_upper_case.dart`) — Dart's `toUpperCase` leaves `ß`, `ŉ` and every astral letter
  /// alone, where Java writes `SS`, `ʼN` and the capital.
  static String normalise(String? text) {
    if (text == null) return '';
    final composed = nfc(text);
    final spaced = StringBuffer();
    var inSpace = false;
    for (final rune in composed.runes) {
      if (isUnicodeWhiteSpace(rune)) {
        if (!inSpace) spaced.write(' ');
        inSpace = true;
      } else {
        spaced.writeCharCode(rune);
        inSpace = false;
      }
    }
    return nfc(javaRootUpperCase(javaStrip(spaced.toString())));
  }

  /// Unicode NFC as the JDK's `java.text.Normalizer` computes it: `unorm_dart`'s, except at
  /// U+D7A4.
  ///
  /// `unorm_dart` 0.3.3 takes U+D7A4, the unassigned code point just past the last Hangul syllable,
  /// for a syllable (its range check is `<` where the algorithm says `<=`), so it would decompose it
  /// into U+1113 U+1161 and compose a trailing jamo onto it; the JDK leaves it alone. It has no
  /// decomposition and composes with nothing on either side, and it is a starter, so normalising the
  /// text on each side of it on its own is exactly NFC of the whole. `row_fingerprints_test.dart`
  /// sweeps every code point against the JDK's table, which is how this was found.
  static String nfc(String text) {
    const unassignedAfterHangul = '\u{D7A4}';
    if (!text.contains(unassignedAfterHangul)) return unorm.nfc(text);
    return text.split(unassignedAfterHangul).map(unorm.nfc).join(unassignedAfterHangul);
  }

  /// Length-prefixed in Java's UTF-8, so that ("ab", "c") and ("a", "bc") are different inputs.
  static void _put(List<int> out, String value) {
    final bytes = javaUtf8(value);
    out
      ..addAll(bytes.length.toString().codeUnits)
      ..add(0x3A)
      ..addAll(bytes)
      ..add(0x0A);
  }

  static String _serverFormOf(String accountId) {
    if (_serverId.hasMatch(accountId)) return accountId;
    if (!_localId.hasMatch(accountId)) {
      throw ArgumentError('An account id is a Local id or the server form of one.');
    }
    return '${accountId.substring(0, 8)}-${accountId.substring(8, 12)}-'
        '${accountId.substring(12, 16)}-${accountId.substring(16, 20)}-${accountId.substring(20)}';
  }
}

/// Java `String.toUpperCase(Locale.ROOT)`: each code point through the JDK's table, a lone surrogate
/// kept as it is. Root upper-casing has no context (only Turkish, Azeri and Lithuanian do), so a
/// table of single code points is the whole of it.
String javaRootUpperCase(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final upper = _javaRootUpperCase[rune];
    if (upper != null) {
      out.write(upper);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// The JDK table [javaRootUpperCase] reads, for the test that holds it to the golden file.
Map<int, String> get javaRootUpperCaseTable => _javaRootUpperCase;
