package prudent.imports;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import prudent.imports.ImportTestSupport.Erste;

/**
 * The catalogue of statements the Erste import must refuse or flag (M6, jlogicsoftware/prudent#77,
 * ADR-094), as data: every malformed, drifted, mixed-currency, oversized and misdirected file with
 * the rule that must name it. {@link ImportFailureMatrixTest} runs each case through the real HTTP
 * API and proves nothing was written; {@link ImportRuleCatalogueTest} holds the set of rules the
 * cases name against the set of rules the importer's sources can emit, so a rule added without a
 * case fails the build.
 *
 * <p>Every file is built in memory from the synthetic base statement of {@link Erste}; none is a
 * copy of a real export.
 */
final class ImportFailureCatalogue {

  private ImportFailureCatalogue() {}

  /** The destination account a case uploads to. */
  enum Destination {
    /** The account whose number the statement carries; it holds PLN and EUR. */
    ERSTE,
    /** No destination at upload (the session is parsed and an account is chosen at preview). */
    NONE,
    /** An active account of the caller with another number. */
    OTHER_NUMBER,
    /** An active account of the caller with no number. */
    UNNUMBERED,
    /** The statement's account, after it stopped holding PLN. */
    WITHOUT_PLN,
    /** An inactive account of the caller. */
    INACTIVE,
    /** An account of another user whose number is the statement's own. */
    SOMEONE_ELSES,
    /** An id that names no account. */
    UNKNOWN_ID,
    /** Text that is not an id at all. */
    NOT_AN_ID
  }

  /**
   * A refusal of a whole upload: the HTTP {@code status}, and either the {@code rule} with the
   * {@code rows} it names (and {@code total}, how many rows broke it) or, for a refusal that has no
   * rule, the exact {@code message}.
   */
  record Refusal(
      String name,
      byte[] content,
      Destination destination,
      int status,
      String rule,
      List<Integer> rows,
      int total,
      String message) {

    /** The message the server must answer with, as the contract words it. */
    String expectedMessage() {
      if (rule == null) {
        return message;
      }
      if (rows.isEmpty()) {
        return "The statement was rejected (" + rule + ").";
      }
      if (rows.size() == 1 && total == 1) {
        return "The statement was rejected at row " + rows.get(0) + " (" + rule + ").";
      }
      String named = String.join(", ", rows.stream().map(String::valueOf).toList());
      int more = total - rows.size();
      return "The statement was rejected at rows " + named + (more > 0 ? " and " + more + " more" : "")
          + " (" + rule + ").";
    }
  }

  /**
   * A statement the importer accepts as a file and flags row by row: {@code codes} has one entry
   * per transaction row, the rule code of a rejected row or {@code null} for an accepted one.
   */
  record Flagged(String name, byte[] content, List<String> codes) {}

  // --- whole-file refusals -----------------------------------------------------------------------

  static List<Refusal> refusals() {
    List<Refusal> out = new ArrayList<>();
    bytesAndEncoding(out);
    layout(out);
    columns(out);
    delimiterAndQuoting(out);
    summary(out);
    currency(out);
    dates(out);
    amounts(out);
    amountColumn(out);
    sequences(out);
    bounds(out);
    truncated(out);
    notAStatement(out);
    destinations(out);
    return out;
  }

  private static void rule(
      List<Refusal> out, String name, byte[] content, String rule, int... rows) {
    ruleFor(out, name, content, Destination.ERSTE, rule, rows);
  }

  private static void ruleFor(
      List<Refusal> out, String name, byte[] content, Destination destination, String rule,
      int... rows) {
    List<Integer> named = new ArrayList<>();
    for (int row : rows) {
      named.add(row);
    }
    out.add(new Refusal(name, content, destination, 400, rule, named, named.size(), null));
  }

  private static void message(List<Refusal> out, String name, byte[] content, Destination destination, String message) {
    out.add(new Refusal(name, content, destination, 400, null, List.of(), 0, message));
  }

  private static byte[] concat(byte[] first, byte[] second) {
    byte[] all = new byte[first.length + second.length];
    System.arraycopy(first, 0, all, 0, first.length);
    System.arraycopy(second, 0, all, first.length, second.length);
    return all;
  }

  private static byte[] encoded(String text, String charset) {
    return text.getBytes(Charset.forName(charset));
  }

  private static byte[] edit(String from, String to) {
    String text = Erste.baseText();
    if (!text.contains(from)) {
      throw new IllegalStateException("the base statement does not contain the text to change");
    }
    return text.replace(from, to).getBytes(StandardCharsets.UTF_8);
  }

