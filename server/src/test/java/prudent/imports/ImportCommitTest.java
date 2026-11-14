package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import jakarta.inject.Inject;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.account.AccountEntity;
import prudent.category.CategoryEntity;
import prudent.error.PrudentException;
import prudent.imports.ImportWorkflow.SessionView;
import prudent.proto.v1.ImportSession;
import prudent.proto.v1.ImportSessionState;
import prudent.proto.v1.PreviewImportSessionRequest;
import prudent.record.RecordEntity;
import prudent.record.RecordWriter;
import zen.proto.v1.ZenError;

/**
 * The real commit (M6, jlogicsoftware/prudent#76, ADR-092) through the real Erste importer, the
 * real duplicate stage and the real {@link LedgerImportCommitter}: what is written, atomicity,
 * idempotence, own-account transfers, duplicate overrides, privacy and a race between threads. Every
 * statement is synthetic and built in memory.
 */
@QuarkusTest
@TestSecurity(user = PrudentTest.ALICE)
class ImportCommitTest {

  private static final UUID ALICE = UUID.fromString(PrudentTest.ALICE);
  private static final String NUMBER_1 = "00000000000000000000000001";
  private static final String NUMBER_2 = "00000000000000000000000002";
  private static final String SUMMARY =
      "2026-11-14,01-01-2026,'00 0000 0000 0000 0000 0000 0001,JAN TESTOWY UL. PRZYKŁADOWA 1/2"
          + " 00-000 TESTOWO,PLN,\"0,00\",\"50,00\",999,";
  private static final String OWN_TRANSFER_PARTY =
      "FIRMA TESTOWA JAN TESTOWY UL. PRZYKŁADOWA 1/2 00-000 TESTOWO WOJ. TESTOWE";

  @Inject ImportWorkflow workflow;

