/// The rule codes of statement import (M6, ADR-089 to ADR-094) and the refusal that carries one.
///
/// A code is the whole of what an import refusal says: the server's `ImportRejectedException`
/// carries a code and row numbers and nothing else, because a statement is personal data and an
/// exception's message ends up in an error body and a log. [ImportRejection] is the same here.
library;

/// Every rule code the server's import code can emit, as constants (the server's literals).
///
/// [parseStage] are the codes this package emits (unit 8a): the upload bounds, the CSV layer, the
/// Erste importer, the statement bounds, the destination check and the own-account hint.
/// [sessionStage] are the codes the import sessions, duplicate detection and commit emit; they are
/// named here so that unit 8b uses the server's spelling, and nothing in this package emits them.
/// `test/imports/import_rule_catalogue_test.dart` holds the two sets to the server's own scan of
/// its sources (`test/golden/erste_import.json`, `emittedRules`).
abstract final class ImportRule {
  // --- the upload ---
  static const emptyUpload = 'statement.empty_upload';
  static const tooLarge = 'statement.too_large';

  // --- bytes and lines (ErsteCsv) ---
  static const encodingBom = 'encoding.bom';
  static const encodingNulByte = 'encoding.nul_byte';
  static const encodingNotUtf8 = 'encoding.not_utf8';
  static const lineEnding = 'layout.line_ending';
  static const noFinalNewline = 'layout.no_final_newline';
  static const csvMalformed = 'csv.malformed';

  // --- layout and the summary row ---
  static const delimiter = 'layout.delimiter';
  static const headerRow = 'layout.header_row';
  static const summaryMissing = 'layout.summary_missing';
  static const amountColumn = 'layout.amount_column';
  static const fieldCount = 'row.field_count';
  static const trailingField = 'row.trailing_field';
  static const exportDateInvalid = 'summary.export_date_invalid';
  static const periodStartInvalid = 'summary.period_start_invalid';
  static const summaryAccountInvalid = 'summary.account_invalid';
  static const currencyUnsupported = 'currency.unsupported';
  static const statementEmpty = 'statement.empty';

  // --- transaction rows: whole-file ---
  static const dateInvalid = 'date.invalid';
  static const dateOutOfRange = 'date.out_of_range';
  static const bookingBeforeTransaction = 'date.booking_before_transaction';
  static const amountInvalid = 'amount.invalid';
  static const amountZero = 'amount.zero';
  static const sequenceInvalid = 'sequence.invalid';
  static const sequenceDuplicate = 'sequence.duplicate';
  static const cardForeignCurrency = 'card.foreign_currency';

  // --- transaction rows: the row is returned rejected ---
  static const unknownShape = 'description.unknown_shape';
  static const signUnexpected = 'amount.sign_unexpected';
  static const cardAmountMismatch = 'card.amount_mismatch';
  static const counterpartyAccountInvalid = 'counterparty_account.invalid';
  static const transferSameAccount = 'transfer.same_account';

  // --- a hint on an accepted row, never a refusal ---
  static const ownAccountTransfer = 'transfer.own_account';

  // --- the statement bounds (ParsedStatements) ---
  static const tooManyRows = 'statement.too_many_rows';
  static const fieldTooLong = 'field.too_long';
  static const identifierMissing = 'identifier.missing';
  static const identifierDuplicate = 'identifier.duplicate';

  // --- the destination (StatementImporter.checkDestination) ---
  static const identityUnverifiable = 'account.identity_unverifiable';
  static const numberMissing = 'account.number_missing';
  static const identityMismatch = 'account.identity_mismatch';

  // --- unit 8b: sessions, duplicates, commit ---
  static const accountNotFound = 'account.not_found';
  static const alreadyImported = 'duplicate.already_imported';
  static const commitCategoryUnavailable = 'commit.category_unavailable';
  static const commitAccountUnavailable = 'commit.account_unavailable';
  static const commitRowRefused = 'commit.row_refused';

