import 'package:zen_core/zen_core.dart';
import 'package:zen_transport/zen_transport.dart' show ZenTransportError, ZenTransportErrorCode;

/// What kind of refusal the server (or the network) gave an import request.
enum ImportFailureKind {
  /// The statement or the destination was refused by a named rule (`encoding.not_utf8`, ...).
  rule,

  /// A 400 with no rule: an unknown format, an inactive or wrong-currency account.
  invalid,

  /// A 409 on upload: the caller already has the most open sessions allowed.
  tooManyOpen,

  /// A 409 anywhere else: the session is not in a state that allows the request, has expired, or the
  /// ledger refused a row. The caller reloads the session to find out which.
  conflict,

  /// A 404: no such session (or row) for this user.
  notFound,

  /// The request never reached the server.
  network,

  /// A 503.
  unavailable,

  /// Anything else, including a response that could not be decoded.
  unexpected,
}

/// A failed import request, reduced to what a localized sentence needs: its [kind], and for a
/// rule refusal the rule code and the row numbers it names.
///
/// The server's message is English and is not shown (docs/erste-csv-contract.md: an error names a
/// rule and a row, never content). It is read only to lift the rule code and the row numbers out of
/// its one fixed shape, and only when the whole message matches that shape, so nothing else in a
/// message can reach the screen through here.
class ImportFailure {
  const ImportFailure({
    required this.kind,
    this.ruleCode,
    this.rowNumbers = const [],
    this.moreRows = 0,
  });

  final ImportFailureKind kind;

  /// The stable rule code, such as `amount.invalid`. Null unless [kind] is [ImportFailureKind.rule].
  final String? ruleCode;

  /// The rows the server named, ascending, at most a handful.
  final List<int> rowNumbers;

  /// How many further rows broke the rule beyond [rowNumbers].
  final int moreRows;

  /// `The statement was rejected`, then optionally ` at row 3` or ` at rows 3, 5 and 2 more`, then
  /// the rule in parentheses. Anchored at both ends on purpose.
  static final RegExp _ruleMessage = RegExp(
    r'^The statement was rejected(?: at rows? (\d+(?:, \d+)*)(?: and (\d+) more)?)? '
    r'\(([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*)\)\.$',
  );

  /// Classifies [error]. [creating] says the request was the upload, where a 409 means too many open
  /// sessions rather than a session in the wrong state.
  factory ImportFailure.from(Object error, {bool creating = false}) {
    final String? wire = error is ZenTransportError ? error.zenError.code : null;
    final String message = error is ZenError ? error.message : '';

    final rule = _ruleMessage.firstMatch(message);
    if (rule != null && (wire == 'invalid' || wire == 'conflict')) {
      final rows = rule.group(1);
      return ImportFailure(
        kind: ImportFailureKind.rule,
        ruleCode: rule.group(3),
        rowNumbers: rows == null ? const [] : [for (final n in rows.split(', ')) int.parse(n)],
        moreRows: int.tryParse(rule.group(2) ?? '') ?? 0,
      );
    }

    if (wire == ZenTransportErrorCode.network.wire) {
      return const ImportFailure(kind: ImportFailureKind.network);
    }
    return switch (wire) {
      'invalid' => const ImportFailure(kind: ImportFailureKind.invalid),
      'conflict' => ImportFailure(
        kind: creating ? ImportFailureKind.tooManyOpen : ImportFailureKind.conflict,
      ),
      'not_found' => const ImportFailure(kind: ImportFailureKind.notFound),
      'unavailable' => const ImportFailure(kind: ImportFailureKind.unavailable),
      _ => const ImportFailure(kind: ImportFailureKind.unexpected),
    };
  }

  /// A refusal after which the screen should reload the session: it may have ended meanwhile.
  bool get shouldReload =>
      kind == ImportFailureKind.conflict || kind == ImportFailureKind.notFound;
}
