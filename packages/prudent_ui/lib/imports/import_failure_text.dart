import '../l10n/generated/prudent_localizations.dart';
import 'import_failure.dart';
import 'import_rule_messages.dart';

/// The sentence a user reads for [failure], in their language: what was wrong and what to do.
///
/// A rule the client does not know falls back to a generic sentence that carries the code, never to
/// the server's English message.
String importFailureMessage(PrudentLocalizations t, ImportFailure failure) {
  switch (failure.kind) {
    case ImportFailureKind.rule:
      final code = failure.ruleCode!;
      return importRuleMessage(t, code) ?? t.importFailureUnknownRule(code);
    case ImportFailureKind.invalid:
      return t.importFailureGeneric;
    case ImportFailureKind.tooManyOpen:
      return t.importFailureTooManyOpen;
    case ImportFailureKind.conflict:
      return t.importFailureConflict;
    case ImportFailureKind.notFound:
      return t.importFailureNotFound;
    case ImportFailureKind.network:
      return t.importFailureNetwork;
    case ImportFailureKind.unavailable:
      return t.importFailureUnavailable;
    case ImportFailureKind.unexpected:
      return t.importFailureUnexpected;
  }
}

/// "Rows involved: 3, 5 and 2 more", or null when the failure names no row.
String? importFailureRows(PrudentLocalizations t, ImportFailure failure) {
  if (failure.rowNumbers.isEmpty) return null;
  final rows = failure.rowNumbers.join(', ');
  return failure.moreRows > 0
      ? t.importFailureRowsMore(rows, failure.moreRows)
      : t.importFailureRowsList(rows);
}
