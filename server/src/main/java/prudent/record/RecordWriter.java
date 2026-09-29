package prudent.record;

import jakarta.enterprise.context.ApplicationScoped;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.UUID;
import prudent.Currencies;
import prudent.Ids;
import prudent.account.AccountEntity;
import prudent.category.CategoryEntity;
import prudent.error.PrudentException;

/**
 * The rules for writing a {@link RecordEntity}'s mutable fields, shared by everything that makes an
 * ordinary record: {@link RecordResource}'s create and replace, and the confirmation of a planned
 * occurrence (M2, jlogicsoftware/prudent#57). One implementation, so a rule cannot hold for a
 * record typed in and lapse for one confirmed from a plan.
 */
@ApplicationScoped
public class RecordWriter {

  /**
   * Validates and writes every mutable field. Shared by create and replace, so a rule cannot hold
   * on create and lapse on edit.
   *
   * <p><strong>The account and the currency are validated together</strong>, because moving a
   * record between accounts and changing its currency are one operation: checking the currency
   * against the <em>old</em> account would let a client move a PLN record into a EUR-only account
   * by sending both changes at once.
   */
  public void apply(
      RecordEntity entity,
      UUID userId,
      String title,
      long amountMinor,
      String date,
      String categoryId,
      String accountId,
      String currency,
      String payee,
      String note) {

    if (title == null || title.isBlank()) {
      throw PrudentException.invalid("A record needs a title.");
    }

    // SIGNED (records.proto, ADR-014): negative is an expense, positive is income. Zero moves
    // nothing and is refused rather than stored as a no-op transaction — a balance summed over a
    // zero-amount row would be correct by accident, and a client that sent zero by mistake would
    // get no signal that anything was wrong.
    if (amountMinor == 0) {
      throw PrudentException.invalid(
          "A record needs a nonzero amount. Negative is an expense, positive is income.");
    }

    // The owning account, looked up AS THE CALLER'S. An account id that is not theirs is refused
    // here rather than stored — a client that can name someone else's account can move money into
    // it.
    AccountEntity account =
        AccountEntity.findOwned(userId, Ids.parseInBody("account", accountId));
    if (account == null) {
      throw PrudentException.invalid("No such account for this user: " + accountId);
    }

    CategoryEntity category =
        CategoryEntity.findOwned(userId, Ids.parseInBody("category", categoryId));
    if (category == null) {
      throw PrudentException.invalid("No such category for this user: " + categoryId);
    }

    String normalized = Currencies.normalize(currency);
    if (!Currencies.isValid(normalized)) {
      throw PrudentException.invalid("'" + currency + "' is not an ISO-4217 currency.");
    }
    // THE REFUSAL THAT REPLACED INHERITANCE (ADR-008). When an account held one currency a record
    // inherited it and disagreement was impossible to express; with several, only the record knows
    // which balance it moved, so the guarantee is this check instead.
    if (!AccountEntity.holds(account, normalized)) {
      throw PrudentException.invalid(
          "Account '" + account.name + "' does not hold " + normalized
              + ". Add the currency to the account first.");
    }

    entity.title = title.trim();
    entity.amountMinor = amountMinor;
    entity.currency = normalized;
    entity.date = parseDate(date);
    entity.categoryId = category.id;
    entity.accountId = account.id;
    entity.payee = blankToNull(payee);
    entity.note = blankToNull(note);
  }

  /**
   * Both {@code payee} and {@code note} are optional wire fields; a blank value is stored as
   * absent rather than as an empty string so the two never disagree about whether the field was
   * filled in.
   */
  private static String blankToNull(String value) {
    if (value == null) {
      return null;
    }
    String trimmed = value.trim();
    return trimmed.isEmpty() ? null : trimmed;
  }

  /**
   * Parses the ISO-8601 civil date the contract carries.
   *
   * <p>{@link LocalDate#parse} is strict about {@code YYYY-MM-DD} and rejects an impossible date
   * such as {@code 2026-02-30} rather than rolling it forward — which is the behaviour wanted here,
   * because a rolled date is a record filed in a month the user did not choose.
   */
  static LocalDate parseDate(String date) {
    if (date == null || date.isBlank()) {
      throw PrudentException.invalid("A record needs a date, as ISO-8601 YYYY-MM-DD.");
    }
    try {
      return LocalDate.parse(date);
    } catch (DateTimeParseException malformed) {
      // Converted to a refusal the caller can read, never defaulted to today: a record silently
      // filed on the wrong day is a wrong total in whatever month it lands in.
      throw PrudentException.invalid(
          "'" + date + "' is not an ISO-8601 date. Expected YYYY-MM-DD.");
    }
  }
}
