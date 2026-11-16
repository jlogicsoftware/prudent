import 'dart:typed_data';

import '../account_numbers.dart';
import '../civil_date.dart';
import '../java_text.dart';
import 'erste_csv.dart';
import 'import_rules.dart';
import 'parsed_statement.dart';

/// The Erste Polska CSV importer — the server's `ErsteStatementImporter.java` (ADR-090), line for
/// line, held to it by `test/golden/erste_import.json`.
///
/// **Whole file first.** The statement is decoded and every row is checked before anything is
/// returned. A failure in the layout or the summary row is thrown at once; a failure in transaction
/// rows is collected for the whole file and thrown as the rule of the first failing row, naming up
/// to [maxReportedRows] rows that broke it and how many did in all. Row numbers count transaction
/// rows: the summary row is not row 1.
///
/// **A row with no known meaning** (a description outside the three observed shapes, a card amount
/// that disagrees with its text, a sign the shape cannot have, a counterparty account of the wrong
/// shape) is returned rejected, so the rest may still be imported.
///
/// **Never read, never kept:** the balance column, the holder's name and address and summary fields
/// 6 to 8; the statement's own account number leaves [parse] only as an identity token. Nothing is
/// logged, and no refusal carries statement text.
///
/// **Java, not Dart.** The patterns are the server's with Java's meanings spelled out, because
/// Dart's differ: Java's `\S` is "not one of the six ASCII white space characters" (Dart's also
/// excludes a no-break space, U+3000 and a byte-order mark), and Java's `.` excludes U+0085 as a
/// line terminator (Dart's does not). `String.isBlank` is [javaIsBlank] and `Character.isDigit` is
/// [isJavaDigitUnit]; the golden file has a case for each place they differ.
abstract final class ErsteStatementImporter {
  /// The server's format id (`ImportFormatIds.ERSTE_PL_CSV`), stored on every session.
  static const formatId = 'erste-pl-csv';

  /// The most rows one rejection names; it also says how many more broke the rule.
  static const maxReportedRows = 10;

  /// The description the bank writes on an own-account transfer, kept verbatim.
  static const ownTransferDescription = 'Przelew na rachunek własny';

  /// The only currency the contract has seen.
  static const currency = 'PLN';

  /// The bank's own entry identifier is not stable across exports (ADR-091): keys are fingerprints.
  static const stableExternalId = false;

  static const _fields = 9;

  static final _isoDate = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$');
  static final _bankDate = RegExp(r'^([0-9]{2})-([0-9]{2})-([0-9]{4})$');

  /// Optional `-`, one to eleven whole digits with no leading zero, a comma and two decimals.
  static final _amount = RegExp(r'^(-?)(0|[1-9][0-9]{0,10}),([0-9]{2})$');
  static final _sequence = RegExp(r'^(?:0|[1-9][0-9]{0,17})$');

  /// Two digits, then six groups of four, as the contract shows a counterparty account.
  static final _counterpartyAccount = RegExp(r'^[0-9]{2}(?: [0-9]{4}){6}$');

  /// Java's `\S` (not space, tab, LF, VT, FF or CR) followed by Java's `.*` (anything but LF, CR,
  /// U+0085, U+2028, U+2029).
  static const _javaNonSpaceThenRest = r'[^ \t\n\x0B\f\r][^\n\r\x85\u2028\u2029]*';

  static final _card = RegExp(
    r'^DOP\. (?:MC|VISA) [0-9]{6}\*{6}[0-9]{4} PŁATNOŚĆ KARTĄ ([0-9]{1,11})\.([0-9]{2}) ([A-Z]{3}) '
    '$_javaNonSpaceThenRest\$',
  );
  static final _blik = RegExp('^Zakup BLIK $_javaNonSpaceThenRest ref:[0-9]{11}\$');

  static final _earliestDate = CivilDate.parse('2000-01-01');

  /// Whether [description] is the bank's own-account transfer wording.
  static bool isOwnAccountTransfer(String? description) => description == ownTransferDescription;

