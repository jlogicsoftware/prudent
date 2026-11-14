package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import prudent.account.AccountEntity;

/**
 * The Erste importer against {@code docs/erste-csv-contract.md}: the three synthetic fixtures parse,
 * and every validation rule fires once on a file built in memory for the purpose. The broad
 * malformed, drift and mixed-currency suite is jlogicsoftware/prudent#77; this one makes each rule
 * trustworthy. Every account, name and merchant here is invented.
 */
class ErsteStatementImporterTest {

  private static final String ACCOUNT_1 = "00000000000000000000000001";
  private static final String SUMMARY =
      "2026-01-31,01-01-2026,'00 0000 0000 0000 0000 0000 0001,JAN TESTOWY UL. PRZYKŁADOWA 1/2"
          + " 00-000 TESTOWO,PLN,\"1,00\",\"226,62\",480,";
  private static final String OTHER_ACCOUNT = "00 0000 0000 0000 0000 0000 0002";

  private final ErsteStatementImporter importer = new ErsteStatementImporter();
  private final ImportContext context = new ImportContext(UUID.randomUUID(), null);

  // --- helpers ----------------------------------------------------------------------------------

  private static byte[] fixture(String name) throws IOException {
    try (InputStream in =
        ErsteStatementImporterTest.class.getResourceAsStream("/import/erste/" + name)) {
      return in.readAllBytes();
    }
  }

  private static byte[] file(String... lines) {
    return (String.join("\n", lines) + "\n").getBytes(StandardCharsets.UTF_8);
  }

  private static String card(
      String booking, String transaction, String embedded, String currency, String amount, String seq) {
    return booking + "," + transaction + ",DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ " + embedded + " "
        + currency + " SKLEP TESTOWY,,,\"" + amount + "\",\"10,00\"," + seq + ",";
  }

  private static String card(String transaction, String amount, String embedded, String seq) {
    return card(transaction, transaction, embedded, "PLN", amount, seq);
  }

  private static String simple(String seq) {
    return card("05-01-2026", "-1,00", "1.00", seq);
  }

  private static String blik(String account, String amount, String seq) {
    return "04-01-2026,04-01-2026,Zakup BLIK SKLEP TESTOWY ref:00000000001,SKLEP TESTOWY,"
        + account + ",\"" + amount + "\",\"10,00\"," + seq + ",";
  }

  private static String own(String account, String amount, String seq) {
    return "04-01-2026,04-01-2026,Przelew na rachunek własny,FIRMA TESTOWA JAN TESTOWY,"
        + account + ",\"" + amount + "\",\"10,00\"," + seq + ",";
  }

  private ImportRejectedException rejected(byte[] content) {
    return assertThrows(ImportRejectedException.class, () -> importer.parse(content, context));
  }

  private void assertRejects(String rule, byte[] content) {
    ImportRejectedException e = rejected(content);
    assertEquals(rule, e.rule(), e.getMessage());
    assertNoStatementText(e.getMessage());
  }

  private void assertRejectsAt(String rule, int row, byte[] content) {
    ImportRejectedException e = rejected(content);
    assertEquals(rule, e.rule(), e.getMessage());
    assertEquals(row, e.rowNumber(), e.getMessage());
    assertNoStatementText(e.getMessage());
  }

  private static void assertNoStatementText(String message) {
    for (String forbidden :
        new String[] {"TESTOWY", "TESTOWA", "SKLEP", "BLIK", "DOP.", "PŁATNOŚĆ", "PRZYKŁADOWA", "0000", "PLN", "ref:", "'"}) {
      assertFalse(message.contains(forbidden), forbidden + " leaked: " + message);
    }
    assertTrue(message.matches("[A-Za-z0-9 ,.()_]*"), "only a rule code and row numbers: " + message);
  }

  private ParsedRow onlyRow(String line) {
    ParsedStatement parsed = importer.parse(file(SUMMARY, line), context);
    assertEquals(1, parsed.rows().size());
    return parsed.rows().get(0);
  }

