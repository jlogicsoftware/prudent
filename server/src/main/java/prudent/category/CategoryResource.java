package prudent.category;

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
import java.time.Instant;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.proto.v1.CreateCategoryRequest;
import prudent.proto.v1.UpdateCategoryRequest;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.budget.BudgetCarryResetEntity;
import prudent.budget.BudgetEntity;
import prudent.error.PrudentException;
import prudent.plan.PlanEntity;
import prudent.record.RecordEntity;
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

  @POST
  @Path("/{id}/archive")
  @Transactional
  @Operation(
      summary = "Archive a category: take it out of use without losing its history",
      description =
          "An archived category stays in the list and keeps every record, plan, budget and"
              + " carry-over reset that points at it, so history stays readable and every total"
              + " is unchanged. It accepts no new record, plan or budget until restored.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "Category")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The category is already archived",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response archive(@PathParam("id") String id) {
    CategoryEntity entity = require(currentUser.id(), id);
    // Refused rather than made idempotent, as skip and restore are for occurrences (ADR-039): the
    // caller asked for a change that is not one, and should be told.
    if (entity.isArchived()) {
      throw PrudentException.conflict("This category is already archived.");
    }
    entity.archivedAt = Instant.now();
    return Response.ok(mapper.toProto(entity)).build();
  }

  @POST
  @Path("/{id}/restore")
  @Transactional
  @Operation(summary = "Restore an archived category to use")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "Category")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The category is not archived, so there is nothing to restore",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response restore(@PathParam("id") String id) {
    CategoryEntity entity = require(currentUser.id(), id);
    if (!entity.isArchived()) {
      throw PrudentException.conflict("This category is not archived.");
    }
    entity.archivedAt = null;
    return Response.ok(mapper.toProto(entity)).build();
  }

  @DELETE
  @Path("/{id}")
  @Transactional
  @Operation(summary = "Delete a category")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Deleted")
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description =
          "Something still points at the category: a record, plan, budget or carry-over reset."
              + " Archive it instead to take it out of use and keep the history.",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response delete(@PathParam("id") String id) {
    UUID userId = currentUser.id();
    CategoryEntity entity = require(userId, id);
    // REFUSED RATHER THAN CASCADED, and the way out is archiving (ADR-047). A category is only ever
    // deleted while nothing refers to it, so there is no history a delete could orphan or hide: a
    // used category is retired, never removed. Deleting one that still has records would orphan
    // them — the same failure ADR-008 refuses for dropping a currency that has records, so it gets
    // the same answer rather than a second philosophy.
    if (RecordEntity.existsForCategory(userId, entity.id)) {
      throw PrudentException.conflict(
          "This category still has records. Delete or re-categorise them first, or archive it.");
    }
    // The same refusal for plans (ADR-037): a plan filed under a deleted category would confirm
    // into a record with no category to file it under.
    if (PlanEntity.existsForCategory(userId, entity.id)) {
      throw PrudentException.conflict(
          "This category still has plans. Delete or re-categorise them first, or archive it.");
    }
    // And for budgets (ADR-043): the budget names a category that would no longer exist. Refused
    // rather than cascaded, so the amounts the user set are never deleted as a side effect.
    if (BudgetEntity.existsForCategory(userId, entity.id)) {
      throw PrudentException.conflict(
          "This category still has budgets. Delete them first, or archive it.");
    }
    // And for carry-over resets (ADR-046). Unlike a budget there is nothing to delete first: the
    // reset history is an audit trail and is never erased, so a category that has one stays, and
    // archiving is the only way it leaves use. That is the answer to what a removed category should
    // leave readable (jlogicsoftware/prudent#62, ADR-047): it is never removed while it has any.
    if (BudgetCarryResetEntity.existsForCategory(userId, entity.id)) {
      throw PrudentException.conflict(
          "This category has carry-over reset history, which is kept, so it cannot be deleted."
              + " Archive it instead.");
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
