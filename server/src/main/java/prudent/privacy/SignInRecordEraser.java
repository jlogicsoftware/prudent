package prudent.privacy;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.ProcessingException;
import jakarta.ws.rs.WebApplicationException;
import java.util.UUID;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;
import prudent.error.PrudentException;

/**
 * Deletes a person's sign-in record — the address and password hash Supabase holds in
 * {@code auth.users} — as the last step of an erasure (ADR-075).
 *
 * <p><strong>Why the server holds a secret key for this.</strong> Until ADR-075 it was meant not to,
 * and the operator deleted the record by hand (jZen ADR-007 and ADR-008 leave {@code auth.users} to
 * Supabase; finding F4 of jZen's security review priced the choice). That left a person who erased
 * their own data with a live sign-in that nobody was told to remove, and signing in again started an
 * empty account. The key is the project's secret key, {@code SUPABASE_SECRET_KEY}
 * ({@link SupabaseKeys}), used by this class only and only for this call, and given to the serving
 * container and not the migration job.
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
  @Inject SupabaseKeys keys;

  /**
   * Deletes the sign-in record of {@code userId}, or confirms there is none. Called last, inside
   * the erasure's transaction ({@code MANDATORY} says so).
   *
   * <p>The transaction is flushed before the call. Deleting the record cannot be undone, so whatever
   * could still refuse — a constraint the anonymised profile breaks — has to refuse before it, not at
   * the commit after it.
   *
   * @param userId the person being erased, whose Prudent id is their Supabase id
   * @throws PrudentException 503 when the record could not be deleted
   */
  @Transactional(Transactional.TxType.MANDATORY)
  public void delete(UUID userId) {
    String key =
        keys.secret()
            .orElseThrow(
                () -> {
                  // Unset, or not an sb_secret_ key: a legacy JWT is never sent (SupabaseKeys).
                  LOG.errorf(
                      "Sign-in record of %s not deleted: SUPABASE_SECRET_KEY is not a secret key",
                      userId);
                  return PrudentException.unavailable(FAILED);
                });
    entityManager.flush();
    try {
      admin.deleteUser(userId, key);
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
      LOG.errorf("Sign-in record of %s not deleted: %s", userId, e.getClass().getSimpleName());
      throw PrudentException.unavailable(FAILED);
    }
    LOG.infof("Sign-in record of %s deleted", userId);
  }
}