  // --- the fixtures -----------------------------------------------------------------------------

  @Test
  void representativeFixture_parsesEveryRowWithTheContractsMeaning() throws Exception {
    ParsedStatement parsed = importer.parse(fixture("statement-representative.csv"), context);
    ParsedStatements.validate(importer.formatId(), parsed);

    assertEquals("PLN", parsed.currency());
    assertEquals(ParsedStatement.identityOf(ACCOUNT_1), parsed.accountIdentity());
    assertEquals(8, parsed.rows().size());
    assertTrue(parsed.rows().stream().noneMatch(ParsedRow::isRejected));
    assertEquals(List.of(1, 2, 3, 4, 5, 6, 7, 8), parsed.rows().stream().map(ParsedRow::rowNumber).toList());

    ParsedRow card = parsed.rows().get(0);
    assertEquals(LocalDate.of(2026, 1, 16), card.transactionDate());
    assertEquals(LocalDate.of(2026, 1, 16), card.bookingDate());
    assertEquals(-710L, card.amountMinor());
    assertEquals("3", card.externalId());
    assertNull(card.counterparty());
    assertNull(card.counterpartyAccount());
    assertTrue(card.description().startsWith("DOP. MC 000000******0000"));

    // The booking date is later than the transaction date, and both are kept.
    ParsedRow transfer = parsed.rows().get(1);
    assertEquals(LocalDate.of(2026, 1, 13), transfer.transactionDate());
    assertEquals(LocalDate.of(2026, 1, 15), transfer.bookingDate());
    assertEquals(2000L, transfer.amountMinor());

    ParsedRow blik = parsed.rows().get(2);
    assertEquals(-9999L, blik.amountMinor());
    assertEquals("Test Payments Sp. z o.o. PRÓBNA 7", blik.counterparty());
    assertEquals("00000000000000000000000011", blik.counterpartyAccount());

    assertEquals(-24990L, parsed.rows().get(3).amountMinor());
    assertEquals(-99L, parsed.rows().get(4).amountMinor());
    assertEquals(-3000L, parsed.rows().get(6).amountMinor());
  }

  @Test
  void ownAccountTransfers_areRecognisedByDescriptionAndCarryOnlyTheOtherAccount() throws Exception {
    ParsedStatement parsed = importer.parse(fixture("statement-representative.csv"), context);
    List<ParsedRow> transfers =
        parsed.rows().stream()
            .filter(r -> ErsteStatementImporter.isOwnAccountTransfer(r.description()))
            .toList();
    assertEquals(2, transfers.size());
    for (ParsedRow transfer : transfers) {
      assertEquals("00000000000000000000000002", transfer.counterpartyAccount());
      assertNull(transfer.counterparty(), "the holder's own name and address is not carried");
      assertTrue(transfer.amountMinor() > 0);
    }
    assertEquals(2, transfers.stream().map(ParsedRow::rowNumber).distinct().count());
  }

  @Test
  void minimalAndDiacriticsFixtures_parse() throws Exception {
    ParsedStatement minimal = importer.parse(fixture("statement-minimal.csv"), context);
    ParsedStatements.validate(importer.formatId(), minimal);
    assertEquals(1, minimal.rows().size());
    assertEquals(-100L, minimal.rows().get(0).amountMinor());
    assertEquals(ParsedStatement.identityOf("00000000000000000000000003"), minimal.accountIdentity());

    ParsedStatement diacritics = importer.parse(fixture("statement-diacritics.csv"), context);
    ParsedStatements.validate(importer.formatId(), diacritics);
    assertEquals(2, diacritics.rows().size());
    assertTrue(diacritics.rows().get(1).description().contains("ĄĆĘŁŃÓŚŹŻ ąćęłńóśźż"));
    assertEquals(-123L, diacritics.rows().get(1).amountMinor());
  }

