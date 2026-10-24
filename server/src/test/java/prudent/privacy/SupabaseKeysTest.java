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
 * The two Supabase keys must be the kinds ADR-075 names: a serving {@code %prod} boot refuses a
 * missing key, a legacy JWT, or a secret key where the publishable one belongs; the migration job
 * and the other profiles do not check; and an erasure with no usable secret key is a 503 before
 * anything is sent. Plain JUnit — the check is a method, and a Quarkus instance per case would prove
 * nothing more.
 */
class SupabaseKeysTest {

  private static final String PUBLISHABLE = "sb_publishable_abc";
  private static final String SECRET = "sb_secret_abc";

  /** The shape of a legacy anon/service_role key: a JWT, three dot-separated parts. */
  private static final String LEGACY_JWT = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x";

  private static SupabaseKeys keys(String publishable, String secret, boolean required, boolean migrateOnly) {
    SupabaseKeys keys = new SupabaseKeys();
    keys.publishableKey = Optional.ofNullable(publishable);
    keys.secretKey = Optional.ofNullable(secret);
    keys.required = required;
    keys.migrateOnly = migrateOnly;
    return keys;
  }

  private static void refused(String publishable, String secret, String names) {
    IllegalStateException e =
        assertThrows(IllegalStateException.class, () -> keys(publishable, secret, true, false).check(null));
    assertTrue(e.getMessage().contains(names), e.getMessage());
    // The message names the variable and the kind; it never repeats what was configured.
    for (String value : new String[] {publishable, secret}) {
      if (value != null && !value.isBlank()) {
        assertTrue(!e.getMessage().contains(value), "the key reached the message");
      }
    }
  }

  @Test
  void aServingProdBootWithBothCurrentKeysStarts() {
    assertDoesNotThrow(() -> keys(PUBLISHABLE, SECRET, true, false).check(null));
  }

  @Test
  void aMissingOrLegacySecretKeyRefusesToStart() {
    for (String bad : new String[] {null, "", "   ", LEGACY_JWT, PUBLISHABLE}) {
      refused(PUBLISHABLE, bad, "SUPABASE_SECRET_KEY");
    }
  }

  @Test
  void aSupabaseKeyThatIsNotThePublishableKeyRefusesToStart() {
    // A legacy anon or service_role JWT, or the secret key — the swap that puts the key that
    // administers everyone on every call made for a person.
    for (String bad : new String[] {null, "", LEGACY_JWT, SECRET}) {
      refused(bad, SECRET, "SUPABASE_KEY");
    }
  }

  @Test
  void theMigrationJobStartsWithoutTheSecretKey() {
    assertDoesNotThrow(() -> keys(PUBLISHABLE, null, true, true).check(null));
  }

  @Test
  void devAndTestStartOnWhateverTheLocalStackHandsOut() {
    assertDoesNotThrow(() -> keys(LEGACY_JWT, null, false, false).check(null));
  }

  @Test
  void aLegacyJwtIsNeverOfferedAsTheSecretKey() {
    assertEquals(Optional.empty(), keys(PUBLISHABLE, LEGACY_JWT, false, false).secret());
    assertEquals(Optional.of(SECRET), keys(PUBLISHABLE, "  " + SECRET + " ", false, false).secret());
  }

  @Test
  void anErasureWithoutAUsableSecretKeyIsRefusedBeforeAnythingIsSent() {
    // No REST client or entity manager is injected: reaching either would be a
    // NullPointerException, not a 503.
    SignInRecordEraser eraser = new SignInRecordEraser();
    eraser.keys = keys(PUBLISHABLE, LEGACY_JWT, false, false);

    PrudentException e = assertThrows(PrudentException.class, () -> eraser.delete(UUID.randomUUID()));
    assertEquals(PrudentException.UNAVAILABLE, e.code());
  }
}
