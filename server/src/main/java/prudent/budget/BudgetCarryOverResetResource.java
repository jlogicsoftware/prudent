package prudent.budget;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.Instant;
import java.time.YearMonth;
import java.util.Set;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.category.CategoryEntity;
import prudent.error.PrudentException;
import prudent.proto.v1.BudgetCarryOverReset;
import prudent.proto.v1.ResetBudgetCarryOverRequest;
import zen.core.http.ZenStatus;

/**
 * Carry-over resets and their audit history: {@code /api/v1/budget-carry-over-resets} (M3,
 * jlogicsoftware/prudent#61, ADR-046).
 *
 * <p>A reset makes a category's carry-over (ADR-045) start again from a chosen month. It is a
 * <strong>boundary the calculation stops at</strong> and nothing else: no budget is deleted, no
 * record changes, and no earlier month's own plan, actual or remaining moves, because carry-over is
 * calculated on read and a reset only narrows which earlier months are summed.
 *
 * <p>Every reset is an audit entry, and <strong>there is no DELETE</strong>. {@code POST
 * /{id}/revoke} takes a reset back by marking the same entry revoked — who and when — so the
 * history still shows that it happened. Each entry records who made it, when, the carry-over it
 * discarded and an optional note, and the summary names the reset that bounds each figure, so a
 * carry-over that a reset changed is never silently different.
 *
 * <p>The resource shape is set out on {@link prudent.category.CategoryResource}.
 */
@Path("/api/v1/budget-carry-over-resets")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class BudgetCarryOverResetResource {

  /** Matches the schema's {@code char_length(note) <= 500}, which counts characters. */
  static final int MAX_NOTE_LENGTH = 500;

  @Inject CurrentUser currentUser;
  @Inject BudgetMapper mapper;

  @GET
  @Operation(
      summary = "The authenticated user's carry-over reset history",
      description =
          "Every reset, revoked ones included, newest first. Optionally narrowed by categoryId"
              + " (UUID) and currency (ISO-4217).")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListBudgetCarryOverResetsResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A malformed categoryId or currency",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response history(
      @QueryParam("categoryId") String categoryId, @QueryParam("currency") String currency) {
    UUID parsedCategory =
        categoryId == null || categoryId.isBlank() ? null : Ids.parseInBody("category", categoryId);
    String parsedCurrency =
        currency == null || currency.isBlank() ? null : BudgetResource.parseCurrency(currency);
    return Response.ok(
            mapper.toHistoryResponse(
                BudgetCarryResetEntity.history(
                    currentUser.id(), parsedCategory, parsedCurrency)))
        .build();
  }

  @POST
  @Transactional
  @Operation(
      summary = "Reset one category's carry-over from a month onward",
      description =
          "Carry-over into the month becomes zero and only budgeted months from it on count toward"
              + " later months, in that currency. Earlier budgets are kept and earlier months'"
              + " own figures do not change. The entry records the carry-over it discarded.")
  @RequestBody(content = @Content(schema = @Schema(ref = "ResetBudgetCarryOverRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "BudgetCarryOverReset")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "A malformed category id, month or currency, or a note longer than 500 characters",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "No such category for this user",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "That category, month and currency already has a reset in effect",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response reset(ResetBudgetCarryOverRequest request) {
    UUID userId = currentUser.id();
    UUID category = Ids.parseInBody("category", request.getCategoryId());
    if (CategoryEntity.findOwned(userId, category) == null) {
      throw PrudentException.notFound("category", request.getCategoryId());
    }
    YearMonth month = BudgetResource.parseMonth(request.getMonth());
    String currency = BudgetResource.parseCurrency(request.getCurrency());
    String note = request.getNote().strip();
    if (note.codePointCount(0, note.length()) > MAX_NOTE_LENGTH) {
      throw PrudentException.invalid(
          "A note may be at most " + MAX_NOTE_LENGTH + " characters.");
    }

    // What the user is about to discard, from the same calculation the summary shows — so the
    // entry records the number they saw, not a second derivation of it.
    long discarded =
        BudgetResource.carryOverInto(userId, month, currency, Set.of(category))
            .amountByCategory()
            .getOrDefault(category, 0L);

    UUID id = UUID.randomUUID();
    Instant now = Instant.now();
    if (!BudgetCarryResetEntity.insertLive(
        id, userId, category, month, currency, discarded, note, now)) {
      throw PrudentException.conflict(
          "The carry-over of this category is already reset from " + month + " in " + currency
              + ". Revoke that reset first if you want to make it again.");
    }

    // Built from the values just written: the insert is native, so the persistence context holds
    // no entity for it.
    BudgetCarryOverReset entry =
        BudgetCarryOverReset.newBuilder()
            .setId(id.toString())
            .setCategoryId(category.toString())
            .setMonth(month.toString())
            .setCurrency(currency)
            .setDiscardedMinor(discarded)
            .setNote(note)
            .setCreatedBy(userId.toString())
            .setCreatedAtMs(now.toEpochMilli())
            .build();
    return Response.status(Response.Status.CREATED).entity(entry).build();
  }

  @POST
  @Path("/{id}/revoke")
  @Transactional
  @Operation(
      summary = "Take a carry-over reset back",
      description =
          "Marks the entry revoked with who and when, and it stops bounding the carry-over. The"
              + " entry stays in the history; nothing is deleted.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "BudgetCarryOverReset")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "No such reset for this user",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The reset was already revoked",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response revoke(@PathParam("id") String id) {
    UUID userId = currentUser.id();
    UUID resetId = Ids.parse("carry-over reset", id);
    if (BudgetCarryResetEntity.findOwned(userId, resetId) == null) {
      throw PrudentException.notFound("carry-over reset", id);
    }
    if (!BudgetCarryResetEntity.revoke(userId, resetId, Instant.now())) {
      throw PrudentException.conflict("This reset was already revoked.");
    }
    // The revoke is a bulk update, so the entity loaded above is stale; read the row again.
    BudgetCarryResetEntity.getEntityManager().clear();
    return Response.ok(mapper.toProto(BudgetCarryResetEntity.findOwned(userId, resetId))).build();
  }
}
