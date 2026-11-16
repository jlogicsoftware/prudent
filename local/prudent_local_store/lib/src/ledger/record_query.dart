import 'package:meta/meta.dart';

/// The record list's filters, as the server's `GET /api/v1/records` takes its query parameters
/// (`RecordResource.list`, phase-0 §0.3 rows 5.46–5.50): raw text where the server parses text, so
/// a malformed date or id is refused here exactly as there.
///
/// Every field is optional; an absent or blank text field is no filter. `amountMin` and `amountMax`
/// bound `abs(amount)`, inclusive, in any currency, and a negative bound is refused.
@immutable
final class RecordQuery {
  /// `YYYY-MM-DD`, inclusive.
  final String? dateFrom;

  /// `YYYY-MM-DD`, inclusive.
  final String? dateTo;

  final String? accountId;
  final String? categoryId;

  /// `income`, `expense`, `transfer` or `correction`, trimmed and without case.
  final String? type;

  final int? amountMin;
  final int? amountMax;

  /// Matched against the folded title, payee and note (ADR-106).
  final String? search;

  const RecordQuery({
    this.dateFrom,
    this.dateTo,
    this.accountId,
    this.categoryId,
    this.type,
    this.amountMin,
    this.amountMax,
    this.search,
  });
}
