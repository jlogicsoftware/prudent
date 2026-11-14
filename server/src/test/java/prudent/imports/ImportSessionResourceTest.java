package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.protobuf.ByteString;
import com.google.protobuf.Message;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.proto.v1.CommitImportSessionRequest;
import prudent.proto.v1.CreateImportSessionRequest;
import prudent.proto.v1.ImportRow;
import prudent.proto.v1.ImportRowStatus;
import prudent.proto.v1.ImportSession;
import prudent.proto.v1.ImportSessionState;
import prudent.proto.v1.ListImportSessionsResponse;
import prudent.proto.v1.PreviewImportSessionRequest;
import prudent.record.RecordEntity;
import zen.proto.v1.ZenError;

/**
 * The import workflow end to end (M6, jlogicsoftware/prudent#72, ADR-089): parse, preview and commit
 * are separate and enforced, a rejected statement writes nothing, the statement itself is never
 * kept, and a session is its owner's alone. The importer is the test-only {@link
 * TestStatementImporter}; the Erste parser is jlogicsoftware/prudent#73.
 */
@QuarkusTest
@TestSecurity(user = PrudentTest.ALICE)
class ImportSessionResourceTest {

  private static final String SESSIONS = "/api/v1/import-sessions";
  /** Present only in the discarded fourth field of the statements below. */
  private static final String RAW_MARKER = "RAWSECRETMARKER";

  @Inject EntityManager entityManager;
  @Inject ImportWorkflow workflow;

