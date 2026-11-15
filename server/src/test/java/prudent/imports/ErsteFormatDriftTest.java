package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;
import java.util.function.UnaryOperator;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import prudent.imports.ImportTestSupport.Erste;

/**
 * Pins the three-way relationship between the contract, the importer and the synthetic fixtures
 * (M6, jlogicsoftware/prudent#77, ADR-094), so that a bank that changes its export fails closed.
 *
 * <ul>
 *   <li>Each committed fixture parses to exactly the rows written out below, field by field (the
 *       expected values are synthetic data typed here, not read back from the importer).
 *   <li>Programmatic mutations of each fixture, the changes a bank is likely to make — a column
 *       added, dropped, moved or shifted, a header, another delimiter or decimal separator, another
 *       encoding or line ending — are all refused with a specific rule, and none is accepted.
 *   <li>The rule codes the contract document names are exactly the ones the importer can emit.
 * </ul>
 */
class ErsteFormatDriftTest {

  private final ErsteStatementImporter importer = new ErsteStatementImporter();
  private final ImportContext context = new ImportContext(UUID.randomUUID(), null);

  private static byte[] fixture(String name) throws IOException {
    try (InputStream in = ErsteFormatDriftTest.class.getResourceAsStream("/import/erste/" + name)) {
      return in.readAllBytes();
    }
  }

  private static final List<String> FIXTURES =
      List.of("statement-minimal.csv", "statement-diacritics.csv", "statement-representative.csv");

  // --- golden rows ------------------------------------------------------------------------------

  /** A row as one comparable line: number, dates, minor units, bank number, account, hint, texts. */
  private static String render(ParsedRow row) {
    return String.join(
        " | ",
        String.valueOf(row.rowNumber()),
        String.valueOf(row.transactionDate()),
        String.valueOf(row.bookingDate()),
        String.valueOf(row.amountMinor()),
        String.valueOf(row.externalId()),
        String.valueOf(row.counterpartyAccount()),
        String.valueOf(row.hintCode()),
        String.valueOf(row.description()),
        String.valueOf(row.counterparty()));
  }

  private static final String CARD = "DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ ";

  private static final List<String> MINIMAL =
      List.of(
          "1 | 2026-02-03 | 2026-02-03 | -100 | 2 | null | null | " + CARD + "1.00 PLN SKLEP TESTOWY MINIMALNY | null");

  private static final List<String> DIACRITICS =
      List.of(
          "1 | 2026-03-03 | 2026-03-03 | -200 | 2 | null | null | " + CARD + "2.00 PLN TEST ŁĄKA ŻÓŁĆ | null",
          "2 | 2026-03-02 | 2026-03-02 | -123 | 3 | null | null | " + CARD
              + "1.23 PLN TEST ĄĆĘŁŃÓŚŹŻ ąćęłńóśźż | null");

  private static final String OWN = "Przelew na rachunek własny";

  private static final List<String> REPRESENTATIVE =
      List.of(
          "1 | 2026-01-16 | 2026-01-16 | -710 | 3 | null | null | " + CARD
              + "7.10 PLN KOMUNIKACJA TESTOWA ŚWIĘTOKRZYSKA WARSZAWA | null",
          "2 | 2026-01-13 | 2026-01-15 | 2000 | 5 | 00000000000000000000000002 | transfer.own_account | " + OWN
              + " | null",
          "3 | 2026-01-11 | 2026-01-11 | -9999 | 6 | 00000000000000000000000011 | null"
              + " | Zakup BLIK Test Payments Sp. z o.o. PRÓBNA 7 ref:00000000002 | Test Payments Sp. z o.o. PRÓBNA 7",
          "4 | 2026-01-09 | 2026-01-12 | -24990 | 9 | null | null | " + CARD
              + "249.90 PLN SKLEP TESTOWY GŁÓWNY KRAKÓW | null",
          "5 | 2026-01-08 | 2026-01-08 | -99 | 12 | null | null | DOP. VISA 000000******0000 PŁATNOŚĆ KARTĄ"
              + " 0.99 PLN KIOSK TESTOWY NR 7 | null",
          "6 | 2026-01-05 | 2026-01-08 | 50000 | 14 | 00000000000000000000000002 | transfer.own_account | " + OWN
              + " | null",
          "7 | 2026-01-04 | 2026-01-04 | -3000 | 15 | 00000000000000000000000010 | null"
              + " | Zakup BLIK SKLEP TESTOWY ONLINE Testowa 1 ref:00000000001 | SKLEP TESTOWY ONLINE Testowa 1",
          "8 | 2026-01-02 | 2026-01-05 | -1250 | 18 | null | null | " + CARD
              + "12.50 PLN SKLEP TESTOWY SPOŻYWCZY ŁÓDŹ | null");