  private static void bytesAndEncoding(List<Refusal> out) {
    String text = Erste.baseText();
    rule(out, "an empty file", new byte[0], "statement.empty_upload");
    rule(out, "a file of one newline", new byte[] {'\n'}, "row.field_count");
    rule(out, "a UTF-8 byte-order mark", concat(new byte[] {(byte) 0xEF, (byte) 0xBB, (byte) 0xBF}, Erste.baseBytes()), "encoding.bom");
    rule(out, "UTF-16 little endian with its byte-order mark", concat(new byte[] {(byte) 0xFF, (byte) 0xFE}, encoded(text, "UTF-16LE")), "encoding.bom");
    rule(out, "UTF-16 big endian with its byte-order mark", concat(new byte[] {(byte) 0xFE, (byte) 0xFF}, encoded(text, "UTF-16BE")), "encoding.bom");
    rule(out, "UTF-16 without a byte-order mark", encoded(text, "UTF-16LE"), "encoding.nul_byte");
    rule(out, "UTF-32 without a byte-order mark", encoded(text, "UTF-32BE"), "encoding.nul_byte");
    rule(out, "Windows-1250 (Polish letters as single bytes)", encoded(text, "windows-1250"), "encoding.not_utf8");
    rule(out, "ISO 8859-2 (Latin-2)", encoded(text, "ISO-8859-2"), "encoding.not_utf8");
    byte[] withNul = Erste.baseBytes();
    withNul[withNul.length / 2] = 0;
    rule(out, "a NUL byte in the middle", withNul, "encoding.nul_byte");
    rule(out, "a lone UTF-8 lead byte at the end", concat(Erste.baseBytes(), new byte[] {(byte) 0xC5}), "encoding.not_utf8");
    rule(out, "an overlong UTF-8 encoding", concat(new byte[] {(byte) 0xC0, (byte) 0xAF}, Erste.baseBytes()), "encoding.not_utf8");
    rule(out, "CRLF line endings", text.replace("\n", "\r\n").getBytes(StandardCharsets.UTF_8), "layout.line_ending");
    rule(out, "a lone CR inside a field", edit("SKLEP B", "SKLEP\rB"), "layout.line_ending");
    rule(out, "no final newline", text.substring(0, text.length() - 1).getBytes(StandardCharsets.UTF_8), "layout.no_final_newline");
    rule(out, "a blank line at the end", (text + "\n").getBytes(StandardCharsets.UTF_8), "row.field_count", 6);
    List<String> lines = Erste.baseLines();
    lines.add(3, "");
    rule(out, "a blank line in the middle", Erste.bytes(lines), "row.field_count", 3);
  }

  private static void layout(List<Refusal> out) {
    String header = "Data księgowania,Data transakcji,Opis,Kontrahent,Rachunek kontrahenta,Kwota,Saldo,Numer,";
    List<String> lines = Erste.baseLines();
    lines.add(0, header);
    rule(out, "a header row above the summary row", Erste.bytes(lines), "layout.header_row");
    lines = Erste.baseLines();
    lines.add(1, header);
    rule(out, "a header row between the summary row and the transactions", Erste.bytes(lines), "date.invalid", 1);
    lines = Erste.baseLines();
    lines.add(0, "Date,Description,Amount");
    rule(out, "a three-column English header", Erste.bytes(lines), "row.field_count");
    lines = Erste.baseLines();
    lines.add(0, "Data;Opis;Kwota");
    rule(out, "a semicolon header", Erste.bytes(lines), "layout.delimiter");

    lines = Erste.baseLines();
    lines.remove(0);
    rule(out, "the summary row missing", Erste.bytes(lines), "layout.summary_missing");
    lines = Erste.baseLines();
    lines.add(1, lines.get(0));
    rule(out, "the summary row repeated as the first transaction", Erste.bytes(lines), "date.invalid", 1);
    lines = Erste.baseLines();
    lines.add(3, lines.get(0));
    rule(out, "the summary row repeated in the middle", Erste.bytes(lines), "date.invalid", 3);
    lines = Erste.baseLines();
    lines.add(lines.remove(0));
    rule(out, "the summary row moved to the end", Erste.bytes(lines), "layout.summary_missing");
    rule(out, "a summary row and nothing else", Erste.bytes(Erste.baseLines().subList(0, 1)), "statement.empty");
  }