  private UUID alicesAccount;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    alicesAccount = PrudentTest.seedAccount(PrudentTest.ALICE, "Checking", "PLN");
  }

  // --- Helpers ----------------------------------------------------------------------------------

  /** Two good rows, one rejected row (a non-numeric amount) and one duplicate-to-be. */
  private static String statement() {
    return String.join(
        "\n",
        "PLN",
        "2026-11-03;-1250;TEST coffee;" + RAW_MARKER + "-1",
        "2026-11-02;45000;TEST salary;" + RAW_MARKER + "-2",
        "2026-11-01;abc;TEST broken;" + RAW_MARKER + "-3",
        "2026-10-30;-300;TEST DUPLICATEME;" + RAW_MARKER + "-4",
        "");
  }

  private static CreateImportSessionRequest.Builder upload(String format, String content) {
    return CreateImportSessionRequest.newBuilder()
        .setFormatId(format)
        .setContent(ByteString.copyFrom(content, StandardCharsets.UTF_8));
  }

  private static Response post(String path, Message body, String mode)
      throws Exception {
    return PrudentTest.body(PrudentTest.request(mode), mode, body).when().post(path).andReturn();
  }

  private static Response post(String path, Message body) throws Exception {
    return post(path, body, PrudentTest.JSON);
  }

  private static ImportSession session(Response response, String mode) throws Exception {
    assertTrue(response.statusCode() < 300, response.asString());
    return PrudentTest.decode(mode, response, ImportSession.newBuilder()).build();
  }

  private static ImportSession session(Response response) throws Exception {
    return session(response, PrudentTest.JSON);
  }

  private static ZenError error(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  private static ImportSession parse(String content) throws Exception {
    return session(post(SESSIONS, upload(TestStatementImporter.FORMAT, content).build()));
  }

  private static Response commit(String id, int confirmed) throws Exception {
    return post(
        SESSIONS + "/" + id + "/commit",
        CommitImportSessionRequest.newBuilder().setConfirmedAcceptedRows(confirmed).build());
  }

  private static Response get(String id) {
    return PrudentTest.request(PrudentTest.JSON).when().get(SESSIONS + "/" + id).andReturn();
  }

  private long count(String entity) {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                ((Number)
                        entityManager
                            .createQuery("select count(e) from " + entity + " e")
                            .getSingleResult())
                    .longValue());
  }

  private void assertNothingWritten() {
    assertEquals(0, count("ImportSessionEntity"), "a session was written");
    assertEquals(0, count("ImportRowEntity"), "a row was written");
    assertEquals(0, RecordEntity.count(), "a ledger record was written");
  }

  /** Records the commit instead of refusing it, so the happy path can be driven before #76. */
  private static final class RecordingCommitter extends UnavailableImportCommitter {
    final List<List<ImportRowEntity>> calls = new ArrayList<>();
    final List<ImportState> stateSeen = new ArrayList<>();

    @Override
    public void commit(ImportSessionEntity session, List<ImportRowEntity> accepted) {
      stateSeen.add(session.state);
      calls.add(new ArrayList<>(accepted));
    }
  }

  private RecordingCommitter installRecordingCommitter() {
    RecordingCommitter committer = new RecordingCommitter();
    // QuarkusMock needs an instance of the bean's own class, hence the subclass.
    QuarkusMock.installMockForType(committer, UnavailableImportCommitter.class);
    return committer;
  }

  // --- Parse ------------------------------------------------------------------------------------

  @Test
  void parse_opensAParsedSessionWithNormalisedRows_inBothModes() throws Exception {
    for (String mode : List.of(PrudentTest.JSON, PrudentTest.PROTOBUF)) {
      Response response = post(SESSIONS, upload(TestStatementImporter.FORMAT, statement()).build(), mode);
      assertEquals(201, response.statusCode(), response.asString());
      ImportSession created = session(response, mode);

      assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PARSED, created.getState());
      assertEquals("PLN", created.getCurrency());
      assertEquals(TestStatementImporter.FORMAT, created.getFormatId());
      assertEquals(4, created.getAcceptedRows() + created.getRejectedRows());
      assertEquals(3, created.getAcceptedRows());
      assertEquals(1, created.getRejectedRows());
      assertEquals(4, created.getRowsCount());
      assertTrue(created.getExpiresAtMs() > created.getCreatedAtMs());
      ImportRow rejected = created.getRows(2);
      assertEquals(ImportRowStatus.IMPORT_ROW_STATUS_REJECTED, rejected.getStatus());
      assertEquals("amount.invalid", rejected.getRejectionCode());
      assertFalse(rejected.hasAmountMinor());
      assertEquals(-1250L, created.getRows(0).getAmountMinor());
    }
  }

  @Test
  void parse_ofAStatementTheImporterRejects_writesNothingAndNamesTheRuleNotTheContent()
      throws Exception {
    ZenError wholeFile = error(post(SESSIONS, upload(TestStatementImporter.FORMAT, "FORBIDDEN\n").build()), 400);
    assertEquals("invalid", wholeFile.getCode());
    assertTrue(wholeFile.getMessage().contains("layout.unsupported"));

    // A bad row after good ones: the good ones must not survive it.
    String badThirdRow =
        "PLN\n2026-11-03;-1250;TEST coffee;x\n2026-11-02;5;TEST salary;x\nnot-a-date;5;TEST;" + RAW_MARKER + "\n";
    ZenError atRow = error(post(SESSIONS, upload(TestStatementImporter.FORMAT, badThirdRow).build()), 400);
    assertTrue(atRow.getMessage().contains("row 3"), atRow.getMessage());
    assertTrue(atRow.getMessage().contains("date.invalid"));
    assertFalse(atRow.getMessage().contains(RAW_MARKER), "the message quoted the statement");

    assertNothingWritten();
  }

  @Test
  void parse_withAnUnknownFormat_isRejectedAsAZenErrorAndWritesNothing() throws Exception {
    // erste-pl-csv is no longer in this list: the Erste importer registers it (ADR-090).
    for (String format : List.of("no-such-bank", "")) {
      ZenError refused = error(post(SESSIONS, upload(format, statement()).build()), 400);
      assertEquals("invalid", refused.getCode());
      assertTrue(refused.getMessage().contains("Unsupported import format"));
      assertTrue(refused.getMessage().contains(TestStatementImporter.FORMAT));
    }
    assertNothingWritten();
  }

  @Test
  void parse_withAnEmptyStatementOrAnAccountThatIsNotTheCallers_isRefused() throws Exception {
    assertEquals("invalid", error(post(SESSIONS, upload(TestStatementImporter.FORMAT, "").build()), 400).getCode());

    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's", "PLN");
    error(
        post(
            SESSIONS,
            upload(TestStatementImporter.FORMAT, statement()).setAccountId(bobsAccount.toString()).build()),
        400);
    error(
        post(SESSIONS, upload(TestStatementImporter.FORMAT, statement()).setAccountId("not-a-uuid").build()),
        400);
    assertNothingWritten();
  }

  // --- The statement is never kept ---------------------------------------------------------------

  @Test
  void theUploadedStatementIsNotPersistedAnywhere() throws Exception {
    ImportSession created = parse(statement());
    session(
        post(
            SESSIONS + "/" + created.getId() + "/preview",
            PreviewImportSessionRequest.newBuilder().setAccountId(alicesAccount.toString()).build()));

    @SuppressWarnings("unchecked")
    List<Object> bytea =
        QuarkusTransaction.requiringNew()
            .call(
                () ->
                    entityManager
                        .createNativeQuery(
                            "select table_name || '.' || column_name from information_schema.columns"
                                + " where table_schema = 'public'"
                                + " and table_name in ('prudent_import_session', 'prudent_import_row')"
                                + " and data_type = 'bytea'")
                        .getResultList());
    assertTrue(bytea.isEmpty(), "a binary column can hold the upload: " + bytea);

    for (String table : List.of("prudent_import_session", "prudent_import_row")) {
      @SuppressWarnings("unchecked")
      List<Object> dumps =
          QuarkusTransaction.requiringNew()
              .call(
                  () ->
                      entityManager
                          .createNativeQuery("select t::text from " + table + " t")
                          .getResultList());
      assertFalse(dumps.isEmpty(), table + " is empty, so this proves nothing");
      for (Object dump : dumps) {
        assertFalse(dump.toString().contains(RAW_MARKER), table + " holds raw statement content");
        // The file's own line shape is not reproduced either.
        assertFalse(dump.toString().contains("PLN\n"), table + " holds raw statement content");
      }
    }
  }

  // --- Phases are enforced ----------------------------------------------------------------------

  @Test
  void aSessionThatWasNeverParsedCannotBePreviewedOrCommitted() throws Exception {
    String nothing = UUID.randomUUID().toString();
    error(post(SESSIONS + "/" + nothing + "/preview", PreviewImportSessionRequest.getDefaultInstance()), 404);
    error(commit(nothing, 1), 404);
    error(post(SESSIONS + "/not-a-uuid/preview", PreviewImportSessionRequest.getDefaultInstance()), 404);
  }

  @Test
  void commit_beforePreview_isAConflictAndWritesNothing() throws Exception {
    RecordingCommitter committer = installRecordingCommitter();
    ImportSession parsed = parse(statement());

    ZenError refused = error(commit(parsed.getId(), parsed.getAcceptedRows()), 409);
    assertEquals("conflict", refused.getCode());
    assertTrue(refused.getMessage().contains("Preview"));
    assertTrue(committer.calls.isEmpty());
    assertEquals(
        ImportSessionState.IMPORT_SESSION_STATE_PARSED,
        session(get(parsed.getId())).getState());
  }

  @Test
  void preview_classifiesRows_fixesTheAccount_andMayBeRepeatedWhileOpen() throws Exception {
    ImportSession parsed = parse(statement());

    ImportSession shown =
        session(
            post(
                SESSIONS + "/" + parsed.getId() + "/preview",
                PreviewImportSessionRequest.newBuilder().setAccountId(alicesAccount.toString()).build()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, shown.getState());
    assertEquals(alicesAccount.toString(), shown.getAccountId());
    assertEquals(2, shown.getAcceptedRows());
    assertEquals(1, shown.getDuplicateRows());
    assertEquals(1, shown.getRejectedRows());
    assertEquals(ImportRowStatus.IMPORT_ROW_STATUS_DUPLICATE, shown.getRows(3).getStatus());

    // Omitting the account keeps it and classifies again to the same result.
    ImportSession again =
        session(
            post(
                SESSIONS + "/" + parsed.getId() + "/preview",
                PreviewImportSessionRequest.getDefaultInstance()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, again.getState());
    assertEquals(alicesAccount.toString(), again.getAccountId());
    assertEquals(shown.getAcceptedRows(), again.getAcceptedRows());
    assertEquals(shown.getDuplicateRows(), again.getDuplicateRows());
    assertEquals(shown.getRejectedRows(), again.getRejectedRows());
  }

  @Test
  void preview_withAnAccountThatIsNotTheCallers_isRefusedAndTheSessionStaysParsed() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's", "PLN");
    ImportSession parsed = parse(statement());
    error(
        post(
            SESSIONS + "/" + parsed.getId() + "/preview",
            PreviewImportSessionRequest.newBuilder().setAccountId(bobsAccount.toString()).build()),
        400);
    assertEquals(
        ImportSessionState.IMPORT_SESSION_STATE_PARSED, session(get(parsed.getId())).getState());
  }

  @Test
  void commit_writesOnlyAcceptedRowsOnce_thenEndsTheSessionAndDeletesItsRows() throws Exception {
    RecordingCommitter committer = installRecordingCommitter();
    ImportSession parsed = parse(statement());
    session(
        post(
            SESSIONS + "/" + parsed.getId() + "/preview",
            PreviewImportSessionRequest.newBuilder().setAccountId(alicesAccount.toString()).build()));

    ImportSession done = session(commit(parsed.getId(), 2));

    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_COMMITTED, done.getState());
    assertEquals(0, done.getRowsCount());
    assertEquals(2, done.getAcceptedRows(), "the counts outlive the rows");
    assertEquals(1, committer.calls.size());
    assertEquals(List.of(ImportState.PREVIEWED), committer.stateSeen);
    assertEquals(2, committer.calls.get(0).size());
    assertTrue(committer.calls.get(0).stream().allMatch(row -> row.status == RowStatus.ACCEPTED));
    assertEquals(0, count("ImportRowEntity"), "the personal data is gone once committed");

    ImportSession reread = session(get(parsed.getId()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_COMMITTED, reread.getState());
    assertEquals(0, reread.getRowsCount());

    // Terminal: a second commit (or a discard) is refused, so the committer is not called again.
    error(commit(parsed.getId(), 2), 409);
    error(post(SESSIONS + "/" + parsed.getId() + "/discard", PreviewImportSessionRequest.getDefaultInstance()), 409);
    assertEquals(1, committer.calls.size());
  }

  @Test
  void commit_needsTheConfirmedCountAndADestinationAccount() throws Exception {
    RecordingCommitter committer = installRecordingCommitter();

    ImportSession noAccount = parse(statement());
    session(post(SESSIONS + "/" + noAccount.getId() + "/preview", PreviewImportSessionRequest.getDefaultInstance()));
    assertTrue(error(commit(noAccount.getId(), 2), 409).getMessage().contains("destination account"));

    ImportSession withAccount = parse(statement());
    session(
        post(
            SESSIONS + "/" + withAccount.getId() + "/preview",
            PreviewImportSessionRequest.newBuilder().setAccountId(alicesAccount.toString()).build()));
    for (int wrong : new int[] {0, 1, 3, 4, -1}) {
      assertTrue(error(commit(withAccount.getId(), wrong), 409).getMessage().contains("confirmed"));
    }

    assertTrue(committer.calls.isEmpty());
    ImportSession untouched = session(get(withAccount.getId()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, untouched.getState());
    assertEquals(4, untouched.getRowsCount(), "a refused commit keeps the rows for another try");
  }

  @Test
  void commit_ofASessionWithNothingAccepted_isRefused() throws Exception {
    ImportSession parsed = parse("PLN\n2026-11-01;abc;TEST;x\n2026-11-02;0;TEST;x\n");
    assertEquals(0, parsed.getAcceptedRows());
    session(
        post(
            SESSIONS + "/" + parsed.getId() + "/preview",
            PreviewImportSessionRequest.newBuilder().setAccountId(alicesAccount.toString()).build()));
    assertTrue(error(commit(parsed.getId(), 0), 409).getMessage().contains("no accepted rows"));
  }

  @Test
  void commit_untilTheLedgerWriterExists_answers503AndKeepsTheSessionPreviewed() throws Exception {
    // No committer installed: the default bean is the one that ships until jlogicsoftware/prudent#76.
    ImportSession parsed = parse(statement());
    session(
        post(
            SESSIONS + "/" + parsed.getId() + "/preview",
            PreviewImportSessionRequest.newBuilder().setAccountId(alicesAccount.toString()).build()));

    ZenError unavailable = error(commit(parsed.getId(), 2), 503);
    assertEquals("unavailable", unavailable.getCode());

    ImportSession kept = session(get(parsed.getId()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, kept.getState());
    assertEquals(4, kept.getRowsCount());
    assertEquals(0, RecordEntity.count(), "nothing reached the ledger");
  }

  @Test
  void aCommitterThatFails_leavesTheSessionPreviewedAndItsRowsInPlace() throws Exception {
    QuarkusMock.installMockForType(
        new UnavailableImportCommitter() {
          @Override
          public void commit(ImportSessionEntity session, List<ImportRowEntity> accepted) {
            throw new IllegalStateException("the ledger write failed");
          }
        },
        UnavailableImportCommitter.class);
    ImportSession parsed = parse(statement());
    session(
        post(
            SESSIONS + "/" + parsed.getId() + "/preview",
            PreviewImportSessionRequest.newBuilder().setAccountId(alicesAccount.toString()).build()));

    assertEquals(500, commit(parsed.getId(), 2).statusCode());

    ImportSession kept = session(get(parsed.getId()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, kept.getState());
    assertEquals(4, kept.getRowsCount());
  }

  // --- Discard and expiry -------------------------------------------------------------------------

  @Test
  void discard_endsTheSessionAndDeletesItsRows() throws Exception {
    ImportSession parsed = parse(statement());
    ImportSession discarded =
        session(post(SESSIONS + "/" + parsed.getId() + "/discard", PreviewImportSessionRequest.getDefaultInstance()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_DISCARDED, discarded.getState());
    assertEquals(0, count("ImportRowEntity"));
    assertEquals(1, count("ImportSessionEntity"), "the session row stays, without its content");
    error(post(SESSIONS + "/" + parsed.getId() + "/preview", PreviewImportSessionRequest.getDefaultInstance()), 409);
  }

  @Test
  void anExpiredSession_cannotBePreviewedOrCommitted_andIsEndedByARead() throws Exception {
    UUID due = PrudentTest.seedImportSession(PrudentTest.ALICE, ImportState.PARSED, Instant.now().minusSeconds(5));
    error(post(SESSIONS + "/" + due + "/preview", PreviewImportSessionRequest.getDefaultInstance()), 409);
    assertEquals(1, count("ImportRowEntity"), "a refused preview does not itself delete");

    ImportSession read = session(get(due.toString()));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_EXPIRED, read.getState());
    assertEquals(0, read.getRowsCount());
    assertEquals(0, count("ImportRowEntity"));

    UUID previewedDue =
        PrudentTest.seedImportSession(PrudentTest.ALICE, ImportState.PREVIEWED, Instant.now().minusSeconds(5));
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              ImportSessionEntity s = ImportSessionEntity.findById(previewedDue);
              s.accountId = alicesAccount;
            });
    assertTrue(error(commit(previewedDue.toString(), 1), 409).getMessage().contains("expired"));
  }

  @Test
  void theSweep_expiresOnlyDueSessionsAndDeletesTheirRows() {
    UUID due = PrudentTest.seedImportSession(PrudentTest.ALICE, ImportState.PREVIEWED, Instant.now().minusSeconds(5));
    UUID live = PrudentTest.seedImportSession(PrudentTest.ALICE, ImportState.PARSED, Instant.now().plusSeconds(3600));
    UUID ended = PrudentTest.seedImportSession(PrudentTest.ALICE, ImportState.COMMITTED, Instant.now().minusSeconds(5));

    assertEquals(1, workflow.expireDue());
    assertEquals(0, workflow.expireDue(), "idempotent");

    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              assertEquals(ImportState.EXPIRED, ImportSessionEntity.<ImportSessionEntity>findById(due).state);
              assertEquals(ImportState.PARSED, ImportSessionEntity.<ImportSessionEntity>findById(live).state);
              assertEquals(ImportState.COMMITTED, ImportSessionEntity.<ImportSessionEntity>findById(ended).state);
            });
    assertEquals(1, count("ImportRowEntity"), "only the live session still holds its row");
  }

  // --- Ownership -------------------------------------------------------------------------------

  @Test
  void aSessionIsItsOwnersAlone() throws Exception {
    RecordingCommitter committer = installRecordingCommitter();
    UUID bobs = PrudentTest.seedImportSession(PrudentTest.BOB, ImportState.PREVIEWED, Instant.now().plusSeconds(3600));
    String id = bobs.toString();

    assertEquals(404, get(id).statusCode());
    error(post(SESSIONS + "/" + id + "/preview", PreviewImportSessionRequest.getDefaultInstance()), 404);
    error(commit(id, 1), 404);
    error(post(SESSIONS + "/" + id + "/discard", PreviewImportSessionRequest.getDefaultInstance()), 404);
    ListImportSessionsResponse list =
        PrudentTest.decode(
                PrudentTest.JSON,
                PrudentTest.request(PrudentTest.JSON).when().get(SESSIONS).andReturn(),
                ListImportSessionsResponse.newBuilder())
            .build();
    assertEquals(0, list.getSessionsCount(), "Alice must see none of Bob's sessions");

    assertTrue(committer.calls.isEmpty());
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              ImportSessionEntity untouched = ImportSessionEntity.findById(bobs);
              assertEquals(ImportState.PREVIEWED, untouched.state);
              assertEquals(1, ImportRowEntity.count("sessionId", bobs));
            });
  }

  @Test
  void list_isNewestFirst_hasNoRows_andCanBeNarrowedByState() throws Exception {
    ImportSession first = parse(statement());
    ImportSession second = parse(statement());
    session(post(SESSIONS + "/" + first.getId() + "/discard", PreviewImportSessionRequest.getDefaultInstance()));

    ListImportSessionsResponse all =
        PrudentTest.decode(
                PrudentTest.JSON,
                PrudentTest.request(PrudentTest.JSON).when().get(SESSIONS).andReturn(),
                ListImportSessionsResponse.newBuilder())
            .build();
    assertEquals(2, all.getSessionsCount());
    assertEquals(second.getId(), all.getSessions(0).getId());
    assertEquals(0, all.getSessions(0).getRowsCount());

    Response parsedOnly = PrudentTest.request(PrudentTest.JSON).when().get(SESSIONS + "?state=PARSED").andReturn();
    assertEquals(
        1,
        PrudentTest.decode(PrudentTest.JSON, parsedOnly, ListImportSessionsResponse.newBuilder())
            .getSessionsCount());
    assertEquals(400, PrudentTest.request(PrudentTest.JSON).when().get(SESSIONS + "?state=nope").andReturn().statusCode());
  }
}