  /// The codes this package emits.
  static const Set<String> parseStage = {
    emptyUpload,
    tooLarge,
    encodingBom,
    encodingNulByte,
    encodingNotUtf8,
    lineEnding,
    noFinalNewline,
    csvMalformed,
    delimiter,
    headerRow,
    summaryMissing,
    amountColumn,
    fieldCount,
    trailingField,
    exportDateInvalid,
    periodStartInvalid,
    summaryAccountInvalid,
    currencyUnsupported,
    statementEmpty,
    dateInvalid,
    dateOutOfRange,
    bookingBeforeTransaction,
    amountInvalid,
    amountZero,
    sequenceInvalid,
    sequenceDuplicate,
    cardForeignCurrency,
    unknownShape,
    signUnexpected,
    cardAmountMismatch,
    counterpartyAccountInvalid,
    transferSameAccount,
    ownAccountTransfer,
    tooManyRows,
    fieldTooLong,
    identifierMissing,
    identifierDuplicate,
    identityUnverifiable,
    numberMissing,
    identityMismatch,
  };

  /// The codes of the stages after the parse (unit 8b). Named, never emitted here.
  static const Set<String> sessionStage = {
    accountNotFound,
    alreadyImported,
    commitCategoryUnavailable,
    commitAccountUnavailable,
    commitRowRefused,
  };

  /// The shape of a rule code: lower-case words and digits joined by dots or underscores — the
  /// server's `ImportRejectedException.RULE`, so free text cannot pass for a code.
  static final RegExp shape = RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$');
}

/// A statement refused as a whole — the server's `ImportRejectedException`.
///
/// It holds a [rule] code and, for a rule that rows broke, the first [rowNumbers] that broke it
/// (bounded by the caller) and how many did in all ([totalRows]). **It cannot carry statement
/// text**: the constructor refuses a [rule] that is not a code, and there is no other field. Its
/// [message] is the server's own wording, built from those numbers alone.
final class ImportRejection implements Exception {
  /// A statement-level refusal (no row) or one on a single row.
  ImportRejection(this.rule, [int? row])
    : rowNumbers = row == null ? const [] : List.unmodifiable([row]),
      totalRows = row == null ? 0 : 1 {
    _check();
  }

  /// One rule broken on several rows: the rows to name, 1-based and ascending, and how many rows
  /// broke it in all.
  ImportRejection.rows(this.rule, List<int> rows, this.totalRows)
    : rowNumbers = List.unmodifiable(rows) {
    if (rowNumbers.isEmpty || totalRows < rowNumbers.length) {
      throw ArgumentError('a multi-row rejection names at least one row');
    }
    _check();
  }

  final String rule;
  final List<int> rowNumbers;
  final int totalRows;

  /// The first row the rule failed on, or `null` for a statement-level rule.
  int? get rowNumber => rowNumbers.isEmpty ? null : rowNumbers.first;

  void _check() {
    if (!ImportRule.shape.hasMatch(rule)) {
      // Not the text: it is not a code, so it may be anything, a statement's content included.
      throw ArgumentError('an import rule code is a short dotted identifier');
    }
    for (final row in rowNumbers) {
      if (row < 1) throw ArgumentError('row numbers start at 1');
    }
  }

  /// The server's message, word for word: what the client's `importRuleMessage` has replaced with a
  /// sentence of its own, and what a log line may hold.
  String get message {
    if (rowNumbers.isEmpty) return 'The statement was rejected ($rule).';
    if (rowNumbers.length == 1 && totalRows == 1) {
      return 'The statement was rejected at row ${rowNumbers.first} ($rule).';
    }
    final more = totalRows - rowNumbers.length;
    return 'The statement was rejected at rows ${rowNumbers.join(', ')}'
        '${more > 0 ? ' and $more more' : ''} ($rule).';
  }

  @override
  String toString() => 'ImportRejection: $message';
}