  private static void columns(List<Refusal> out) {
    rule(out, "every row without its trailing comma (8 fields)", rows(r -> java.util.Arrays.copyOf(r, 8)), "row.field_count");
    rule(out, "every row with one more empty column (10 fields)", rows(r -> java.util.Arrays.copyOf(r, 10)), "row.field_count");
    rule(out, "every row with two more columns (11 fields)", rows(r -> java.util.Arrays.copyOf(r, 11)), "row.field_count");
    rule(out, "transaction rows with 8 fields, summary intact", txRows(r -> java.util.Arrays.copyOf(r, 8)), "row.field_count", 1, 2, 3, 4, 5);
    rule(out, "transaction rows with 10 fields, summary intact", txRows(r -> java.util.Arrays.copyOf(r, 10)), "row.field_count", 1, 2, 3, 4, 5);
    rule(out, "a new first column on transaction rows", txRows(r -> {
      String[] wider = new String[10];
      wider[0] = "NEW";
      System.arraycopy(r, 0, wider, 1, 9);
      return wider;
    }), "row.field_count", 1, 2, 3, 4, 5);
    rule(out, "the counterparty column removed from transaction rows", txRows(r -> {
      String[] narrower = new String[8];
      System.arraycopy(r, 0, narrower, 0, 3);
      System.arraycopy(r, 4, narrower, 3, 5);
      return narrower;
    }), "row.field_count", 1, 2, 3, 4, 5);
    rule(out, "a value in the trailing field of every transaction row", txRows(r -> {
      String[] copy = r.clone();
      copy[8] = "x";
      return copy;
    }), "row.trailing_field", 1, 2, 3, 4, 5);
    rule(out, "a value in the summary row's trailing field", Erste.withSummaryField(8, "x"), "row.trailing_field");
    rule(out, "the whole file shifted one column left", rows(r -> shiftLeft(r)), "layout.summary_missing");
    rule(out, "transaction rows shifted one column left", txRows(r -> shiftLeft(r)), "date.invalid", 1, 2, 3, 4, 5);
    rule(out, "booking and transaction dates swapped", txRows(r -> {
      String[] copy = r.clone();
      copy[0] = r[1];
      copy[1] = r[0];
      return copy;
    }), "date.booking_before_transaction", 1, 4);
    rule(out, "the summary row's account and export date swapped", rows0(r -> {
      String[] copy = r.clone();
      copy[0] = r[2];
      copy[2] = r[0];
      return copy;
    }), "summary.export_date_invalid");
  }

  private static byte[] rows(java.util.function.UnaryOperator<String[]> change) {
    return Erste.mapRows(change);
  }

  /** As {@link #rows} but only the summary row (row 0) is changed. */
  private static byte[] rows0(java.util.function.UnaryOperator<String[]> change) {
    List<String[]> rows = Erste.base();
    rows.set(0, change.apply(rows.get(0)));
    return Erste.bytes(Erste.lines(rows));
  }

  /** Only the transaction rows are changed. */
  private static byte[] txRows(java.util.function.UnaryOperator<String[]> change) {
    List<String[]> rows = Erste.base();
    for (int i = 1; i < rows.size(); i++) {
      rows.set(i, change.apply(rows.get(i)));
    }
    return Erste.bytes(Erste.lines(rows));
  }

  private static String[] shiftLeft(String[] row) {
    String[] shifted = new String[row.length];
    System.arraycopy(row, 1, shifted, 0, row.length - 1);
    shifted[row.length - 1] = "";
    return shifted;
  }

  private static void delimiterAndQuoting(List<Refusal> out) {
    String text = Erste.baseText();
    // The amounts stay quoted, so a quote now sits inside an unquoted field.
    rule(out, "semicolons instead of commas, amounts still quoted", delimited(";", false, true), "csv.malformed");
    rule(out, "semicolons and dot decimals, no quotes", delimited(";", true, false), "layout.delimiter");
    rule(out, "tabs and dot decimals", delimited("\t", true, false), "layout.delimiter");
    rule(out, "tabs with comma decimals (the commas split the summary row)", delimited("\t", false, false), "row.field_count");
    rule(out, "pipes and dot decimals", delimited("|", true, false), "row.field_count");
    rule(out, "amounts unquoted, so the comma splits them", text.replace("\"", "").getBytes(StandardCharsets.UTF_8), "row.field_count");
    rule(out, "amounts unquoted on transaction rows only", unquotedTransactionAmounts(), "row.field_count", 1, 2, 3, 4, 5);
    rule(out, "single quotes around amounts", text.replace('"', '\'').getBytes(StandardCharsets.UTF_8), "row.field_count");
    rule(out, "an unterminated quote on a transaction row", edit("\"-25,00\"", "\"-25,00"), "csv.malformed", 2);
    rule(out, "a stray quote inside an unquoted field", edit("SKLEP C TESTOWY", "SKLEP \"C TESTOWY"), "csv.malformed", 4);
    rule(out, "text after a closing quote", edit("\"-3,00\",", "\"-3,00\"x,"), "csv.malformed", 4);
    rule(out, "an unterminated quote on the summary row", edit("\"0,00\"", "\"0,00"), "csv.malformed");
  }