  private static List<String> golden(String fixture) {
    return switch (fixture) {
      case "statement-minimal.csv" -> MINIMAL;
      case "statement-diacritics.csv" -> DIACRITICS;
      default -> REPRESENTATIVE;
    };
  }

  @Test
  void everyFixtureParsesToExactlyTheRowsTheContractDescribes() throws Exception {
    for (String name : FIXTURES) {
      ParsedStatement parsed = importer.parse(fixture(name), context);
      assertEquals("PLN", parsed.currency(), name);
      assertEquals(golden(name), parsed.rows().stream().map(ErsteFormatDriftTest::render).toList(), name);
      assertTrue(parsed.rows().stream().noneMatch(ParsedRow::isRejected), name);
    }
  }

  @Test
  void theFixtureTableOfTheContractNamesTheFixturesThatExist() throws IOException {
    String contract = Files.readString(Path.of("../docs/erste-csv-contract.md"), StandardCharsets.UTF_8);
    for (String name : FIXTURES) {
      assertTrue(contract.contains("`" + name + "`"), name + " is not in the contract's fixture table");
    }
    try (var files = Files.list(Path.of("src/test/resources/import/erste"))) {
      Set<String> onDisk = new TreeSet<>();
      files.map(p -> p.getFileName().toString()).filter(n -> n.endsWith(".csv")).forEach(onDisk::add);
      assertEquals(new TreeSet<>(FIXTURES), onDisk, "a fixture without golden rows is not pinned");
    }
  }

  // --- mutations: the changes a bank might make -------------------------------------------------

  private static List<String[]> rows(byte[] content) {
    List<String[]> rows = new ArrayList<>();
    for (String line : new String(content, StandardCharsets.UTF_8).split("\n")) {
      rows.add(ErsteCsv.fields(line).toArray(String[]::new));
    }
    return rows;
  }

  private static byte[] bytes(List<String[]> rows) {
    return Erste.bytes(Erste.lines(rows));
  }

  /** The fixture with {@code change} applied to every line, the summary row included. */
  private static byte[] mapAll(byte[] content, UnaryOperator<String[]> change) {
    List<String[]> rows = rows(content);
    rows.replaceAll(change);
    return bytes(rows);
  }

  /** As {@link #mapAll}, for transaction rows only. */
  private static byte[] mapTransactions(byte[] content, UnaryOperator<String[]> change) {
    List<String[]> rows = rows(content);
    for (int i = 1; i < rows.size(); i++) {
      rows.set(i, change.apply(rows.get(i)));
    }
    return bytes(rows);
  }

  private static String[] without(String[] row, int index) {
    List<String> kept = new ArrayList<>(List.of(row));
    kept.remove(index);
    return kept.toArray(String[]::new);
  }

  private static String[] with(String[] row, int index, String value) {
    List<String> grown = new ArrayList<>(List.of(row));
    grown.add(index, value);
    return grown.toArray(String[]::new);
  }

  private String ruleOf(byte[] content) {
    return assertThrows(ImportRejectedException.class, () -> importer.parse(content, context)).rule();
  }

  private void assertRefused(String rule, String fixture, String change, byte[] content) {
    ImportRejectedException refused =
        assertThrows(
            ImportRejectedException.class,
            () -> importer.parse(content, context),
            fixture + ": " + change + " was accepted");
    assertEquals(rule, refused.rule(), fixture + ": " + change);
    assertTrue(refused.getMessage().matches("[A-Za-z0-9 ,.()_]*"), refused.getMessage());
  }

  @Test
  void theFixturesRoundTripThroughTheMutationHelpers() throws Exception {
    // A mutation that changed nothing would prove nothing: the helpers must reproduce the bytes.
    for (String name : FIXTURES) {
      byte[] original = fixture(name);
      assertEquals(
          new String(original, StandardCharsets.UTF_8),
          new String(mapAll(original, r -> r), StandardCharsets.UTF_8),
          name);
    }
  }

  @Test
  void aColumnDroppedFromEveryRow_atAnyPosition_isRefused() throws Exception {
    for (String name : FIXTURES) {
      for (int column = 0; column < 9; column++) {
        int dropped = column;
        assertRefused("row.field_count", name, "column " + column + " dropped",
            mapAll(fixture(name), r -> without(r, dropped)));
      }
    }
  }

