package prudent.privacy;

import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.jboss.logging.Logger;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.error.PrudentException;
import zen.core.http.ZenStatus;
import zen.identity.user.UserRole;

/**
 * Erasure of one person's data on the operator's request — {@code /api/v1/admin/privacy}, for the
 * person who can no longer sign in and so cannot use {@link PrivacyResource#erase}.
 *
 * <p><strong>Who may call it.</strong> Only a signed-in user whose {@code users.role} is
 * {@code admin} — the gate the framework's own {@code AdminUserResource} uses, resolved from the
 * database on every request by {@code RoleAugmentor} and never from the token, so revoking the role
 * takes effect at the next call. Anyone else is refused (401 without a session, 403 with another
 * role) before this method runs. No new credential or secret exists for it, and it is not reachable
 * through the machine route that drives the retention job.
 *
 * <p><strong>What it does is what the person's own request does, minus the typed address.</strong>
 * The same {@link PrudentDataEraser} and {@link PrudentIdentityAnonymiser} run in one transaction,
 * so the two routes cannot disagree about what "all of a person's data" is, and a failure half-way
 * leaves the person as they were. The typed address is absent because its purpose — making the
 * person type something only they would know — does not carry over to an operator; the id in the
 * path has to be spelled out in full instead.
 *
 * <p><strong>The sign-in record goes too</strong> ({@link SignInRecordEraser}, ADR-075), last and in
 * the same transaction, so a refusal from Supabase is a 503 with nothing erased. A record that is
 * already gone — deleted in the dashboard, or by an earlier erasure — is not an error.
 *
 * <p>The operator may not erase themselves here — that is the self-service route's job, with its
 * confirmation, and an operator account that lost its profile to a mistyped id would lose the very
 * access needed to put it right.
 */
@Path("/api/v1/admin/privacy")
@RolesAllowed(UserRole.Names.ADMIN)
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class OperatorErasureResource {

  private static final Logger LOG = Logger.getLogger(OperatorErasureResource.class);

  @Inject CurrentUser currentUser;
  @Inject PrudentDataEraser eraser;
  @Inject PrudentIdentityAnonymiser identity;
  @Inject SignInRecordEraser signIn;

  @POST
  @Path("/users/{userId}/erase")
  @Transactional
  @Operation(
      summary = "Erase one person's data on the operator's request",
      description =
          "IRREVERSIBLE. Deletes every Prudent row the named user owns, anonymises their"
              + " profile and deletes their sign-in record at the identity provider, in one"
              + " transaction, exactly as their own erasure does. Admin role only. Repeating it"
              + " for an already erased user succeeds and deletes nothing.")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Erased")
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "The id is the caller's own; nothing is deleted",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(responseCode = ZenStatus.UNAUTHORIZED, description = "No active session")
  @APIResponse(responseCode = ZenStatus.FORBIDDEN, description = "Session lacks the admin role")
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "The id is not a user id, or Prudent holds nothing under it",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.SERVICE_UNAVAILABLE,
      description = "The sign-in record could not be deleted; nothing is deleted",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response erase(@PathParam("userId") String userId) {
    UUID target = Ids.parse("user", userId);
    UUID operator = currentUser.id();
    if (target.equals(operator)) {
      throw PrudentException.invalid(
          "An operator cannot erase their own account here; use Delete my data in Settings."
              + " Nothing was deleted.");
    }

    PrudentDataEraser.Erased erased = eraser.erase(target);
    boolean hadProfile = identity.anonymise(target);
    if (!hadProfile && !erased.any()) {
      // Nothing under that id: a typo and a stranger look the same. The exception rolls the
      // transaction back, which has nothing in it to undo.
      throw PrudentException.notFound("user", target);
    }
    signIn.delete(target);
    LOG.infof("Account %s erased at an operator's request (operator %s)", target, operator);
    return Response.noContent().build();
  }
}