  /** The base statement joined with {@code separator}, as another locale or tool might write it. */
  private static byte[] delimited(String separator, boolean dotDecimals, boolean quoteAmounts) {
    List<String> lines = new ArrayList<>();
    for (String[] row : Erste.base()) {
      String[] copy = row.clone();
      for (int i : new int[] {5, 6}) {
        if (dotDecimals) {
          copy[i] = copy[i].replace(',', '.');
        }
        if (quoteAmounts) {
          copy[i] = "\"" + copy[i] + "\"";
        }
      }
      lines.add(String.join(separator, copy));
    }
    return Erste.bytes(lines);
  }

  private static byte[] unquotedTransactionAmounts() {
    List<String> lines = Erste.baseLines();
    for (int i = 1; i < lines.size(); i++) {
      lines.set(i, lines.get(i).replace("\"", ""));
    }
    return Erste.bytes(lines);
  }

  private static void summary(List<Refusal> out) {
    // A bank date in the first field is what a transaction row starts with: no summary row.
    rule(out, "the export date written as DD-MM-YYYY", Erste.withSummaryField(0, "14-11-2026"), "layout.summary_missing");
    rule(out, "an impossible export date", Erste.withSummaryField(0, "2026-02-30"), "summary.export_date_invalid");
    rule(out, "an empty export date", Erste.withSummaryField(0, ""), "summary.export_date_invalid");
    rule(out, "the period start written as ISO", Erste.withSummaryField(1, "2026-01-01"), "summary.period_start_invalid");
    rule(out, "an impossible period start", Erste.withSummaryField(1, "31-04-2026"), "summary.period_start_invalid");
    rule(out, "an empty period start", Erste.withSummaryField(1, ""), "summary.period_start_invalid");
    rule(out, "an account number without its apostrophe", Erste.withSummaryField(2, "00 0000 0000 0000 0000 0000 0001"), "summary.account_invalid");
    rule(out, "an apostrophe and nothing else", Erste.withSummaryField(2, "'"), "summary.account_invalid");
    rule(out, "an account number that is too short", Erste.withSummaryField(2, "'12 3456"), "summary.account_invalid");
    rule(out, "an account number with punctuation", Erste.withSummaryField(2, "'00-0000-0000-0000-0000-0000-0001"), "summary.account_invalid");
    // "ß" must not fold to "SS" on the way to the shape check (the account-number nit of ADR-094).
    rule(out, "an account number with a letter that upper-cases to two", Erste.withSummaryField(2, "'00 0000 0000 0000 0000 0ß01"), "summary.account_invalid");
    rule(out, "an account number with a dotless i", Erste.withSummaryField(2, "'00 0000 0000 0000 0000 0ı01"), "summary.account_invalid");
    rule(out, "an empty account number", Erste.withSummaryField(2, ""), "summary.account_invalid");
    rule(out, "another bank's file of the same shape (ISO dates)", anotherBank(), "summary.period_start_invalid");
  }

  private static byte[] anotherBank() {
    List<String> lines = new ArrayList<>();
    lines.add("2026-03-10,2026-03-10,Card payment TEST,,,-7.10,100.00,1,");
    lines.add("2026-03-09,2026-03-09,Transfer TEST,,,-25.00,75.00,2,");
    return Erste.bytes(lines);
  }

  private static void currency(List<Refusal> out) {
    for (String currency : new String[] {"EUR", "USD", "pln", "", "PLN ", "ZŁ", "XXX", "PL", "PLNN"}) {
      rule(out, "a summary currency of '" + currency + "'", Erste.withSummaryField(4, currency), "currency.unsupported");
    }
    rule(out, "a summary currency of EUR over rows that are all PLN card payments", Erste.withSummaryField(4, "EUR"), "currency.unsupported");
    List<String[]> rows = Erste.base();
    rows.set(4, euroCard());
    rule(out, "one card payment in euros among zloty rows", Erste.bytes(Erste.lines(rows)), "card.foreign_currency", 4);
    rows = Erste.base();
    rows.set(2, usdCard());
    rows.set(4, euroCard());
    rule(out, "card payments in two foreign currencies", Erste.bytes(Erste.lines(rows)), "card.foreign_currency", 2, 4);
    rows = Erste.base();
    rows.set(1, euroCard());
    ruleFor(out, "a card payment in euros into an account that holds PLN and EUR", Erste.bytes(Erste.lines(rows)), Destination.ERSTE, "card.foreign_currency", 1);
    rule(out, "an amount with a currency suffix", Erste.withField(1, 5, "-7,10 PLN"), "amount.invalid", 1);
    rule(out, "an amount with a currency prefix", Erste.withField(1, 5, "PLN -7,10"), "amount.invalid", 1);
    rule(out, "an amount in another currency", Erste.withField(1, 5, "-7,10 EUR"), "amount.invalid", 1);
    message(out, "a PLN statement into an account that no longer holds PLN", Erste.baseBytes(), Destination.WITHOUT_PLN,
        "The destination account does not hold PLN. Add the currency to it first.");
  }

