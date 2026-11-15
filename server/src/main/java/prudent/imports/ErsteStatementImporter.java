package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import java.time.Clock;
import java.time.DateTimeException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import prudent.account.AccountEntity;
import prudent.account.AccountNumbers;

/**
 * The Erste Polska CSV importer (M6, jlogicsoftware/prudent#73, ADR-090). It validates one export
 * against {@code docs/erste-csv-contract.md} and rejects what that document has not observed.
 *
 * <p><strong>Whole file first.</strong> The statement is decoded and every row is checked before
 * anything is returned, so a refusal can leave nothing behind (and the importer writes nothing at
 * all, as {@link StatementImporter} requires). A failure in the layout or the summary row is thrown
 * at once; a failure in transaction rows is collected for the whole file and thrown as the rule of
 * the first failing row, naming up to {@link #MAX_REPORTED_ROWS} rows that broke it and how many
 * did in all. <strong>Row numbers count transaction rows</strong> (the summary row is not row 1),
 * the same numbering {@link ParsedRow#rowNumber()} uses.
 *
 * <p>Two kinds of problem, as in the contract:
 *
 * <ul>
 *   <li><em>The file is not a statement this importer understands</em> — encoding, line ending,
 *       delimiter, header, field count, dates (real days, 2000 to a year ahead), decimals, currency, sequence numbers, a foreign
 *       currency card payment, an empty statement. The whole statement is rejected.
 *   <li><em>A row has no known meaning</em> — a description outside the three observed shapes, a
 *       card amount that disagrees with the column, a sign the shape cannot have (on a card or BLIK
 *       row that is a whole-file refusal instead, {@link #amountColumnMoved}), a counterparty
 *       account that is not shaped like one. The row is returned {@linkplain ParsedRow#rejected
 *       rejected} so the count the user sees is the count in the file, and the rest may still be
 *       imported.
 * </ul>
 *
 * <p><strong>Never read, never kept, never shape-checked:</strong> the balance column and summary
 * fields 4 (the holder's name and address) and 6 to 8 (the contract says they do not chain or
 * are not understood), and the
 * statement's own account number, which leaves {@code parse} only as {@link
 * ParsedStatement#identityOf}. Nothing is logged, and no exception carries statement text.
 *
 * <p><strong>The bank's sequence number is a hint, not a key.</strong> It is returned as {@link
 * ParsedRow#externalId()} because the model has nowhere else to put it, but the contract does not
 * know whether it survives a second export that covers more rows. Duplicate detection (#75) must
 * not treat it as a stable identifier.
 */
@ApplicationScoped
public class ErsteStatementImporter implements StatementImporter {

  /** The most rows one rejection names; the exception also says how many more broke the rule. */
  static final int MAX_REPORTED_ROWS = 10;

  /**
   * The description the bank writes on an own-account transfer, kept verbatim as the row's {@link
   * ParsedRow#description()}. A row is an own-account transfer exactly when {@link
   * #isOwnAccountTransfer} says so, and its {@link ParsedRow#counterpartyAccount()} is the user's
   * other account in {@link AccountNumbers}' normal form (ADR-090).
   */
  public static final String OWN_TRANSFER_DESCRIPTION = "Przelew na rachunek własny";

  /** The only currency the contract has seen. */
  static final String CURRENCY = "PLN";

  private static final int FIELDS = 9;

  private static final Pattern ISO_DATE = Pattern.compile("(\\d{4})-(\\d{2})-(\\d{2})");
  private static final Pattern BANK_DATE = Pattern.compile("(\\d{2})-(\\d{2})-(\\d{4})");
  /**
   * An amount: optional {@code -}, one to eleven whole digits with no separator and no leading zero
   * (a lone {@code 0} before the comma is the only zero), a comma and exactly two decimals. Eleven
   * digits keep the minor-unit value far inside a {@code long}.
   */
  private static final Pattern AMOUNT = Pattern.compile("(-?)(0|[1-9][0-9]{0,10}),([0-9]{2})");
  /** Dates before this are not a bank statement of today (a typo or a different calendar). */
  private static final LocalDate EARLIEST_DATE = LocalDate.of(2000, 1, 1);
  private static final Pattern SEQUENCE = Pattern.compile("0|[1-9][0-9]{0,17}");
  /** The counterparty account as the contract shows it: two digits, then six groups of four. */
  private static final Pattern COUNTERPARTY_ACCOUNT = Pattern.compile("[0-9]{2}( [0-9]{4}){6}");

