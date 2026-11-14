package prudent.imports;

import java.util.HashSet;
import java.util.Set;
import java.util.regex.Pattern;
import prudent.Currencies;
import prudent.error.PrudentException;

/**
 * The workflow's own checks on what an importer returned — the half of "separate parse from
 * commit" that does not depend on which bank the file came from.
 *
 * <p>These checks can only <em>add</em> strictness to an importer's own. Two kinds of refusal:
 *
 * <ul>
 *   <li>A malformed result is an importer bug and an {@link IllegalStateException} (a 500 naming
 *       the importer's id and the rule, never a row), not a 400 blaming the user for it.
 *   <li>A well-formed result that is too big for what the workflow will hold — more rows than the
 *       limit, or a text field longer than {@link #MAX_FIELD_CHARS} — is the statement's doing, so
 *       it is an {@link ImportRejectedException} (a 400 naming a rule and a row number).
 * </ul>
 */
final class ParsedStatements {

  /** The default for {@code prudent.import.max-rows}; a personal account's export is far below it. */
  static final int DEFAULT_MAX_ROWS = 5_000;

  /**
   * The longest a normalised text field (description, counterparty, counterparty account, bank
   * entry id) may be, in characters. A bank's own fields are a few hundred at most; a bound stops a
   * single row from turning staging into storage for arbitrary text.
   */
  static final int MAX_FIELD_CHARS = 1_024;

  /** The longest a rejection code may be; the rule shape alone does not bound it. */
  private static final int MAX_RULE_CHARS = 100;

  private static final Pattern IDENTITY = Pattern.compile("[0-9a-f]{64}");

  private ParsedStatements() {}

  /**
   * Checks that {@code statement} is a well-formed result: one real currency, at least one row, row
   * numbers that are unique and positive, an accepted row that is complete and non-zero, and a
   * rejected row that names a rule and nothing else.
   */
  static void validate(String formatId, ParsedStatement statement) {
    validate(formatId, statement, DEFAULT_MAX_ROWS);
  }

  /** As {@link #validate(String, ParsedStatement)}, with an explicit row limit. */
  static void validate(String formatId, ParsedStatement statement, int maxRows) {
    validate(formatId, statement, maxRows, false);
  }

  /**
   * As above; with {@code stableExternalId} (the importer's declaration, see {@link
   * StatementImporter#stableExternalId()}) every non-rejected row must also carry a distinct
   * identifier, because the identifier is then the row's whole key. A violation is the file's
   * doing, so a rule on a row number and no text: {@code identifier.missing},
   * {@code identifier.duplicate}.
   */
  static void validate(
      String formatId, ParsedStatement statement, int maxRows, boolean stableExternalId) {
    if (statement == null || statement.rows() == null) {
      throw broken(formatId, "returned no result");
    }
    String currency = statement.currency();
    if (currency == null
        || !currency.equals(Currencies.normalize(currency))
        || !Currencies.isValid(currency)) {
      throw broken(formatId, "did not return one upper-case ISO-4217 currency");
    }
    if (statement.accountIdentity() != null
        && !IDENTITY.matcher(statement.accountIdentity()).matches()) {
      throw broken(formatId, "returned an account identity that is not ParsedStatement.identityOf");
    }
    if (statement.rows().isEmpty()) {
      throw broken(formatId, "returned a statement with no rows; reject it instead");
    }
    if (statement.rows().size() > maxRows) {
      // The statement's doing, not the importer's: a 400 that gives the limit and nothing else.
      throw PrudentException.invalid(
          "The statement has more than " + maxRows + " transaction rows, which is the most an"
              + " import can hold.");
    }
    Set<Integer> seen = new HashSet<>();
    Set<String> identifiers = new HashSet<>();
    for (ParsedRow row : statement.rows()) {
      if (row == null || row.rowNumber() < 1 || !seen.add(row.rowNumber())) {
        throw broken(formatId, "returned a missing, non-positive or repeated row number");
      }
      if (row.isRejected()) {
        if (row.rejectionCode().length() > MAX_RULE_CHARS
            || !ImportRejectedException.RULE.matcher(row.rejectionCode()).matches()) {
          throw broken(formatId, "returned a rejection code that is not a rule identifier");
        }
        if (row.description() != null
            || row.counterparty() != null
            || row.counterpartyAccount() != null
            || row.externalId() != null) {
          // A rejected row is by definition one the importer could not understand; whatever text it
          // carries would be unvalidated personal data stored for no purpose.
          throw broken(formatId, "returned a rejected row that carries content");
        }
        if (row.hintCode() != null) {
          throw broken(formatId, "returned a rejected row with a hint");
        }
      } else if (row.transactionDate() == null
          || row.amountMinor() == null
          || row.amountMinor() == 0L) {
        throw broken(formatId, "returned an accepted row without a date or with no amount");
      } else {
        if (row.hintCode() != null
            && (row.hintCode().length() > MAX_RULE_CHARS
                || !ImportRejectedException.RULE.matcher(row.hintCode()).matches())) {
          throw broken(formatId, "returned a hint code that is not a rule identifier");
        }
        for (String text :
            new String[] {
              row.description(), row.counterparty(), row.counterpartyAccount(), row.externalId()
            }) {
          if (text != null && text.length() > MAX_FIELD_CHARS) {
            throw new ImportRejectedException("field.too_long", row.rowNumber());
          }
        }
        if (stableExternalId) {
          if (row.externalId() == null || row.externalId().isBlank()) {
            throw new ImportRejectedException("identifier.missing", row.rowNumber());
          }
          if (!identifiers.add(row.externalId().strip())) {
            throw new ImportRejectedException("identifier.duplicate", row.rowNumber());
          }
        }
      }
    }
  }

  private static IllegalStateException broken(String formatId, String what) {
    return new IllegalStateException("Importer '" + formatId + "' " + what + ".");
  }
}
