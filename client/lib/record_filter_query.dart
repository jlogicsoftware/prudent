import 'package:intl/intl.dart';
import 'package:prudent_ui/record/record_filter.dart';

/// How a [RecordFilter] is written on the server's REST route. This is a transport concern, so it
/// lives with `ServerPrudentRepository` and not on the filter, which screens and any other
/// repository read by field (ADR-108).
extension RecordFilterQuery on RecordFilter {
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
}