  @Test
  void theBalanceColumnAndTheSummaryPeriodAreNotValidated() throws Exception {
    // The fixtures' balances do not chain and their oldest row precedes nothing the summary says;
    // a parser that asserted either would have failed above. Pinned by changing both wildly.
    byte[] content =
        file(
            "2026-01-31,01-12-2030,'00 0000 0000 0000 0000 0000 0001,JAN TESTOWY,PLN,\"9,99\",\"-5,00\",1,",
            "05-01-2026,05-01-2026,DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ 1.00 PLN SKLEP TESTOWY,,,\"-1,00\",\"123456,00\",2,");
    assertEquals(1, importer.parse(content, context).rows().size());
  }

  @Test
  void theRegistryFindsTheImporterUnderItsFormatId() {
    ImportFormats formats = new ImportFormats(List.of(importer));
    assertTrue(formats.find(ImportFormatIds.ERSTE_PL_CSV).isPresent());
  }

  // --- destination identity ---------------------------------------------------------------------

  private static AccountEntity account(String number) {
    AccountEntity account = new AccountEntity();
    account.id = UUID.randomUUID();
    account.name = "Checking";
    account.accountNumber = number;
    return account;
  }

  @Test
  void checkDestination_acceptsOnlyTheAccountWhoseNumberTheStatementCarries() throws Exception {
    String identity = importer.parse(fixture("statement-representative.csv"), context).accountIdentity();

    importer.checkDestination(identity, account(ACCOUNT_1));

    assertEquals(
        "account.identity_mismatch",
        assertThrows(
                ImportRejectedException.class,
                () -> importer.checkDestination(identity, account("00000000000000000000000009")))
            .rule());
  }

  @Test
  void checkDestination_failsClosedWhenTheAccountHasNoNumber() throws Exception {
    String identity = importer.parse(fixture("statement-minimal.csv"), context).accountIdentity();
    for (String none : new String[] {null, "", "  "}) {
      ImportRejectedException e =
          assertThrows(ImportRejectedException.class, () -> importer.checkDestination(identity, account(none)));
      assertEquals("account.number_missing", e.rule());
      assertNoStatementText(e.getMessage());
    }
  }

  @Test
  void checkDestination_refusesAStatementThatCarriesNoIdentity() {
    assertEquals(
        "account.identity_unverifiable",
        assertThrows(ImportRejectedException.class, () -> importer.checkDestination(null, account(ACCOUNT_1)))
            .rule());
  }

  @Test
  void identityOf_hasOneNormalisation_nbspAndPlPrefixIncluded() {
    String expected = ParsedStatement.identityOf(ACCOUNT_1);
    assertEquals(expected, ParsedStatement.identityOf("PL00 0000 0000 0000 0000 0000 0001"));
    assertEquals(expected, ParsedStatement.identityOf("pl00000000000000000000000001"));
    assertEquals(expected, ParsedStatement.identityOf("00\u00a00000\u202f0000 0000 0000 0000 0001"));
    assertThrows(IllegalArgumentException.class, () -> ParsedStatement.identityOf("  "));
    assertThrows(IllegalArgumentException.class, () -> ParsedStatement.identityOf(null));
  }

  @Test
  void aSummaryAccountWithNoBreakSpaces_isTheSameAccount() {
    String summary = SUMMARY.replace("'00 0000 0000", "'00\u00a00000\u202f0000");
    assertEquals(
        ParsedStatement.identityOf(ACCOUNT_1),
        importer.parse(file(summary, simple("2")), context).accountIdentity());
  }

  // --- encoding and layout ----------------------------------------------------------------------

