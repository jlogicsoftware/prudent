package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static prudent.imports.ImportTestSupport.commit;
import static prudent.imports.ImportTestSupport.post;
import static prudent.imports.ImportTestSupport.preview;
import static prudent.imports.ImportTestSupport.session;

import com.google.protobuf.ByteString;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.account.AccountEntity;
import prudent.proto.v1.CreateImportSessionRequest;
import zen.proto.v1.ZenError;
import prudent.proto.v1.ImportRow;
import prudent.proto.v1.ImportRowStatus;
import prudent.proto.v1.ImportSession;
import prudent.record.RecordEntity;

/**
 * Duplicate detection end to end (M6, jlogicsoftware/prudent#75, ADR-091): statements are imported
 * through the real parse, preview and commit ({@link LedgerImportCommitter}, ADR-092), which copies
 * a row's key onto the record it writes. Every statement is synthetic and built in memory.
 */
@QuarkusTest
@TestSecurity(user = PrudentTest.ALICE)
class ImportDuplicateDetectionTest {

  private static final String ACCOUNT_NUMBER = "00000000000000000000000001";
  private static final String SUMMARY =
      "2026-11-14,01-01-2026,'00 0000 0000 0000 0000 0000 0001,JAN TESTOWY UL. PRZYKŁADOWA 1/2"
          + " 00-000 TESTOWO,PLN,\"0,00\",\"50,00\",999,";

  @Inject EntityManager entityManager;

