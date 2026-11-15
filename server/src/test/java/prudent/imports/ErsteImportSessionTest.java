package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static prudent.imports.ImportTestSupport.error;
import static prudent.imports.ImportTestSupport.post;
import static prudent.imports.ImportTestSupport.preview;
import static prudent.imports.ImportTestSupport.session;

import com.google.protobuf.ByteString;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import java.io.IOException;
import java.io.InputStream;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.account.AccountEntity;
import prudent.proto.v1.CreateImportSessionRequest;
import prudent.proto.v1.ImportRowStatus;
import prudent.proto.v1.ImportSession;
import prudent.proto.v1.ImportSessionState;
import zen.proto.v1.ZenError;

/**
 * The Erste importer through the real workflow (M6, jlogicsoftware/prudent#73, ADR-090): the
 * representative fixture opens a session for the account whose number it carries, any other
 * destination is refused at every point it can be set, and every refusal writes nothing.
 */
@QuarkusTest
@TestSecurity(user = PrudentTest.ALICE)
class ErsteImportSessionTest {

  private static final String ACCOUNT_1 = "00 0000 0000 0000 0000 0000 0001";

  @Inject EntityManager entityManager;

  private UUID matching;
  private UUID other;
  private UUID unnumbered;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    matching = PrudentTest.seedAccount(PrudentTest.ALICE, "Erste", "PLN");
    other = PrudentTest.seedAccount(PrudentTest.ALICE, "Other", "PLN");
    unnumbered = PrudentTest.seedAccount(PrudentTest.ALICE, "No number", "PLN");
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              AccountEntity.<AccountEntity>findById(matching).accountNumber = "00000000000000000000000001";
              AccountEntity.<AccountEntity>findById(other).accountNumber = "00000000000000000000000009";
            });
  }

  private static byte[] fixture(String name) throws IOException {
    try (InputStream in = ErsteImportSessionTest.class.getResourceAsStream("/import/erste/" + name)) {
      return in.readAllBytes();
    }
  }

  private static Response upload(byte[] content, UUID accountId) throws Exception {
    CreateImportSessionRequest.Builder request =
        CreateImportSessionRequest.newBuilder()
            .setFormatId(ImportFormatIds.ERSTE_PL_CSV)
            .setContent(ByteString.copyFrom(content));
    if (accountId != null) {
      request.setAccountId(accountId.toString());
    }
    return post(ImportTestSupport.SESSIONS, request.build());
  }

  private void assertNothingWritten() {
    assertEquals(0, ImportTestSupport.count(entityManager, "ImportSessionEntity"));
    assertEquals(0, ImportTestSupport.count(entityManager, "ImportRowEntity"));
  }

  private static void assertNoStatementText(ZenError refused) {
    String text = refused.getMessage();
    for (String forbidden : new String[] {"TESTOWY", "0001", "0003", "0009", "PLN ", "JAN", "PRZYKŁADOWA"}) {
      assertFalse(text.contains(forbidden), forbidden + " leaked: " + text);
    }
    assertFalse(text.matches("(?s).*[0-9a-f]{20}.*"), "a digest must not be echoed: " + text);
  }

  @Test
  void theRepresentativeStatement_opensASessionForTheAccountItIsFor() throws Exception {
    ImportSession parsed = session(upload(fixture("statement-representative.csv"), matching));

    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PARSED, parsed.getState());
    assertEquals(ImportFormatIds.ERSTE_PL_CSV, parsed.getFormatId());
    assertEquals("PLN", parsed.getCurrency());
    assertEquals(8, parsed.getAcceptedRows());
    assertEquals(0, parsed.getRejectedRows());
    assertEquals(8, parsed.getRowsCount());
    assertTrue(parsed.getRowsList().stream().allMatch(r -> r.getStatus() == ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED));
    // The statement's own account and the holder are not on the wire.
    String wire = parsed.toString();
    assertFalse(wire.contains(ACCOUNT_1.replace(" ", "")) || wire.contains("JAN TESTOWY"), wire);
  }

  @Test
  void aStatementParsedWithoutADestination_isCheckedWhenOneIsChosen() throws Exception {
    ImportSession parsed = session(upload(fixture("statement-minimal.csv"), null));
    assertEquals(1, parsed.getAcceptedRows());
    // minimal's account is ...0003; none of Alice's accounts holds it.
    ZenError refused = error(preview(parsed.getId(), matching), 400);
    assertTrue(refused.getMessage().contains("account.identity_mismatch"), refused.getMessage());
    assertNoStatementText(refused);
  }

  @Test
  void aWrongDestination_isRefusedAndWritesNothing() throws Exception {
    ZenError mismatch = error(upload(fixture("statement-representative.csv"), other), 400);
    assertTrue(mismatch.getMessage().contains("account.identity_mismatch"), mismatch.getMessage());
    assertNoStatementText(mismatch);
    assertNothingWritten();
  }

  @Test
  void aDestinationWithNoNumber_failsClosedWithARuleThatSaysToAddIt() throws Exception {
    ZenError refused = error(upload(fixture("statement-representative.csv"), unnumbered), 400);
    assertTrue(refused.getMessage().contains("account.number_missing"), refused.getMessage());
    assertNothingWritten();

    // And at preview, for a session parsed without a destination.
    ImportSession parsed = session(upload(fixture("statement-representative.csv"), null));
    ZenError atPreview = error(preview(parsed.getId(), unnumbered), 400);
    assertTrue(atPreview.getMessage().contains("account.number_missing"), atPreview.getMessage());
    ImportSession previewed = session(preview(parsed.getId(), matching));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED, previewed.getState());
    assertEquals(matching.toString(), previewed.getAccountId());
  }

  @Test
  void theNumberRemovedAfterTheParse_stopsAPreview() throws Exception {
    ImportSession parsed = session(upload(fixture("statement-representative.csv"), matching));
    QuarkusTransaction.requiringNew()
        .run(() -> AccountEntity.<AccountEntity>findById(matching).accountNumber = null);
    ZenError refused = error(preview(parsed.getId(), null), 400);
    assertTrue(refused.getMessage().contains("account.number_missing"), refused.getMessage());
  }

  @Test
  void aRejectedStatement_writesNothing_andNamesTheRuleAndRowOnly() throws Exception {
    String text = new String(fixture("statement-representative.csv"), java.nio.charset.StandardCharsets.UTF_8);
    // Row 3's amount loses a decimal: a whole-file rule, found after two good rows.
    byte[] broken = text.replace("\"-99,99\"", "\"-99,9\"").getBytes(java.nio.charset.StandardCharsets.UTF_8);

    ZenError refused = error(upload(broken, matching), 400);
    assertEquals("The statement was rejected at row 3 (amount.invalid).", refused.getMessage());
    assertNothingWritten();

    ZenError bom = error(upload(("\uFEFF" + text).getBytes(java.nio.charset.StandardCharsets.UTF_8), matching), 400);
    assertTrue(bom.getMessage().contains("encoding.bom"), bom.getMessage());
    assertNothingWritten();
  }

  @Test
  void aFlaggedRow_isListedAsRejectedButTheRestIsKept() throws Exception {
    String text = new String(fixture("statement-minimal.csv"), java.nio.charset.StandardCharsets.UTF_8);
    String unknown = "03-02-2026,03-02-2026,Opłata TEST,,,\"-1,00\",\"1,00\",3,\n";
    // minimal's account is ...0003: seed one that holds it.
    UUID erste = PrudentTest.seedAccount(PrudentTest.ALICE, "Minimal", "PLN");
    QuarkusTransaction.requiringNew()
        .run(() -> AccountEntity.<AccountEntity>findById(erste).accountNumber = "00000000000000000000000003");
    byte[] content = (text + unknown).getBytes(java.nio.charset.StandardCharsets.UTF_8);

    ImportSession parsed = session(upload(content, erste));
    assertEquals(1, parsed.getAcceptedRows());
    assertEquals(1, parsed.getRejectedRows());
    assertEquals("description.unknown_shape", parsed.getRows(1).getRejectionCode());
    assertFalse(parsed.getRows(1).getDescription().length() > 0, "a flagged row keeps no text");
  }
}
