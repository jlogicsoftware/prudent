import 'package:fixnum/fixnum.dart';

// NOTHING IN THIS FILE MAY IMPORT `package:flutter/*` (client/integration_test/e2e_test.dart's own
// header comment). prudent_repository.dart, which that suite imports directly to run on the plain
// Dart VM, imports this file — a `dart:ui`-reaching import here breaks `dart test` at compile time,
// not just at runtime.

/// The three shapes a record can be filtered to, matching `RecordType` on the server
/// (jlogicsoftware/prudent#52). Not generated from the contract — query parameters are a
/// REST-layer concern, not a proto field, on both ends.
enum RecordFilterType {
  income('income'),
  expense('expense'),
  transfer('transfer');

  const RecordFilterType(this.wireValue);

  final String wireValue;
}

/// Every criterion `GET /api/v1/records` can be filtered by, independently optional and
/// composable — mirrors the server's own query params 1:1 (see records.proto).
///
/// Immutable: the records filter sheet builds a new instance from its own local editable state
/// and writes it to [recordFilterProvider] wholesale on "Apply", rather than patching this one
/// field at a time.
class RecordFilter {
  const RecordFilter({
    this.dateFrom,
    this.dateTo,
    this.accountId,
    this.categoryId,
    this.type,
    this.amountMin,
    this.amountMax,
    this.search,
  });

  static const RecordFilter empty = RecordFilter();

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? accountId;
  final String? categoryId;
  final RecordFilterType? type;

  /// Non-negative minor units, matched server-side against the record's absolute amount —
  /// currency-agnostic by design (docs/DECISIONS.md).
  final Int64? amountMin;
  final Int64? amountMax;

  /// Case-insensitive substring match against title, payee, or note.
  final String? search;

  bool get isEmpty =>
      dateFrom == null &&
      dateTo == null &&
      accountId == null &&
      categoryId == null &&
      type == null &&
      amountMin == null &&
      amountMax == null &&
      (search == null || search!.trim().isEmpty);

  @override
  bool operator ==(Object other) =>
      other is RecordFilter &&
      other.dateFrom == dateFrom &&
      other.dateTo == dateTo &&
      other.accountId == accountId &&
      other.categoryId == categoryId &&
      other.type == type &&
      other.amountMin == amountMin &&
      other.amountMax == amountMax &&
      other.search == search;

  @override
  int get hashCode =>
      Object.hash(dateFrom, dateTo, accountId, categoryId, type, amountMin, amountMax, search);
}
