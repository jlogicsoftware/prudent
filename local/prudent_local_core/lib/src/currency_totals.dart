import 'minor_units.dart';

/// Amounts kept apart by currency — the one shape a Prudent total may have (rule 3.3: nothing is
/// ever summed across currencies; ADR-008, ADR-009, `AnalyticsResource.java:191`,
/// `BudgetResource.java:121`).
///
/// There is deliberately no "grand total" here: a sum of PLN and EUR is not a number of anything,
/// and the server never computes one. Each currency's figure is an exact sum ([addExact]), so an
/// overflow is a [MoneyOverflow], never a wrapped balance. A currency is a canonical code
/// (`Currencies.parse`); this class does not normalise, so `"pln"` and `"PLN"` here would be two
/// currencies — the caller parses first, as the server does before anything is stored.
final class CurrencyTotals {
  final Map<String, int> _byCurrency = {};

  /// Adds [amountMinor] to [currency]'s total.
  void add(String currency, int amountMinor) {
    _byCurrency[currency] = addExact(_byCurrency[currency] ?? 0, amountMinor);
  }

  /// The total of [currency], or zero when nothing was added in it.
  int of(String currency) => _byCurrency[currency] ?? 0;

  /// Whether anything was added in [currency] — a zero total is still a total.
  bool holds(String currency) => _byCurrency.containsKey(currency);

  /// The currencies with a total, in code order.
  List<String> get currencies => _byCurrency.keys.toList()..sort();

  /// Every total, in code order of currency.
  Map<String, int> asMap() => {for (final currency in currencies) currency: _byCurrency[currency]!};
}
