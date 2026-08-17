package prudent.server;

import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import zen.identity.auth.SupabaseSessionResponse.UserPayload;
import zen.identity.user.User;
import zen.identity.user.UserStore;

/**
 * Prudent ships {@code {en, uk, pl}}, and a Polish user's {@code users.language} must hold
 * {@code pl}.
 *
 * <p><strong>This is a data test, not a styling one.</strong> {@code users.language} is the sole
 * locale source for email — a message has no request to read {@code Accept-Language} from — so a
 * column written {@code en} for a Polish user means every later message to them goes out in the
 * wrong language. Nothing fails; the data is quietly wrong. That is why this asserts against the
 * database rather than reading the configuration back.
 *
 * <p>{@code ZenLocales.shipped} is jZen's own inventory ({@code {en, uk}}) and is a <em>floor, not
 * a ceiling</em> (jZen ADR-044). Prudent declares the wider set through {@code zen.i18n.supported},
 * and the framework must not clamp a stored preference back to its own list. The second test is the
 * other half of that: the set is <strong>wider, not open</strong>.
 *
 * <p>The {@code @TestProfile} supplies the property explicitly rather than relying on
 * {@code application.properties}, so the test states the precondition it depends on instead of
 * inheriting it — a suite that passed only because of a line in a config file would go green again
 * the day someone narrowed that line for an unrelated reason.
 */
@QuarkusTest
@TestProfile(ApplicationLocaleSetTest.PrudentLocales.class)
class ApplicationLocaleSetTest {

  /** Prudent's locale set, as the server is configured to accept it. */
  public static class PrudentLocales implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of("zen.i18n.supported", "en,uk,pl");
    }
  }

  @Inject UserStore userStore;

  private static UserPayload payload(UUID id) {
    return new UserPayload(id.toString(), "locale-" + id + "@example.test", null, null, null);
  }

  @Test
  void registeringWithPolish_leavesPlInTheUserRow() {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew().run(() -> userStore.upsertOnLogin(payload(id), "pl-PL"));

    User stored = QuarkusTransaction.requiringNew().call(() -> User.findById(id));
    assertEquals(
        "pl",
        stored.language,
        "Prudent supports pl, so a pl-PL registration must store pl — this column is what makes a"
            + " Polish user's email Polish.");
  }

  @Test
  void registeringWithAnUnsupportedTag_fallsBackToEnglish() {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew().run(() -> userStore.upsertOnLogin(payload(id), "de"));

    User stored = QuarkusTransaction.requiringNew().call(() -> User.findById(id));
    assertEquals("en", stored.language, "the supported set is wider than the framework's, not open");
  }

  @Test
  void registeringWithUkrainian_stillWorks() {
    // uk is in both jZen's inventory and Prudent's set. Asserted so that a change which fixed pl by
    // replacing the framework's list rather than widening it would be caught.
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew().run(() -> userStore.upsertOnLogin(payload(id), "uk-UA"));

    User stored = QuarkusTransaction.requiringNew().call(() -> User.findById(id));
    assertEquals("uk", stored.language);
  }
}
