package prudent.server.category;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.proto.v1.CreateCategoryRequest;
import prudent.proto.v1.UpdateCategoryRequest;
import prudent.server.CurrentUser;
import prudent.server.Ids;
import prudent.server.PrudentException;
import prudent.server.record.RecordEntity;
import zen.core.http.ZenStatus;

/**
 * Prudent's categories: {@code /api/v1/categories}.
 *
 * <p>The shape here is the framework's and is not negotiable, so it is stated once:
 *
 * <ul>
 *   <li><strong>Every method returns {@link Response}, never a bare proto message.</strong>
 *       SmallRye cannot introspect a protobuf class — it documents the builder internals and emits
 *       a hundred-plus garbage schemas — and a bare proto return type also 500s at runtime, because
 *       it triggers Quarkus's build-time Jackson writer.
 *   <li><strong>The response schema is declared by reference</strong> into
 *       {@code META-INF/openapi.yaml}. Paths come from these annotations; schemas come from the
 *       application.
 *   <li><strong>{@code @Authenticated}, never {@code @RolesAllowed(USER)}.</strong> Roles are single
 *       and have no hierarchy, so gating on {@code USER} would 403 an admin.
 *   <li><strong>The resource never names a wire format.</strong> The {@code X-Zen-Transport} seam
 *       picks JSON or Protobuf; {@code @Produces} lists both and nothing else.
 * </ul>
 *
 * <p><strong>Ownership is resolved from the token on every verb</strong>, through
 * {@link CurrentUser}, and never read from a request body — the contract carries no {@code user_id}
 * field in either direction precisely so there is nothing to be tempted by.
 */
@Path("/api/v1/categories")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class CategoryResource {

  @Inject CurrentUser currentUser;
  @Inject CategoryMapper mapper;

  @GET
  @Operation(summary = "List the authenticated user's categories")
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "Every category owned by the caller",
      content = @Content(schema = @Schema(ref = "ListCategoriesResponse")))
  public Response list() {
    UUID userId = currentUser.id();
    return Response.ok(mapper.toListResponse(CategoryEntity.listOwnedBy(userId))).build();
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Read one category")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "Category")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "No such category for this user",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response get(@PathParam("id") String id) {
    UUID userId = currentUser.id();
    return Response.ok(mapper.toProto(require(userId, id))).build();
  }

  @POST
  @Transactional
  @Operation(summary = "Create a category")
  // The request schema is declared by reference for the SAME reason the response schema is:
  // SmallRye scans method PARAMETERS too, and left to introspect a protobuf-generated class it
  // documents the builder internals. Naming the schema here is what keeps the generated document
  // clean on the way in as well as on the way out.
  @RequestBody(content = @Content(schema = @Schema(ref = "CreateCategoryRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "Category")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A blank title, or an icon_key the client cannot render",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response create(CreateCategoryRequest request) {
    UUID userId = currentUser.id();
    CategoryEntity entity = new CategoryEntity();
    // THE ID IS SERVER-MINTED. The request message has no id field to read one from, which is the
    // contract enforcing what this line would otherwise merely prefer.
    entity.id = UUID.randomUUID();
    entity.userId = userId;
    apply(entity, request.getTitle(), request.getIconKey(), request.getDescription(),
        request.getColorArgb());
    entity.persist();
    return Response.status(Response.Status.CREATED).entity(mapper.toProto(entity)).build();
  }

  @PUT
  @Path("/{id}")
  @Transactional
  @Operation(summary = "Replace a category")
  @RequestBody(content = @Content(schema = @Schema(ref = "UpdateCategoryRequest")))
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Category")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response replace(@PathParam("id") String id, UpdateCategoryRequest request) {
    UUID userId = currentUser.id();
    CategoryEntity entity = require(userId, id);
    // A FULL REPLACEMENT, not a patch: every mutable field is applied, including one the client
    // sent as its proto3 default. Plain proto3 scalars have no presence, so an absent field and an
    // explicitly-sent default are byte-identical on the wire — a merge would have to guess which
    // it received, and would guess wrong half the time.
    apply(entity, request.getTitle(), request.getIconKey(), request.getDescription(),
        request.getColorArgb());
    return Response.ok(mapper.toProto(entity)).build();
  }

  @DELETE
  @Path("/{id}")
  @Transactional
  @Operation(summary = "Delete a category")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Deleted")
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The category still has records",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response delete(@PathParam("id") String id) {
    UUID userId = currentUser.id();
    CategoryEntity entity = require(userId, id);
    // REFUSED RATHER THAN CASCADED. Deleting a category that still has records would orphan them —
    // the same failure ADR-008 refuses for dropping a currency that has records, so it gets the
    // same answer rather than a second philosophy. The user deletes or re-categorises first.
    if (RecordEntity.existsForCategory(userId, entity.id)) {
      throw PrudentException.conflict(
          "This category still has records. Delete or re-categorise them first.");
    }
    entity.delete();
    return Response.noContent().build();
  }

  /** The one lookup, so "not found" and "not yours" cannot drift apart into two answers. */
  private CategoryEntity require(UUID userId, String id) {
    CategoryEntity entity = CategoryEntity.findOwned(userId, Ids.parse("category", id));
    if (entity == null) {
      throw PrudentException.notFound("category", id);
    }
    return entity;
  }

  /**
   * Validates and writes the mutable fields. Shared by create and replace so the two cannot
   * validate differently — a rule enforced on create and forgotten on update is a rule that holds
   * only until a user edits something.
   */
  private void apply(
      CategoryEntity entity, String title, String iconKey, String description, int colorArgb) {
    if (title == null || title.isBlank()) {
      throw PrudentException.invalid("A category needs a title.");
    }
    if (!IconKeys.permits(iconKey)) {
      throw PrudentException.invalid(
          "Unknown icon_key '" + iconKey + "'. Permitted: " + IconKeys.PERMITTED);
    }
    entity.title = title.trim();
    entity.iconKey = iconKey;
    entity.description = description == null ? "" : description;
    // Widened back to the unsigned value the column holds; see CategoryMapper.toUint32 for why the
    // column is BIGINT. Integer.toUnsignedLong rather than a plain cast: a plain cast would
    // sign-extend, storing 0xFF000000 as a negative number.
    entity.colorArgb = Integer.toUnsignedLong(colorArgb);
  }
}
