package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static prudent.imports.ImportTestSupport.SESSIONS;
import static prudent.imports.ImportTestSupport.commit;
import static prudent.imports.ImportTestSupport.error;
import static prudent.imports.ImportTestSupport.get;
import static prudent.imports.ImportTestSupport.installRecordingCommitter;
import static prudent.imports.ImportTestSupport.post;
import static prudent.imports.ImportTestSupport.preview;
import static prudent.imports.ImportTestSupport.session;
import static prudent.imports.ImportTestSupport.statement;
import static prudent.imports.ImportTestSupport.upload;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.account.AccountBalance;
import prudent.account.AccountEntity;
import prudent.proto.v1.ImportSession;
import prudent.proto.v1.ImportSessionState;
import prudent.proto.v1.PreviewImportSessionRequest;
import zen.proto.v1.ZenError;

/**
 * Where an import may be written (ADR-089): the destination account is checked wherever it is set or
 * replaced — parse, preview, a repeated preview — and again at commit, for ownership, being active,
 * holding the session's currency and, through {@link StatementImporter#checkDestination}, being the
 * account the statement is for. The test importer's "account number" is the account's name.
 */
@QuarkusTest
@TestSecurity(user = PrudentTest.ALICE)
class ImportDestinationTest {

  /** The statement is "for" the account named Checking. */
  private static final String FOR_CHECKING = "PLN;Checking";

  @Inject EntityManager entityManager;