  @Test
  void aColumnAddedToEveryRow_atAnyPosition_isRefused() throws Exception {
    for (String name : FIXTURES) {
      for (int column = 0; column <= 9; column++) {
        int added = column;
        assertRefused("row.field_count", name, "column added at " + column,
            mapAll(fixture(name), r -> with(r, added, "x")));
      }
    }
  }

  @Test
  void aColumnAddedOrDroppedOnTransactionRowsAlone_isRefusedAtRowOne() throws Exception {
    for (String name : FIXTURES) {
      ImportRejectedException added =
          assertThrows(
              ImportRejectedException.class,
              () -> importer.parse(mapTransactions(fixture(name), r -> with(r, 4, "x")), context));
      assertEquals("row.field_count", added.rule());
      assertEquals(1, added.rowNumber());
      ImportRejectedException dropped =
          assertThrows(
              ImportRejectedException.class,
              () -> importer.parse(mapTransactions(fixture(name), r -> without(r, 4)), context));
      assertEquals("row.field_count", dropped.rule());
    }
  }

  @Test
  void columnsShiftedOrMoved_areRefusedWithTheRuleOfWhatLandedWhere() throws Exception {
    for (String name : FIXTURES) {
      byte[] original = fixture(name);
      // Everything one column to the left: the summary row now starts with a bank date.
      assertRefused("layout.summary_missing", name, "all shifted left",
          mapAll(original, ErsteFormatDriftTest::shiftLeft));
      // Only the transactions: the description sits where a date is read.
      assertRefused("date.invalid", name, "transactions shifted left",
          mapTransactions(original, ErsteFormatDriftTest::shiftLeft));
      // Everything one column to the right (a new first column, the last dropped): the bank sequence
      // number lands in the field that must be empty.
      assertRefused("layout.header_row", name, "all shifted right",
          mapAll(original, r -> shiftRight(r, "Data")));
      assertRefused("row.trailing_field", name, "transactions shifted right",
          mapTransactions(original, r -> shiftRight(r, "x")));
      // Summary fields in another order.
      byte[] reordered = bytes(summaryReordered(rows(original)));
      assertRefused("summary.export_date_invalid", name, "summary account first", reordered);
    }
  }

  private static String[] shiftLeft(String[] row) {
    String[] shifted = new String[row.length];
    System.arraycopy(row, 1, shifted, 0, row.length - 1);
    shifted[row.length - 1] = "";
    return shifted;
  }

  private static String[] shiftRight(String[] row, String first) {
    String[] shifted = new String[row.length];
    shifted[0] = first;
    System.arraycopy(row, 0, shifted, 1, row.length - 1);
    return shifted;
  }

  private static List<String[]> summaryReordered(List<String[]> rows) {
    String[] summary = rows.get(0).clone();
    String date = summary[0];
    summary[0] = summary[2];
    summary[2] = date;
    rows.set(0, summary);
    return rows;
  }

  @Test
  void swappedDateColumns_areRefusedWhereTheyCanBeTold_andAFixtureWithEqualDatesIsUnchanged() throws Exception {
    for (String name : FIXTURES) {
      byte[] swapped =
          mapTransactions(fixture(name), r -> {
            String[] copy = r.clone();
            copy[0] = r[1];
            copy[1] = r[0];
            return copy;
          });
      boolean anyBookedLater = rows(fixture(name)).stream().skip(1).anyMatch(r -> !r[0].equals(r[1]));
      if (anyBookedLater) {
        assertRefused("date.booking_before_transaction", name, "dates swapped", swapped);
      } else {
        // Booking and transaction dates are equal in this fixture, so swapping them changes nothing.
        assertEquals(golden(name), importer.parse(swapped, context).rows().stream().map(ErsteFormatDriftTest::render).toList());
      }
    }
  }

  @Test
  void swappedAmountAndBalance_isRefusedAsAWholeWhereverACardOrBlikRowWitnessesIt() throws Exception {
    // ADR-094: the balance column is never read, so a swap is told from the card and BLIK rows (a
    // positive figure, or a figure that disagrees with the card text). An own-account transfer
    // alone cannot witness it, so a fixture with no card or BLIK row is the one thing not refused.
    for (String name : FIXTURES) {
      byte[] swapped =
          mapTransactions(fixture(name), r -> {
            String[] copy = r.clone();
            copy[5] = r[6];
            copy[6] = r[5];
            return copy;
          });
      boolean witnessed =
          golden(name).stream().anyMatch(row -> {
            String description = row.split(" \\| ")[7];
            return !ErsteStatementImporter.isOwnAccountTransfer(description);
          });
      if (witnessed) {
        assertRefused("layout.amount_column", name, "amount and balance swapped", swapped);
      } else {
        for (ParsedRow row : importer.parse(swapped, context).rows()) {
          assertFalse(row.isRejected(), name + " row " + row.rowNumber());
        }
      }
    }
  }

