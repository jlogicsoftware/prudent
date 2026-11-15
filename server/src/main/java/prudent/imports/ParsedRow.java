package prudent.imports;

import java.time.LocalDate;

/**
 * One normalised row an importer hands to the workflow. Either well formed ({@link #accepted}) or
 * flagged ({@link #rejected}); a row an importer cannot read is flagged, not omitted, so the count
 * the user sees is the count in the file.
 *
 * @param rowNumber 1-based position among the statement's transaction rows
 * @param transactionDate the day of the operation; {@code null} only when rejected
 * @param bookingDate the bank's booking date, or {@code null} if the format has none
 * @param amountMinor signed minor units, negative for money out, never zero; {@code null} only when
 *     rejected
 * @param rejectionCode a rule code ({@link ImportRejectedException#RULE}) when rejected, else
 *     {@code null}
 * @param externalId the bank's own entry identifier, when the format has one
 * @param hintCode a stable rule-shaped code about an accepted row (never content), or {@code null};
 *     see {@link #HINT_OWN_ACCOUNT_TRANSFER}
 */
public record ParsedRow(
    int rowNumber,
    LocalDate transactionDate,
    LocalDate bookingDate,
    Long amountMinor,
    String description,
    String counterparty,
    String counterpartyAccount,
    String externalId,
    String rejectionCode,
    String hintCode) {

  /**
   * The row is an incoming transfer from another account of the user's own (ADR-092). It is written
   * as a plain record of the destination only; the user must record the other side as a plain
   * expense, never as a Prudent Transfer, which would credit this account a second time.
   */
  public static final String HINT_OWN_ACCOUNT_TRANSFER = "transfer.own_account";

  /** A row without a hint. */
  public ParsedRow(
      int rowNumber,
      LocalDate transactionDate,
      LocalDate bookingDate,
      Long amountMinor,
      String description,
      String counterparty,
      String counterpartyAccount,
      String externalId,
      String rejectionCode) {
    this(
        rowNumber,
        transactionDate,
        bookingDate,
        amountMinor,
        description,
        counterparty,
        counterpartyAccount,
        externalId,
        rejectionCode,
        null);
  }

  /** This row with {@code code} as its hint. */
  public ParsedRow withHint(String code) {
    return new ParsedRow(
        rowNumber,
        transactionDate,
        bookingDate,
        amountMinor,
        description,
        counterparty,
        counterpartyAccount,
        externalId,
        rejectionCode,
        code);
  }

  /** A row that can be written on commit. */
  public static ParsedRow accepted(
      int rowNumber,
      LocalDate transactionDate,
      LocalDate bookingDate,
      long amountMinor,
      String description,
      String counterparty,
      String counterpartyAccount,
      String externalId) {
    return new ParsedRow(
        rowNumber,
        transactionDate,
        bookingDate,
        amountMinor,
        description,
        counterparty,
        counterpartyAccount,
        externalId,
        null);
  }

  /** A row the importer could not use, named by the rule it broke and never by its content. */
  public static ParsedRow rejected(int rowNumber, String rejectionCode) {
    return new ParsedRow(rowNumber, null, null, null, null, null, null, null, rejectionCode);
  }

  public boolean isRejected() {
    return rejectionCode != null;
  }
}