  private static final Pattern CARD =
      Pattern.compile(
          "DOP\\. (?:MC|VISA) [0-9]{6}\\*{6}[0-9]{4} PŁATNOŚĆ KARTĄ ([0-9]{1,11})\\.([0-9]{2}) ([A-Z]{3}) \\S.*");
  private static final Pattern BLIK = Pattern.compile("Zakup BLIK \\S.* ref:[0-9]{11}");

  /** The source of "today" for the date range check; a test replaces it. */
  Clock clock = Clock.systemUTC();

  @Override
  public String formatId() {
    return ImportFormatIds.ERSTE_PL_CSV;
  }

  /**
   * Whether {@code description} is the bank's own-account transfer wording. The row's {@code
   * counterpartyAccount} is then the user's other account; {@code
   * AccountEntity.findOwnedByNumber(userId, thatNumber)} finds it when the user has stored its
   * number.
   */
  public static boolean isOwnAccountTransfer(String description) {
    return OWN_TRANSFER_DESCRIPTION.equals(description);
  }

  @Override
  public ParsedStatement parse(byte[] content, ImportContext context) {
    List<String> lines = ErsteCsv.lines(content);

    String accountNumber = readSummary(lines.get(0));
    List<Failure> failures = new ArrayList<>();
    List<ParsedRow> rows = new ArrayList<>();
    Set<String> sequences = new HashSet<>();
    LocalDate latest = LocalDate.now(clock).plusYears(1);
    int positiveOutgoing = 0;
    int cardRows = 0;
    int cardMismatches = 0;

    for (int index = 1; index < lines.size(); index++) {
      int number = index; // transaction row n is file line n + 1
      List<String> fields = ErsteCsv.fields(lines.get(index));
      if (fields == null) {
        failures.add(new Failure("csv.malformed", number));
        continue;
      }
      String structural = structure(fields);
      if (structural != null) {
        failures.add(new Failure(structural, number));
        continue;
      }
      RowResult result = readRow(number, fields, accountNumber, latest);
      if (result.rule() != null) {
        failures.add(new Failure(result.rule(), number));
        continue;
      }
      switch (result.column()) {
        case POSITIVE -> positiveOutgoing++;
        case MISMATCH -> {
          cardRows++;
          cardMismatches++;
        }
        case CONSISTENT -> cardRows++;
        case UNCHECKED -> {}
      }
      // Sequence numbers: well-formed (checked in readRow) and unique within the file.
      if (!sequences.add(fields.get(7))) {
        failures.add(new Failure("sequence.duplicate", number));
        continue;
      }
      rows.add(result.row());
    }

    if (!failures.isEmpty()) {
      throw rejection(failures);
    }
    if (amountColumnMoved(positiveOutgoing, cardRows, cardMismatches)) {
      throw new ImportRejectedException("layout.amount_column");
    }
    if (rows.isEmpty()) {
      throw new ImportRejectedException("statement.empty");
    }
    return new ParsedStatement(CURRENCY, List.copyOf(rows), ParsedStatement.identityOf(accountNumber));
  }

  /**
   * Whether the amount column no longer holds the amount (for example because the amount and the
   * balance columns changed places), told from two witnesses that never use the balance column:
   *
   * <ul>
   *   <li>Every real card payment and BLIK purchase is an outgoing, negative amount, so even one
   *       of them with a positive figure means the column is not the amount: a single such row is
   *       enough, because a real export has none.
   *   <li>A card payment writes its own amount in its description. When the column disagrees with
   *       that text on <em>half or more</em> of at least two card rows, the column is not the
   *       amount; one disagreeing row in an otherwise consistent file stays what it was, a row the
   *       user decides on ({@code card.amount_mismatch}).
   * </ul>
   *
   * An incoming own-account transfer cannot be told apart this way, so the whole file is refused
   * rather than leave it as the one row accepted with a balance for its amount.
   */
  static boolean amountColumnMoved(int positiveOutgoing, int cardRows, int cardMismatches) {
    return positiveOutgoing > 0 || (cardRows >= 2 && cardMismatches * 2 >= cardRows);
  }

  /**
   * The statement's own account must be the destination's stored number. An account with no number
   * is refused (fail closed, {@code account.number_missing}: add the number first), as is a
   * statement that carries no identity ({@code account.identity_unverifiable}, which this importer
   * never produces) and a different number ({@code account.identity_mismatch}).
   */
  @Override
  public void checkDestination(String statementIdentity, AccountEntity destination) {
    if (statementIdentity == null) {
      throw new ImportRejectedException("account.identity_unverifiable");
    }
    String stored = destination.accountNumber;
    if (stored == null || stored.isBlank()) {
      throw new ImportRejectedException("account.number_missing");
    }
    if (!statementIdentity.equals(ParsedStatement.identityOf(stored))) {
      throw new ImportRejectedException("account.identity_mismatch");
    }
  }

