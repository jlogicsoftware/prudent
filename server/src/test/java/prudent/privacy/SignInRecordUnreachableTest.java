package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.security.TestSecurity;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.proto.v1.EraseAccountRequest;
import prudent.record.RecordEntity;

/**
 * A Supabase that cannot be reached at all — nothing listens on the port — is the same answer to
 * the person as one that refuses: 503, nothing erased. This is the path {@link SignInRecordErasureTest}
 * cannot reach, because its fake always answers.
 */
@QuarkusTest
@TestProfile(SignInRecordUnreachableTest.Unreachable.class)
class SignInRecordUnreachableTest {

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    PrivacySeed.everythingFor(PrudentTest.ALICE);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anUnreachableSupabaseErasesNothing() throws Exception {
    long before =
        QuarkusTransaction.requiringNew()
            .call(() -> RecordEntity.count("userId", UUID.fromString(PrudentTest.ALICE)));

    int status =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                EraseAccountRequest.newBuilder().setConfirmEmail("alice@example.com").build())
            .when()
            .post("/api/v1/privacy/erase")
            .statusCode();

    assertEquals(503, status);
    assertEquals(
        before,
        QuarkusTransaction.requiringNew()
            .call(() -> RecordEntity.count("userId", UUID.fromString(PrudentTest.ALICE))));
  }

  /** Port 1 is reserved (tcpmux) and nothing on a test machine listens there. */
  public static class Unreachable implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of("quarkus.rest-client.supabase-admin.url", "http://127.0.0.1:1/auth/v1");
    }
  }
}
