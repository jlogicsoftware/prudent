package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import prudent.error.PrudentException;

/**
 * When the service-role key is missing: a serving {@code %prod} boot refuses to start, the migration
 * job does not care, and an erasure attempted without it is a 503 before anything is sent. Plain
 * JUnit — the boot check is a method, and a Quarkus instance per case would prove nothing more.
 */
class SignInRecordEraserKeyTest {

  private static SignInRecordEraser eraser(String key, boolean required, boolean migrateOnly) {
    SignInRecordEraser eraser = new SignInRecordEraser();
    eraser.serviceRoleKey = Optional.ofNullable(key);
    eraser.keyRequired = required;
    eraser.migrateOnly = migrateOnly;
    return eraser;
  }

  @Test
  void aServingProdBootWithoutTheKeyRefusesToStart() {
    for (String missing : new String[] {null, "", "   "}) {
      IllegalStateException e =
          assertThrows(IllegalStateException.class, () -> eraser(missing, true, false).requireKey(null));
      assertTrue(e.getMessage().contains("SUPABASE_SERVICE_ROLE_KEY"), e.getMessage());
    }
  }

  @Test
  void theMigrationJobStartsWithoutIt() {
    assertDoesNotThrow(() -> eraser(null, true, true).requireKey(null));
  }

  @Test
  void devAndTestStartWithoutIt() {
    assertDoesNotThrow(() -> eraser(null, false, false).requireKey(null));
  }

  @Test
  void aServingBootWithTheKeyStarts() {
    assertDoesNotThrow(() -> eraser("sb_secret_x", true, false).requireKey(null));
  }

  @Test
  void anErasureWithoutTheKeyIsRefusedBeforeAnythingIsSent() {
    // No REST client is injected here: reaching it would be a NullPointerException, not a 503.
    SignInRecordEraser eraser = eraser(null, false, false);
    eraser.entityManager = null;

    PrudentException e = assertThrows(PrudentException.class, () -> eraser.delete(UUID.randomUUID()));
    assertEquals(PrudentException.UNAVAILABLE, e.code());
  }
}