  private static String[] euroCard() {
    return Erste.tx("07-03-2026", "07-03-2026", "DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ 10.00 EUR SKLEP E TESTOWY", "", "", "-43,10", 4);
  }

  private static String[] usdCard() {
    return Erste.tx("08-03-2026", "08-03-2026", "DOP. VISA 000000******0000 PŁATNOŚĆ KARTĄ 10.00 USD SKLEP F TESTOWY", "", "", "-39,00", 2);
  }

  private static void dates(List<Refusal> out) {
    for (String bad : new String[] {
      "2026-03-10", "03-30-2026", "10-03-26", "10/03/2026", "10.03.2026", "30-02-2026", "31-04-2026",
      "29-02-2026", "00-03-2026", "10-00-2026", "10-13-2026", "", "yesterday", "10-3-2026", " 10-03-2026"
    }) {
      rule(out, "a transaction date of '" + bad + "'", withDates(2, bad), "date.invalid", 2);
    }
    for (String far : new String[] {"31-12-1999", "01-01-1900", "10-03-0000", "10-03-2099", "10-03-9999"}) {
      rule(out, "a date of " + far + " is out of range", withDates(2, far), "date.out_of_range", 2);
    }
    rule(out, "a booking date long after the transaction", Erste.withField(4, 0, "10-03-2099"), "date.out_of_range", 4);
    rule(out, "a booking date before the transaction date", Erste.withField(5, 0, "05-03-2026"), "date.booking_before_transaction", 5);
    // Thirteen rows break one rule: ten are named, three are counted.
    List<String[]> rows = new ArrayList<>();
    rows.add(Erste.summary());
    for (int i = 1; i <= 13; i++) {
      rows.add(Erste.card("30-02-2026", "30-02-2026", "SKLEP TESTOWY " + i, "-1,00", i));
    }
    out.add(new Refusal("thirteen rows with an impossible date", Erste.bytes(Erste.lines(rows)), Destination.ERSTE, 400, "date.invalid", List.of(1, 2, 3, 4, 5, 6, 7, 8, 9, 10), 13, null));
    // The first failing rule wins, whatever comes after it.
    rows = Erste.base();
    rows.get(2)[1] = "31-02-2026";
    rows.get(2)[0] = "31-02-2026";
    rows.get(4)[5] = "0,00";
    rule(out, "two different faults: the first rule in file order is the one named", Erste.bytes(Erste.lines(rows)), "date.invalid", 2);
  }

  /** Both dates of a row set to {@code value}, so that the booking order cannot be the cause. */
  private static byte[] withDates(int row, String value) {
    List<String[]> rows = Erste.base();
    rows.get(row)[0] = value;
    rows.get(row)[1] = value;
    return Erste.bytes(Erste.lines(rows));
  }

  private static void amounts(List<Refusal> out) {
    for (String bad : new String[] {
      "-1.000,00", "-1 000,00", "-1 000,00", "-12.50", "-12,500", "-12,5", "-12", "-12,50 PLN",
      "PLN -12,50", "+12,50", "", "-", "-,50", ",50", "--12,50", "1e3,00", "-١٢,٥٠",
      "-１２,５０", "-12,50-", "(12,50)", "-0012,50", "-123456789012,00", "-12,50​",
      "- 12,50", "12,50,00", "0,5", "-00,50"
    }) {
      rule(out, "an amount of '" + bad + "'", Erste.withField(1, 5, bad), "amount.invalid", 1);
    }
    rule(out, "an amount of zero", Erste.withField(3, 5, "0,00"), "amount.zero", 3);
    rule(out, "an amount of minus zero", Erste.withField(3, 5, "-0,00"), "amount.zero", 3);
  }

  /**
   * The amount column that no longer holds the amount: a positive card or BLIK row is a whole-file
   * refusal, and so is a column that disagrees with the card text on half or more of at least two
   * card rows. A lone disagreeing card row is flagged instead (see {@link #flagged}).
   */
  private static void amountColumn(List<Refusal> out) {
    String rule = "layout.amount_column";
    rule(out, "a card payment with a positive amount", Erste.withField(1, 5, "7,10"), rule);
    rule(out, "a BLIK purchase with a positive amount", Erste.withField(2, 5, "25,00"), rule);
    rule(out, "amount and balance columns swapped on every row", swapAmountAndBalance(), rule);
    rule(out, "amount and balance columns swapped on the card and BLIK rows only", swapOnRows(1, 2), rule);
    // The card text is the second witness: the column is not the amount when it disagrees with
    // the text on half or more of at least two card rows (the base statement has three).
    rule(out, "every card row disagreeing with its text", edits(new String[][] {{"1", "5", "-7,11"}, {"4", "5", "-3,01"}, {"5", "5", "-1,01"}}), rule);
    rule(out, "two of three card rows disagreeing with their text", edits(new String[][] {{"1", "5", "-7,11"}, {"4", "5", "-3,01"}}), rule);
    rule(out, "one of two card rows disagreeing with its text", edits(new String[][] {{"1", "5", "-7,11"}, {"5", "2", "CARD PAYMENT TEST"}}), rule);
  }

