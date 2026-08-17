package prudent.server.settings;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.proto.v1.UpdateSettingsRequest;
import prudent.server.Currencies;
import prudent.server.CurrentUser;
import prudent.server.PrudentException;
import zen.core.http.ZenStatus;

/**
 * Prudent's per-user settings: {@code /api/v1/settings}.
 *
 * <p><strong>A singleton, so the URL carries no id</strong> — the token is the entire addressing
 * scheme. There is no create, no delete and no list; the row is created on first login by
 * {@link prudent.server.onboarding.NewUserSetup}.
 *
 * <p>The resource shape is otherwise the one set out on
 * {@link prudent.server.category.CategoryResource}.
 */
@Path("/api/v1/settings")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class SettingsResource {

  @Inject CurrentUser currentUser;
  @Inject SettingsMapper mapper;

  @GET
  @Transactional
  @Operation(summary = "Read the authenticated user's settings")
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Settings")))
  public Response get() {
    UUID userId = currentUser.id();
    return Response.ok(mapper.toProto(requireOrCreate(userId))).build();
  }

  @PUT
  @Transactional
  @Operation(summary = "Replace the authenticated user's settings")
  // Declared by reference so SmallRye does not introspect the protobuf parameter; see
  // CategoryResource.create.
  @RequestBody(content = @Content(schema = @Schema(ref = "UpdateSettingsRequest")))
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "The settings AS STORED, which may differ from what was sent if a default was"
          + " substituted",
      content = @Content(schema = @Schema(ref = "Settings")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A non-empty main_currency that is not an ISO-4217 code",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response replace(UpdateSettingsRequest request) {
    UUID userId = currentUser.id();
    SettingsEntity entity = requireOrCreate(userId);

    String requested = request.getMainCurrency();
    if (requested == null || requested.isBlank()) {
      // AN EMPTY VALUE MEANS "RESET TO THE DEFAULT", not "leave unchanged" — the full-replacement
      // rule applied to a one-field message. proto3 has no presence for a string, so "" and unset
      // are the same bytes and one of the two readings had to be chosen; ADR-009 chose this one,
      // and there is nothing else in the message that "leave unchanged" could preserve anyway.
      entity.mainCurrency = SettingsEntity.DEFAULT_MAIN_CURRENCY;
    } else {
      String normalized = Currencies.normalize(requested);
      if (!Currencies.isValid(normalized)) {
        throw PrudentException.invalid("'" + requested + "' is not an ISO-4217 currency.");
      }
      // NOT checked against the user's accounts, deliberately: main_currency is a display
      // preference, and a user who picks PLN before opening their first account is a normal state
      // rather than an inconsistency to reject (ADR-009).
      entity.mainCurrency = normalized;
    }

    // Responds with the resulting Settings rather than an empty body: the server may have
    // substituted a default, and a client that has to re-read to learn what it just wrote is a
    // round trip the response could have saved.
    return Response.ok(mapper.toProto(entity)).build();
  }

  /**
   * The user's settings row, created on first touch if onboarding never ran for them.
   *
   * <p>{@link prudent.server.onboarding.NewUserSetup} creates this row when a user registers, so in
   * the ordinary case it exists. This fallback covers the one case that is not ordinary and is not
   * hypothetical: a user who registered before this feature shipped has no row, and answering their
   * {@code GET} with a 404 would be telling them their own settings do not exist. Creating on read
   * is safe because the row has no content that could be lost — every field has a defined default.
   */
  private SettingsEntity requireOrCreate(UUID userId) {
    SettingsEntity entity = SettingsEntity.findOwned(userId);
    if (entity == null) {
      entity = new SettingsEntity();
      entity.userId = userId;
      entity.mainCurrency = SettingsEntity.DEFAULT_MAIN_CURRENCY;
      entity.persist();
    }
    return entity;
  }
}