  /// Parses one statement, or throws [ImportRejection]. [today] is the server's
  /// `LocalDate.now(clock)`: a date more than a year after it is out of range.
  static ParsedStatement parse(Uint8List content, {required CivilDate today}) {
    final lines = ErsteCsv.lines(content);

    final accountNumber = _readSummary(lines[0]);
    final failures = <_Failure>[];
    final rows = <ParsedRow>[];
    final sequences = <String>{};
    final latest = _plusOneYear(today);
    var positiveOutgoing = 0;
    var cardRows = 0;
    var cardMismatches = 0;

    for (var index = 1; index < lines.length; index++) {
      final number = index; // transaction row n is file line n + 1
      final fields = ErsteCsv.fields(lines[index]);
      if (fields == null) {
        failures.add(_Failure(ImportRule.csvMalformed, number));
        continue;
      }
      final structural = _structure(fields);
      if (structural != null) {
        failures.add(_Failure(structural, number));
        continue;
      }
      final result = _readRow(number, fields, accountNumber, latest);
      if (result.rule != null) {
        failures.add(_Failure(result.rule!, number));
        continue;
      }
      switch (result.column) {
        case _Column.positive:
          positiveOutgoing++;
        case _Column.mismatch:
          cardRows++;
          cardMismatches++;
        case _Column.consistent:
          cardRows++;
        case _Column.unchecked:
          break;
      }
      // Sequence numbers: well-formed (checked in _readRow) and unique within the file.
      if (!sequences.add(fields[7])) {
        failures.add(_Failure(ImportRule.sequenceDuplicate, number));
        continue;
      }
      rows.add(result.row!);
    }

    if (failures.isNotEmpty) throw _rejection(failures);
    if (amountColumnMoved(positiveOutgoing, cardRows, cardMismatches)) {
      throw ImportRejection(ImportRule.amountColumn);
    }
    if (rows.isEmpty) throw ImportRejection(ImportRule.statementEmpty);
    return ParsedStatement(currency, rows, ParsedStatement.identityOf(accountNumber));
  }

  /// Whether the amount column no longer holds the amount: any card or BLIK row with a positive
  /// figure, or a column that disagrees with the card text on half or more of at least two card
  /// rows. The balance column is never used to tell.
  static bool amountColumnMoved(int positiveOutgoing, int cardRows, int cardMismatches) =>
      positiveOutgoing > 0 || (cardRows >= 2 && cardMismatches * 2 >= cardRows);

  /// The statement's own account must be the destination's stored number: refused with
  /// `account.identity_unverifiable` (no identity), `account.number_missing` (no stored number) or
  /// `account.identity_mismatch`. [storedNumber] is the destination's `account_number`.
  static void checkDestination(String? statementIdentity, String? storedNumber) {
    if (statementIdentity == null) throw ImportRejection(ImportRule.identityUnverifiable);
    if (storedNumber == null || javaIsBlank(storedNumber)) {
      throw ImportRejection(ImportRule.numberMissing);
    }
    if (statementIdentity != ParsedStatement.identityOf(storedNumber)) {
      throw ImportRejection(ImportRule.identityMismatch);
    }
  }

  // --- the summary row --------------------------------------------------------------------------

  /// Validates row 1 and returns the statement's own account number, normalised.
  static String _readSummary(String line) {
    final fields = ErsteCsv.fields(line);
    if (fields == null) throw ImportRejection(ImportRule.csvMalformed);
    if (fields.length == 1 && (line.contains(';') || line.contains('\t'))) {
      throw ImportRejection(ImportRule.delimiter);
    }
    if (fields.length == _fields && _looksLikeHeader(fields[0])) {
      throw ImportRejection(ImportRule.headerRow);
    }
    final structural = _structure(fields);
    if (structural != null) throw ImportRejection(structural);
    if (_bankDate.hasMatch(fields[0])) {
      // The first row is a transaction: the summary row is absent.
      throw ImportRejection(ImportRule.summaryMissing);
    }
    if (_parseIsoDate(fields[0]) == null) throw ImportRejection(ImportRule.exportDateInvalid);
    if (_parseBankDate(fields[1]) == null) throw ImportRejection(ImportRule.periodStartInvalid);
    final account = fields[2];
    if (!account.startsWith("'")) throw ImportRejection(ImportRule.summaryAccountInvalid);
    final normalised = AccountNumbers.normalizeOrNull(account.substring(1));
    if (normalised == null) throw ImportRejection(ImportRule.summaryAccountInvalid);
    if (fields[4] != currency) throw ImportRejection(ImportRule.currencyUnsupported);
    // Fields 4 (the holder) and 6 to 8, counted from 1, are never read: personal data, or not
    // understood (contract).
    return normalised;
  }

  /// A header names its columns; every first field the contract has seen starts with a digit.
  /// Java's `firstField.chars().noneMatch(Character::isDigit)`, over UTF-16 units.
  static bool _looksLikeHeader(String firstField) =>
      firstField.isNotEmpty && !firstField.codeUnits.any(isJavaDigitUnit);