  // --- the summary row -------------------------------------------------------------------------

  /** Validates row 1 and returns the statement's own account number, normalised. */
  private static String readSummary(String line) {
    List<String> fields = ErsteCsv.fields(line);
    if (fields == null) {
      throw new ImportRejectedException("csv.malformed");
    }
    if (fields.size() == 1 && (line.indexOf(';') >= 0 || line.indexOf('\t') >= 0)) {
      throw new ImportRejectedException("layout.delimiter");
    }
    if (fields.size() == FIELDS && looksLikeHeader(fields.get(0))) {
      throw new ImportRejectedException("layout.header_row");
    }
    String structural = structure(fields);
    if (structural != null) {
      throw new ImportRejectedException(structural);
    }
    if (BANK_DATE.matcher(fields.get(0)).matches()) {
      // The first row is a transaction: the summary row is absent.
      throw new ImportRejectedException("layout.summary_missing");
    }
    if (parseIsoDate(fields.get(0)) == null) {
      throw new ImportRejectedException("summary.export_date_invalid");
    }
    if (parseBankDate(fields.get(1)) == null) {
      throw new ImportRejectedException("summary.period_start_invalid");
    }
    String account = fields.get(2);
    if (!account.startsWith("'")) {
      throw new ImportRejectedException("summary.account_invalid");
    }
    String normalised = AccountNumbers.normalizeOrNull(account.substring(1));
    if (normalised == null) {
      throw new ImportRejectedException("summary.account_invalid");
    }
    if (!CURRENCY.equals(fields.get(4))) {
      throw new ImportRejectedException("currency.unsupported");
    }
    // Fields 4 (holder) and 6 to 8 are never read: personal data, or not understood (contract).
    return normalised;
  }

  private static boolean looksLikeHeader(String firstField) {
    // A header names its columns; every first field the contract has seen starts with a digit.
    return !firstField.isEmpty() && firstField.chars().noneMatch(Character::isDigit);
  }

  // --- transaction rows ------------------------------------------------------------------------

  /** Field count and the empty trailing field, for the summary row and every transaction row. */
  private static String structure(List<String> fields) {
    if (fields.size() != FIELDS) {
      return "row.field_count";
    }
    if (!fields.get(8).isEmpty()) {
      return "row.trailing_field";
    }
    return null;
  }

  /** Either a row (accepted or flagged) or the whole-file rule it broke. */
  private record RowResult(ParsedRow row, String rule, Column column) {
    static RowResult of(ParsedRow row) {
      return new RowResult(row, null, Column.UNCHECKED);
    }

    static RowResult of(ParsedRow row, Column column) {
      return new RowResult(row, null, column);
    }

    static RowResult fail(String rule) {
      return new RowResult(null, rule, Column.UNCHECKED);
    }
  }

  /** What a row says about whether the amount column still holds the amount. */
  private enum Column {
    /** Nothing: the row is not a card or BLIK row, or it was refused for another reason. */
    UNCHECKED,
    /** A card payment whose column equals the amount in its text. */
    CONSISTENT,
    /** A card payment whose column differs from the amount in its text. */
    MISMATCH,
    /** A card or BLIK row with a positive amount, which a real export never has. */
    POSITIVE
  }

