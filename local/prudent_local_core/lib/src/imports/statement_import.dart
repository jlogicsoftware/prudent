import 'dart:typed_data';

import '../civil_date.dart';
import '../currencies.dart';
import '../java_text.dart';
import 'erste_statement_importer.dart';
import 'import_rules.dart';
import 'parsed_statement.dart';

/// The bounds a statement must keep and the checks on what an importer returned — the server's
/// `ParsedStatements.java` and the upload bounds of `ImportWorkflow.create`.
///
/// Two kinds of refusal, as on the server: a malformed result is an importer bug and a
/// [StateError] naming the format and never a row; a well-formed result that is too big (more rows
/// than the limit, a text field over [maxFieldChars]) is the statement's doing, an
/// [ImportRejection] naming a rule and a row.
abstract final class StatementBounds {
  /// The largest upload accepted (`ImportWorkflow.MAX_CONTENT_BYTES`).
  static const maxContentBytes = 5 * 1024 * 1024;

  /// The most transaction rows a statement may hold (`prudent.import.max-rows`'s default).
  static const defaultMaxRows = 5000;

  /// The longest a description, counterparty, counterparty account or bank entry id may be, in
  /// UTF-16 units (Java's `String.length()`).
  static const maxFieldChars = 1024;

  static const _maxRuleChars = 100;
  static final _identity = RegExp(r'^[0-9a-f]{64}$');

  /// The upload bounds, before any importer reads the bytes: `statement.empty_upload`,
  /// `statement.too_large`.
  static void checkUpload(Uint8List content) {
    if (content.isEmpty) throw ImportRejection(ImportRule.emptyUpload);
    if (content.length > maxContentBytes) throw ImportRejection(ImportRule.tooLarge);
  }

  /// `ParsedStatements.validate`: one upper-case ISO-4217 currency, at least one row, unique
  /// positive row numbers, complete non-zero accepted rows, rejected rows that carry a code and
  /// nothing else; then the bounds. With [stableExternalId] every accepted row must also carry a
  /// distinct identifier (`identifier.missing`, `identifier.duplicate`).
  static void validate(
    String formatId,
    ParsedStatement statement, {
    int maxRows = defaultMaxRows,
    bool stableExternalId = false,
  }) {
    final currency = statement.currency;
    if (currency != Currencies.normalize(currency) || !Currencies.isValid(currency)) {
      throw _broken(formatId, 'did not return one upper-case ISO-4217 currency');
    }
    final identity = statement.accountIdentity;
    if (identity != null && !_identity.hasMatch(identity)) {
      throw _broken(formatId, 'returned an account identity that is not ParsedStatement.identityOf');
    }
    if (statement.rows.isEmpty) {
      throw _broken(formatId, 'returned a statement with no rows; reject it instead');
    }
    if (statement.rows.length > maxRows) throw ImportRejection(ImportRule.tooManyRows);
    final seen = <int>{};
    final identifiers = <String>{};
    for (final row in statement.rows) {
      if (row.rowNumber < 1 || !seen.add(row.rowNumber)) {
        throw _broken(formatId, 'returned a missing, non-positive or repeated row number');
      }
      final code = row.rejectionCode;
      if (code != null) {
        if (code.length > _maxRuleChars || !ImportRule.shape.hasMatch(code)) {
          throw _broken(formatId, 'returned a rejection code that is not a rule identifier');
        }
        if (row.description != null ||
            row.counterparty != null ||
            row.counterpartyAccount != null ||
            row.externalId != null) {
          throw _broken(formatId, 'returned a rejected row that carries content');
        }
        if (row.hintCode != null) throw _broken(formatId, 'returned a rejected row with a hint');
      } else if (row.transactionDate == null || row.amountMinor == null || row.amountMinor == 0) {
        throw _broken(formatId, 'returned an accepted row without a date or with no amount');
      } else {
        final hint = row.hintCode;
        if (hint != null && (hint.length > _maxRuleChars || !ImportRule.shape.hasMatch(hint))) {
          throw _broken(formatId, 'returned a hint code that is not a rule identifier');
        }
        for (final text in [
          row.description,
          row.counterparty,
          row.counterpartyAccount,
          row.externalId,
        ]) {
          if (text != null && text.length > maxFieldChars) {
            throw ImportRejection(ImportRule.fieldTooLong, row.rowNumber);
          }
        }
        if (stableExternalId) {
          final id = row.externalId;
          if (id == null || javaIsBlank(id)) {
            throw ImportRejection(ImportRule.identifierMissing, row.rowNumber);
          }
          if (!identifiers.add(javaStrip(id))) {
            throw ImportRejection(ImportRule.identifierDuplicate, row.rowNumber);
          }
        }
      }
    }
  }

  static StateError _broken(String formatId, String what) =>
      StateError("Importer '$formatId' $what.");
}

/// The parse stage of an Erste statement upload: what the server's `ImportWorkflow.create` does
/// before a session exists — the upload bounds, [ErsteStatementImporter.parse] and
/// [StatementBounds.validate]. Throws [ImportRejection] with the rule the server would name, rows
/// included. The destination check is [ErsteStatementImporter.checkDestination]; sessions,
/// duplicates and the commit are unit 8b's.
///
/// Pure: it reads the bytes and keeps none of them, writes nothing and logs nothing.
ParsedStatement parseErsteStatement(
  Uint8List content, {
  required CivilDate today,
  int maxRows = StatementBounds.defaultMaxRows,
}) {
  StatementBounds.checkUpload(content);
  final statement = ErsteStatementImporter.parse(content, today: today);
  StatementBounds.validate(
    ErsteStatementImporter.formatId,
    statement,
    maxRows: maxRows,
    stableExternalId: ErsteStatementImporter.stableExternalId,
  );
  return statement;
}