  // --- transaction rows -------------------------------------------------------------------------

  /// Field count and the empty trailing field, for the summary row and every transaction row.
  static String? _structure(List<String> fields) {
    if (fields.length != _fields) return ImportRule.fieldCount;
    if (fields[8].isNotEmpty) return ImportRule.trailingField;
    return null;
  }

  static _RowResult _readRow(
    int number,
    List<String> fields,
    String statementAccount,
    CivilDate latest,
  ) {
    final booking = _parseBankDate(fields[0]);
    final transaction = _parseBankDate(fields[1]);
    if (booking == null || transaction == null) return _RowResult.fail(ImportRule.dateInvalid);
    if (_outOfRange(booking, latest) || _outOfRange(transaction, latest)) {
      return _RowResult.fail(ImportRule.dateOutOfRange);
    }
    if (booking.compareTo(transaction) < 0) {
      return _RowResult.fail(ImportRule.bookingBeforeTransaction);
    }
    final amount = _amount.firstMatch(fields[5]);
    if (amount == null) return _RowResult.fail(ImportRule.amountInvalid);
    final magnitude = int.parse(amount.group(2)!) * 100 + int.parse(amount.group(3)!);
    if (magnitude == 0) return _RowResult.fail(ImportRule.amountZero);
    final amountMinor = amount.group(1)!.isEmpty ? magnitude : -magnitude;
    if (!_sequence.hasMatch(fields[7])) return _RowResult.fail(ImportRule.sequenceInvalid);

    final description = fields[2];
    final counterparty = fields[3];
    final counterpartyAccountText = fields[4];
    final sequence = fields[7];

    ParsedRow accepted(String? counterpartyName, String? other, [String? hint]) =>
        ParsedRow.accepted(
          rowNumber: number,
          transactionDate: transaction,
          bookingDate: booking,
          amountMinor: amountMinor,
          description: description,
          counterparty: counterpartyName,
          counterpartyAccount: other,
          externalId: sequence,
          hintCode: hint,
        );
    _RowResult rejected(String rule, [_Column column = _Column.unchecked]) =>
        _RowResult.of(ParsedRow.rejected(number, rule), column);

    final card = _card.firstMatch(description);
    if (card != null) {
      if (card.group(3) != currency) return _RowResult.fail(ImportRule.cardForeignCurrency);
      if (counterparty.isNotEmpty || counterpartyAccountText.isNotEmpty) {
        return rejected(ImportRule.unknownShape);
      }
      if (amountMinor > 0) return rejected(ImportRule.signUnexpected, _Column.positive);
      final embedded = int.parse(card.group(1)!) * 100 + int.parse(card.group(2)!);
      if (embedded != magnitude) return rejected(ImportRule.cardAmountMismatch, _Column.mismatch);
      return _RowResult.of(accepted(null, null), _Column.consistent);
    }
    if (_blik.hasMatch(description)) {
      if (javaIsBlank(counterparty)) return rejected(ImportRule.unknownShape);
      final other = _counterpartyAccountOf(counterpartyAccountText);
      if (other == null) return rejected(ImportRule.counterpartyAccountInvalid);
      if (amountMinor > 0) return rejected(ImportRule.signUnexpected, _Column.positive);
      return _RowResult.of(accepted(counterparty, other));
    }
    if (description == ownTransferDescription) {
      final other = _counterpartyAccountOf(counterpartyAccountText);
      if (other == null) return rejected(ImportRule.counterpartyAccountInvalid);
      if (other == statementAccount) return rejected(ImportRule.transferSameAccount);
      // The wording of an outgoing own-account transfer is unknown (contract).
      if (amountMinor < 0) return rejected(ImportRule.signUnexpected);
      // The counterparty field holds the holder's own name and address: not carried.
      return _RowResult.of(accepted(null, other, ImportRule.ownAccountTransfer));
    }
    return rejected(ImportRule.unknownShape);
  }

  /// The counterparty account in normal form, or `null` unless it has the contract's shape.
  static String? _counterpartyAccountOf(String text) =>
      _counterpartyAccount.hasMatch(text) ? AccountNumbers.normalizeOrNull(text) : null;

  // --- helpers ----------------------------------------------------------------------------------

  static bool _outOfRange(CivilDate date, CivilDate latest) =>
      date.compareTo(_earliestDate) < 0 || date.compareTo(latest) > 0;

