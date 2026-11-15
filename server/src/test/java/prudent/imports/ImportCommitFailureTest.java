package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static prudent.imports.ImportTestSupport.commit;
import static prudent.imports.ImportTestSupport.defaults;
import static prudent.imports.ImportTestSupport.discard;
import static prudent.imports.ImportTestSupport.error;
import static prudent.imports.ImportTestSupport.get;
import static prudent.imports.ImportTestSupport.preview;
import static prudent.imports.ImportTestSupport.session;
import static prudent.imports.ImportTestSupport.uploadErste;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import jakarta.inject.Inject;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.account.AccountBalance;
import prudent.account.AccountEntity;
import prudent.category.CategoryEntity;
import prudent.error.PrudentException;
import prudent.imports.ImportTestSupport.Erste;
import prudent.proto.v1.ImportSession;
import prudent.proto.v1.ImportSessionState;
import prudent.record.RecordEntity;
import prudent.record.RecordWriter;
import zen.proto.v1.ZenError;

/**
 * What happens when the world changes between the preview and the commit, and when a phase fails
 * (M6, jlogicsoftware/prudent#77, ADR-094), through the real HTTP API with the real Erste importer
 * and ledger committer. Each case checks the same four things: the refusal says which rule and which
 * rows and quotes no text, the ledger and the accounts are exactly as they were, the session is
 * still open so the user can fix the cause, and the retry after the fix writes the statement once.
 */
@QuarkusTest
@TestSecurity(user = PrudentTest.ALICE)
class ImportCommitFailureTest {

  private static final UUID ALICE = UUID.fromString(PrudentTest.ALICE);
  private static final long BASE_NET = -710 - 2500 + 10000 - 300 - 100;

  @Inject ImportWorkflow workflow;

