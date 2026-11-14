package prudent.imports;

import java.util.regex.Pattern;

/**
 * A statement a {@link StatementImporter} refuses as a whole — an unsupported encoding, a changed
 * layout, a currency it does not know. Thrown before anything is written, so a rejected statement
 * leaves no session and no ledger row behind.
 *
 * <p><strong>It cannot carry content.</strong> A statement is personal data, and an exception's
 * message ends up in an error body and in logs. The only things it holds are a {@code rule} — a
 * short stable code such as {@code encoding.not_utf8}, checked against {@link #RULE} so free text
 * cannot be smuggled through it — and, optionally, a row number. That is what the Erste contract
 * asks of its error messages too (docs/erste-csv-contract.md: "name the row number and the rule,
 * never the row's content").
 */
public class ImportRejectedException extends RuntimeException {

  /** The shape of a rule code: lower-case words and digits joined by dots or underscores. */
  public static final Pattern RULE = Pattern.compile("[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*");

  private final String rule;
  private final Integer rowNumber;

  /** A statement-level rejection. */
  public ImportRejectedException(String rule) {
    this(rule, null);
  }

  /** A rejection that names the row it was found on. */
  public ImportRejectedException(String rule, Integer rowNumber) {
    super(message(rule, rowNumber));
    this.rule = rule;
    this.rowNumber = rowNumber;
  }

  private static String message(String rule, Integer rowNumber) {
    if (rule == null || !RULE.matcher(rule).matches()) {
      throw new IllegalArgumentException("an import rule code is a short dotted identifier");
    }
    if (rowNumber != null && rowNumber < 1) {
      throw new IllegalArgumentException("row numbers start at 1");
    }
    return rowNumber == null
        ? "The statement was rejected (" + rule + ")."
        : "The statement was rejected at row " + rowNumber + " (" + rule + ").";
  }

  public String rule() {
    return rule;
  }

  /** The 1-based row the rule failed on, or {@code null} for a statement-level rule. */
  public Integer rowNumber() {
    return rowNumber;
  }
}
