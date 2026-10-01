package prudent.goal;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.Currencies;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.error.PrudentException;
import prudent.proto.v1.CreateGoalRequest;
import prudent.proto.v1.UpdateGoalRequest;
import zen.core.http.ZenStatus;

/**
 * Prudent's savings goals: {@code /api/v1/goals} (M4, jlogicsoftware/prudent#38, ADR-049).
 *
 * <p>A goal is a name, a currency, a positive target amount and an optional target date, in one of
 * three lifecycle states ({@link GoalState}). Creating, editing or changing the state of one
 * touches only {@code prudent_goal}; no balance, record or analytics total moves.
 *
 * <p><strong>There is no DELETE.</strong> A goal is completed or archived, never removed, so the
 * history later M4 tasks keep against it stays readable (ADR-049).
 *
 * <p>The resource shape is set out on {@link prudent.category.CategoryResource}.
 */
@Path("/api/v1/goals")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class GoalResource {

  @Inject CurrentUser currentUser;
  @Inject GoalMapper mapper;

  @GET
  @Operation(
      summary = "List the authenticated user's goals",
      description =
          "Optionally narrowed by status (ACTIVE, COMPLETED or ARCHIVED), oldest first. Archived"
              + " and completed goals are listed like any other: nothing is ever removed.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListGoalsResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A status that is not ACTIVE, COMPLETED or ARCHIVED",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response list(@QueryParam("status") String status) {
    GoalState parsed = status == null || status.isBlank() ? null : parseStatus(status);
    return Response.ok(mapper.toListResponse(GoalEntity.listOwnedBy(currentUser.id(), parsed)))
        .build();
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Read one goal")
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Goal")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "No such goal for this user",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response get(@PathParam("id") String id) {
    return Response.ok(mapper.toProto(require(currentUser.id(), id))).build();
  }

  @POST
  @Transactional
  @Operation(summary = "Create a goal", description = "The goal starts ACTIVE.")
  @RequestBody(content = @Content(schema = @Schema(ref = "CreateGoalRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "Goal")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "A blank name, a currency that is not ISO-4217, a target amount that is not positive,"
              + " or a target date that is not YYYY-MM-DD",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response create(CreateGoalRequest request) {
    GoalEntity entity = new GoalEntity();
    // Server-minted; the request message has no id field.
    entity.id = UUID.randomUUID();
    entity.userId = currentUser.id();
    entity.currency = parseCurrency(request.getCurrency());
    entity.status = GoalState.ACTIVE;
    entity.createdAt = Instant.now();
    entity.statusChangedAt = entity.createdAt;
    apply(
        entity,
        request.getName(),
        request.getTargetAmountMinor(),
        request.hasTargetDate() ? request.getTargetDate() : null);
    entity.persist();
    return Response.status(Response.Status.CREATED).entity(mapper.toProto(entity)).build();
  }

  @PUT
  @Path("/{id}")
  @Transactional
  @Operation(
      summary = "Replace a goal's name, target amount and target date",
      description =
          "A full replacement: an absent targetDate clears it. The currency and the status are not"
              + " editable here. An archived goal is read-only until it is reactivated.")
  @RequestBody(content = @Content(schema = @Schema(ref = "UpdateGoalRequest")))
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Goal")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The goal is archived",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response replace(@PathParam("id") String id, UpdateGoalRequest request) {
    GoalEntity entity = require(currentUser.id(), id);
    // Read-only once archived: the user retired it, so a stray edit must not change what the
    // archive recorded. Reactivating it is the explicit way back to editing.
    if (entity.status == GoalState.ARCHIVED) {
      throw PrudentException.conflict("This goal is archived. Reactivate it to edit it.");
    }
    // A FULL REPLACEMENT, for the reason CategoryResource.replace gives: an absent date is a
    // cleared date, not an unchanged one.
    apply(
        entity,
        request.getName(),
        request.getTargetAmountMinor(),
        request.hasTargetDate() ? request.getTargetDate() : null);
    return Response.ok(mapper.toProto(entity)).build();
  }

  @POST
  @Path("/{id}/complete")
  @Transactional
  @Operation(summary = "Mark an active goal as reached")
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Goal")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The goal is not active",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response complete(@PathParam("id") String id) {
    return transition(id, GoalState.COMPLETED);
  }

  @POST
  @Path("/{id}/archive")
  @Transactional
  @Operation(
      summary = "Archive a goal: retire it without losing its history",
      description =
          "An archived goal stays in the list and is read-only. Archiving deletes nothing.")
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Goal")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The goal is already archived",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response archive(@PathParam("id") String id) {
    return transition(id, GoalState.ARCHIVED);
  }

  @POST
  @Path("/{id}/reactivate")
  @Transactional
  @Operation(summary = "Return a completed or archived goal to active")
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Goal")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The goal is already active",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response reactivate(@PathParam("id") String id) {
    return transition(id, GoalState.ACTIVE);
  }

  private Response transition(String id, GoalState target) {
    GoalEntity entity = require(currentUser.id(), id);
    entity.transitionTo(target, Instant.now());
    return Response.ok(mapper.toProto(entity)).build();
  }

  /** The one lookup, so "not found" and "not yours" cannot drift apart into two answers. */
  private GoalEntity require(UUID userId, String id) {
    GoalEntity entity = GoalEntity.findOwned(userId, Ids.parse("goal", id));
    if (entity == null) {
      throw PrudentException.notFound("goal", id);
    }
    return entity;
  }

  /**
   * Validates and writes the fields a client may edit. Shared by create and replace, so a rule
   * cannot hold on create and lapse on edit.
   */
  private static void apply(GoalEntity entity, String name, long targetAmountMinor, String date) {
    if (name == null || name.isBlank()) {
      throw PrudentException.invalid("A goal needs a name.");
    }
    // Positive, not merely nonzero: a goal is an amount to reach. Zero is also what an omitted
    // field decodes to, so refusing it keeps a body that forgot the target from becoming a goal of
    // nothing.
    if (targetAmountMinor <= 0) {
      throw PrudentException.invalid("A goal needs a positive target amount.");
    }
    entity.name = name.strip();
    entity.targetAmountMinor = targetAmountMinor;
    entity.targetDate = date == null ? null : parseDate(date);
  }

  static String parseCurrency(String currency) {
    String normalized = Currencies.normalize(currency);
    if (!Currencies.isValid(normalized)) {
      throw PrudentException.invalid("'" + currency + "' is not an ISO-4217 currency.");
    }
    return normalized;
  }

  /** Strict {@code YYYY-MM-DD}; an impossible date is refused rather than rolled forward. */
  static LocalDate parseDate(String date) {
    try {
      return LocalDate.parse(date);
    } catch (DateTimeParseException malformed) {
      throw PrudentException.invalid(
          "'" + date + "' is not an ISO-8601 target date. Expected YYYY-MM-DD.");
    }
  }

  /** The status a query names, by exact constant name — refused, not guessed, when it is not one. */
  static GoalState parseStatus(String status) {
    try {
      return GoalState.valueOf(status);
    } catch (IllegalArgumentException unknown) {
      throw PrudentException.invalid(
          "'" + status + "' is not a goal status. Expected ACTIVE, COMPLETED or ARCHIVED.");
    }
  }
}
