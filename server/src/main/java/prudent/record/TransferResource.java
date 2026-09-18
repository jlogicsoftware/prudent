package prudent.record;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.Currencies;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.account.AccountEntity;
import prudent.error.PrudentException;
import prudent.proto.v1.CreateTransferRequest;
import zen.core.http.ZenStatus;

/**
 * Prudent's transfers: {@code /api/v1/transfers} (jlogicsoftware/prudent#32,
 * jlogicsoftware/prudent#50).
 *
 * <p>A transfer is two linked {@link RecordEntity} rows sharing one {@code transferId}: a negative
 * leg on the source account and a positive leg on the destination account. There is no separate
 * balance to update — an account's balance is derived from its records (docs/DECISIONS.md
 * ADR-014), so persisting both rows in one {@code @Transactional} method IS the atomic balance
 * update. Neither leg carries a category: a transfer is neither income nor expense, and
 * {@link RecordEntity#expenseRows} excludes any row with a non-null {@code transferId} from
 * analytics.
 *
 * <p><strong>Cross-currency (ADR-032):</strong> each leg carries its own amount and currency. A
 * same-currency transfer is simply the case where the two happen to agree — there is no separate
 * mode, no rate lookup, and no arithmetic linking one leg's amount to the other's. The user enters
 * both amounts explicitly; the server persists exactly what was entered.
 *
 * <p>Once created, a transfer's legs cannot be edited or deleted individually: {@code
 * RecordResource} refuses to touch a record with a non-null {@code transferId}. {@link #delete}
 * is the only way to remove one.
 */
@Path("/api/v1/transfers")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class TransferResource {

  @Inject CurrentUser currentUser;
  @Inject RecordMapper mapper;

  @POST
  @Transactional
  @Operation(summary = "Create a transfer between two of the caller's own accounts")
  @RequestBody(content = @Content(schema = @Schema(ref = "CreateTransferRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "Transfer")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "A non-positive amount on either leg, the same account on both sides, an account that"
              + " is not the caller's, a malformed date, or a currency an account does not hold",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response create(CreateTransferRequest request) {
    UUID userId = currentUser.id();

    if (request.getFromAmountMinor() <= 0) {
      throw PrudentException.invalid("A transfer needs a positive source amount.");
    }
    if (request.getToAmountMinor() <= 0) {
      throw PrudentException.invalid("A transfer needs a positive destination amount.");
    }

    AccountEntity fromAccount =
        AccountEntity.findOwned(userId, Ids.parseInBody("account", request.getFromAccountId()));
    if (fromAccount == null) {
      throw PrudentException.invalid("No such account for this user: " + request.getFromAccountId());
    }
    AccountEntity toAccount =
        AccountEntity.findOwned(userId, Ids.parseInBody("account", request.getToAccountId()));
    if (toAccount == null) {
      throw PrudentException.invalid("No such account for this user: " + request.getToAccountId());
    }
    if (fromAccount.id.equals(toAccount.id)) {
      throw PrudentException.invalid("A transfer needs two different accounts.");
    }

    String fromCurrency = Currencies.normalize(request.getFromCurrency());
    if (!Currencies.isValid(fromCurrency)) {
      throw PrudentException.invalid(
          "'" + request.getFromCurrency() + "' is not an ISO-4217 currency.");
    }
    if (!AccountEntity.holds(fromAccount, fromCurrency)) {
      throw PrudentException.invalid(
          "Account '" + fromAccount.name + "' does not hold " + fromCurrency
              + ". Add the currency to the account first.");
    }

    String toCurrency = Currencies.normalize(request.getToCurrency());
    if (!Currencies.isValid(toCurrency)) {
      throw PrudentException.invalid(
          "'" + request.getToCurrency() + "' is not an ISO-4217 currency.");
    }
    if (!AccountEntity.holds(toAccount, toCurrency)) {
      throw PrudentException.invalid(
          "Account '" + toAccount.name + "' does not hold " + toCurrency
              + ". Add the currency to the account first.");
    }

    LocalDate date = parseDate(request.getDate());
    String title = request.getTitle() == null || request.getTitle().isBlank()
        ? "Transfer" : request.getTitle().trim();

    UUID transferId = UUID.randomUUID();

    RecordEntity from = new RecordEntity();
    from.id = UUID.randomUUID();
    from.userId = userId;
    from.title = title;
    from.amountMinor = -request.getFromAmountMinor();
    from.currency = fromCurrency;
    from.date = date;
    from.categoryId = null;
    from.accountId = fromAccount.id;
    from.transferId = transferId;
    from.persist();

    RecordEntity to = new RecordEntity();
    to.id = UUID.randomUUID();
    to.userId = userId;
    to.title = title;
    to.amountMinor = request.getToAmountMinor();
    to.currency = toCurrency;
    to.date = date;
    to.categoryId = null;
    to.accountId = toAccount.id;
    to.transferId = transferId;
    to.persist();

    return Response.status(Response.Status.CREATED)
        .entity(mapper.toTransferProto(transferId, from, to))
        .build();
  }

  @DELETE
  @Path("/{transferId}")
  @Transactional
  @Operation(summary = "Delete both legs of a transfer atomically")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Deleted")
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response delete(@PathParam("transferId") String transferId) {
    UUID userId = currentUser.id();
    UUID id = Ids.parse("transfer", transferId);
    List<RecordEntity> legs = RecordEntity.findByTransferId(userId, id);
    // Exactly two legs, or this id is not a real transfer of the caller's — not found either way.
    if (legs.size() != 2) {
      throw PrudentException.notFound("transfer", transferId);
    }
    for (RecordEntity leg : legs) {
      leg.delete();
    }
    return Response.noContent().build();
  }

  /**
   * Parses the ISO-8601 civil date the contract carries. Same strict behaviour as
   * {@code RecordResource.parseDate} — an impossible date is refused rather than rolled forward.
   */
  private static LocalDate parseDate(String date) {
    if (date == null || date.isBlank()) {
      throw PrudentException.invalid("A transfer needs a date, as ISO-8601 YYYY-MM-DD.");
    }
    try {
      return LocalDate.parse(date);
    } catch (DateTimeParseException malformed) {
      throw PrudentException.invalid(
          "'" + date + "' is not an ISO-8601 date. Expected YYYY-MM-DD.");
    }
  }
}