  @Test
  void aByteOrderMark_isRejectedNotStripped() throws Exception {
    byte[] plain = fixture("statement-minimal.csv");
    byte[] bom = new byte[plain.length + 3];
    bom[0] = (byte) 0xEF;
    bom[1] = (byte) 0xBB;
    bom[2] = (byte) 0xBF;
    System.arraycopy(plain, 0, bom, 3, plain.length);
    assertRejects("encoding.bom", bom);
    assertRejects("encoding.bom", new byte[] {(byte) 0xFF, (byte) 0xFE, 'a', 0});
  }

  @Test
  void aNulByte_isRejected() {
    assertRejects("encoding.nul_byte", new byte[] {'a', 0, 'b', '\n'});
  }

  @Test
  void bytesThatAreNotUtf8_areRejected() {
    byte[] latin = "2026-01-31,01-01-2026,'x\n".getBytes(StandardCharsets.ISO_8859_1);
    latin[3] = (byte) 0xC3; // a lone lead byte
    latin[4] = (byte) 0x28;
    assertRejects("encoding.not_utf8", latin);
    // Windows-1250 "ł" (0xB3) on its own is invalid UTF-8 too.
    assertRejects("encoding.not_utf8", new byte[] {(byte) 0xB3, '\n'});
  }

  @Test
  void crlfLineEndings_areRejected() {
    byte[] crlf = (SUMMARY + "\r\n" + simple("2") + "\r\n").getBytes(StandardCharsets.UTF_8);
    assertRejects("layout.line_ending", crlf);
  }

  @Test
  void aFileWithoutItsFinalNewline_isRejected() {
    assertRejects("layout.no_final_newline", (SUMMARY + "\n" + simple("2")).getBytes(StandardCharsets.UTF_8));
  }

  @Test
  void anotherDelimiter_isRejected() {
    assertRejects(
        "layout.delimiter",
        file("2026-01-31;01-01-2026;'00 0000 0000 0000 0000 0000 0001;JAN TESTOWY;PLN;1.00;2.00;480;"));
    assertRejects("layout.delimiter", file("a\tb\tc"));
  }

  @Test
  void aHeaderRow_isRejected() {
    assertRejects(
        "layout.header_row",
        file(
            "Data księgowania,Data transakcji,Opis,Kontrahent,Rachunek,Kwota,Saldo,Numer,",
            simple("2")));
  }

  @Test
  void aFileWithoutTheSummaryRow_isRejected() {
    assertRejects("layout.summary_missing", file(simple("2"), simple("3")));
  }

  @Test
  void malformedQuoting_isRejected() {
    assertRejects("csv.malformed", file("2026-01-31,\"unterminated,x"));
    assertRejectsAt("csv.malformed", 1, file(SUMMARY, "05-01-2026,05-01-\"2026\",x,,,,,,"));
    assertRejectsAt("csv.malformed", 1, file(SUMMARY, "\"05-01-2026\"x,05-01-2026,x,,,,,,"));
  }

  @Test
  void anEmptyStatement_isRejected() {
    assertRejects("statement.empty", file(SUMMARY));
  }

  // --- the summary row --------------------------------------------------------------------------

  @Test
  void theSummaryRowMustHaveNineFieldsWithAnEmptyLast() {
    assertRejects("row.field_count", file(SUMMARY.substring(0, SUMMARY.length() - 1), simple("2")));
    assertRejects("row.trailing_field", file(SUMMARY + "x", simple("2")));
  }

  @Test
  void theSummaryRowsDatesAccountAndCurrencyAreChecked() {
    assertRejects("summary.export_date_invalid", file(SUMMARY.replace("2026-01-31", "2026-02-31"), simple("2")));
    assertRejects("summary.export_date_invalid", file(SUMMARY.replace("2026-01-31", "31-01-20x6"), simple("2")));
    assertRejects("summary.period_start_invalid", file(SUMMARY.replace("01-01-2026", "2026-01-01"), simple("2")));
    assertRejects("summary.account_invalid", file(SUMMARY.replace("'00 0000", "00 0000"), simple("2")));
    assertRejects("summary.account_invalid", file(SUMMARY.replace("'00 0000 0000 0000 0000 0000 0001", "'12"), simple("2")));
    assertRejects("currency.unsupported", file(SUMMARY.replace("PLN", "EUR"), simple("2")));
    assertRejects("currency.unsupported", file(SUMMARY.replace("PLN", "pln"), simple("2")));
  }