  @Test
  void theAmountColumnRuleIsExactlyThePinnedOne() {
    // positive card/BLIK row anywhere, or half or more of at least two card rows disagreeing.
    assertTrue(ErsteStatementImporter.amountColumnMoved(1, 0, 0));
    assertTrue(ErsteStatementImporter.amountColumnMoved(0, 2, 1));
    assertTrue(ErsteStatementImporter.amountColumnMoved(0, 3, 2));
    assertTrue(ErsteStatementImporter.amountColumnMoved(0, 4, 2));
    assertFalse(ErsteStatementImporter.amountColumnMoved(0, 3, 1));
    assertFalse(ErsteStatementImporter.amountColumnMoved(0, 1, 1));
    assertFalse(ErsteStatementImporter.amountColumnMoved(0, 0, 0));
    assertFalse(ErsteStatementImporter.amountColumnMoved(0, 10, 4));
  }

  @Test
  void descriptionAndCounterpartySwapped_acceptsNoRow() throws Exception {
    for (String name : FIXTURES) {
      byte[] swapped =
          mapTransactions(fixture(name), r -> {
            String[] copy = r.clone();
            copy[2] = r[3];
            copy[3] = r[2];
            return copy;
          });
      ParsedStatement parsed = importer.parse(swapped, context);
      assertTrue(parsed.rows().stream().allMatch(ParsedRow::isRejected), name);
      assertTrue(
          parsed.rows().stream().allMatch(r -> "description.unknown_shape".equals(r.rejectionCode())), name);
    }
  }

  @Test
  void aFirstTransactionFieldEmptiedOrBroken_isRefusedWithItsOwnRule() throws Exception {
    String[][] expectations = {
      {"0", "", "date.invalid"},
      {"1", "", "date.invalid"},
      {"5", "", "amount.invalid"},
      {"5", "-1.00", "amount.invalid"},
      {"5", "1 000,00", "amount.invalid"},
      {"7", "", "sequence.invalid"},
      {"7", "x", "sequence.invalid"},
      {"8", "x", "row.trailing_field"},
    };
    for (String name : FIXTURES) {
      for (String[] expectation : expectations) {
        int field = Integer.parseInt(expectation[0]);
        List<String[]> rows = rows(fixture(name));
        rows.get(1)[field] = expectation[1];
        assertRefused(expectation[2], name, "field " + field + " set to '" + expectation[1] + "'", bytes(rows));
      }
    }
  }

  @Test
  void aDifferentDecimalSeparatorOrADifferentCurrency_isRefused() throws Exception {
    for (String name : FIXTURES) {
      assertRefused("amount.invalid", name, "dot decimals",
          mapTransactions(fixture(name), r -> {
            String[] copy = r.clone();
            copy[5] = r[5].replace(',', '.');
            return copy;
          }));
      for (String currency : new String[] {"EUR", "USD", "pln"}) {
        List<String[]> rows = rows(fixture(name));
        rows.get(0)[4] = currency;
        assertRefused("currency.unsupported", name, "currency " + currency, bytes(rows));
      }
    }
  }

  @Test
  void aHeaderAddedOrASummaryChanged_isRefused() throws Exception {
    String header = "Data księgowania,Data transakcji,Opis,Kontrahent,Rachunek,Kwota,Saldo,Numer,";
    for (String name : FIXTURES) {
      String text = new String(fixture(name), StandardCharsets.UTF_8);
      assertRefused("layout.header_row", name, "header added", (header + "\n" + text).getBytes(StandardCharsets.UTF_8));
      String withoutSummary = text.substring(text.indexOf('\n') + 1);
      assertRefused("layout.summary_missing", name, "summary removed", withoutSummary.getBytes(StandardCharsets.UTF_8));
      String summary = text.substring(0, text.indexOf('\n') + 1);
      assertRefused("date.invalid", name, "summary repeated", (summary + text).getBytes(StandardCharsets.UTF_8));
      assertRefused("statement.empty", name, "transactions removed", summary.getBytes(StandardCharsets.UTF_8));
    }
  }