  private static byte[] edits(String[][] changes) {
    List<String[]> rows = Erste.base();
    for (String[] change : changes) {
      rows.get(Integer.parseInt(change[0]))[Integer.parseInt(change[1])] = change[2];
    }
    return Erste.bytes(Erste.lines(rows));
  }

  private static byte[] swapOnRows(int... indexes) {
    List<String[]> rows = Erste.base();
    for (int i : indexes) {
      String amount = rows.get(i)[5];
      rows.get(i)[5] = rows.get(i)[6];
      rows.get(i)[6] = amount;
    }
    return Erste.bytes(Erste.lines(rows));
  }

  private static void sequences(List<Refusal> out) {
    for (String bad : new String[] {"abc", "-5", "", "1.5", "007", "12345678901234567890", " 7", "٣", "0x1"}) {
      rule(out, "a sequence number of '" + bad + "'", Erste.withField(2, 7, bad), "sequence.invalid", 2);
    }
    rule(out, "a sequence number that repeats the one before", Erste.withField(3, 7, "2"), "sequence.duplicate", 3);
    rule(out, "a sequence number that repeats the first", Erste.withField(5, 7, "1"), "sequence.duplicate", 5);
  }

  private static void bounds(List<Refusal> out) {
    rule(out, "more rows than an import holds", Erste.manyCards(5_001), "statement.too_many_rows");
    byte[] big = new byte[5 * 1024 * 1024 + 1];
    java.util.Arrays.fill(big, (byte) 'a');
    rule(out, "a file over 5 MiB", big, "statement.too_large");
    String longText = "X".repeat(1_100);
    rule(out, "a description over the field limit", Erste.withField(2, 2, "Zakup BLIK " + longText + " ref:00000000001"), "field.too_long", 2);
    rule(out, "a counterparty over the field limit", Erste.withField(2, 3, longText), "field.too_long", 2);
  }

  private static void truncated(List<Refusal> out) {
    String text = Erste.baseText();
    int midRow = text.indexOf("SKLEP C") + 3;
    rule(out, "cut inside a row, no newline", text.substring(0, midRow).getBytes(StandardCharsets.UTF_8), "layout.no_final_newline");
    rule(out, "cut inside a row, newline added", (text.substring(0, midRow) + "\n").getBytes(StandardCharsets.UTF_8), "row.field_count", 4);
    int amount = text.indexOf("\"-3,00\"") + 3;
    rule(out, "cut inside a quoted amount, newline added", (text.substring(0, amount) + "\n").getBytes(StandardCharsets.UTF_8), "csv.malformed", 4);
    rule(out, "cut inside the summary row, newline added", (text.substring(0, 40) + "\n").getBytes(StandardCharsets.UTF_8), "row.field_count");
    // The first byte of a two-byte Polish letter is all that is left.
    byte[] all = Erste.baseBytes();
    int letter = new String(all, StandardCharsets.UTF_8).indexOf("PŁATNO") + 1;
    int bytePosition = new String(all, StandardCharsets.UTF_8).substring(0, letter).getBytes(StandardCharsets.UTF_8).length;
    byte[] cut = java.util.Arrays.copyOf(all, bytePosition + 1);
    rule(out, "cut inside a multi-byte letter", cut, "encoding.not_utf8");
  }

