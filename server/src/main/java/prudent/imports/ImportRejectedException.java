package prudent.imports;

import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

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
  private final List<Integer> rowNumbers;
  private final int totalRows;

  /** A statement-level rejection. */
  public ImportRejectedException(String rule) {
    this(rule, null);
  }

  /** A rejection that names the row it was found on. */
  public ImportRejectedException(String rule, Integer rowNumber) {
    super(message(rule, rowNumber));
    this.rule = rule;
    this.rowNumber = rowNumber;
    this.rowNumbers = rowNumber == null ? List.of() : List.of(rowNumber);
    this.totalRows = this.rowNumbers.size();
  }

  /**
   * A rejection of one rule on several rows, for an importer that validates the whole file before
   * it throws (jlogicsoftware/prudent#73): the first {@code rowNumbers} that broke the rule, and how
   * many rows broke it in all. The caller bounds the list; the message names at most the rows given
   * and says how many more there were. {@link #rowNumber()} answers the first.
   *
   * @param rowNumbers the rows to name, 1-based, ascending, non-empty
   * @param totalRows how many rows broke the rule, at least {@code rowNumbers.size()}
   */
  public ImportRejectedException(String rule, List<Integer> rowNumbers, int totalRows) {
    super(message(rule, rowNumbers, totalRows));
    this.rule = rule;
    this.rowNumbers = List.copyOf(rowNumbers);
    this.rowNumber = this.rowNumbers.get(0);
    this.totalRows = totalRows;
  }

  private static String message(String rule, List<Integer> rowNumbers, int totalRows) {
    if (rowNumbers == null || rowNumbers.isEmpty() || totalRows < rowNumbers.size()) {
      throw new IllegalArgumentException("a multi-row rejection names at least one row");
    }
    if (rowNumbers.size() == 1 && totalRows == 1) {
      return message(rule, rowNumbers.get(0));
    }
    if (rule == null || !RULE.matcher(rule).matches()) {
      throw new IllegalArgumentException("an import rule code is a short dotted identifier");
    }
    for (Integer number : rowNumbers) {
      if (number == null || number < 1) {
        throw new IllegalArgumentException("row numbers start at 1");
      }
    }
    String named = rowNumbers.stream().map(String::valueOf).collect(Collectors.joining(", "));
    int more = totalRows - rowNumbers.size();
    return "The statement was rejected at rows "
        + named
        + (more > 0 ? " and " + more + " more" : "")
        + " ("
        + rule
        + ").";
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

  /** The rows named, 1-based and possibly bounded; empty for a statement-level rule. */
  public List<Integer> rowNumbers() {
    return rowNumbers;
  }

  /** How many rows broke the rule, which can exceed {@link #rowNumbers()}'s size. */
  public int totalRows() {
    return totalRows;
  }

  /** The first 1-based row the rule failed on, or {@code null} for a statement-level rule. */
  public Integer rowNumber() {
    return rowNumber;
  }
}