  private UUID erste;
  private UUID category;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    erste = PrudentTest.seedAccount(PrudentTest.ALICE, "Erste", "PLN");
    category = PrudentTest.seedCategory(PrudentTest.ALICE, "Everything");
    QuarkusTransaction.requiringNew()
        .run(() -> AccountEntity.<AccountEntity>findById(erste).accountNumber = ACCOUNT_NUMBER);
  }

  // --- statements ----------------------------------------------------------------------------

  /** A card payment row: booking date, transaction date, merchant, amount "-7,10", sequence. */
  private static String card(String booking, String day, String merchant, String amount, int seq) {
    String embedded = amount.replace("-", "").replace(",", ".");
    return booking + "," + day + ",DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ " + embedded
        + " PLN " + merchant + ",,,\"" + amount + "\",\"10,00\"," + seq + ",";
  }

  private static byte[] statement(String... rows) {
    return (SUMMARY + "\n" + String.join("\n", rows) + "\n").getBytes(StandardCharsets.UTF_8);
  }

  // --- the flow ------------------------------------------------------------------------------

  private ImportSession previewOf(byte[] content, UUID account) throws Exception {
    ImportSession parsed =
        session(
            post(
                ImportTestSupport.SESSIONS,
                CreateImportSessionRequest.newBuilder()
                    .setFormatId(ImportFormatIds.ERSTE_PL_CSV)
                    .setContent(ByteString.copyFrom(content))
                    .build()));
    return session(preview(parsed.getId(), account));
  }

  /**
   * Imports a statement: preview, then commit what it accepted, through the real committer, with
   * the session's default categories standing in for a category on every row. Returns the preview.
   */
  private ImportSession importStatement(byte[] content, UUID account) throws Exception {
    ImportSession previewed = previewOf(content, account);
    if (previewed.getAcceptedRows() > 0) {
      commitWithDefaults(previewed);
    }
    return previewed;
  }

  /** Commits a previewed session after giving it default categories; returns the committed one. */
  private ImportSession commitWithDefaults(ImportSession previewed) throws Exception {
    ImportTestSupport.defaults(previewed.getId(), category, category);
    return session(commit(previewed.getId(), previewed.getAcceptedRows()));
  }

  private long records() {
    return ImportTestSupport.count(entityManager, "RecordEntity");
  }

  private static List<Integer> rowsWith(ImportSession preview, ImportRowStatus status) {
    return preview.getRowsList().stream()
        .filter(r -> r.getStatus() == status)
        .map(ImportRow::getRowNumber)
        .collect(Collectors.toList());
  }

  // --- tests ---------------------------------------------------------------------------------

  @Test
  void aFreshStatementHasNoDuplicates() throws Exception {
    ImportSession preview =
        importStatement(
            statement(
                card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
                card("09-03-2026", "09-03-2026", "SKLEP B TESTOWY", "-3,00", 2)),
            erste);

    assertEquals(2, preview.getAcceptedRows());
    assertEquals(0, preview.getDuplicateRows());
    assertEquals(2, records());
  }

  @Test
  void theSameStatementImportedTwiceYieldsNoNewRowsAndNoLoss() throws Exception {
    byte[] file =
        statement(
            card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
            card("09-03-2026", "09-03-2026", "SKLEP B TESTOWY", "-3,00", 2),
            card("08-03-2026", "08-03-2026", "SKLEP C TESTOWY", "-1,00", 3));
    importStatement(file, erste);
    assertEquals(3, records());

    ImportSession again = previewOf(file, erste);

    assertEquals(0, again.getAcceptedRows());
    assertEquals(3, again.getDuplicateRows());
    assertTrue(
        again.getRowsList().stream().allMatch(r -> r.getDuplicateCode().equals("duplicate.already_imported")));
    assertEquals(3, records(), "a preview writes nothing to the ledger");
  }

  @Test
  void genuinelyRepeatedRowsInOneStatementAreNotCollapsed() throws Exception {
    // Two tickets, one merchant, one amount, one day: two rows.
    ImportSession preview =
        importStatement(
            statement(
                card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 1),
                card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 2)),
            erste);

    assertEquals(2, preview.getAcceptedRows());
    assertEquals(2, records());
    // The same file again: both are recognised, neither is lost nor doubled.
    ImportSession again =
        previewOf(
            statement(
                card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 1),
                card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 2)),
            erste);
    assertEquals(2, again.getDuplicateRows());
  }

  @Test
  void overlappingStatementsWithOtherSequenceNumbersAndPositionsYieldExactlyTheNewRows()
      throws Exception {
    // The older export: three rows, sequence 1..3 (a rank from ITS newest row).
    importStatement(
        statement(
            card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
            card("09-03-2026", "09-03-2026", "SKLEP B TESTOWY", "-3,00", 2),
            card("08-03-2026", "08-03-2026", "SKLEP C TESTOWY", "-1,00", 3)),
        erste);
    assertEquals(3, records());

    // The later export adds two newer rows above, so every old row has a new sequence number and
    // position; one old row's booking date has also moved a day.
    ImportSession second =
        importStatement(
            statement(
                card("14-03-2026", "13-03-2026", "SKLEP E TESTOWY", "-9,99", 1),
                card("12-03-2026", "12-03-2026", "SKLEP D TESTOWY", "-2,50", 2),
                card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 3),
                card("10-03-2026", "09-03-2026", "SKLEP B TESTOWY", "-3,00", 4),
                card("08-03-2026", "08-03-2026", "SKLEP C TESTOWY", "-1,00", 5)),
            erste);

    assertEquals(List.of(1, 2), rowsWith(second, ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED));
    assertEquals(List.of(3, 4, 5), rowsWith(second, ImportRowStatus.IMPORT_ROW_STATUS_DUPLICATE));
    assertEquals(5, records(), "the union of both files, each row once");

    // And the older file again, after both: nothing new.
    ImportSession third =
        previewOf(
            statement(
                card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
                card("09-03-2026", "09-03-2026", "SKLEP B TESTOWY", "-3,00", 2),
                card("08-03-2026", "08-03-2026", "SKLEP C TESTOWY", "-1,00", 3)),
            erste);
    assertEquals(0, third.getAcceptedRows());
  }

  @Test
  void anOverlapThatCutsThroughIdenticalRowsImportsOnlyTheMissingOne() throws Exception {
    // The older export ends mid-day with two of three identical purchases.
    importStatement(
        statement(
            card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 1),
            card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 2)),
        erste);
    assertEquals(2, records());

    // The later export has all three, and a newer row.
    ImportSession second =
        importStatement(
            statement(
                card("11-03-2026", "11-03-2026", "SKLEP A TESTOWY", "-1,00", 1),
                card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 2),
                card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 3),
                card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 4)),
            erste);

    assertEquals(2, second.getAcceptedRows(), "the newer row and the third ticket");
    assertEquals(2, second.getDuplicateRows());
    assertEquals(4, records());
    assertEquals(
        3,
        QuarkusTransaction.requiringNew().call(() -> RecordEntity.count("amountMinor", -440L)));
  }

  @Test
  void changedDescriptionOrAmountIsAnotherRow() throws Exception {
    importStatement(
        statement(card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1)), erste);

    ImportSession other =
        previewOf(
            statement(
                card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,11", 1),
                card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY 2", "-7,10", 2),
                card("11-03-2026", "11-03-2026", "SKLEP A TESTOWY", "-7,10", 3)),
            erste);

    assertEquals(3, other.getAcceptedRows());
  }

  @Test
  void aDeletedImportedRecordIsOfferedAgain() throws Exception {
    byte[] file = statement(card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1));
    importStatement(file, erste);
    QuarkusTransaction.requiringNew().run(() -> RecordEntity.deleteAll());

    assertEquals(1, previewOf(file, erste).getAcceptedRows());
  }

  @Test
  void aRecordTypedByHandIsNotADuplicateOfAStatementRow() throws Exception {
    PrudentTest.seedRecord(
        PrudentTest.ALICE, erste, null, -710, "PLN", java.time.LocalDate.of(2026, 3, 10));

    ImportSession preview =
        previewOf(
            statement(card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1)), erste);

    assertEquals(1, preview.getAcceptedRows());
  }

  @Test
  void rowsAreNotMarkedWithoutADestinationAccount() throws Exception {
    byte[] file = statement(card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1));
    importStatement(file, erste);

    ImportSession parsed =
        session(
            post(
                ImportTestSupport.SESSIONS,
                CreateImportSessionRequest.newBuilder()
                    .setFormatId(ImportFormatIds.ERSTE_PL_CSV)
                    .setContent(ByteString.copyFrom(file))
                    .build()));
    assertEquals(ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED, parsed.getRows(0).getStatus());
    ImportSession previewed = session(preview(parsed.getId(), null));
    assertEquals(0, previewed.getDuplicateRows(), "no account, no duplicates");
  }

  @Test
  void theWireCarriesTheReasonAndNeverTheKey() throws Exception {
    byte[] file = statement(card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1));
    importStatement(file, erste);

    ImportSession again = previewOf(file, erste);

    assertEquals("duplicate.already_imported", again.getRows(0).getDuplicateCode());
    // The strongest check available: the stored keys themselves, in every shape the wire has.
    List<String> stored =
        QuarkusTransaction.requiringNew()
            .call(
                () ->
                    ImportRowEntity.<ImportRowEntity>listAll().stream()
                        .map(row -> row.fingerprint)
                        .toList());
    assertFalse(stored.isEmpty());
    String json = ImportTestSupport.get(again.getId()).asString();
    for (String key : stored) {
      String digest = key.substring(key.indexOf(':') + 1);
      assertFalse(json.contains(digest), "a stored key is on the wire (JSON)");
      assertFalse(again.toString().contains(digest), "a stored key is on the wire (message)");
      assertFalse(
          again.toByteString().toStringUtf8().contains(digest), "a stored key is on the wire (bytes)");
    }
    assertFalse(json.matches("(?s).*[0-9a-f]{20,}.*"), "no long hex run, whatever the scheme");
    assertFalse(json.contains("v1:") || json.contains("e1:"), "no scheme prefix");
  }

  @Test
  void aRowTheImporterRejectedGetsNoKeyAndIsNeverADuplicate() throws Exception {
    // An unknown description shape is returned rejected, not dropped.
    String odd = "10-03-2026,10-03-2026,Zlecenie stałe TESTOWE,,,\"-5,00\",\"10,00\",4,";
    ImportSession preview =
        previewOf(
            statement(card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1), odd), erste);

    assertEquals(1, preview.getRejectedRows());
    long keyed =
        QuarkusTransaction.requiringNew()
            .call(
                () ->
                    ImportRowEntity.<ImportRowEntity>list("fingerprint is not null").size());
    assertEquals(1, keyed);
  }

  @Test
  void aRepeatedPreviewForAnotherAccountStartsFromScratchAndComesBack() throws Exception {
    UUID a = PrudentTest.seedAccount(PrudentTest.ALICE, "A", "PLN");
    UUID b = PrudentTest.seedAccount(PrudentTest.ALICE, "B", "PLN");
    String text = "PLN\n2026-03-10;-710;SKLEP A TESTOWY;x\n2026-03-09;-300;SKLEP B TESTOWY;x\n";
    ImportSession first = uploadTest(text, a);
    ImportSession previewedA = session(preview(first.getId(), a));
    commitWithDefaults(previewedA);
    assertEquals(2, records());

    // The same statement, again, into A: duplicates.
    ImportSession again = uploadTest(text, a);
    assertEquals(2, session(preview(again.getId(), a)).getDuplicateRows());
    // Previewed again for B, which holds nothing: the duplicates are gone.
    ImportSession forB = session(preview(again.getId(), b));
    assertEquals(0, forB.getDuplicateRows());
    assertEquals(2, forB.getAcceptedRows());
    assertTrue(forB.getRowsList().stream().allMatch(r -> r.getDuplicateCode().isEmpty()));
    // And for A once more: they are back.
    ImportSession backToA = session(preview(again.getId(), a));
    assertEquals(2, backToA.getDuplicateRows());
    assertEquals(0, backToA.getAcceptedRows());
  }

  @Test
  void aFormatWithAProvenStableIdentifierIsKeyedByItNotByContent() throws Exception {
    UUID account = PrudentTest.seedAccount(PrudentTest.ALICE, "S", "PLN");
    String first = "PLN\n2026-03-10;-710;SKLEP A;1001\n2026-03-09;-300;SKLEP B;1002\n";
    ImportSession one = uploadStable(first, account);
    ImportSession previewed = session(preview(one.getId(), account));
    commitWithDefaults(previewed);

    // The same two operations with other dates, amounts and text but the same identifiers are the
    // same rows; a new identifier is a new row, even with identical content to another.
    String second = "PLN\n2026-03-11;-1;CHANGED;1001\n2026-03-09;-300;SKLEP B;1002\n2026-03-09;-300;SKLEP B;1003\n";
    ImportSession two = uploadStable(second, account);
    ImportSession again = session(preview(two.getId(), account));

    assertEquals(List.of(3), rowsWith(again, ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED));
    assertEquals(List.of(1, 2), rowsWith(again, ImportRowStatus.IMPORT_ROW_STATUS_DUPLICATE));
  }

  @Test
  void deletingOneOfTwoIdenticalImportedRecordsFreesOnlyThatKey() throws Exception {
    byte[] two =
        statement(
            card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 1),
            card("10-03-2026", "10-03-2026", "BILETY TESTOWE", "-4,40", 2));
    importStatement(two, erste);
    assertEquals(2, records());
    QuarkusTransaction.requiringNew()
        .run(() -> RecordEntity.<RecordEntity>listAll().get(0).delete());
    assertEquals(1, records());

    ImportSession again = previewOf(two, erste);

    assertEquals(1, again.getAcceptedRows(), "only the deleted record's slot is free");
    assertEquals(1, again.getDuplicateRows());
    commitWithDefaults(again);
    assertEquals(2, records());
    assertEquals(0, previewOf(two, erste).getAcceptedRows());
  }

  @Test
  void twoSessionsOfTheSameFileCommittedOneAfterTheOtherDoNotDoubleTheLedger() throws Exception {
    byte[] file =
        statement(
            card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
            card("10-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 2));
    // Two tabs: both previews run before either commit, so both see no duplicates.
    ImportSession tabOne = previewOf(file, erste);
    ImportSession tabTwo = previewOf(file, erste);
    assertEquals(2, tabOne.getAcceptedRows());
    assertEquals(2, tabTwo.getAcceptedRows());

    ImportSession first = commitWithDefaults(tabOne);
    ImportSession second = commitWithDefaults(tabTwo);

    assertEquals(2, records(), "the second commit wrote nothing");
    assertEquals(2, first.getCommittedWritten());
    assertEquals(0, first.getCommittedAlreadyImported());
    assertEquals(0, second.getCommittedWritten());
    assertEquals(2, second.getCommittedAlreadyImported());
  }

  @Test
  void aRowBookedOnAnotherDayWithTheSameTransactionDateAmountAndTextIsTakenForADuplicate()
      throws Exception {
    // THE DOCUMENTED LOSS MODE (ADR-091): the booking date is not part of the key and card rows
    // carry no unique reference, so a genuinely new operation that looks like an imported one is
    // marked DUPLICATE, silently, when the two exports do not overlap by transaction date. This
    // test pins today's behaviour; #74 must let the user include such a row.
    importStatement(
        statement(card("10-03-2026", "10-03-2026", "KAWIARNIA TESTOWA", "-12,00", 1)), erste);

    ImportSession adjacent =
        previewOf(
            statement(card("11-03-2026", "10-03-2026", "KAWIARNIA TESTOWA", "-12,00", 1)), erste);

    assertEquals(1, adjacent.getDuplicateRows());
    assertEquals(0, adjacent.getAcceptedRows());
  }

  @Test
  void aStableIdentifierFormatRefusesAFileWhoseIdentifiersAreMissingOrRepeated() throws Exception {
    UUID account = PrudentTest.seedAccount(PrudentTest.ALICE, "S2", "PLN");
    String repeated = "PLN\n2026-03-10;-710;SKLEP A;1001\n2026-03-09;-300;SKLEP B;1001\n";
    ZenError duplicate = ImportTestSupport.error(postStable(repeated, account), 400);
    assertTrue(duplicate.getMessage().contains("identifier.duplicate"), duplicate.getMessage());
    assertTrue(duplicate.getMessage().contains("row 2"), duplicate.getMessage());
    assertFalse(duplicate.getMessage().contains("1001"), "the identifier is not echoed");

    String missing = "PLN\n2026-03-10;-710;SKLEP A;\n";
    ZenError none = ImportTestSupport.error(postStable(missing, account), 400);
    assertTrue(none.getMessage().contains("identifier.missing"), none.getMessage());
    assertEquals(0, ImportTestSupport.count(entityManager, "ImportSessionEntity"));
  }

  private io.restassured.response.Response postStable(String text, UUID account) throws Exception {
    return post(
        ImportTestSupport.SESSIONS,
        CreateImportSessionRequest.newBuilder()
            .setFormatId(TestStableIdImporter.FORMAT)
            .setContent(ByteString.copyFrom(text, StandardCharsets.UTF_8))
            .setAccountId(account.toString())
            .build());
  }

  private ImportSession uploadTest(String text, UUID account) throws Exception {
    return session(ImportTestSupport.upload(text, account));
  }

  private ImportSession uploadStable(String text, UUID account) throws Exception {
    return session(
        post(
            ImportTestSupport.SESSIONS,
            CreateImportSessionRequest.newBuilder()
                .setFormatId(TestStableIdImporter.FORMAT)
                .setContent(ByteString.copyFrom(text, StandardCharsets.UTF_8))
                .setAccountId(account.toString())
                .build()));
  }
}