  private UUID erste;
  private UUID other;
  private UUID category;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    erste = PrudentTest.seedAccount(PrudentTest.ALICE, "Erste", "PLN");
    other = PrudentTest.seedAccount(PrudentTest.ALICE, "Savings", "PLN");
    category = PrudentTest.seedCategory(PrudentTest.ALICE, "Everything");
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              AccountEntity.<AccountEntity>findById(erste).accountNumber = NUMBER_1;
              AccountEntity.<AccountEntity>findById(other).accountNumber = NUMBER_2;
            });
  }

  // --- statements ------------------------------------------------------------------------------

  private static String card(String day, String merchant, String amount, int seq) {
    String embedded = amount.replace("-", "").replace(",", ".");
    return day + "," + day + ",DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ " + embedded + " PLN "
        + merchant + ",,,\"" + amount + "\",\"10,00\"," + seq + ",";
  }

  private static String ownTransfer(String day, String amount, int seq) {
    return day + "," + day + ",Przelew na rachunek własny," + OWN_TRANSFER_PARTY
        + ",00 0000 0000 0000 0000 0000 0002,\"" + amount + "\",\"300,00\"," + seq + ",";
  }

  private static byte[] statement(String... rows) {
    return (SUMMARY + "\n" + String.join("\n", rows) + "\n").getBytes(StandardCharsets.UTF_8);
  }

  private static byte[] threeRows() {
    return statement(
        card("10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
        card("09-03-2026", "SKLEP B TESTOWY", "-3,00", 2),
        card("08-03-2026", "SKLEP C TESTOWY", "-1,00", 3));
  }

  // --- flow helpers ----------------------------------------------------------------------------

  /** Parse, preview into {@code account}, and give every writable row the test category. */
  private SessionView previewed(byte[] file, UUID account) {
    SessionView parsed =
        workflow.create(ALICE, ImportFormatIds.ERSTE_PL_CSV, file, null);
    SessionView view = workflow.preview(ALICE, parsed.session().id, account);
    return categorised(view);
  }

  private SessionView categorised(SessionView view) {
    for (ImportRowEntity row : view.rows()) {
      if (row.status != RowStatus.REJECTED) {
        workflow.updateRow(ALICE, view.session().id, row.rowNumber, category, false, null, null);
      }
    }
    return workflow.get(ALICE, view.session().id);
  }

  private static long records() {
    return RecordEntity.count();
  }

  private long net(UUID account) {
    return QuarkusTransaction.requiringNew()
        .call(() -> RecordEntity.netByAccount(ALICE, account).getOrDefault("PLN", 0L));
  }

  private List<RecordEntity> recordsOf(UUID account) {
    return QuarkusTransaction.requiringNew()
        .call(() -> RecordEntity.<RecordEntity>list("accountId", account));
  }

  // --- what is written -------------------------------------------------------------------------

  @Test
  void commit_writesOneOrdinaryRecordPerRow_withTheKeyAndNothingElseSpecial() {
    SessionView view = previewed(threeRows(), erste);
    UUID id = view.session().id;
    workflow.updateRow(ALICE, id, 1, null, false, "  my note ", null);

    SessionView done = workflow.commit(ALICE, id, 3);

    assertEquals(ImportState.COMMITTED, done.session().state);
    assertEquals(3, done.session().committedWritten);
    assertEquals(0, done.session().committedAlreadyImported);
    assertEquals(3, records());
    assertEquals(-1110L, net(erste));
    List<RecordEntity> written = recordsOf(erste);
    assertTrue(written.stream().allMatch(r -> r.importFingerprint != null && r.importOccurrence == 1));
    assertTrue(written.stream().allMatch(r -> category.equals(r.categoryId) && "PLN".equals(r.currency)));
    assertTrue(written.stream().allMatch(r -> r.transferId == null && !r.isCorrection));
    assertTrue(written.stream().allMatch(r -> r.planId == null));
    RecordEntity noted = written.stream().filter(r -> r.amountMinor == -710).findFirst().orElseThrow();
    assertEquals("my note", noted.note);
    assertEquals(java.time.LocalDate.of(2026, 3, 10), noted.date);
  }

  @Test
  void commit_withoutACategoryOnEveryRow_isRefusedBeforeAnythingIsWritten() {
    SessionView parsed = workflow.create(ALICE, ImportFormatIds.ERSTE_PL_CSV, threeRows(), null);
    UUID id = parsed.session().id;
    workflow.preview(ALICE, id, erste);
    workflow.updateRow(ALICE, id, 1, category, false, null, null);

    PrudentException refused =
        assertThrows(PrudentException.class, () -> workflow.commit(ALICE, id, 3));
    assertTrue(refused.getMessage().contains("2 row(s) have no category"), refused.getMessage());
    assertEquals(0, records());
    assertEquals(ImportState.PREVIEWED, workflow.get(ALICE, id).session().state);
  }

  // --- atomicity -------------------------------------------------------------------------------

  @Test
  void aRowTheLedgerRefusesAtTheThirdRow_rollsBackEverything() {
    SessionView view = previewed(threeRows(), erste);
    UUID id = view.session().id;
    // Archived after it was chosen: rows 1 and 2 are written first, then row 3 is refused.
    UUID retired = PrudentTest.seedCategory(PrudentTest.ALICE, "Retired");
    workflow.updateRow(ALICE, id, 3, retired, false, null, null);
    QuarkusTransaction.requiringNew()
        .run(() -> CategoryEntity.<CategoryEntity>findById(retired).archivedAt = java.time.Instant.now());

    PrudentException refused =
        assertThrows(PrudentException.class, () -> workflow.commit(ALICE, id, 3));

    assertEquals(409, refused.status().getStatusCode());
    assertTrue(refused.getMessage().startsWith("Row 3 cannot be written"), refused.getMessage());
    assertFalse(refused.getMessage().contains("SKLEP"), "no statement text in an error");
    assertEquals(0, records(), "rows 1 and 2 were written and must be gone");
    SessionView kept = workflow.get(ALICE, id);
    assertEquals(ImportState.PREVIEWED, kept.session().state);
    assertEquals(3, kept.rows().size());
    assertNull(kept.session().committedWritten);
  }

  /** Fails at the Nth call, as a bug or a database error in the middle of a batch would. */
  static final class FailingWriter extends RecordWriter {
    int calls;
    final int failAt;

    FailingWriter(int failAt) {
      this.failAt = failAt;
    }

    @Override
    public void apply(
        RecordEntity entity, UUID userId, String title, long amountMinor, String date,
        String categoryId, String accountId, String currency, String payee, String note) {
      if (++calls == failAt) {
        throw new IllegalStateException("injected failure");
      }
      super.apply(entity, userId, title, amountMinor, date, categoryId, accountId, currency, payee, note);
    }
  }

  @Test
  void anUnexpectedFailureAtAnyRow_rollsBackEverything_andALaterCommitStillWorks() {
    for (int failAt = 1; failAt <= 3; failAt++) {
      PrudentTest.reset();
      seed();
      SessionView view = previewed(threeRows(), erste);
      UUID id = view.session().id;
      QuarkusMock.installMockForType(new FailingWriter(failAt), RecordWriter.class);

      assertThrows(IllegalStateException.class, () -> workflow.commit(ALICE, id, 3));

      assertEquals(0, records(), "failure at row " + failAt + " left records behind");
      assertEquals(ImportState.PREVIEWED, workflow.get(ALICE, id).session().state);
      assertEquals(3, workflow.get(ALICE, id).rows().size());

      QuarkusMock.installMockForType(new RecordWriter(), RecordWriter.class);
      assertEquals(3, workflow.commit(ALICE, id, 3).session().committedWritten);
      assertEquals(3, records());
    }
  }

  @Test
  void aCommitThatFailsOverHttp_isA500WithNoStatementTextAndNothingWritten() throws Exception {
    SessionView view = previewed(threeRows(), erste);
    QuarkusMock.installMockForType(new FailingWriter(2), RecordWriter.class);

    Response response = ImportTestSupport.commit(view.session().id.toString(), 3);

    assertEquals(500, response.statusCode());
    assertFalse(response.asString().contains("SKLEP"));
    assertEquals(0, records());
  }

  // --- idempotence -----------------------------------------------------------------------------

  @Test
  void aRepeatedCommitOfACommittedSession_answersTheSameResult_andWritesNothing() {
    SessionView view = previewed(threeRows(), erste);
    UUID id = view.session().id;
    SessionView first = workflow.commit(ALICE, id, 3);

    SessionView again = workflow.commit(ALICE, id, 3);

    assertEquals(ImportState.COMMITTED, again.session().state);
    assertEquals(first.session().committedWritten, again.session().committedWritten);
    assertEquals(first.session().committedAlreadyImported, again.session().committedAlreadyImported);
    assertEquals(3, records());
    assertThrows(PrudentException.class, () -> workflow.commit(ALICE, id, 2));
    assertThrows(PrudentException.class, () -> workflow.discard(ALICE, id));
  }

  @Test
  void aDiscardedSessionStaysRefused() {
    SessionView view = previewed(threeRows(), erste);
    UUID id = view.session().id;
    workflow.discard(ALICE, id);
    PrudentException refused =
        assertThrows(PrudentException.class, () -> workflow.commit(ALICE, id, 3));
    assertEquals(409, refused.status().getStatusCode());
    assertEquals(0, records());
  }

  @Test
  void twoSessionsOfOneFilePreviewedBeforeEitherCommits_doNotDoubleTheLedger() {
    SessionView a = previewed(threeRows(), erste);
    SessionView b = previewed(threeRows(), erste);
    assertEquals(3, b.session().acceptedRows, "the preview of the second session saw no duplicates");

    SessionView first = workflow.commit(ALICE, a.session().id, 3);
    SessionView second = workflow.commit(ALICE, b.session().id, 3);

    assertEquals(3, first.session().committedWritten);
    assertEquals(0, second.session().committedWritten);
    assertEquals(3, second.session().committedAlreadyImported);
    assertEquals(3, records());
    assertEquals(-1110L, net(erste));
  }

  @Test
  void aRealRaceBetweenSessionsOfOneFile_writesItOnce_withoutDeadlockOrError() throws Exception {
    int sessions = 6;
    List<UUID> ids = new ArrayList<>();
    for (int i = 0; i < sessions; i++) {
      ids.add(previewed(threeRows(), erste).session().id);
    }
    List<Callable<Object>> commits = new ArrayList<>();
    for (UUID id : ids) {
      commits.add(() -> workflow.commit(ALICE, id, 3));
    }

    List<Object> outcomes = race(commits);

    int written = 0;
    int already = 0;
    for (Object outcome : outcomes) {
      assertTrue(outcome instanceof SessionView, "a commit failed: " + outcome);
      ImportSessionEntity session = ((SessionView) outcome).session();
      assertEquals(ImportState.COMMITTED, session.state);
      assertEquals(3, session.committedWritten + session.committedAlreadyImported);
      written += session.committedWritten;
      already += session.committedAlreadyImported;
    }
    assertEquals(3, written, "exactly one import wrote the file");
    assertEquals(3 * (sessions - 1), already);
    assertEquals(3, records());
  }

  @Test
  void aRealRaceOfOneSessionCommittedTwice_isTwoSuccessesWithTheSameResult() throws Exception {
    UUID id = previewed(threeRows(), erste).session().id;

    List<Object> outcomes =
        race(List.of(() -> workflow.commit(ALICE, id, 3), () -> workflow.commit(ALICE, id, 3)));

    for (Object outcome : outcomes) {
      assertTrue(outcome instanceof SessionView, "a commit failed: " + outcome);
      assertEquals(3, ((SessionView) outcome).session().committedWritten);
    }
    assertEquals(3, records());
  }

  /** Runs every task at once; each result is the value returned or the Throwable thrown. */
  private static List<Object> race(List<Callable<Object>> tasks) throws Exception {
    ExecutorService pool = Executors.newFixedThreadPool(tasks.size());
    try {
      CountDownLatch go = new CountDownLatch(1);
      List<Future<Object>> futures = new ArrayList<>();
      for (Callable<Object> task : tasks) {
        futures.add(
            pool.submit(
                () -> {
                  go.await();
                  return task.call();
                }));
      }
      go.countDown();
      List<Object> outcomes = new ArrayList<>();
      for (Future<Object> future : futures) {
        try {
          outcomes.add(future.get(90, TimeUnit.SECONDS));
        } catch (ExecutionException failed) {
          outcomes.add(failed.getCause());
        }
      }
      return outcomes;
    } finally {
      pool.shutdownNow();
    }
  }

  // --- own-account transfers -------------------------------------------------------------------

  @Test
  void anIncomingOwnTransfer_isAPlainRecordOfTheDestination_andTheOtherAccountIsUntouched() {
    SessionView view =
        previewed(
            statement(
                card("10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
                ownTransfer("09-03-2026", "500,00", 2)),
            erste);
    assertEquals(2, view.session().acceptedRows);

    workflow.commit(ALICE, view.session().id, 2);

    assertEquals(2, records());
    assertEquals(50000L - 710L, net(erste));
    assertEquals(0L, net(other), "no leg is invented in the other account");
    assertTrue(recordsOf(erste).stream().allMatch(r -> r.transferId == null));
    assertEquals(0, recordsOf(other).size());
  }

  @Test
  void anOutgoingOwnTransfer_staysRejected_andIsNeverWritten() {
    SessionView view =
        previewed(
            statement(
                card("10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
                ownTransfer("09-03-2026", "-500,00", 2)),
            erste);
    assertEquals(1, view.session().acceptedRows);
    assertEquals(1, view.session().rejectedRows);

    workflow.commit(ALICE, view.session().id, 1);

    assertEquals(1, records());
    assertEquals(-710L, net(erste));
  }

  // --- duplicate override ----------------------------------------------------------------------

  private byte[] twoRows() {
    return statement(
        card("10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
        card("09-03-2026", "SKLEP B TESTOWY", "-3,00", 2));
  }

  private void importOnce(byte[] file) {
    SessionView view = previewed(file, erste);
    workflow.commit(ALICE, view.session().id, view.session().acceptedRows);
  }

  @Test
  void anIncludedDuplicate_isWrittenUnderTheNextFreeOccurrence() {
    importOnce(twoRows());
    SessionView again = previewed(twoRows(), erste);
    assertEquals(2, again.session().duplicateRows);
    assertEquals(0, again.session().acceptedRows);
    UUID id = again.session().id;

    ImportWorkflow.RowDecision included = workflow.updateRow(ALICE, id, 1, null, false, null, true);
    assertEquals(1, included.session().acceptedRows, "an included duplicate is confirmed with the accepted rows");
    assertEquals(1, included.session().duplicateRows);
    // The category belongs to the row, so a DUPLICATE row needs it too.
    workflow.updateRow(ALICE, id, 1, category, false, null, null);
    SessionView done = workflow.commit(ALICE, id, 1);

    assertEquals(1, done.session().committedWritten);
    assertEquals(3, records());
    List<RecordEntity> sameRow =
        recordsOf(erste).stream().filter(r -> r.amountMinor == -710).toList();
    assertEquals(2, sameRow.size());
    assertEquals(
        List.of(1, 2),
        sameRow.stream().map(r -> r.importOccurrence).sorted().toList(),
        "the fingerprint is the same, the occurrence is the next free one");
    assertEquals(sameRow.get(0).importFingerprint, sameRow.get(1).importFingerprint);

    // A third time: the original and the forced copy are both recognised as imported, so the row
    // is again a single duplicate rather than a fresh row.
    SessionView third = previewed(twoRows(), erste);
    assertEquals(2, third.session().duplicateRows);
    assertEquals(0, third.session().acceptedRows);
  }

  @Test
  void aSecondIncludeOfTheSameRow_takesTheOccurrenceAfterTheFirst() {
    importOnce(twoRows());
    for (int expectedOccurrence = 2; expectedOccurrence <= 3; expectedOccurrence++) {
      SessionView again = previewed(twoRows(), erste);
      UUID id = again.session().id;
      workflow.updateRow(ALICE, id, 1, category, false, null, true);
      workflow.commit(ALICE, id, 1);
      List<Integer> occurrences =
          recordsOf(erste).stream()
              .filter(r -> r.amountMinor == -710)
              .map(r -> r.importOccurrence)
              .sorted()
              .toList();
      assertEquals(expectedOccurrence, occurrences.size());
      assertEquals(expectedOccurrence, occurrences.get(occurrences.size() - 1));
    }
  }

  @Test
  void twoIncludedRowsWithOneFingerprintInOneSession_getConsecutiveOccurrences() {
    byte[] twins =
        statement(
            card("10-03-2026", "BILETY TESTOWE", "-4,40", 1),
            card("10-03-2026", "BILETY TESTOWE", "-4,40", 2));
    importOnce(twins);
    SessionView again = previewed(twins, erste);
    UUID id = again.session().id;
    workflow.updateRow(ALICE, id, 1, category, false, null, true);
    workflow.updateRow(ALICE, id, 2, category, false, null, true);

    SessionView done = workflow.commit(ALICE, id, 2);

    assertEquals(2, done.session().committedWritten);
    assertEquals(
        List.of(1, 2, 3, 4),
        recordsOf(erste).stream().map(r -> r.importOccurrence).sorted().toList());
  }

  @Test
  void includingARowThatIsNotADuplicate_orARejectedRow_isRefused_andTheDecisionCanBeTakenBack() {
    importOnce(statement(card("10-03-2026", "SKLEP A TESTOWY", "-7,10", 1)));
    SessionView view =
        previewed(
            statement(
                card("10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
                card("09-03-2026", "SKLEP B TESTOWY", "-3,00", 2),
                ownTransfer("08-03-2026", "-500,00", 3)),
            erste);
    UUID id = view.session().id;
    assertEquals(
        RowStatus.DUPLICATE,
        view.rows().stream().filter(r -> r.rowNumber == 1).findFirst().orElseThrow().status);

    PrudentException notDuplicate =
        assertThrows(
            PrudentException.class, () -> workflow.updateRow(ALICE, id, 2, null, false, null, true));
    assertEquals(400, notDuplicate.status().getStatusCode());
    PrudentException rejected =
        assertThrows(
            PrudentException.class, () -> workflow.updateRow(ALICE, id, 3, null, false, null, true));
    assertEquals(409, rejected.status().getStatusCode());
    assertThrows(
        PrudentException.class, () -> workflow.updateRow(ALICE, id, 9, null, false, null, true));

    assertEquals(2, workflow.updateRow(ALICE, id, 1, null, false, null, true).session().acceptedRows);
    assertEquals(1, workflow.updateRow(ALICE, id, 1, null, false, null, false).session().acceptedRows);
  }

  @Test
  void aNewPreview_clearsTheIncludeDecision() {
    importOnce(twoRows());
    SessionView again = previewed(twoRows(), erste);
    UUID id = again.session().id;
    workflow.updateRow(ALICE, id, 1, null, false, null, true);

    SessionView repeated = workflow.preview(ALICE, id, erste);

    assertEquals(0, repeated.session().acceptedRows);
    assertEquals(2, repeated.session().duplicateRows);
    assertTrue(repeated.rows().stream().noneMatch(r -> r.includeDuplicate));
  }

  @Test
  void theConfirmedCountOfAnIncludedDuplicate_mustMatch() {
    importOnce(twoRows());
    SessionView again = previewed(twoRows(), erste);
    UUID id = again.session().id;
    workflow.updateRow(ALICE, id, 1, null, false, null, true);
    assertThrows(PrudentException.class, () -> workflow.commit(ALICE, id, 0));
    assertEquals(2, records());
  }

  // --- the category and the note of a row ------------------------------------------------------

  @Test
  void aRowCategory_mustBeTheCallersActiveAndSuitTheDirection() {
    SessionView view = previewed(threeRows(), erste);
    UUID id = view.session().id;
    UUID bobs = PrudentTest.seedCategory(PrudentTest.BOB, "Bobs");
    assertEquals(
        400,
        assertThrows(
                PrudentException.class,
                () -> workflow.updateRow(ALICE, id, 1, bobs, false, null, null))
            .status()
            .getStatusCode());

    UUID incomeOnly = PrudentTest.seedCategory(PrudentTest.ALICE, "Salary");
    QuarkusTransaction.requiringNew()
        .run(() -> CategoryEntity.<CategoryEntity>findById(incomeOnly).kind = 2);
    assertEquals(
        400,
        assertThrows(
                PrudentException.class,
                () -> workflow.updateRow(ALICE, id, 1, incomeOnly, false, null, null))
            .status()
            .getStatusCode());

    ImportWorkflow.RowDecision cleared = workflow.updateRow(ALICE, id, 1, null, true, null, null);
    assertNull(cleared.row().categoryId);
  }

  // --- defaults, the light row answer, hints, notes, zero rows ---------------------------------

  /** Parse and preview without deciding any row. */
  private SessionView bare(byte[] file, UUID account) {
    SessionView parsed = workflow.create(ALICE, ImportFormatIds.ERSTE_PL_CSV, file, null);
    return workflow.preview(ALICE, parsed.session().id, account);
  }

  private UUID kindedCategory(String title, int kind) {
    UUID id = PrudentTest.seedCategory(PrudentTest.ALICE, title);
    QuarkusTransaction.requiringNew()
        .run(() -> CategoryEntity.<CategoryEntity>findById(id).kind = (short) kind);
    return id;
  }

  @Test
  void sessionDefaults_fileEveryRowWithoutItsOwnCategory_byTheSignOfItsAmount() {
    UUID spending = kindedCategory("Spending", 1);
    UUID salary = kindedCategory("Salary", 2);
    SessionView view =
        bare(
            statement(
                card("10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
                card("09-03-2026", "SKLEP B TESTOWY", "-3,00", 2),
                ownTransfer("08-03-2026", "500,00", 3)),
            erste);
    UUID id = view.session().id;
    // One row keeps its own category, which beats the default.
    workflow.updateRow(ALICE, id, 2, category, false, null, null);
    workflow.setDefaults(ALICE, id, spending, false, salary, false);

    workflow.commit(ALICE, id, 3);

    java.util.Map<Long, UUID> byAmount = new java.util.HashMap<>();
    recordsOf(erste).forEach(r -> byAmount.put(r.amountMinor, r.categoryId));
    assertEquals(spending, byAmount.get(-710L));
    assertEquals(category, byAmount.get(-300L));
    assertEquals(salary, byAmount.get(50000L));
  }

  @Test
  void aRowWithNeitherACategoryNorADefaultForItsDirection_refusesTheWholeCommit() {
    UUID spending = kindedCategory("Spending", 1);
    SessionView view =
        bare(
            statement(
                card("10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
                ownTransfer("08-03-2026", "500,00", 2)),
            erste);
    UUID id = view.session().id;
    workflow.setDefaults(ALICE, id, spending, false, null, false);

    PrudentException refused =
        assertThrows(PrudentException.class, () -> workflow.commit(ALICE, id, 2));

    assertTrue(refused.getMessage().contains("1 row(s) have no category"), refused.getMessage());
    assertEquals(0, records());
    assertEquals(ImportState.PREVIEWED, workflow.get(ALICE, id).session().state);
  }

  @Test
  void aDefaultMustBeTheCallersActiveAndSuitItsDirection_andCanBeCleared() {
    SessionView view = bare(threeRows(), erste);
    UUID id = view.session().id;
    UUID bobs = PrudentTest.seedCategory(PrudentTest.BOB, "Bobs");
    UUID incomeOnly = kindedCategory("Salary", 2);
    UUID expenseOnly = kindedCategory("Spending", 1);
    UUID retired = PrudentTest.seedCategory(PrudentTest.ALICE, "Retired");
    QuarkusTransaction.requiringNew()
        .run(() -> CategoryEntity.<CategoryEntity>findById(retired).archivedAt = java.time.Instant.now());

    assertEquals(
        400,
        assertThrows(PrudentException.class, () -> workflow.setDefaults(ALICE, id, bobs, false, null, false))
            .status().getStatusCode());
    assertEquals(
        400,
        assertThrows(
                PrudentException.class,
                () -> workflow.setDefaults(ALICE, id, incomeOnly, false, null, false))
            .status().getStatusCode());
    assertEquals(
        400,
        assertThrows(
                PrudentException.class,
                () -> workflow.setDefaults(ALICE, id, null, false, expenseOnly, false))
            .status().getStatusCode());
    assertEquals(
        409,
        assertThrows(PrudentException.class, () -> workflow.setDefaults(ALICE, id, retired, false, null, false))
            .status().getStatusCode());

    SessionView set = workflow.setDefaults(ALICE, id, expenseOnly, false, incomeOnly, false);
    assertEquals(expenseOnly, set.session().defaultExpenseCategoryId);
    assertEquals(incomeOnly, set.session().defaultIncomeCategoryId);
    SessionView cleared = workflow.setDefaults(ALICE, id, null, true, null, false);
    assertNull(cleared.session().defaultExpenseCategoryId);
    assertEquals(incomeOnly, cleared.session().defaultIncomeCategoryId);
  }

  @Test
  void aDefaultArchivedAfterItWasSet_isRefusedAtCommit_andNothingIsWritten() {
    UUID spending = kindedCategory("Spending", 1);
    SessionView view = bare(threeRows(), erste);
    UUID id = view.session().id;
    workflow.setDefaults(ALICE, id, spending, false, null, false);
    QuarkusTransaction.requiringNew()
        .run(() -> CategoryEntity.<CategoryEntity>findById(spending).archivedAt = java.time.Instant.now());

    PrudentException refused =
        assertThrows(PrudentException.class, () -> workflow.commit(ALICE, id, 3));

    assertEquals(409, refused.status().getStatusCode());
    assertEquals(0, records());
    assertEquals(ImportState.PREVIEWED, workflow.get(ALICE, id).session().state);
  }

  @Test
  void defaultsEndWithTheSession_onCommitAndOnDiscard() {
    SessionView one = bare(threeRows(), erste);
    workflow.setDefaults(ALICE, one.session().id, category, false, null, false);
    workflow.commit(ALICE, one.session().id, 3);
    assertNull(workflow.get(ALICE, one.session().id).session().defaultExpenseCategoryId);

    SessionView two = bare(statement(card("01-03-2026", "SKLEP Z TESTOWY", "-1,00", 1)), erste);
    workflow.setDefaults(ALICE, two.session().id, category, false, category, false);
    workflow.discard(ALICE, two.session().id);
    ImportSessionEntity ended = workflow.get(ALICE, two.session().id).session();
    assertNull(ended.defaultExpenseCategoryId);
    assertNull(ended.defaultIncomeCategoryId);
    PrudentException closed =
        assertThrows(
            PrudentException.class,
            () -> workflow.setDefaults(ALICE, two.session().id, category, false, null, false));
    assertEquals(409, closed.status().getStatusCode());
  }

  @Test
  void aRowDecisionOverHttp_answersTheRowAndTheCountsNotTheWholeSession() throws Exception {
    importOnce(twoRows());
    SessionView again = bare(twoRows(), erste);
    String id = again.session().id.toString();

    Response response =
        ImportTestSupport.post(
            ImportTestSupport.SESSIONS + "/" + id + "/rows/1",
            prudent.proto.v1.UpdateImportRowRequest.newBuilder()
                .setIncludeDuplicate(true)
                .setNote("kept")
                .build());

    assertEquals(200, response.statusCode(), response.asString());
    prudent.proto.v1.UpdateImportRowResponse body =
        PrudentTest.decode(
                PrudentTest.JSON, response, prudent.proto.v1.UpdateImportRowResponse.newBuilder())
            .build();
    assertEquals(1, body.getRow().getRowNumber());
    assertTrue(body.getRow().getIncludeDuplicate());
    assertEquals("kept", body.getRow().getNote());
    assertEquals(1, body.getAcceptedRows());
    assertEquals(1, body.getDuplicateRows());
    assertEquals(0, body.getRejectedRows());
    assertFalse(response.asString().contains("\"rows\""), "no session, no other row");
    assertFalse(response.asString().contains("SKLEP B"), "no other row's content");
  }

  @Test
  void anIncomingOwnTransfer_carriesTheHintAndNoOtherRowDoes() throws Exception {
    SessionView view =
        bare(
            statement(
                card("10-03-2026", "SKLEP A TESTOWY", "-7,10", 1),
                ownTransfer("09-03-2026", "500,00", 2)),
            erste);

    assertNull(view.rows().get(0).hintCode);
    assertEquals(ParsedRow.HINT_OWN_ACCOUNT_TRANSFER, view.rows().get(1).hintCode);
    ImportSession wire =
        ImportTestSupport.session(ImportTestSupport.get(view.session().id.toString()));
    assertEquals("", wire.getRows(0).getHintCode());
    assertEquals("transfer.own_account", wire.getRows(1).getHintCode());
  }

  @Test
  void aNoteOverFiveHundredCharacters_isRefused_andFiveHundredIsKept() {
    SessionView view = bare(threeRows(), erste);
    UUID id = view.session().id;

    PrudentException refused =
        assertThrows(
            PrudentException.class,
            () -> workflow.updateRow(ALICE, id, 1, null, false, "x".repeat(501), null));
    assertEquals(400, refused.status().getStatusCode());

    ImportWorkflow.RowDecision ok =
        workflow.updateRow(ALICE, id, 1, null, false, "  " + "y".repeat(500) + "  ", null);
    assertEquals(500, ok.row().note.length());
  }

  @Test
  void committingAStatementImportedInFull_completesWithNothingWritten() {
    importOnce(twoRows());
    SessionView again = bare(twoRows(), erste);
    assertEquals(0, again.session().acceptedRows);
    assertEquals(2, again.session().duplicateRows);

    SessionView done = workflow.commit(ALICE, again.session().id, 0);

    assertEquals(ImportState.COMMITTED, done.session().state);
    assertEquals(0, done.session().committedWritten);
    assertEquals(0, done.session().committedAlreadyImported);
    assertEquals(2, records(), "the ledger is unchanged");
    assertEquals(0, ImportRowEntity.count(), "no staging row is left");
  }

  // --- privacy ---------------------------------------------------------------------------------

  @Test
  void afterACommit_nothingOfTheStatementPersists_andTheResponseCarriesCountsOnly() throws Exception {
    SessionView view = previewed(threeRows(), erste);
    String id = view.session().id.toString();
    ImportTestSupport.post(
        ImportTestSupport.SESSIONS + "/" + id + "/rows/1",
        prudent.proto.v1.UpdateImportRowRequest.newBuilder().setNote("my own note").build());

    Response response = ImportTestSupport.commit(id, 3);
    ImportSession done = ImportTestSupport.session(response);

    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_COMMITTED, done.getState());
    assertEquals(3, done.getCommittedWritten());
    assertEquals(0, done.getRowsCount());
    String body = response.asString();
    assertFalse(body.contains("SKLEP"));
    assertFalse(body.contains("my own note"));
    assertFalse(body.contains("PŁATNOŚĆ"));
    ImportSessionEntity stored =
        QuarkusTransaction.requiringNew().call(() -> ImportSessionEntity.findById(UUID.fromString(id)));
    assertNull(stored.statementIdentity);
    assertEquals(0, ImportRowEntity.count(), "no statement row is kept after the commit");
  }
}
