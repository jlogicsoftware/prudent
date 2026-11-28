package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.FineStoredClock;
import prudent.PrudentTest;
import prudent.proto.v1.ImportSession;

/**
 * An import session is answered with the instants a later read gives, even when the clock reads finer
 * than the database keeps (ADR-139, jlogicsoftware/prudent#284).
 */
@QuarkusTest
class ImportStoredInstantTest {

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    FineStoredClock.install();
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aPreviewAndACommitAreStampedAsTheyAreReadBack() throws Exception {
    UUID account = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    ImportTestSupport.installRecordingCommitter(0);

    ImportSession parsed = upload();
    assertStamped(parsed);
    assertStamped(ImportTestSupport.session(ImportTestSupport.preview(parsed.getId(), account)));
    assertStamped(ImportTestSupport.session(ImportTestSupport.commit(parsed.getId(), 1)));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aDiscardIsStampedAsItIsReadBack() throws Exception {
    ImportSession parsed = upload();

    assertStamped(ImportTestSupport.session(ImportTestSupport.discard(parsed.getId())));
  }

  private static ImportSession upload() throws Exception {
    return ImportTestSupport.session(
        ImportTestSupport.upload(ImportTestSupport.statement("PLN", "TEST coffee"), null));
  }

  /**
   * Holds the answer to the clock's instant as well as to the later read: on a clock that reads whole
   * microseconds an uncut instant also agrees with itself, so only the fixed value shows that a phase
   * took its stamp from {@code StoredClock}.
   */
  private static void assertStamped(ImportSession answered) throws Exception {
    assertEquals(
        FineStoredClock.EPOCH_MILLI, answered.getStateChangedAtMs(), "state_changed_at_ms");
    assertEquals(FineStoredClock.EPOCH_MILLI, answered.getCreatedAtMs(), "created_at_ms");

    ImportSession read = ImportTestSupport.session(ImportTestSupport.get(answered.getId()));
    assertEquals(answered.getCreatedAtMs(), read.getCreatedAtMs(), "created_at_ms");
    assertEquals(answered.getStateChangedAtMs(), read.getStateChangedAtMs(), "state_changed_at_ms");
    assertEquals(answered.getExpiresAtMs(), read.getExpiresAtMs(), "expires_at_ms");
  }
}