  // --- transaction rows: whole-file rules ---------------------------------------------------------

  @Test
  void aRowWithTheWrongNumberOfFieldsOrANonEmptyLast_isRejectedWithItsRowNumber() {
    assertRejectsAt("row.field_count", 2, file(SUMMARY, simple("2"), "05-01-2026,05-01-2026,x"));
    String extra = simple("3") + "x";
    assertRejectsAt("row.trailing_field", 1, file(SUMMARY, extra));
  }

  @Test
  void datesMustBeRealCalendarDaysInDdMmYyyy() {
    assertRejectsAt("date.invalid", 1, file(SUMMARY, card("31-02-2026", "31-02-2026", "1.00", "PLN", "-1,00", "2")));
    assertRejectsAt("date.invalid", 1, file(SUMMARY, card("2026-01-05", "2026-01-05", "1.00", "PLN", "-1,00", "2")));
    assertRejectsAt("date.invalid", 1, file(SUMMARY, card("5-1-2026", "5-1-2026", "1.00", "PLN", "-1,00", "2")));
  }

  @Test
  void aBookingDateBeforeTheTransactionDate_isRejected() {
    assertRejectsAt(
        "date.booking_before_transaction",
        1,
        file(SUMMARY, card("04-01-2026", "05-01-2026", "1.00", "PLN", "-1,00", "2")));
  }

  @Test
  void amountsMustBeCommaDecimalsWithExactlyTwoDecimals() {
    for (String bad : new String[] {"-1.00", "-1,0", "-1,000", "-1", "+1,00", "- 1,00", "1 000,00", "1.000,00", "1\u00a0000,00", "1,000,00", "01,00", "-007,50", "00,50", "123456789012,00", "abc", ""}) {
      assertRejectsAt("amount.invalid", 1, file(SUMMARY, card("05-01-2026", bad, "1.00", "2")));
    }
  }

  @Test
  void zeroAmounts_areRejected() {
    assertRejectsAt("amount.zero", 1, file(SUMMARY, card("05-01-2026", "0,00", "0.00", "2")));
    assertRejectsAt("amount.zero", 1, file(SUMMARY, card("05-01-2026", "-0,00", "0.00", "2")));
  }

  @Test
  void largeAmountsWithoutSeparators_areAccepted_andNeverOverflow() {
    assertEquals(-100000L, onlyRow(card("05-01-2026", "-1000,00", "1000.00", "2")).amountMinor());
    assertEquals(-123456789000L, onlyRow(card("05-01-2026", "-1234567890,00", "1234567890.00", "2")).amountMinor());
    assertEquals(
        -9999999999999L,
        onlyRow(card("05-01-2026", "-99999999999,99", "99999999999.99", "2")).amountMinor());
    assertEquals(50L, onlyRow(own(OTHER_ACCOUNT, "0,50", "2")).amountMinor());
  }

  @Test
  void theBalanceColumnAndSummaryFieldsSixToEightAreNeverShapeChecked() {
    for (String balance : new String[] {"\"1 234,56\"", "\"1.234,56\"", "abc", ""}) {
      assertEquals(1, importer.parse(file(SUMMARY, simple("2").replace("\"10,00\"", balance)), context).rows().size(), balance);
    }
    byte[] odd = file(SUMMARY.replace("\"1,00\",\"226,62\",480", "x,y,z"), simple("2"));
    assertEquals(1, importer.parse(odd, context).rows().size());
    assertEquals(1, importer.parse(file(SUMMARY.replace("JAN TESTOWY UL. PRZYKŁADOWA 1/2 00-000 TESTOWO", ""), simple("2")), context).rows().size());
  }

