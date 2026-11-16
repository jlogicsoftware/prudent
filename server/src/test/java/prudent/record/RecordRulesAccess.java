package prudent.record;

import java.time.LocalDate;

/**
 * Opens the package-private record rules to the golden-vector generator
 * ({@link prudent.parity.GoldenVectorsTest}), so the vectors come from the method the server runs
 * and not from a copy of it in the test.
 */
public final class RecordRulesAccess {

  private RecordRulesAccess() {}

  /** {@link RecordWriter#parseDate}, the strict ISO-8601 civil date every record carries. */
  public static LocalDate parseDate(String date) {
    return RecordWriter.parseDate(date);
  }
}
