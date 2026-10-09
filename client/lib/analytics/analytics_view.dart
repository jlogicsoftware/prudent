/// The two ways the analytics screen shows spending. They share one currency, and only one is on
/// screen at a time.
enum AnalyticsView {
  /// A bar per month over the trailing year.
  byMonth,

  /// A donut of one month's spend split by category.
  byCategory,
}
