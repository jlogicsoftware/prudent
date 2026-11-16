package prudent.budget;

import java.time.YearMonth;

/**
 * Opens the package-private budget rules to the golden-vector generator
 * ({@link prudent.parity.GoldenVectorsTest}), so the vectors come from the methods the server runs
 * and not from a copy of them in the test.
 */
public final class BudgetRulesAccess {

  private BudgetRulesAccess() {}

  /** {@link BudgetResource#parseMonth}: strictly {@code YYYY-MM}. */
  public static YearMonth parseMonth(String month) {
    return BudgetResource.parseMonth(month);
  }

  /** {@link BudgetResource#parseCurrency}: normalised, and refused unless ISO-4217. */
  public static String parseCurrency(String currency) {
    return BudgetResource.parseCurrency(currency);
  }
}