  @Test
  void datesOutsideTheSanityRange_rejectTheWholeFile() {
    importer.clock = java.time.Clock.fixed(java.time.Instant.parse("2026-11-14T10:00:00Z"), java.time.ZoneOffset.UTC);
    assertRejectsAt("date.out_of_range", 1, file(SUMMARY, card("31-12-1999", "31-12-1999", "1.00", "PLN", "-1,00", "2")));
    assertRejectsAt("date.out_of_range", 1, file(SUMMARY, card("15-11-2027", "05-01-2026", "1.00", "PLN", "-1,00", "2")));
    assertRejectsAt("date.out_of_range", 1, file(SUMMARY, card("15-11-2027", "15-11-2027", "1.00", "PLN", "-1,00", "2")));
    assertEquals(1, importer.parse(file(SUMMARY, card("01-01-2000", "01-01-2000", "1.00", "PLN", "-1,00", "2")), context).rows().size());
    assertEquals(1, importer.parse(file(SUMMARY, card("14-11-2027", "14-11-2027", "1.00", "PLN", "-1,00", "2")), context).rows().size());
  }

  @Test
  void rowsInAnyDateOrder_areAccepted() {
    assertEquals(
        2,
        importer
            .parse(file(SUMMARY, card("04-01-2026", "-1,00", "1.00", "2"), card("05-01-2026", "-1,00", "1.00", "3")), context)
            .rows()
            .size());
  }

  @Test
  void sequenceNumbersMustBeDigitsWithoutLeadingZerosAndUnique() {
    assertRejectsAt("sequence.invalid", 1, file(SUMMARY, simple("x")));
    assertRejectsAt("sequence.invalid", 1, file(SUMMARY, simple("007")));
    assertRejectsAt("sequence.invalid", 1, file(SUMMARY, simple("")));
    assertRejectsAt("sequence.duplicate", 2, file(SUMMARY, simple("2"), simple("2")));
  }

  @Test
  void aForeignCurrencyCardPayment_rejectsTheWholeFile() {
    assertRejectsAt(
        "card.foreign_currency",
        2,
        file(SUMMARY, simple("2"), card("05-01-2026", "05-01-2026", "10.00", "EUR", "-43,10", "3")));
  }

  // --- transaction rows: per-row flags ----------------------------------------------------------

  @Test
  void aDescriptionOutsideTheThreeShapes_isFlaggedNotDropped() {
    ParsedStatement parsed =
        importer.parse(
            file(
                SUMMARY,
                "05-01-2026,05-01-2026,Opłata za kartę TEST,,,\"-5,00\",\"1,00\",2,",
                simple("3")),
            context);
    assertEquals(2, parsed.rows().size());
    assertTrue(parsed.rows().get(0).isRejected());
    assertEquals("description.unknown_shape", parsed.rows().get(0).rejectionCode());
    assertNull(parsed.rows().get(0).description(), "a flagged row carries no text");
    assertEquals(1, parsed.rows().get(0).rowNumber());
    assertFalse(parsed.rows().get(1).isRejected());
  }

  @Test
  void aCardPaymentWhoseEmbeddedAmountDiffersFromTheColumn_isFlagged() {
    ParsedRow row = onlyRow(card("05-01-2026", "-1,00", "1.01", "2"));
    assertEquals("card.amount_mismatch", row.rejectionCode());
  }

  @Test
  void aCardPaymentWithACounterparty_orAMalformedMask_hasNoKnownShape() {
    assertEquals(
        "description.unknown_shape",
        onlyRow(simple("2").replace(",,,\"-1,00\"", ",SOMEONE TESTOWY,,\"-1,00\"")).rejectionCode());
    assertEquals(
        "description.unknown_shape",
        onlyRow(simple("2").replace("000000******0000", "00000******0000")).rejectionCode());
  }

