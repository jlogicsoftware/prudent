package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static prudent.imports.ImportTestSupport.SESSIONS;
import static prudent.imports.ImportTestSupport.error;
import static prudent.imports.ImportTestSupport.post;
import static prudent.imports.ImportTestSupport.session;
import static prudent.imports.ImportTestSupport.upload;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.error.PrudentException;
import prudent.proto.v1.ImportSession;
import prudent.proto.v1.PreviewImportSessionRequest;
import zen.proto.v1.ZenError;

/**
 * The bounds on what staging will hold (ADR-089): rows per statement, characters per text field, open
 * sessions per user, and sessions per list response. The limits are the defaults of {@code
 * prudent.import.max-rows} (5000), {@code prudent.import.max-open-sessions} (10) and the list
 * route's cap of 100.
 */
@QuarkusTest
@TestSecurity(user = PrudentTest.ALICE)
class ImportBoundsTest {

  @Inject EntityManager entityManager;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
  }

  private static String rows(int count, String description) {
    StringBuilder text = new StringBuilder("PLN\n");
    for (int i = 1; i <= count; i++) {
      text.append("2026-11-01;-").append(i).append(';').append(description).append(";x\n");
    }
    return text.toString();
  }

  private void assertNothingWritten() {
    assertEquals(0, ImportTestSupport.count(entityManager, "ImportSessionEntity"));
    assertEquals(0, ImportTestSupport.count(entityManager, "ImportRowEntity"));
  }

  @Test
  void aStatementWithMoreRowsThanTheLimitIsA400ThatWritesNothing() throws Exception {
    ZenError refused = error(upload(rows(5_001, "TEST"), null), 400);
    assertEquals("invalid", refused.getCode());
    assertTrue(refused.getMessage().contains("5000"), refused.getMessage());
    assertNothingWritten();
  }

  @Test
  void aStatementAtTheRowLimitIsAccepted() throws Exception {
    ImportSession opened = session(upload(rows(5_000, "TEST"), null));
    assertEquals(5_000, opened.getAcceptedRows());
  }

  @Test
  void aTextFieldLongerThanTheLimitIsA400NamingTheRuleAndRowNotTheText() throws Exception {
    String marker = "X".repeat(1_025);
    ZenError refused = error(upload(rows(1, marker), null), 400);
    assertTrue(refused.getMessage().contains("field.too_long"), refused.getMessage());
    assertTrue(refused.getMessage().contains("row 1"), refused.getMessage());
    assertTrue(!refused.getMessage().contains("XXXX"), "the text must not be echoed");
    assertNothingWritten();

    session(upload(rows(1, "X".repeat(1_024)), null));
  }

  @Test
  void theWorkflowChecksAreRuleViolationsOrImporterBugsAsDocumented() {
    LocalDate day = LocalDate.of(2026, 11, 1);
    List<ParsedRow> two =
        List.of(
            ParsedRow.accepted(1, day, null, 5, "TEST", null, null, null),
            ParsedRow.accepted(2, day, null, 6, "TEST", null, null, null));
    // Too many rows: the statement's doing, a 400 and not a 500.
    PrudentException tooMany =
        assertThrows(
            PrudentException.class,
            () -> ParsedStatements.validate("f", new ParsedStatement("PLN", two), 1));
    assertEquals(PrudentException.INVALID, tooMany.code());
    ParsedStatements.validate("f", new ParsedStatement("PLN", two), 2);

    // Too long a field: a rejection naming the row.
    List<ParsedRow> longField =
        List.of(ParsedRow.accepted(3, day, null, 5, "X".repeat(1_025), null, null, null));
    ImportRejectedException rejected =
        assertThrows(
            ImportRejectedException.class,
            () -> ParsedStatements.validate("f", new ParsedStatement("PLN", longField)));
    assertEquals("field.too_long", rejected.rule());
    assertEquals(3, rejected.rowNumber());

    // An identity that is not a digest of identityOf: an importer bug, a 500.
    assertThrows(
        IllegalStateException.class,
        () -> ParsedStatements.validate("f", new ParsedStatement("PLN", two, "not-a-digest")));
    ParsedStatements.validate(
        "f", new ParsedStatement("PLN", two, ParsedStatement.identityOf("XX00 TEST 0001")));
  }

  @Test
  void aUserCannotHoldMoreThanTheOpenSessionLimit_andEndedOrOverdueOnesDoNotCount() throws Exception {
    // An overdue session the sweep has not reached counts for nothing.
    PrudentTest.seedImportSession(PrudentTest.ALICE, ImportState.PARSED, Instant.now().minusSeconds(5));

    List<String> ids = new ArrayList<>();
    for (int i = 0; i < 10; i++) {
      ids.add(session(upload(rows(1, "TEST"), null)).getId());
    }
    ZenError refused = error(upload(rows(1, "TEST"), null), 409);
    assertEquals("conflict", refused.getCode());
    assertTrue(refused.getMessage().contains("Too many"), refused.getMessage());
    assertEquals(11, ImportTestSupport.count(entityManager, "ImportSessionEntity"));

    // Another user is not affected.
    // (Bob's own sessions are seeded directly; the cap is per user.)
    PrudentTest.seedImportSession(PrudentTest.BOB, ImportState.PARSED, Instant.now().plusSeconds(3600));

    session(
        post(
            SESSIONS + "/" + ids.get(0) + "/discard",
            PreviewImportSessionRequest.getDefaultInstance()));
    session(upload(rows(1, "TEST"), null));
  }

  @Test
  void theListIsBoundedAndTheLimitIsValidated() throws Exception {
    for (int i = 0; i < 3; i++) {
      session(upload(rows(1, "TEST"), null));
    }
    assertEquals(3, ImportTestSupport.list("").getSessionsCount());
    assertEquals(2, ImportTestSupport.list("?limit=2").getSessionsCount());
    assertEquals(3, ImportTestSupport.list("?limit=100").getSessionsCount());
    for (String bad : List.of("?limit=0", "?limit=101", "?limit=-1")) {
      assertEquals(
          400,
          PrudentTest.request(PrudentTest.JSON).when().get(SESSIONS + bad).andReturn().statusCode(),
          bad);
    }
    // The newest come first, so a cut-off keeps the newest.
    List<ImportSession> two = ImportTestSupport.list("?limit=2").getSessionsList();
    assertTrue(two.get(0).getCreatedAtMs() >= two.get(1).getCreatedAtMs());
  }
}
