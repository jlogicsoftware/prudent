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
import prudent.Currencies;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.error.PrudentException;
import prudent.account.AccountBalance;
import prudent.account.AccountEntity;
import prudent.category.CategoryEntity;
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

  @GET
  @Operation(summary = "List the authenticated user's records")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListRecordsResponse")))
  public Response list() {
    UUID userId = currentUser.id();
    return Response.ok(mapper.toListResponse(RecordEntity.listOwnedBy(userId))).build();
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
    apply(entity, userId, request.getTitle(), request.getAmountMinor(), request.getDate(),
        request.getCategoryId(), request.getAccountId(), request.getCurrency());
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
  public Response replace(@PathParam("id") String id, UpdateRecordRequest request) {
    UUID userId = currentUser.id();
    RecordEntity entity = require(userId, id);
    apply(entity, userId, request.getTitle(), request.getAmountMinor(), request.getDate(),
        request.getCategoryId(), request.getAccountId(), request.getCurrency());
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
  public Response delete(@PathParam("id") String id) {
    UUID userId = currentUser.id();
    // A HARD DELETE. A soft delete would leave the row readable by Phase 4's analytics, which is
    // the problem rather than the feature: a user who deletes a mistyped 5,000 PLN entry and still
    // sees it in a total is looking at a wrong number that looks right.
    require(userId, id).delete();
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
   * Validates and writes every mutable field. Shared by create and replace, so a rule cannot hold
   * on create and lapse on edit.
   *
   * <p><strong>The account and the currency are validated together</strong>, because moving a
   * record between accounts and changing its currency are one operation: checking the currency
   * against the <em>old</em> account would let a client move a PLN record into a EUR-only account
   * by sending both changes at once.
   */
  private void apply(
      RecordEntity entity,
      UUID userId,
      String title,
      long amountMinor,
      String date,
      String categoryId,
      String accountId,
      String currency) {

    if (title == null || title.isBlank()) {
      throw PrudentException.invalid("A record needs a title.");
    }

    // SIGNED (records.proto, ADR-014): negative is an expense, positive is income. Zero moves
    // nothing and is refused rather than stored as a no-op transaction — a balance summed over a
    // zero-amount row would be correct by accident, and a client that sent zero by mistake would
    // get no signal that anything was wrong.
    if (amountMinor == 0) {
      throw PrudentException.invalid(
          "A record needs a nonzero amount. Negative is an expense, positive is income.");
    }

    // The owning account, looked up AS THE CALLER'S. An account id that is not theirs is refused
    // here rather than stored — a client that can name someone else's account can move money into
    // it.
    AccountEntity account =
        AccountEntity.findOwned(userId, Ids.parseInBody("account", accountId));
    if (account == null) {
      throw PrudentException.invalid("No such account for this user: " + accountId);
    }

    CategoryEntity category =
        CategoryEntity.findOwned(userId, Ids.parseInBody("category", categoryId));
    if (category == null) {
      throw PrudentException.invalid("No such category for this user: " + categoryId);
    }

    String normalized = Currencies.normalize(currency);
    if (!Currencies.isValid(normalized)) {
      throw PrudentException.invalid("'" + currency + "' is not an ISO-4217 currency.");
    }
    // THE REFUSAL THAT REPLACED INHERITANCE (ADR-008). When an account held one currency a record
    // inherited it and disagreement was impossible to express; with several, only the record knows
    // which balance it moved, so the guarantee is this check instead.
    if (!holds(account, normalized)) {
      throw PrudentException.invalid(
          "Account '" + account.name + "' does not hold " + normalized
              + ". Add the currency to the account first.");
    }

    entity.title = title.trim();
    entity.amountMinor = amountMinor;
    entity.currency = normalized;
    entity.date = parseDate(date);
    entity.categoryId = category.id;
    entity.accountId = account.id;
  }

  private static boolean holds(AccountEntity account, String currency) {
    for (AccountBalance balance : account.balances) {
      if (currency.equals(balance.currency)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Parses the ISO-8601 civil date the contract carries.
   *
   * <p>{@link LocalDate#parse} is strict about {@code YYYY-MM-DD} and rejects an impossible date
   * such as {@code 2026-02-30} rather than rolling it forward — which is the behaviour wanted here,
   * because a rolled date is a record filed in a month the user did not choose.
   */
  private static LocalDate parseDate(String date) {
    if (date == null || date.isBlank()) {
      throw PrudentException.invalid("A record needs a date, as ISO-8601 YYYY-MM-DD.");
    }
    try {
      return LocalDate.parse(date);
    } catch (DateTimeParseException malformed) {
      // Converted to a refusal the caller can read, never defaulted to today: a record silently
      // filed on the wrong day is a wrong total in whatever month it lands in.
      throw PrudentException.invalid(
          "'" + date + "' is not an ISO-8601 date. Expected YYYY-MM-DD.");
    }
  }
}
