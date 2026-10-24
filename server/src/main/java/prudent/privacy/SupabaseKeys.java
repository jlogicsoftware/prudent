package prudent.privacy;

import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * The two Supabase keys the server holds, and the check that each is the kind it must be (ADR-075).
 *
 * <ul>
 *   <li>{@code SUPABASE_KEY} ({@code supabase.key}) is the <strong>publishable</strong> key,
 *       {@code sb_publishable_…}. zen-identity sends it as {@code apikey} on every call it makes
 *       for a person: sign-in, sign-up, refresh.
 *   <li>{@code SUPABASE_SECRET_KEY} ({@code prudent.supabase.secret-key}) is the
 *       <strong>secret</strong> key, {@code sb_secret_…}, for the one server-to-server call
 *       Prudent makes: deleting a person's sign-in record ({@link SignInRecordEraser}).
 * </ul>
 *
 * <p><strong>Why the prefixes are checked.</strong> Supabase recommends these keys over the legacy
 * {@code anon} and {@code service_role} JWTs. The new keys can be revoked one at a time, and a secret
 * key is refused when it comes from a browser. The legacy pair are both JWTs that look alike, and the
 * runbook once asked for the service-role JWT under {@code SUPABASE_KEY}. That is the mistake that
 * puts the key administering every identity on every call made for a person. A prefix tells the kinds
 * apart without decoding anything, so a serving {@code %prod} process refuses to start unless each key
 * is the kind it must be.
 *
 * <p>Only a serving {@code %prod} process is held to it ({@code prudent.supabase.keys-required}):
 * {@code %dev} runs on whatever the local stack hands out and {@code %test} talks to no Supabase.
 * The migration job ({@code zen.migrate-only}) is exempt: it calls neither Supabase API, and it is
 * not given the secret key.
 */
@ApplicationScoped
public class SupabaseKeys {

  static final String PUBLISHABLE_PREFIX = "sb_publishable_";
  static final String SECRET_PREFIX = "sb_secret_";

  @ConfigProperty(name = "supabase.key")
  Optional<String> publishableKey;

  @ConfigProperty(name = "prudent.supabase.secret-key")
  Optional<String> secretKey;

  @ConfigProperty(name = "prudent.supabase.keys-required", defaultValue = "false")
  boolean required;

  @ConfigProperty(name = "zen.migrate-only", defaultValue = "false")
  boolean migrateOnly;

  /**
   * Refuses to start a serving {@code %prod} process whose keys are missing or of the wrong kind,
   * so a deployment that lacks them fails at boot rather than at a person's sign-in or erasure.
   * The messages name the variable and the kind, never the value.
   */
  void check(@Observes StartupEvent event) {
    if (!required || migrateOnly) {
      return;
    }
    if (!publishableKey.map(String::trim).filter(k -> k.startsWith(PUBLISHABLE_PREFIX)).isPresent()) {
      throw new IllegalStateException(
          "SUPABASE_KEY must be the project's publishable key (" + PUBLISHABLE_PREFIX + "…)."
              + " A legacy anon or service_role JWT, or a secret key, is refused (ADR-075).");
    }
    if (secret().isEmpty()) {
      throw new IllegalStateException(
          "SUPABASE_SECRET_KEY must be set to the project's secret key (" + SECRET_PREFIX + "…)."
              + " Erasure deletes the sign-in record with it; the legacy service_role JWT is refused"
              + " (ADR-075).");
    }
  }

  /** The secret key, if one of the right kind is configured; anything else counts as none. */
  Optional<String> secret() {
    return secretKey.map(String::trim).filter(k -> k.startsWith(SECRET_PREFIX));
  }
}
