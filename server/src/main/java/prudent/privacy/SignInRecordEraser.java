package prudent.privacy;

import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.ProcessingException;
import jakarta.ws.rs.WebApplicationException;
import java.util.Optional;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;
import prudent.error.PrudentException;

/**
 * Deletes a person's sign-in record — the address and password hash Supabase holds in
 * {@code auth.users} — as the last step of an erasure (ADR-075).
 *
 * <p><strong>Why the server holds a service-role key for this.</strong> Until ADR-075 it was meant
 * not to, and the operator deleted the record by hand (jZen ADR-007 and ADR-008 leave {@code auth.users} to
 * Supabase; finding F4 of jZen's security review priced the choice). That left a person who erased
 * their own data with a live sign-in that nobody was told to remove, and signing in again started an
 * empty account. The key is held under its own name, {@code SUPABASE_SERVICE_ROLE_KEY}, used by this
 * class only and only for this call, and given to the serving container and not the migration job.
 *
 * <p><strong>A failure is the caller's answer, never a log line alone.</strong> Anything but
 * success or "already gone" throws a 503, and because this runs last inside the erasure's
 * transaction, the throw rolls back the deletion of Prudent's rows as well: the person is left as
 * they were and can ask again. The alternative order — commit, then delete the record — would leave
 * a person whose data is gone and whose self-service retry is refused, because the address it asks
 * them to confirm has already been anonymised.
 *
 * <p>Nothing about the call is logged except the person's id and the status or failure class. The
 * key never is, and neither is GoTrue's answer.
 */
@ApplicationScoped
public class SignInRecordEraser {

  private static final Logger LOG = Logger.getLogger(SignInRecordEraser.class);

  /** GoTrue's answer for an id it has no record of, which for a delete means the work is done. */
  private static final int NOT_FOUND = 404;

  private static final String FAILED =
      "The sign-in record could not be deleted, so nothing was erased. Try again later.";

  @Inject @RestClient SupabaseAdminClient admin;
  @Inject EntityManager entityManager;

  @ConfigProperty(name = "prudent.supabase.service-role-key")
  Optional<String> serviceRoleKey;

  @ConfigProperty(name = "prudent.supabase.service-role-key-required", defaultValue = "false")
  boolean keyRequired;

  @ConfigProperty(name = "zen.migrate-only", defaultValue = "false")
  boolean migrateOnly;

  /**
   * Refuses to start a serving {@code %prod} process without the key, so a deployment that lacks it
   * fails at boot rather than at the first person's erasure. The migration job is exempt: it serves
   * nothing, and giving it the key would widen what that job can do for no use.
   */
  void requireKey(@Observes StartupEvent event) {
    if (keyRequired && !migrateOnly && key().isEmpty()) {
      throw new IllegalStateException(
          "SUPABASE_SERVICE_ROLE_KEY is not set. Erasure deletes the sign-in record with it"
              + " (ADR-075); a service without it cannot erase anyone.");
    }
  }

  /**
   * Deletes the sign-in record of {@code userId}, or confirms there is none. Called last, inside
   * the erasure's transaction ({@code MANDATORY} says so).
   *
   * <p>The transaction is flushed before the call. Deleting the record cannot be undone, so whatever could
   * still refuse — a constraint the anonymised profile breaks — has to refuse before it, not at the
   * commit after it.
   *
   * @param userId the person being erased, whose Prudent id is their Supabase id
   * @throws PrudentException 503 when the record could not be deleted
   */
  @Transactional(Transactional.TxType.MANDATORY)
  public void delete(UUID userId) {
    String key =
        key()
            .orElseThrow(
                () -> {
                  LOG.errorf(
                      "Sign-in record of %s not deleted: SUPABASE_SERVICE_ROLE_KEY is not set",
                      userId);
                  return PrudentException.unavailable(FAILED);
                });
    entityManager.flush();
    try {
      admin.deleteUser(userId, key, "Bearer " + key);
    } catch (WebApplicationException e) {
      int status = e.getResponse().getStatus();
      if (status == NOT_FOUND) {
        // Deleted earlier, by a previous erasure or in the dashboard: what was asked for is true.
        LOG.infof("Sign-in record of %s was already absent", userId);
        return;
      }
      LOG.errorf("Sign-in record of %s not deleted: Supabase answered %d", userId, status);
      throw PrudentException.unavailable(FAILED);
    } catch (ProcessingException e) {
      LOG.errorf(
          "Sign-in record of %s not deleted: %s", userId, e.getClass().getSimpleName());
      throw PrudentException.unavailable(FAILED);
    }
    LOG.infof("Sign-in record of %s deleted", userId);
  }

  private Optional<String> key() {
    return serviceRoleKey.map(String::trim).filter(k -> !k.isEmpty());
  }
}
