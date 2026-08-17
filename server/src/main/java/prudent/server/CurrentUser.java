package prudent.server;

import io.quarkus.security.identity.SecurityIdentity;
import jakarta.enterprise.context.RequestScoped;
import jakarta.inject.Inject;
import java.util.UUID;
import zen.identity.AuthException;

/**
 * The authenticated user's id — <strong>the only place any resource in this server learns who is
 * calling</strong>.
 *
 * <p>This class exists to make one rule structural instead of repeated. {@code user_id} is read
 * from the authenticated identity on every create, read, update, delete and list, and never from a
 * request body: a client that can name an owner can name someone else's. Prudent's contract carries
 * no {@code user_id} field in either direction precisely so that rule has nothing to fight with —
 * but a resource could still reach for a path or query parameter, and the defence against that is
 * that there is exactly one supported way to get an id and it takes no arguments.
 *
 * <p><strong>The failure mode this guards is silent.</strong> A server that reads ownership from
 * the request serves every request successfully; it simply serves the wrong person's data, and
 * nothing in a test that uses one user can see it. That is why the user-scoping suite exercises two
 * identities against every verb rather than asserting this class in isolation.
 */
@RequestScoped
public class CurrentUser {

  @Inject SecurityIdentity securityIdentity;

  /**
   * The calling user's id.
   *
   * <p>Every resource is {@code @Authenticated}, so an anonymous caller is refused before a method
   * body runs and the first check below is a belt to that braces — kept because it costs nothing
   * and because the annotation is one edit away from being dropped by someone who does not know it
   * is load-bearing.
   *
   * @return the id, never {@code null}
   * @throws AuthException if the caller is anonymous, or the principal is not a UUID
   */
  public UUID id() {
    if (securityIdentity == null || securityIdentity.isAnonymous()) {
      throw AuthException.unauthorized("Authentication required");
    }
    String principal = securityIdentity.getPrincipal().getName();
    try {
      return UUID.fromString(principal);
    } catch (IllegalArgumentException notAUuid) {
      // Converted rather than swallowed: an unparseable principal is a broken session, and the
      // caller is told so at 401 instead of the request continuing with no owner.
      throw AuthException.unauthorized("Session principal is not a valid user id");
    }
  }
}