  @Test
  void aSignTheShapeCannotHave_isFlagged() {
    assertEquals("amount.sign_unexpected", onlyRow(card("05-01-2026", "1,00", "1.00", "2")).rejectionCode());
    assertEquals("amount.sign_unexpected", onlyRow(blik(OTHER_ACCOUNT, "1,00", "2")).rejectionCode());
    // An outgoing own-account transfer: its wording is not known.
    assertEquals("amount.sign_unexpected", onlyRow(own(OTHER_ACCOUNT, "-1,00", "2")).rejectionCode());
  }

  @Test
  void aCounterpartyAccountThatIsNotShapedLikeOne_isFlagged() {
    for (String bad : new String[] {"", "123", "00 0000 0000 0000 0000 0000 000X", "PL00 0000 0000 0000 0000 0000 0002", "00000000000000000000000002"}) {
      assertEquals("counterparty_account.invalid", onlyRow(blik(bad, "-1,00", "2")).rejectionCode(), bad);
      assertEquals("counterparty_account.invalid", onlyRow(own(bad, "1,00", "2")).rejectionCode(), bad);
    }
  }

  @Test
  void anOwnTransferToTheStatementsOwnAccount_isFlagged() {
    assertEquals(
        "transfer.same_account",
        onlyRow(own("00 0000 0000 0000 0000 0000 0001", "1,00", "2")).rejectionCode());
  }

  // --- reporting --------------------------------------------------------------------------------

  @Test
  void aRejection_namesTheFirstFailingRule_andABoundedListOfItsRows() {
    List<String> lines = new ArrayList<>();
    lines.add(SUMMARY);
    lines.add(simple("2")); // row 1 fine
    for (int i = 0; i < 12; i++) {
      lines.add(card("31-02-2026", "31-02-2026", "1.00", "PLN", "-1,00", String.valueOf(10 + i)));
    }
    lines.add(card("05-01-2026", "00,00", "0.00", "99")); // a later, different rule
    ImportRejectedException e = rejected(file(lines.toArray(String[]::new)));

    assertEquals("date.invalid", e.rule());
    assertEquals(List.of(2, 3, 4, 5, 6, 7, 8, 9, 10, 11), e.rowNumbers());
    assertEquals(12, e.totalRows());
    assertEquals(2, e.rowNumber());
    assertEquals(
        "The statement was rejected at rows 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 and 2 more (date.invalid).",
        e.getMessage());
  }

  @Test
  void aLaterRowsFailureIsFoundBeforeAnyRowIsReturned() {
    // Row 1 is fine, row 2 is not: nothing comes back, not even row 1.
    assertRejectsAt("amount.zero", 2, file(SUMMARY, simple("2"), card("05-01-2026", "0,00", "0.00", "3")));
  }

  @Test
  void aLongFreeTextField_isRefusedByTheWorkflowsOwnBound() {
    String longText = "x".repeat(ParsedStatements.MAX_FIELD_CHARS + 1);
    ParsedStatement parsed =
        importer.parse(
            file(SUMMARY, "05-01-2026,05-01-2026,Zakup BLIK " + longText + " ref:00000000001," + longText + "," + OTHER_ACCOUNT + ",\"-1,00\",\"1,00\",2,"),
            context);
    ImportRejectedException e =
        assertThrows(ImportRejectedException.class, () -> ParsedStatements.validate(importer.formatId(), parsed));
    assertEquals("field.too_long", e.rule());
  }

  @Test
  void theParsedStatementHoldsNoAccountNumberOrHolderName() throws Exception {
    ParsedStatement parsed = importer.parse(fixture("statement-representative.csv"), context);
    String everything = parsed.toString();
    assertFalse(everything.contains("JAN TESTOWY"), "the holder is never carried");
    assertFalse(everything.contains(ACCOUNT_1), "the statement's own account leaves parse only as a digest");
    assertTrue(parsed.accountIdentity().matches("[0-9a-f]{64}"));
  }
}