  @Test
  void anotherDelimiterEncodingOrLineEnding_isRefused() throws Exception {
    for (String name : FIXTURES) {
      byte[] original = fixture(name);
      String text = new String(original, StandardCharsets.UTF_8);
      assertRefused("csv.malformed", name, "semicolons", text.replace(",\"", ";\"").replace("\",", "\";").replace(",", ";").getBytes(StandardCharsets.UTF_8));
      assertRefused("layout.line_ending", name, "CRLF", text.replace("\n", "\r\n").getBytes(StandardCharsets.UTF_8));
      assertRefused("layout.no_final_newline", name, "no final newline", text.substring(0, text.length() - 1).getBytes(StandardCharsets.UTF_8));
      byte[] bom = new byte[original.length + 3];
      System.arraycopy(new byte[] {(byte) 0xEF, (byte) 0xBB, (byte) 0xBF}, 0, bom, 0, 3);
      System.arraycopy(original, 0, bom, 3, original.length);
      assertRefused("encoding.bom", name, "BOM", bom);
      assertRefused("encoding.not_utf8", name, "Windows-1250", text.getBytes(Charset.forName("windows-1250")));
      assertRefused("encoding.not_utf8", name, "ISO 8859-2", text.getBytes(Charset.forName("ISO-8859-2")));
      assertRefused("encoding.nul_byte", name, "UTF-16", text.getBytes(StandardCharsets.UTF_16LE));
      // A cut: the last line is incomplete.
      assertRefused("layout.no_final_newline", name, "cut short", text.substring(0, text.length() - 12).getBytes(StandardCharsets.UTF_8));
    }
  }

  @Test
  void aNewTransactionWording_isFlaggedAndNeverImported() throws Exception {
    for (String name : FIXTURES) {
      byte[] reworded =
          mapTransactions(fixture(name), r -> {
            String[] copy = r.clone();
            copy[2] = "Nowy opis operacji TEST";
            return copy;
          });
      ParsedStatement parsed = importer.parse(reworded, context);
      assertEquals(golden(name).size(), parsed.rows().size());
      assertTrue(parsed.rows().stream().allMatch(ParsedRow::isRejected), name);
    }
  }

  @Test
  void everyMutationChangedTheFile() throws Exception {
    // A guard on the guards: each helper above must change the bytes, or its assertion is vacuous.
    for (String name : FIXTURES) {
      byte[] original = fixture(name);
      assertFalse(java.util.Arrays.equals(original, mapAll(original, r -> without(r, 2))));
      assertFalse(java.util.Arrays.equals(original, mapAll(original, r -> with(r, 2, "x"))));
      assertFalse(java.util.Arrays.equals(original, mapAll(original, ErsteFormatDriftTest::shiftLeft)));
      assertFalse(ruleOf(mapAll(original, r -> without(r, 2))).isEmpty());
    }
  }

  // --- the contract's own list of rules -------------------------------------------------------------

  private static final Pattern DOCUMENTED = Pattern.compile("`([a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*)`");

  /** The rule codes written in the contract's validation list, in backticks. */
  private static Set<String> documentedRules() throws IOException {
    String contract = Files.readString(Path.of("../docs/erste-csv-contract.md"), StandardCharsets.UTF_8);
    String section = contract.substring(contract.indexOf("## Validation expectations"), contract.indexOf("## Unsupported and unknown variants"));
    Set<String> rules = new TreeSet<>();
    Matcher matcher = DOCUMENTED.matcher(section);
    while (matcher.find()) {
      rules.add(matcher.group(1));
    }
    return rules;
  }

  @Test
  void theRulesTheContractNamesAreExactlyTheOnesTheErsteImporterCanEmit() throws IOException {
    Set<String> documented = documentedRules();
    Set<String> inImporter = new TreeSet<>();
    for (String file : new String[] {"ErsteStatementImporter.java", "ErsteCsv.java"}) {
      String source =
          Files.readString(Path.of("src/main/java/prudent/imports", file), StandardCharsets.UTF_8)
              .replaceAll("(?s)/\\*.*?\\*/", "")
              .replaceAll("//[^\\n]*", "");
      Matcher literal = Pattern.compile("\"([a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*)\"").matcher(source);
      while (literal.find()) {
        inImporter.add(literal.group(1));
      }
    }
    Set<String> undocumented = new TreeSet<>(inImporter);
    undocumented.removeAll(documented);
    Set<String> unimplemented = new TreeSet<>(documented);
    unimplemented.removeAll(inImporter);
    assertEquals(Set.of(), undocumented, "the importer emits rules the contract does not list");
    assertEquals(Set.of(), unimplemented, "the contract lists rules the importer never emits");
    assertTrue(documented.size() > 30, documented.toString());
  }
}
