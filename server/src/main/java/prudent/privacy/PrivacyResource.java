package prudent.privacy;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.jboss.logging.Logger;
import prudent.CurrentUser;
import prudent.error.PrudentException;
import prudent.proto.v1.EraseAccountRequest;
import zen.core.http.ZenStatus;
import zen.identity.user.User;

/**
 * A person's two rights over what Prudent holds about them: to be handed all of it, and to have it
 * deleted — {@code /api/v1/privacy}.
 *
 * <p>The resource shape is set out on {@link prudent.category.CategoryResource}. Neither route
 * names a user: the caller is the one authenticated, so there is no id to substitute for someone
 * else's.
 *
 * <p><strong>Erasure is one transaction, and it is Prudent's whole data or none of it.</strong>
 * The financial rows go through {@link PrudentDataEraser} — the same code dormancy retention runs —
 * and the {@code users} row is anonymised in the same unit of work, so a failure half-way leaves the
 * person exactly as they were rather than half-deleted.
 *
 * <p><strong>The sign-in record goes too</strong> ({@link SignInRecordEraser}, ADR-075), last and
 * inside the same transaction: if Supabase does not delete it, the answer is 503 and nothing at all
 * is erased, so the person can simply ask again. It does not end the caller's session — the client
 * logs out when it succeeds, and the access token it held stops at its own expiry.
 */
@Path("/api/v1/privacy")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class PrivacyResource {

  private static final Logger LOG = Logger.getLogger(PrivacyResource.class);

  @Inject CurrentUser currentUser;
  @Inject PrudentDataExporter exporter;
  @Inject PrudentDataEraser eraser;
  @Inject PrudentIdentityAnonymiser identity;
  @Inject SignInRecordEraser signIn;

  @GET
  @Path("/export")
  @Operation(
      summary = "Export everything stored for the authenticated user",
      description =
          "One document holding every account, category, record, plan, occurrence, budget,"
              + " carry-over reset, goal and envelope entry the caller owns, in any lifecycle"
              + " state, plus their settings and profile. With the default JSON transport it is"
              + " readable in any text editor.")
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "DataExport")))
  public Response export() {
    UUID userId = currentUser.id();
    // no-store: this is the most sensitive response the server produces, and a shared cache or a
    // browser's back-forward cache has no business keeping a copy of it.
    return Response.ok(exporter.export(userId))
        .header(HttpHeaders.CACHE_CONTROL, "no-store")
        .build();
  }

  @POST
  @Path("/erase")
  @Transactional
  @Operation(
      summary = "Erase the authenticated user's data",
      description =
          "IRREVERSIBLE. Deletes every Prudent row the caller owns, anonymises their profile"
              + " and deletes their sign-in record at the identity provider, in one transaction."
              + " Refused unless confirmEmail matches the account's sign-in address.")
  @RequestBody(content = @Content(schema = @Schema(ref = "EraseAccountRequest")))
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Erased")
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "confirmEmail is missing or is not this account's address; nothing is deleted",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.SERVICE_UNAVAILABLE,
      description = "The sign-in record could not be deleted; nothing is deleted",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response erase(EraseAccountRequest request) {
    UUID userId = currentUser.id();
    User user = User.findById(userId);
    String confirmed = request == null ? "" : request.getConfirmEmail().trim();
    // Compared against the stored address and not against anything the client sent about itself:
    // the point is that the person types something only they would know to type.
    if (user == null || confirmed.isEmpty() || !confirmed.equalsIgnoreCase(user.email)) {
      throw PrudentException.invalid(
          "Enter the email address of this account to confirm. Nothing was deleted.");
    }

    eraser.erase(userId);
    identity.anonymise(userId);
    signIn.delete(userId);
    LOG.infof("Account %s erased at its owner's request", userId);
    return Response.noContent().build();
  }
}