  /// The rule of the first failure, with the rows that broke that rule (bounded) and their count.
  static ImportRejection _rejection(List<_Failure> failures) {
    final rule = failures.first.rule;
    final rows = [for (final failure in failures) if (failure.rule == rule) failure.row];
    return ImportRejection.rows(
      rule,
      rows.sublist(0, rows.length < maxReportedRows ? rows.length : maxReportedRows),
      rows.length,
    );
  }

  static CivilDate? _parseIsoDate(String text) {
    final m = _isoDate.firstMatch(text);
    return m == null ? null : _date(m.group(1)!, m.group(2)!, m.group(3)!);
  }

  /// A real `DD-MM-YYYY` calendar day, or `null`.
  static CivilDate? _parseBankDate(String text) {
    final m = _bankDate.firstMatch(text);
    return m == null ? null : _date(m.group(3)!, m.group(2)!, m.group(1)!);
  }

  /// Java's `LocalDate.of(year, month, day)` for a four-digit year and two-digit month and day,
  /// `null` where it throws.
  static CivilDate? _date(String year, String month, String day) =>
      CivilDate.tryParse('$year-$month-$day');

  /// Java's `LocalDate.plusYears(1)`: the same day a year on, the 28th for a 29th of February.
  static CivilDate _plusOneYear(CivilDate date) {
    final year = date.year + 1;
    final last = CivilDate.daysInMonth(year, date.month);
    final day = date.day < last ? date.day : last;
    return CivilDate.parse(
      '${formatIsoYear(year)}-${'${date.month}'.padLeft(2, '0')}-${'$day'.padLeft(2, '0')}',
    );
  }
}

/// Java's `Character.isDigit(char)`: a UTF-16 unit in Unicode category Nd. The ranges are the JDK's
/// own answer over all 65 536 units (`isDigitUnits` in `test/golden/erste_import.json`, compared in
/// full); no supplementary digit counts, because Java's test reads units, not code points.
bool isJavaDigitUnit(int unit) {
  for (final range in _javaDigitUnits) {
    if (unit < range.$1) return false;
    if (unit <= range.$2) return true;
  }
  return false;
}

const List<(int, int)> _javaDigitUnits = [
  (0x0030, 0x0039),
  (0x0660, 0x0669),
  (0x06F0, 0x06F9),
  (0x07C0, 0x07C9),
  (0x0966, 0x096F),
  (0x09E6, 0x09EF),
  (0x0A66, 0x0A6F),
  (0x0AE6, 0x0AEF),
  (0x0B66, 0x0B6F),
  (0x0BE6, 0x0BEF),
  (0x0C66, 0x0C6F),
  (0x0CE6, 0x0CEF),
  (0x0D66, 0x0D6F),
  (0x0DE6, 0x0DEF),
  (0x0E50, 0x0E59),
  (0x0ED0, 0x0ED9),
  (0x0F20, 0x0F29),
  (0x1040, 0x1049),
  (0x1090, 0x1099),
  (0x17E0, 0x17E9),
  (0x1810, 0x1819),
  (0x1946, 0x194F),
  (0x19D0, 0x19D9),
  (0x1A80, 0x1A89),
  (0x1A90, 0x1A99),
  (0x1B50, 0x1B59),
  (0x1BB0, 0x1BB9),
  (0x1C40, 0x1C49),
  (0x1C50, 0x1C59),
  (0xA620, 0xA629),
  (0xA8D0, 0xA8D9),
  (0xA900, 0xA909),
  (0xA9D0, 0xA9D9),
  (0xA9F0, 0xA9F9),
  (0xAA50, 0xAA59),
  (0xABF0, 0xABF9),
  (0xFF10, 0xFF19),
];

final class _Failure {
  const _Failure(this.rule, this.row);
  final String rule;
  final int row;
}

/// What a row says about whether the amount column still holds the amount.
enum _Column {
  /// Nothing: not a card or BLIK row, or refused for another reason.
  unchecked,

  /// A card payment whose column equals the amount in its text.
  consistent,

  /// A card payment whose column differs from the amount in its text.
  mismatch,

  /// A card or BLIK row with a positive amount, which a real export never has.
  positive,
}

/// Either a row (accepted or flagged) or the whole-file rule it broke.
final class _RowResult {
  const _RowResult.of(ParsedRow this.row, [this.column = _Column.unchecked]) : rule = null;
  const _RowResult.fail(String this.rule) : row = null, column = _Column.unchecked;

  final ParsedRow? row;
  final String? rule;
  final _Column column;
}
