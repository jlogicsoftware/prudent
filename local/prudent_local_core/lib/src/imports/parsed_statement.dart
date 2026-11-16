import '../account_numbers.dart';
import '../civil_date.dart';
import 'import_rules.dart';

/// One normalised statement row — the server's `ParsedRow`: accepted (it can be written) or
/// rejected (named by the rule it broke, and carrying nothing else). A row the importer cannot read
/// is returned rejected, not dropped, so the count the person sees is the count in the file.
///
/// [toString] names the row and its codes and **never its text**: a description or counterparty is
/// personal data, and a `toString` is what ends up in a log line or a failed test's output.
final class ParsedRow {
  /// A row that can be written.
  const ParsedRow.accepted({
    required this.rowNumber,
    required CivilDate this.transactionDate,
    required this.bookingDate,
    required int this.amountMinor,
    required this.description,
    required this.counterparty,
    required this.counterpartyAccount,
    required this.externalId,
    this.hintCode,
  }) : rejectionCode = null;

  /// A row the importer could not use, named by the rule it broke and never by its content.
  const ParsedRow.rejected(this.rowNumber, String this.rejectionCode)
    : transactionDate = null,
      bookingDate = null,
      amountMinor = null,
      description = null,
      counterparty = null,
      counterpartyAccount = null,
      externalId = null,
      hintCode = null;

  /// 1-based position among the statement's transaction rows (the summary row is not row 1).
  final int rowNumber;

  /// The day of the operation; `null` only when rejected.
  final CivilDate? transactionDate;

  /// The bank's booking date, or `null`.
  final CivilDate? bookingDate;

  /// Signed minor units, negative for money out, never zero; `null` only when rejected.
  final int? amountMinor;

  final String? description;
  final String? counterparty;

  /// The other account in `AccountNumbers` normal form, or `null`.
  final String? counterpartyAccount;

  /// The bank's own entry identifier (Erste: the sequence number, a hint and never a key, ADR-091).
  final String? externalId;

  /// The rule this row broke, or `null` when accepted.
  final String? rejectionCode;

  /// A rule-shaped code about an accepted row, or `null`: [ImportRule.ownAccountTransfer].
  final String? hintCode;

  bool get isRejected => rejectionCode != null;

  @override
  String toString() => isRejected
      ? 'ParsedRow($rowNumber, rejected $rejectionCode)'
      : 'ParsedRow($rowNumber, accepted${hintCode == null ? '' : ', hint $hintCode'})';
}

/// What an importer produces from one statement — the server's `ParsedStatement`: the currency of
/// every row, the rows, and an opaque token for the statement's own account ([identityOf]), never
/// the number itself.
final class ParsedStatement {
  ParsedStatement(this.currency, List<ParsedRow> rows, this.accountIdentity)
    : rows = List.unmodifiable(rows);

  final String currency;
  final List<ParsedRow> rows;

  /// [identityOf] of the statement's own account, or `null` for a format that carries none.
  final String? accountIdentity;

  /// `ParsedStatement.identityOf`: `AccountNumbers.identityOf`, the one definition.
  static String identityOf(String accountNumber) => AccountNumbers.identityOf(accountNumber);

  @override
  String toString() => 'ParsedStatement($currency, ${rows.length} rows)';
}
