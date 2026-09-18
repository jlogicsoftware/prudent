import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

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
@immutable
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

  /// The query parameters this filter maps to, matching `RecordResource.list`'s param names
  /// exactly. Empty entries are simply absent, never sent as blank — that is what "no filter for
  /// this criterion" means on both ends.
  Map<String, String> toQueryParameters() {
    final query = <String, String>{};
    if (dateFrom != null) query['dateFrom'] = DateFormat('yyyy-MM-dd').format(dateFrom!);
    if (dateTo != null) query['dateTo'] = DateFormat('yyyy-MM-dd').format(dateTo!);
    if (accountId != null) query['accountId'] = accountId!;
    if (categoryId != null) query['categoryId'] = categoryId!;
    if (type != null) query['type'] = type!.wireValue;
    if (amountMin != null) query['amountMin'] = '$amountMin';
    if (amountMax != null) query['amountMax'] = '$amountMax';
    final trimmedSearch = search?.trim();
    if (trimmedSearch != null && trimmedSearch.isNotEmpty) query['search'] = trimmedSearch;
    return query;
  }

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