  private UUID checking;
  private UUID savings;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    checking = PrudentTest.seedAccount(PrudentTest.ALICE, "Checking", "PLN");
    savings = PrudentTest.seedAccount(PrudentTest.ALICE, "Savings", "PLN");
  }

  private void edit(UUID accountId, java.util.function.Consumer<AccountEntity> change) {
    QuarkusTransaction.requiringNew()
        .run(() -> change.accept(AccountEntity.<AccountEntity>findById(accountId)));
  }

  private static void assertNoSensitiveText(ZenError refused) {
    String text = refused.getMessage();
    assertFalse(text.contains("Checking") || text.contains("Savings"), text);
    assertFalse(text.matches("(?s).*[0-9a-f]{20}.*"), "a digest must not be echoed: " + text);
  }

  @Test
  void parseIntoAnAccountThatIsNotTheStatementsOwn_isRefusedAndWritesNothing() throws Exception {
    ZenError refused = error(upload(statement(FOR_CHECKING, "TEST a"), savings), 400);
    assertTrue(refused.getMessage().contains("account.identity_mismatch"), refused.getMessage());
    assertNoSensitiveText(refused);
    assertEquals(0, ImportTestSupport.count(entityManager, "ImportSessionEntity"));
    assertEquals(0, ImportTestSupport.count(entityManager, "ImportRowEntity"));

    ImportSession opened = session(upload(statement(FOR_CHECKING, "TEST a"), checking));
    assertEquals(checking.toString(), opened.getAccountId());
  }

  @Test
  void changingTheAccountAtPreviewIsCheckedLikeTheFirstChoice() throws Exception {
    // Parsed with no account (so nothing was checked at parse), then previewed into the wrong one.
    ImportSession parsed = session(upload(statement(FOR_CHECKING, "TEST a"), null));

    ZenError refused = error(preview(parsed.getId(), savings), 400);
    assertTrue(refused.getMessage().contains("account.identity_mismatch"));
    assertNoSensitiveText(refused);
    assertEquals(
        ImportSessionState.IMPORT_SESSION_STATE_PARSED, session(get(parsed.getId())).getState());

    assertEquals(
        ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED,
        session(preview(parsed.getId(), checking)).getState());
  }

  @Test
  void parsedForOneAccountPreviewedIntoAnotherAndCommittedNeverGetsThrough() throws Exception {
    ImportTestSupport.RecordingCommitter committer = installRecordingCommitter(0);
    ImportSession parsed = session(upload(statement(FOR_CHECKING, "TEST a"), checking));
    session(preview(parsed.getId(), checking));

    // Replacing the account on a repeated preview is checked and refused; the first choice stands.
    error(preview(parsed.getId(), savings), 400);
    ImportSession kept = session(get(parsed.getId()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, kept.getState());
    assertEquals(checking.toString(), kept.getAccountId());

    assertEquals(
        ImportSessionState.IMPORT_SESSION_STATE_COMMITTED,
        session(commit(parsed.getId(), 1)).getState());
    assertEquals(1, committer.calls.size());
  }

  @Test
  void commitChecksTheDestinationAgainWhenTheAccountChangedAfterThePreview() throws Exception {
    ImportTestSupport.RecordingCommitter committer = installRecordingCommitter(0);
    ImportSession parsed = session(upload(statement(FOR_CHECKING, "TEST a"), checking));
    session(preview(parsed.getId(), checking));

    // The account stops being the statement's own (stand-in: it is renamed) before the commit.
    edit(checking, account -> account.name = "Renamed");
    ZenError refused = error(commit(parsed.getId(), 1), 409);
    assertTrue(refused.getMessage().contains("account.identity_mismatch"));
    assertNoSensitiveText(refused);
    assertTrue(committer.calls.isEmpty());
    assertEquals(
        ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, session(get(parsed.getId())).getState());
  }

  @Test
  void aStatementWithNoIdentityFitsAnyOfTheCallersAccounts() throws Exception {
    ImportSession parsed = session(upload(statement("PLN", "TEST a"), null));
    assertEquals(
        savings.toString(), session(preview(parsed.getId(), savings)).getAccountId());
    assertEquals(
        checking.toString(), session(preview(parsed.getId(), checking)).getAccountId());
  }

  @Test
  void aSessionThatIsPreviewedAgainWithAnotherAccountMovesAndKeepsItsClassification()
      throws Exception {
    ImportSession parsed = session(upload(statement("PLN", "TEST a", "TEST DUPLICATEME"), null));
    ImportSession first = session(preview(parsed.getId(), checking));
    ImportSession second = session(preview(parsed.getId(), savings));

    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, second.getState());
    assertEquals(savings.toString(), second.getAccountId());
    assertEquals(first.getAcceptedRows(), second.getAcceptedRows());
    assertEquals(1, second.getDuplicateRows());
    assertEquals(first.getRowsList(), second.getRowsList());
  }

  @Test
  void anAccountThatDoesNotHoldTheSessionsCurrencyIsRefusedAtEveryStep() throws Exception {
    UUID usdOnly = PrudentTest.seedAccount(PrudentTest.ALICE, "Dollars", "USD");

    assertTrue(
        error(upload(statement("PLN", "TEST a"), usdOnly), 400).getMessage().contains("PLN"));
    ImportSession parsed = session(upload(statement("PLN", "TEST a"), null));
    error(preview(parsed.getId(), usdOnly), 400);
    assertEquals(
        ImportSessionState.IMPORT_SESSION_STATE_PARSED, session(get(parsed.getId())).getState());

    // Commit: the account stops holding PLN after it was chosen.
    ImportTestSupport.RecordingCommitter committer = installRecordingCommitter(0);
    session(preview(parsed.getId(), savings));
    edit(
        savings,
        account -> {
          account.balances.clear();
          account.balances.add(new AccountBalance("USD", 0L));
        });
    assertTrue(error(commit(parsed.getId(), 1), 409).getMessage().contains("PLN"));
    assertTrue(committer.calls.isEmpty());
  }

  @Test
  void anInactiveAccountIsRefusedAtEveryStep() throws Exception {
    UUID retired = PrudentTest.seedAccount(PrudentTest.ALICE, "Retired", "PLN");
    edit(retired, account -> account.isActive = false);

    assertTrue(
        error(upload(statement("PLN", "TEST a"), retired), 400).getMessage().contains("inactive"));
    ImportSession parsed = session(upload(statement("PLN", "TEST a"), null));
    error(preview(parsed.getId(), retired), 400);

    ImportTestSupport.RecordingCommitter committer = installRecordingCommitter(0);
    session(preview(parsed.getId(), savings));
    edit(savings, account -> account.isActive = false);
    assertTrue(error(commit(parsed.getId(), 1), 409).getMessage().contains("inactive"));
    assertTrue(committer.calls.isEmpty());
  }

  @Test
  void anAccountThatIsNotTheCallersIsStillRefused() throws Exception {
    UUID bobs = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's", "PLN");
    error(upload(statement("PLN", "TEST a"), bobs), 400);
    ImportSession parsed = session(upload(statement("PLN", "TEST a"), null));
    error(preview(parsed.getId(), bobs), 400);
  }

  @Test
  void theStatementIdentityIsKeptWhileOpenAndClearedWhenTheSessionEnds() throws Exception {
    installRecordingCommitter(0);
    ImportSession parsed = session(upload(statement(FOR_CHECKING, "TEST a"), checking));
    UUID id = UUID.fromString(parsed.getId());
    assertEquals(
        ParsedStatement.identityOf("Checking"),
        QuarkusTransaction.requiringNew()
            .call(() -> ImportSessionEntity.<ImportSessionEntity>findById(id).statementIdentity));

    session(preview(parsed.getId(), checking));
    session(commit(parsed.getId(), 1));
    assertNull(
        QuarkusTransaction.requiringNew()
            .call(() -> ImportSessionEntity.<ImportSessionEntity>findById(id).statementIdentity));

    ImportSession discarded = session(upload(statement(FOR_CHECKING, "TEST a"), null));
    session(post(SESSIONS + "/" + discarded.getId() + "/discard",
        PreviewImportSessionRequest.getDefaultInstance()));
    UUID discardedId = UUID.fromString(discarded.getId());
    assertNull(
        QuarkusTransaction.requiringNew()
            .call(
                () -> ImportSessionEntity.<ImportSessionEntity>findById(discardedId).statementIdentity));
  }

  // --- The default hook and the identity token ------------------------------------------------

  @Test
  void theDefaultHookAcceptsAStatementWithoutIdentityAndRefusesWhatItCannotVerify() {
    StatementImporter plain =
        new StatementImporter() {
          @Override
          public String formatId() {
            return "plain";
          }

          @Override
          public ParsedStatement parse(byte[] content, ImportContext context) {
            throw new UnsupportedOperationException();
          }
        };
    plain.checkDestination(null, null);
    ImportRejectedException refused =
        assertThrows(
            ImportRejectedException.class,
            () -> plain.checkDestination(ParsedStatement.identityOf("XX00 TEST 0001"), null));
    assertEquals("account.identity_unverifiable", refused.rule());
  }

  @Test
  void identityOfIsStableAcrossSpacingAndCaseAndIsADigest() {
    String a = ParsedStatement.identityOf("xx00 test 0001 0002");
    assertEquals(a, ParsedStatement.identityOf("XX00TEST00010002"));
    assertTrue(a.matches("[0-9a-f]{64}"));
    assertFalse(a.equals(ParsedStatement.identityOf("XX00TEST00010003")));
    assertThrows(IllegalArgumentException.class, () -> ParsedStatement.identityOf(" "));
    assertThrows(IllegalArgumentException.class, () -> ParsedStatement.identityOf(null));
  }
}