  /**
   * Reads one well-formed (nine fields) transaction row: a whole-file rule it breaks is the result's
   * rule; a row the importer cannot give a meaning is returned rejected.
   */
  private static RowResult readRow(
      int number, List<String> fields, String statementAccount, LocalDate latest) {
    LocalDate booking = parseBankDate(fields.get(0));
    LocalDate transaction = parseBankDate(fields.get(1));
    if (booking == null || transaction == null) {
      return RowResult.fail("date.invalid");
    }
    if (outOfRange(booking, latest) || outOfRange(transaction, latest)) {
      return RowResult.fail("date.out_of_range");
    }
    if (booking.isBefore(transaction)) {
      return RowResult.fail("date.booking_before_transaction");
    }
    String amountText = fields.get(5);
    Matcher amount = AMOUNT.matcher(amountText);
    if (!amount.matches()) {
      return RowResult.fail("amount.invalid");
    }
    long magnitude = Long.parseLong(amount.group(2)) * 100 + Long.parseLong(amount.group(3));
    if (magnitude == 0) {
      return RowResult.fail("amount.zero");
    }
    long amountMinor = amount.group(1).isEmpty() ? magnitude : -magnitude;
    if (!SEQUENCE.matcher(fields.get(7)).matches()) {
      return RowResult.fail("sequence.invalid");
    }

    String description = fields.get(2);
    String counterparty = fields.get(3);
    String counterpartyAccountText = fields.get(4);
    String sequence = fields.get(7);

    Matcher card = CARD.matcher(description);
    if (card.matches()) {
      if (!CURRENCY.equals(card.group(3))) {
        return RowResult.fail("card.foreign_currency");
      }
      if (!counterparty.isEmpty() || !counterpartyAccountText.isEmpty()) {
        return RowResult.of(ParsedRow.rejected(number, "description.unknown_shape"));
      }
      if (amountMinor > 0) {
        return RowResult.of(ParsedRow.rejected(number, "amount.sign_unexpected"), Column.POSITIVE);
      }
      long embedded = Long.parseLong(card.group(1)) * 100 + Long.parseLong(card.group(2));
      if (embedded != magnitude) {
        return RowResult.of(ParsedRow.rejected(number, "card.amount_mismatch"), Column.MISMATCH);
      }
      return RowResult.of(
          ParsedRow.accepted(number, transaction, booking, amountMinor, description, null, null, sequence),
          Column.CONSISTENT);
    }
    if (BLIK.matcher(description).matches()) {
      if (counterparty.isBlank()) {
        return RowResult.of(ParsedRow.rejected(number, "description.unknown_shape"));
      }
      String other = counterpartyAccount(counterpartyAccountText);
      if (other == null) {
        return RowResult.of(ParsedRow.rejected(number, "counterparty_account.invalid"));
      }
      if (amountMinor > 0) {
        return RowResult.of(ParsedRow.rejected(number, "amount.sign_unexpected"), Column.POSITIVE);
      }
      return RowResult.of(ParsedRow.accepted(
          number, transaction, booking, amountMinor, description, counterparty, other, sequence));
    }
    if (OWN_TRANSFER_DESCRIPTION.equals(description)) {
      String other = counterpartyAccount(counterpartyAccountText);
      if (other == null) {
        return RowResult.of(ParsedRow.rejected(number, "counterparty_account.invalid"));
      }
      if (other.equals(statementAccount)) {
        return RowResult.of(ParsedRow.rejected(number, "transfer.same_account"));
      }
      if (amountMinor < 0) {
        // The wording of an outgoing own-account transfer is unknown (contract).
        return RowResult.of(ParsedRow.rejected(number, "amount.sign_unexpected"));
      }
      // The counterparty field holds the holder's own name and address: personal data with no use
      // here, so it is not carried. The other account is what identifies the transfer.
      return RowResult.of(
          ParsedRow.accepted(
                  number, transaction, booking, amountMinor, description, null, other, sequence)
              .withHint(ParsedRow.HINT_OWN_ACCOUNT_TRANSFER));
    }
    return RowResult.of(ParsedRow.rejected(number, "description.unknown_shape"));
  }

  /** The counterparty account in normal form, or {@code null} unless it has the contract's shape. */
  private static String counterpartyAccount(String text) {
    return COUNTERPARTY_ACCOUNT.matcher(text).matches() ? AccountNumbers.normalizeOrNull(text) : null;
  }

  // --- helpers ---------------------------------------------------------------------------------

  private static boolean outOfRange(LocalDate date, LocalDate latest) {
    return date.isBefore(EARLIEST_DATE) || date.isAfter(latest);
  }

  private record Failure(String rule, int row) {}

  /** The rule of the first failure, with the rows that broke that rule (bounded) and their count. */
  private static ImportRejectedException rejection(List<Failure> failures) {
    String rule = failures.get(0).rule();
    List<Integer> rows =
        failures.stream().filter(f -> f.rule().equals(rule)).map(Failure::row).toList();
    return new ImportRejectedException(
        rule, rows.subList(0, Math.min(rows.size(), MAX_REPORTED_ROWS)), rows.size());
  }

  private static LocalDate parseIsoDate(String text) {
    Matcher m = ISO_DATE.matcher(text);
    return m.matches() ? date(m.group(1), m.group(2), m.group(3)) : null;
  }

  /** A real {@code DD-MM-YYYY} calendar day, or {@code null}. */
  private static LocalDate parseBankDate(String text) {
    Matcher m = BANK_DATE.matcher(text);
    return m.matches() ? date(m.group(3), m.group(2), m.group(1)) : null;
  }

  private static LocalDate date(String year, String month, String day) {
    try {
      return LocalDate.of(Integer.parseInt(year), Integer.parseInt(month), Integer.parseInt(day));
    } catch (DateTimeException notADay) {
      return null;
    }
  }
}
