package prudent.record;

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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.proto.v1.CreateRecordRequest;
import prudent.proto.v1.UpdateRecordRequest;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.error.PrudentException;
import prudent.plan.PlanOccurrenceEntity;
import zen.core.http.ZenStatus;

/**
 * Prudent's records: {@code /api/v1/records}.
 *
 * <p>The resource shape is set out on {@link prudent.category.CategoryResource}.
 *
 * <p><strong>The list is unpaginated in v1</strong>, which the contract decides rather than this
 * class: a personal expense tracker's record list is bounded by one person's spending, and page
 * parameters no screen sends and no test exercises are ceremony. Adding them later is a
 * backward-compatible proto3 change plus two query parameters. See
 * {@code proto/prudent/v1/records.proto}.
 */
@Path("/api/v1/records")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class RecordResource {

  @Inject CurrentUser currentUser;
  @Inject RecordMapper mapper;
  @Inject RecordWriter writer;

  @GET
  @Operation(
      summary = "List the authenticated user's records, optionally filtered",
      description =
          "Query parameters (all optional, independently composable — see records.proto):"
              + " dateFrom/dateTo (ISO-8601 YYYY-MM-DD, inclusive), accountId/categoryId (UUID),"
              + " type (income|expense|transfer|correction), amountMin/amountMax (non-negative"
              + " minor units, inclusive, matched against the absolute amount), search"
              + " (case-insensitive substring against title/payee/note). Omitting a parameter"
              + " clears that filter; omitting all of them returns the full unfiltered list.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListRecordsResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A malformed dateFrom/dateTo, accountId/categoryId, type, or a negative amount",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response list(
      @QueryParam("dateFrom") String dateFromParam,
      @QueryParam("dateTo") String dateToParam,
      @QueryParam("accountId") String accountIdParam,
      @QueryParam("categoryId") String categoryIdParam,
      @QueryParam("type") String typeParam,
      @QueryParam("amountMin") Long amountMin,
      @QueryParam("amountMax") Long amountMax,
      @QueryParam("search") String search) {
    UUID userId = currentUser.id();
    LocalDate dateFrom = parseOptionalDate(dateFromParam, "dateFrom");
    LocalDate dateTo = parseOptionalDate(dateToParam, "dateTo");
    UUID accountId = parseOptionalUuid(accountIdParam, "accountId");
    UUID categoryId = parseOptionalUuid(categoryIdParam, "categoryId");
    RecordType type = RecordType.parse(typeParam);
    requireNonNegative(amountMin, "amountMin");
    requireNonNegative(amountMax, "amountMax");

    return Response.ok(
            mapper.toListResponse(
                RecordEntity.search(
                    userId, dateFrom, dateTo, accountId, categoryId, type, amountMin, amountMax,
                    search)))
        .build();
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Read one record")
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Record")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response get(@PathParam("id") String id) {
    UUID userId = currentUser.id();
    return Response.ok(mapper.toProto(require(userId, id))).build();
  }

  @POST
  @Transactional
  @Operation(summary = "Create a record")
  // Declared by reference so SmallRye does not introspect the protobuf parameter; see
  // CategoryResource.create.
  @RequestBody(content = @Content(schema = @Schema(ref = "CreateRecordRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "Record")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "A blank title, a malformed date, an account or category that is not the caller's, or a"
              + " currency the account does not hold",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response create(CreateRecordRequest request) {
    UUID userId = currentUser.id();
    RecordEntity entity = new RecordEntity();
    // Server-minted; the request message has no id field.
    entity.id = UUID.randomUUID();
    entity.userId = userId;
    writer.apply(entity, userId, request.getTitle(), request.getAmountMinor(), request.getDate(),
        request.getCategoryId(), request.getAccountId(), request.getCurrency(),
        request.getPayee(), request.getNote());
    entity.persist();
    return Response.status(Response.Status.CREATED).entity(mapper.toProto(entity)).build();
  }

  @PUT
  @Path("/{id}")
  @Transactional
  @Operation(summary = "Replace a record")
  @RequestBody(content = @Content(schema = @Schema(ref = "UpdateRecordRequest")))
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Record")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description =
          "The record is a transfer leg or a balance correction; delete it via its own endpoint"
              + " instead of editing it",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response replace(@PathParam("id") String id, UpdateRecordRequest request) {
    UUID userId = currentUser.id();
    RecordEntity entity = require(userId, id);
    requireNotTransferLeg(entity);
    requireNotCorrection(entity);
    writer.apply(entity, userId, request.getTitle(), request.getAmountMinor(), request.getDate(),
        request.getCategoryId(), request.getAccountId(), request.getCurrency(),
        request.getPayee(), request.getNote());
    return Response.ok(mapper.toProto(entity)).build();
  }

  @DELETE
  @Path("/{id}")
  @Transactional
  @Operation(summary = "Delete a record")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Deleted")
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description =
          "The record is a transfer leg or a balance correction; delete it via its own endpoint"
              + " instead",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response delete(@PathParam("id") String id) {
    UUID userId = currentUser.id();
    RecordEntity entity = require(userId, id);
    requireNotTransferLeg(entity);
    requireNotCorrection(entity);
    if (entity.planOccurrenceId != null) {
      // A confirmed occurrence is COMPLETED because this record exists. Without it the occurrence
      // would claim a transaction that is gone -- and, being final, could never be confirmed
      // again -- so it goes back to being open. Locked like every other transition, so this cannot
      // interleave with a confirmation of the same occurrence.
      PlanOccurrenceEntity occurrence =
          PlanOccurrenceEntity.findOwnedForUpdate(userId, entity.planOccurrenceId);
      if (occurrence != null) {
        occurrence.reopen();
      }
    }
    // A HARD DELETE. A soft delete would leave the row readable by Phase 4's analytics, which is
    // the problem rather than the feature: a user who deletes a mistyped 5,000 PLN entry and still
    // sees it in a total is looking at a wrong number that looks right.
    entity.delete();
    return Response.noContent().build();
  }

  private RecordEntity require(UUID userId, String id) {
    RecordEntity entity = RecordEntity.findOwned(userId, Ids.parse("record", id));
    if (entity == null) {
      throw PrudentException.notFound("record", id);
    }
    return entity;
  }

  /**
   * Refuses to touch a transfer leg through the single-record endpoints. A transfer's two rows
   * are linked by {@code transferId} (jlogicsoftware/prudent#32); editing or deleting one leg
   * here would silently break that pairing. {@code DELETE /api/v1/transfers/{id}} is the only way
   * to remove one, and a transfer is never edited in place — delete and recreate it instead.
   */
  private static void requireNotTransferLeg(RecordEntity entity) {
    if (entity.transferId != null) {
      throw PrudentException.conflict(
          "This record is part of a transfer and cannot be changed directly. Delete the transfer"
              + " (DELETE /api/v1/transfers/{id}) instead.");
    }
  }

  /**
   * Refuses to touch a balance correction through the single-record endpoints (M1,
   * jlogicsoftware/prudent#53). A correction is the auditable trail the acceptance criterion asks
   * for — editing it in place here would let it be silently turned into a different amount after
   * the fact, exactly what a correction exists to prevent. {@code DELETE /api/v1/corrections/{id}}
   * is the only way to remove one, and a correction is never edited — create a new one instead.
   */
  private static void requireNotCorrection(RecordEntity entity) {
    if (entity.isCorrection) {
      throw PrudentException.conflict(
          "This record is a balance correction and cannot be changed directly. Delete it"
              + " (DELETE /api/v1/corrections/{id}) instead.");
    }
  }

  /**
   * The {@code dateFrom}/{@code dateTo} filter params: {@code null} means the caller sent no
   * filter for that end of the range, so it is returned as-is rather than rejected. A present but
   * malformed value is still a refusal, via {@link RecordWriter#parseDate}.
   */
  private static LocalDate parseOptionalDate(String date, String paramName) {
    if (date == null || date.isBlank()) {
      return null;
    }
    try {
      return LocalDate.parse(date);
    } catch (DateTimeParseException malformed) {
      throw PrudentException.invalid(
          "'" + date + "' is not an ISO-8601 date for " + paramName + ". Expected YYYY-MM-DD.");
    }
  }

  /**
   * An {@code accountId}/{@code categoryId} filter param: {@code null}/blank means no filter for
   * that criterion. A present but malformed value is a 400 — unlike a path id, this never reaches
   * a not-found row, so there is no reason to prefer 404 the way {@link Ids#parse} does.
   */
  private static UUID parseOptionalUuid(String id, String paramName) {
    if (id == null || id.isBlank()) {
      return null;
    }
    try {
      return UUID.fromString(id);
    } catch (IllegalArgumentException notAUuid) {
      throw PrudentException.invalid("'" + id + "' is not a valid " + paramName + ".");
    }
  }

  private static void requireNonNegative(Long value, String paramName) {
    if (value != null && value < 0) {
      throw PrudentException.invalid(paramName + " must not be negative.");
    }
  }
}