  private static void notAStatement(List<Refusal> out) {
    rule(out, "a PDF (binary header)", concat("%PDF-1.7\n%".getBytes(StandardCharsets.ISO_8859_1), new byte[] {(byte) 0xE2, (byte) 0xE3, (byte) 0xCF, (byte) 0xD3, '\n'}), "encoding.not_utf8");
    rule(out, "a PDF (text only)", "%PDF-1.4\n1 0 obj\n<< >>\nendobj\n".getBytes(StandardCharsets.UTF_8), "row.field_count");
    rule(out, "a PNG", concat(new byte[] {(byte) 0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n', 0, 0, 0, 13}, new byte[] {'I', 'H', 'D', 'R'}), "encoding.nul_byte");
    rule(out, "an XLSX (a zip)", new byte[] {'P', 'K', 3, 4, 20, 0, 0, 0, 8, 0}, "encoding.nul_byte");
    rule(out, "a gzip stream", new byte[] {0x1F, (byte) 0x8B, 8, 0, 0, 0, 0, 0}, "encoding.nul_byte");
    byte[] noise = new byte[2048];
    new Random(77).nextBytes(noise);
    rule(out, "random bytes", noise, "encoding.nul_byte");
    rule(out, "JSON with quotes", "{\"transactions\": []}\n".getBytes(StandardCharsets.UTF_8), "csv.malformed");
    rule(out, "pretty-printed JSON", "{\n  \"a\": 1\n}\n".getBytes(StandardCharsets.UTF_8), "row.field_count");
    rule(out, "a JSON array", "[1,2,3]\n".getBytes(StandardCharsets.UTF_8), "row.field_count");
    rule(out, "XML", "<?xml version=\"1.0\"?>\n<a/>\n".getBytes(StandardCharsets.UTF_8), "csv.malformed");
    rule(out, "HTML", "<html><body>Error</body></html>\n".getBytes(StandardCharsets.UTF_8), "row.field_count");
    rule(out, "prose", "Hello, this is not a statement.\n".getBytes(StandardCharsets.UTF_8), "row.field_count");
    rule(out, "nine words in a row", "Lorem,ipsum,dolor,sit,amet,consectetur,adipiscing,elit,\n".getBytes(StandardCharsets.UTF_8), "layout.header_row");
  }

  private static void destinations(List<Refusal> out) {
    byte[] base = Erste.baseBytes();
    ruleFor(out, "an account with another number", base, Destination.OTHER_NUMBER, "account.identity_mismatch");
    ruleFor(out, "an account without a number", base, Destination.UNNUMBERED, "account.number_missing");
    message(out, "an inactive account", base, Destination.INACTIVE, "The destination account is inactive.");
    ruleFor(out, "another user's account that carries the statement's number", base, Destination.SOMEONE_ELSES, "account.not_found");
    ruleFor(out, "an id that names no account", base, Destination.UNKNOWN_ID, "account.not_found");
  }

  // --- rows the importer flags ---------------------------------------------------------------------

  static List<Flagged> flagged() {
    List<Flagged> out = new ArrayList<>();
    String unknown = "description.unknown_shape";
    for (String description : new String[] {
      "Przelew zewnętrzny TEST", "Polecenie zapłaty TEST", "Opłata za prowadzenie rachunku TEST",
      "Wypłata z bankomatu TEST", "Zwrot płatności kartą TEST", "Odsetki TEST", "Zlecenie stałe TEST",
      "Przelew na rachunek własny ", "przelew na rachunek własny", "Zakup BLIK  ref:00000000001",
      "Zakup BLIK SKLEP TESTOWY ref:0000000001", "Zakup BLIK SKLEP TESTOWY ref:000000000011",
      "Zakup BLIK SKLEP TESTOWY", "DOP. AMEX 000000******0000 PŁATNOŚĆ KARTĄ 1.00 PLN SKLEP TESTOWY",
      "CARD PAYMENT TEST", "", " "
    }) {
      out.add(new Flagged("a BLIK row now described as '" + description + "'", Erste.withField(2, 2, description), codes(null, unknown, null, null, null)));
    }
    out.add(new Flagged("a card payment whose mask has five stars", Erste.withField(1, 2, "DOP. MC 000000*****0000 PŁATNOŚĆ KARTĄ 7.10 PLN SKLEP TESTOWY"), codes(unknown, null, null, null, null)));
    out.add(new Flagged("a card payment whose currency is lower case", Erste.withField(1, 2, "DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ 7.10 pln SKLEP TESTOWY"), codes(unknown, null, null, null, null)));
    out.add(new Flagged("a card payment that names a counterparty", Erste.withField(1, 3, "SOMEONE TESTOWY"), codes(unknown, null, null, null, null)));
    out.add(new Flagged("a card payment whose amount differs from its text", Erste.withField(1, 5, "-7,11"), codes("card.amount_mismatch", null, null, null, null)));
    out.add(new Flagged("one of three card rows disagreeing with its text (a lone anomaly, not a moved column)", Erste.withField(4, 5, "-3,01"), codes(null, null, null, "card.amount_mismatch", null)));
    out.add(new Flagged("a lone card row, whatever its column says", edits(new String[][] {{"4", "2", "CARD PAYMENT TEST"}, {"5", "2", "CARD PAYMENT TEST"}, {"1", "5", "-7,11"}}), codes("card.amount_mismatch", null, null, "description.unknown_shape", "description.unknown_shape")));
    out.add(new Flagged("an outgoing own-account transfer", Erste.withField(3, 5, "-100,00"), codes(null, null, "amount.sign_unexpected", null, null)));
    for (String account : new String[] {"", "123", "00 0000 0000 0000 0000 0000 000X", "PL00 0000 0000 0000 0000 0000 0010", "00000000000000000000000010", "00  0000 0000 0000 0000 0000 0010"}) {
      out.add(new Flagged("a BLIK counterparty account of '" + account + "'", Erste.withField(2, 4, account), codes(null, "counterparty_account.invalid", null, null, null)));
      out.add(new Flagged("an own-account transfer from '" + account + "'", Erste.withField(3, 4, account), codes(null, null, "counterparty_account.invalid", null, null)));
    }
    out.add(new Flagged("an own-account transfer from the statement's own account", Erste.withField(3, 4, "00 0000 0000 0000 0000 0000 0001"), codes(null, null, "transfer.same_account", null, null)));
    out.add(new Flagged("description and counterparty columns swapped", txRowsSwapped(), codes(unknown, unknown, unknown, unknown, unknown)));
    out.add(new Flagged("only unsupported operations", onlyUnsupported(), codes(unknown, unknown, unknown, unknown, unknown)));
    out.add(new Flagged("UTF-8 read as Windows-1250 and written back (mojibake)", mojibake(), codes(unknown, null, unknown, unknown, unknown)));
    out.add(new Flagged("every field quoted (a benign variation: the same statement)", allQuoted(), codes(null, null, null, null, null)));
    return out;
  }

  private static List<String> codes(String... codes) {
    return java.util.Arrays.asList(codes);
  }

  private static byte[] swapAmountAndBalance() {
    List<String[]> rows = Erste.base();
    for (int i = 1; i < rows.size(); i++) {
      String amount = rows.get(i)[5];
      rows.get(i)[5] = rows.get(i)[6];
      rows.get(i)[6] = amount;
    }
    return Erste.bytes(Erste.lines(rows));
  }

  private static byte[] txRowsSwapped() {
    return txRows(r -> {
      String[] copy = r.clone();
      copy[2] = r[3];
      copy[3] = r[2];
      return copy;
    });
  }

  private static byte[] onlyUnsupported() {
    return txRows(r -> {
      String[] copy = r.clone();
      copy[2] = "Operacja nieznana TEST";
      return copy;
    });
  }

  private static byte[] mojibake() {
    String text = Erste.baseText();
    String garbled = new String(text.getBytes(StandardCharsets.UTF_8), Charset.forName("windows-1250"));
    return garbled.getBytes(StandardCharsets.UTF_8);
  }

  private static byte[] allQuoted() {
    List<String> lines = new ArrayList<>();
    for (String[] row : Erste.base()) {
      List<String> quoted = new ArrayList<>();
      for (String field : row) {
        quoted.add("\"" + field.replace("\"", "\"\"") + "\"");
      }
      lines.add(String.join(",", quoted));
    }
    return Erste.bytes(lines);
  }

  // --- the rules ---------------------------------------------------------------------------------

  /** Every rule the whole-file cases and the flagged-row cases name. */
  static Set<String> coveredRules() {
    Set<String> rules = new TreeSet<>();
    for (Refusal refusal : refusals()) {
      if (refusal.rule() != null) {
        rules.add(refusal.rule());
      }
    }
    for (Flagged flagged : flagged()) {
      flagged.codes().stream().filter(java.util.Objects::nonNull).forEach(rules::add);
    }
    return rules;
  }

  /**
   * Rules the importer's sources can emit that the matrix cannot reach through an Erste file, each
   * with the test that does: a rule that belongs to another stage (a duplicate, a hint, a commit
   * refusal) or to a generic hook the Erste importer never calls. The catalogue test fails when a
   * named method does not exist, so a rename cannot leave a rule silently unproven.
   */
  static Map<String, String> coveredElsewhere() {
    Map<String, String> where = new TreeMap<>();
    where.put("account.identity_unverifiable", "ErsteStatementImporterTest#checkDestination_refusesAStatementThatCarriesNoIdentity");
    where.put("identifier.missing", "ImportDuplicateDetectionTest#aStableIdentifierFormatRefusesAFileWhoseIdentifiersAreMissingOrRepeated");
    where.put("identifier.duplicate", "ImportDuplicateDetectionTest#aStableIdentifierFormatRefusesAFileWhoseIdentifiersAreMissingOrRepeated");
    where.put("duplicate.already_imported", "ImportDuplicateDetectionTest#theWireCarriesTheReasonAndNeverTheKey");
    where.put("transfer.own_account", "ImportCommitTest#anIncomingOwnTransfer_carriesTheHintAndNoOtherRowDoes");
    where.put("commit.category_unavailable", "ImportCommitFailureTest#aCategoryRemovedAfterItWasChosenIsNamedByRuleAndRowsAndNothingIsWritten");
    where.put("commit.row_refused", "ImportCommitFailureTest#aRowTheLedgerRefusesIsNamedByRuleAndRowAndNeverQuoted");
    where.put("commit.account_unavailable", "ImportCommitFailureTest#anAccountThatStoppedBeingUsableIsNamedByRuleAndNothingIsWritten");
    return where;
  }
}