  private UUID erste;
  private UUID spending;
  private UUID income;
  private UUID other;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    erste = PrudentTest.seedAccount(PrudentTest.ALICE, "Erste", "PLN");
    spending = PrudentTest.seedCategory(PrudentTest.ALICE, "Spending");
    income = PrudentTest.seedCategory(PrudentTest.ALICE, "Income");
    other = PrudentTest.seedCategory(PrudentTest.ALICE, "Other");
    QuarkusTransaction.requiringNew()
        .run(() -> AccountEntity.<AccountEntity>findById(erste).accountNumber = Erste.ACCOUNT);
  }

  // --- helpers ---------------------------------------------------------------------------------

  private ImportSession previewed() throws Exception {
    ImportSession parsed = session(uploadErste(Erste.baseBytes(), erste));
    session(preview(parsed.getId(), erste));
    defaults(parsed.getId(), spending, income);
    return parsed;
  }

  private static long records() {
    return RecordEntity.count();
  }

  private long net() {
    return QuarkusTransaction.requiringNew()
        .call(() -> RecordEntity.netByAccount(ALICE, erste).getOrDefault("PLN", 0L));
  }

  private void edit(UUID account, java.util.function.Consumer<AccountEntity> change) {
    QuarkusTransaction.requiringNew()
        .run(() -> change.accept(AccountEntity.<AccountEntity>findById(account)));
  }

  private void editCategory(UUID category, java.util.function.Consumer<CategoryEntity> change) {
    QuarkusTransaction.requiringNew()
        .run(() -> change.accept(CategoryEntity.<CategoryEntity>findById(category)));
  }

  private static void assertRule(ZenError refused, String message) {
    assertEquals(message, refused.getMessage());
    assertEquals("conflict", refused.getCode());
    assertFalse(refused.getMessage().contains("Spending") || refused.getMessage().contains("Erste"));
  }

  private void assertStillOpenAndEmpty(String id) throws Exception {
    assertEquals(0, records());
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, session(get(id)).getState());
    assertEquals(5, session(get(id)).getRowsCount(), "the review is still there to be fixed");
  }

  // --- the world changes after the preview ------------------------------------------------------

  @Test
  void aCategoryRemovedAfterItWasChosenIsNamedByRuleAndRowsAndNothingIsWritten() throws Exception {
    ImportSession session = previewed();
    // The expense default is deleted: rows 1, 2, 4 and 5 are expenses; row 3 is income.
    QuarkusTransaction.requiringNew().run(() -> CategoryEntity.deleteById(spending));

    ZenError refused = error(commit(session.getId(), 5), 409);

    assertRule(refused, "The statement was rejected at rows 1, 2, 4, 5 (commit.category_unavailable).");
    assertStillOpenAndEmpty(session.getId());

    // The fix is a new default; the same commit then succeeds once.
    defaults(session.getId(), other, income);
    assertEquals(5, session(commit(session.getId(), 5)).getCommittedWritten());
    assertEquals(BASE_NET, net());
  }

  @Test
  void aCategoryArchivedAfterItWasChosenForOneRowIsNamedByThatRow() throws Exception {
    ImportSession session = previewed();
    UUID id = UUID.fromString(session.getId());
    workflow.updateRow(ALICE, id, 2, other, false, null, null);
    editCategory(other, c -> c.archivedAt = Instant.now());

    ZenError refused = error(commit(session.getId(), 5), 409);

    assertRule(refused, "The statement was rejected at row 2 (commit.category_unavailable).");
    assertStillOpenAndEmpty(session.getId());

    editCategory(other, c -> c.archivedAt = null);
    assertEquals(5, session(commit(session.getId(), 5)).getCommittedWritten());
  }

  @Test
  void aCategoryThatNowSuitsTheOtherDirectionIsRefusedForTheRowsItCannotFile() throws Exception {
    ImportSession session = previewed();
    // Expense-only (kind 1) after the statement's income row chose it as the default.
    editCategory(income, c -> c.kind = 1);

    ZenError refused = error(commit(session.getId(), 5), 409);

    assertRule(refused, "The statement was rejected at row 3 (commit.category_unavailable).");
    assertStillOpenAndEmpty(session.getId());
  }

  @Test
  void aStatementWhoseEveryRowLostItsCategoryNamesTenRowsAndCountsTheRest() throws Exception {
    ImportSession parsed = session(uploadErste(ImportTestSupport.Erste.manyCards(13), erste));
    session(preview(parsed.getId(), erste));
    defaults(parsed.getId(), spending, income);
    QuarkusTransaction.requiringNew().run(() -> CategoryEntity.deleteById(spending));

    ZenError refused = error(commit(parsed.getId(), 13), 409);

    assertRule(
        refused,
        "The statement was rejected at rows 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 and 3 more"
            + " (commit.category_unavailable).");
    assertEquals(0, records());
  }

  @Test
  void anAccountRenumberedAfterThePreviewIsRefusedAndTheOldNumberRestoresIt() throws Exception {
    ImportSession session = previewed();
    edit(erste, a -> a.accountNumber = Erste.OTHER_ACCOUNT);

    assertRule(
        error(commit(session.getId(), 5), 409),
        "The statement was rejected (account.identity_mismatch).");
    assertStillOpenAndEmpty(session.getId());

    edit(erste, a -> a.accountNumber = null);
    assertRule(
        error(commit(session.getId(), 5), 409),
        "The statement was rejected (account.number_missing).");
    assertEquals(0, records());

    edit(erste, a -> a.accountNumber = Erste.ACCOUNT);
    assertEquals(5, session(commit(session.getId(), 5)).getCommittedWritten());
  }

  @Test
  void anAccountThatStoppedBeingUsableIsNamedByRuleAndNothingIsWritten() throws Exception {
    ImportSession session = previewed();
    String unavailable = "The statement was rejected (commit.account_unavailable).";

    edit(erste, a -> a.isActive = false);
    assertRule(error(commit(session.getId(), 5), 409), unavailable);
    assertStillOpenAndEmpty(session.getId());
    edit(erste, a -> a.isActive = true);

    edit(
        erste,
        a -> {
          a.balances.clear();
          a.balances.add(new AccountBalance("EUR", 0L));
        });
    assertRule(error(commit(session.getId(), 5), 409), unavailable);
    assertEquals(0, records());
    edit(
        erste,
        a -> {
          a.balances.clear();
          a.balances.add(new AccountBalance("PLN", 0L));
        });

    assertEquals(5, session(commit(session.getId(), 5)).getCommittedWritten());
    assertEquals(BASE_NET, net());
  }

  @Test
  void aDestinationDeletedTogetherWithItsRecordsCannotReceiveTheCommit() throws Exception {
    PrudentTest.seedRecord(PrudentTest.ALICE, erste, spending, -500L, "PLN");
    ImportSession session = previewed();

    Response deleted =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/accounts/" + erste + "?deleteRecords=true")
            .andReturn();
    assertEquals(204, deleted.statusCode(), deleted.asString());
    assertEquals(0, records(), "the account's own record went with it, by the user's own request");

    assertRule(
        error(commit(session.getId(), 5), 409),
        "The statement was rejected (commit.account_unavailable).");
    assertEquals(0, records(), "no record was written for an account that no longer exists");
    assertEquals(
        ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, session(get(session.getId())).getState());
    // The review is still there to be discarded or pointed at another account.
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_DISCARDED, session(discard(session.getId())).getState());
  }

  // --- the session ends under the user -------------------------------------------------------------

  @Test
  void aSessionThatExpiredMidFlowCannotBeCommittedAndIsEndedBySeeingIt() throws Exception {
    ImportSession session = previewed();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              ImportSessionEntity entity =
                  ImportSessionEntity.<ImportSessionEntity>findById(UUID.fromString(session.getId()));
              // A session that is over is also old: the schema keeps the expiry after the creation.
              entity.createdAt = Instant.now().minusSeconds(7200);
              entity.stateChangedAt = entity.createdAt;
              entity.expiresAt = Instant.now().minusSeconds(1);
            });

    ZenError refused = error(commit(session.getId(), 5), 409);
    assertTrue(refused.getMessage().contains("expired"), refused.getMessage());
    assertEquals(0, records());

    ImportSession read = session(get(session.getId()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_EXPIRED, read.getState());
    assertEquals(0, read.getRowsCount(), "the statement's rows are gone with the session");
    assertEquals(0, ImportRowEntity.count());

    // Starting again is straightforward.
    ImportSession again = previewed();
    assertEquals(5, session(commit(again.getId(), 5)).getCommittedWritten());
  }

  @Test
  void twoTabsOnOneSession_theSecondCommitIsTheSameAnswerOrAClearConflict() throws Exception {
    ImportSession session = previewed();
    assertEquals(5, session(commit(session.getId(), 5)).getCommittedWritten());
    long after = records();

    // Tab B still shows the review and confirms the same count: a retry of the same commit.
    assertEquals(5, session(commit(session.getId(), 5)).getCommittedWritten());
    // Tab B's count was stale: refused, nothing written.
    assertTrue(error(commit(session.getId(), 4), 409).getMessage().contains("different number"));
    // Tab B can no longer preview or change anything.
    error(preview(session.getId(), erste), 409);
    error(defaults2(session.getId()), 409);
    assertEquals(after, records());
  }

  private static Response defaults2(String id) throws Exception {
    return ImportTestSupport.post(
        ImportTestSupport.SESSIONS + "/" + id + "/defaults",
        prudent.proto.v1.SetImportDefaultsRequest.newBuilder()
            .setDefaultExpenseCategoryId(UUID.randomUUID().toString())
            .build());
  }

  @Test
  void aDiscardAndACommitOfOneSession_inEitherOrder_endInOneStateAndWriteAtMostOnce() throws Exception {
    ImportSession discardedFirst = previewed();
    session(discard(discardedFirst.getId()));
    error(commit(discardedFirst.getId(), 5), 409);
    assertEquals(0, records());

    ImportSession committedFirst = previewed();
    session(commit(committedFirst.getId(), 5));
    error(discard(committedFirst.getId()), 409);
    assertEquals(
        ImportSessionState.IMPORT_SESSION_STATE_COMMITTED, session(get(committedFirst.getId())).getState());
    assertEquals(5, records(), "the discard did not undo the commit");
  }

  // --- a phase fails ---------------------------------------------------------------------------------

  /** A parse that fails inside the importer, as a bug would. */
  static final class BrokenImporter extends ErsteStatementImporter {
    @Override
    public ParsedStatement parse(byte[] content, ImportContext context) {
      throw new IllegalStateException("injected parse failure");
    }
  }

  @Test
  void aParseThatFailsUnexpectedly_isA500WithNoStatementTextAndLeavesNoSession() throws Exception {
    QuarkusMock.installMockForType(new BrokenImporter(), ErsteStatementImporter.class);

    Response response = uploadErste(Erste.baseBytes(), erste);

    assertEquals(500, response.statusCode());
    assertFalse(response.asString().contains("TESTOWY") || response.asString().contains("SKLEP"));
    assertEquals(0, ImportSessionEntity.count());
    assertEquals(0, ImportRowEntity.count());

    QuarkusMock.installMockForType(new ErsteStatementImporter(), ErsteStatementImporter.class);
    assertEquals(5, session(uploadErste(Erste.baseBytes(), erste)).getAcceptedRows());
  }

  /** A preview stage that fails, as a bug in duplicate detection would. */
  static final class BrokenStage extends ImportDuplicateStage {
    static volatile boolean failing = true;
    private final ImportDuplicateStage real;

    BrokenStage(ImportDuplicateStage real) {
      this.real = real;
    }

    @Override
    public void apply(ImportSessionEntity session, List<ImportRowEntity> rows) {
      if (failing) {
        throw new IllegalStateException("injected preview failure");
      }
      real.apply(session, rows);
    }
  }

  @Inject ImportDuplicateStage stage;

  @Test
  void aPreviewThatFailsUnexpectedly_leavesTheSessionParsedAndItsRowsAlone() throws Exception {
    ImportSession parsed = session(uploadErste(Erste.baseBytes(), null));
    BrokenStage.failing = true;
    QuarkusMock.installMockForType(
        new BrokenStage(io.quarkus.arc.ClientProxy.unwrap(stage)), ImportDuplicateStage.class);

    Response response = preview(parsed.getId(), erste);

    assertEquals(500, response.statusCode());
    ImportSession kept = session(get(parsed.getId()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PARSED, kept.getState());
    assertFalse(kept.hasAccountId(), "the destination chosen in the failed preview was not kept");
    assertEquals(5, kept.getRowsCount());

    BrokenStage.failing = false;
    assertEquals(
        ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, session(preview(parsed.getId(), erste)).getState());
  }

  @Test
  void aLedgerFailureAtAnyRowOfTheCommit_writesNothing_andTheRetryWritesTheStatementOnce() throws Exception {
    for (int failAt = 1; failAt <= 5; failAt++) {
      PrudentTest.reset();
      seed();
      ImportSession session = previewed();
      QuarkusMock.installMockForType(new ImportCommitTest.FailingWriter(failAt), RecordWriter.class);

      Response response = commit(session.getId(), 5);

      assertEquals(500, response.statusCode(), "failure at row " + failAt);
      assertFalse(response.asString().contains("TESTOWY") || response.asString().contains("SKLEP"));
      assertStillOpenAndEmpty(session.getId());

      QuarkusMock.installMockForType(new RecordWriter(), RecordWriter.class);
      assertEquals(5, session(commit(session.getId(), 5)).getCommittedWritten(), "retry after row " + failAt);
      assertEquals(BASE_NET, net());
      assertEquals(5, records());
    }
  }

  /** A writer that refuses a row with a sentence that quotes what it was given. */
  static final class QuotingWriter extends RecordWriter {
    @Override
    public void apply(
        RecordEntity entity, UUID userId, String title, long amountMinor, String date,
        String categoryId, String accountId, String currency, String payee, String note) {
      throw PrudentException.invalid("Refused '" + title + "' of '" + payee + "'");
    }
  }

  @Test
  void aRowTheLedgerRefusesIsNamedByRuleAndRowAndNeverQuoted() throws Exception {
    ImportSession session = previewed();
    QuarkusMock.installMockForType(new QuotingWriter(), RecordWriter.class);

    ZenError refused = error(commit(session.getId(), 5), 409);

    assertRule(refused, "The statement was rejected at row 1 (commit.row_refused).");
    assertFalse(refused.getMessage().contains("SKLEP"));
    assertStillOpenAndEmpty(session.getId());

    QuarkusMock.installMockForType(new RecordWriter(), RecordWriter.class);
    assertEquals(5, session(commit(session.getId(), 5)).getCommittedWritten());
  }

  @Test
  void anotherUsersSessionAndLedgerAreNeverTouchedByAFailedCommit() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's", "PLN");
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Bob's category");
    PrudentTest.seedRecord(PrudentTest.BOB, bobsAccount, bobsCategory, -42L, "PLN");
    UUID bobsSession =
        PrudentTest.seedImportSession(PrudentTest.BOB, ImportState.PREVIEWED, Instant.now().plusSeconds(3600));
    long bobsRecords = RecordEntity.count("userId", UUID.fromString(PrudentTest.BOB));

    ImportSession session = previewed();
    QuarkusTransaction.requiringNew().run(() -> CategoryEntity.deleteById(spending));
    error(commit(session.getId(), 5), 409);
    // Alice cannot reach Bob's session by id, whatever she asks of it.
    error(commit(bobsSession.toString(), 1), 404);
    error(preview(bobsSession.toString(), erste), 404);
    error(discard(bobsSession.toString()), 404);

    assertEquals(bobsRecords, RecordEntity.count("userId", UUID.fromString(PrudentTest.BOB)));
    assertEquals(
        ImportState.PREVIEWED,
        QuarkusTransaction.requiringNew()
            .call(() -> ImportSessionEntity.<ImportSessionEntity>findById(bobsSession).state));
  }
}
