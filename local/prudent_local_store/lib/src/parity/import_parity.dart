import 'dart:convert';

import 'package:prudent_local_core/parity.dart';

/// The request bodies and the observations of the import parity operations (unit 8b, ADR-114),
/// shared by both backends so that both send the same request and read the answer alike.
///
/// - `import.create` — `{csv, account?, format?}`: the statement as text (synthetic, ADR-088), sent
///   as its UTF-8 bytes; observes the session.
/// - `import.preview` — `{session, account?}`; `import.defaults` — `{session, expense?, income?}`;
///   `import.commit` — `{session, confirmed}`; `import.discard` — `{session}`: each observes the
///   session the server answers.
/// - `import.row` — `{session, row, category?, note?, include?}`: observes the row and the counts.
///
/// What is compared: the phase, the three counts, the committed counts, the destination by bound
/// name, and each row's number, status and codes. Not compared: ids, times, and the row keys, which
/// are never on the wire (and differ anyway: the account id is part of a fingerprint).
abstract final class ImportParity {
  static Map<String, Object?> createBody(Map<String, Object?> input, ParityBindings bindings) => {
    'formatId': input['format'] ?? 'erste-pl-csv',
    'content': base64.encode(utf8.encode(input['csv']! as String)),
    if (input.containsKey('account')) 'accountId': bindings.idOrLiteral(input['account']),
  };

  static Map<String, Object?> previewBody(Map<String, Object?> input, ParityBindings bindings) => {
    if (input.containsKey('account')) 'accountId': bindings.idOrLiteral(input['account']),
  };

  static Map<String, Object?> defaultsBody(Map<String, Object?> input, ParityBindings bindings) => {
    if (input.containsKey('expense'))
      'defaultExpenseCategoryId': _idOrEmpty(input['expense'], bindings),
    if (input.containsKey('income'))
      'defaultIncomeCategoryId': _idOrEmpty(input['income'], bindings),
  };

  static Map<String, Object?> rowBody(Map<String, Object?> input, ParityBindings bindings) => {
    if (input.containsKey('category')) 'categoryId': _idOrEmpty(input['category'], bindings),
    if (input.containsKey('note')) 'note': input['note'],
    if (input.containsKey('include')) 'includeDuplicate': input['include'],
  };

  static Map<String, Object?> commitBody(Map<String, Object?> input) => {
    'confirmedAcceptedRows': input['confirmed'],
  };

  /// The session a step's input names.
  static String session(Map<String, Object?> input, ParityBindings bindings) =>
      bindings.resolve(input['session']);

  /// The row number a step's input names.
  static int rowNumber(Map<String, Object?> input) => input['row']! as int;

  /// What an import session answer observes.
  static Map<String, Object?> sessionObservation(
    Map<String, Object?> json,
    ParityBindings bindings,
  ) => {
    'state': ParityReaders.enumName(json, 'state', 'IMPORT_SESSION_STATE_UNSPECIFIED'),
    'currency': ParityReaders.string(json, 'currency'),
    'account': json.containsKey('accountId') ? bindings.nameOf(json['accountId'] as String) : null,
    'accepted': _int32(json, 'acceptedRows'),
    'duplicates': _int32(json, 'duplicateRows'),
    'rejected': _int32(json, 'rejectedRows'),
    'committedWritten': json['committedWritten'],
    'committedAlreadyImported': json['committedAlreadyImported'],
    'rows': [
      for (final row in ((json['rows'] as List<Object?>?) ?? const []).cast<Map<String, Object?>>())
        rowObservation(row),
    ],
  };

  /// What one row observes: its number, status and codes, and the person's decisions.
  static Map<String, Object?> rowObservation(Map<String, Object?> row) => {
    'row': _int32(row, 'rowNumber'),
    'status': ParityReaders.enumName(row, 'status', 'IMPORT_ROW_STATUS_UNSPECIFIED'),
    'rejectionCode': ParityReaders.string(row, 'rejectionCode'),
    'duplicateCode': ParityReaders.string(row, 'duplicateCode'),
    'hintCode': ParityReaders.string(row, 'hintCode'),
    'includeDuplicate': ParityReaders.boolean(row, 'includeDuplicate'),
    'hasCategory': row.containsKey('categoryId'),
    'note': row['note'] as String?,
  };

  /// What a row decision observes: the row and the counts.
  static Map<String, Object?> rowDecisionObservation(Map<String, Object?> json) => {
    'row': rowObservation((json['row'] as Map<String, Object?>?) ?? const {}),
    'accepted': _int32(json, 'acceptedRows'),
    'duplicates': _int32(json, 'duplicateRows'),
    'rejected': _int32(json, 'rejectedRows'),
  };

  static String _idOrEmpty(Object? value, ParityBindings bindings) =>
      value == '' ? '' : bindings.idOrLiteral(value)!;

  /// A proto3 `int32`: a JSON number, omitted when zero.
  static int _int32(Map<String, Object?> json, String key) => (json[key] as int?) ?? 0;
}
