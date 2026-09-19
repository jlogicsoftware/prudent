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
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.Currencies;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.account.AccountBalance;
import prudent.account.AccountEntity;
import prudent.error.PrudentException;
import prudent.proto.v1.CreateCorrectionRequest;
import zen.core.http.ZenStatus;

/**
 * Prudent's balance corrections: {@code /api/v1/corrections} (M1, jlogicsoftware/prudent#53).
 *
 * <p><strong>What this endpoint is for.</strong> "reconciliation records an auditable correction
 * instead of silently rewriting opening balance or transaction history" (the issue's acceptance
 * criterion). Before this existed, the only way to make Prudent's balance match a bank statement
 * was either to hand-edit {@code UpdateAccountRequest.balances} (which re-bases the derived
 * balance with no record of why) or to fabricate an ordinary record with a made-up category. Both
 * are silent: neither one is visibly a correction when read back later.
 *
 * <p>A correction is one {@link RecordEntity} row, like a transfer leg — there is no separate
 * balance to update, because an account's balance is derived from its records (docs/DECISIONS.md
 * ADR-014). The caller supplies the account's TRUE balance as observed (e.g. from a bank
 * statement); the server computes the delta against the account's current derived balance and
 * persists exactly that delta as {@code amountMinor}, with {@code isCorrection} set. The row IS
 * the audit trail: its amount, date and optional note say exactly what changed and by how much.
 *
 * <p>Once created, a correction cannot be edited or deleted through {@code RecordResource}: {@link
 * #delete} is the only way to remove one, the same restriction {@code TransferResource} places on
 * a transfer leg.
 */
@Path("/api/v1/corrections")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class CorrectionResource {

  @Inject CurrentUser currentUser;
  @Inject RecordMapper mapper;

  @POST
  @Transactional
  @Operation(
      summary = "Record an explicit balance correction against one of the caller's own accounts")
  @RequestBody(content = @Content(schema = @Schema(ref = "CreateCorrectionRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "Record")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "An account that is not the caller's, a malformed date, a currency the account does not"
              + " hold, or a target balance that already matches the account's current balance",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response create(CreateCorrectionRequest request) {
    UUID userId = currentUser.id();

    AccountEntity account =
        AccountEntity.findOwned(userId, Ids.parseInBody("account", request.getAccountId()));
    if (account == null) {
      throw PrudentException.invalid("No such account for this user: " + request.getAccountId());
    }

    String currency = Currencies.normalize(request.getCurrency());
    if (!Currencies.isValid(currency)) {
      throw PrudentException.invalid("'" + request.getCurrency() + "' is not an ISO-4217 currency.");
    }
    if (!AccountEntity.holds(account, currency)) {
      throw PrudentException.invalid(
          "Account '" + account.name + "' does not hold " + currency
              + ". Add the currency to the account first.");
    }

    LocalDate date = parseDate(request.getDate());

    // THE CURRENT DERIVED BALANCE (ADR-014): opening amount plus this account's net of records in
    // this currency — the same formula AccountMapper uses to answer what GET /api/v1/accounts
    // shows for this account today.
    long opening = 0L;
    for (AccountBalance balance : account.balances) {
      if (currency.equals(balance.currency)) {
        opening = balance.amountMinor;
        break;
      }
    }
    long net = RecordEntity.netByAccount(userId, account.id).getOrDefault(currency, 0L);
    long currentBalance = opening + net;
    long delta = request.getBalanceMinor() - currentBalance;

    // A correction that changes nothing is not a correction — see Record.amount_minor, which
    // forbids a zero-amount row for the same reason: it would be a no-op transaction that looks
    // like an intentional one, and a client that sent an already-matching balance by mistake gets
    // no signal that nothing happened.
    if (delta == 0) {
      throw PrudentException.invalid(
          "Account '" + account.name + "' already balances at " + request.getBalanceMinor() + " "
              + currency + "; there is nothing to correct.");
    }

    String title =
        request.hasTitle() && !request.getTitle().isBlank()
            ? request.getTitle().trim()
            : "Balance correction";

    RecordEntity entity = new RecordEntity();
    entity.id = UUID.randomUUID();
    entity.userId = userId;
    entity.title = title;
    entity.amountMinor = delta;
    entity.currency = currency;
    entity.date = date;
    entity.categoryId = null;
    entity.accountId = account.id;
    entity.isCorrection = true;
    entity.note = blankToNull(request.hasNote() ? request.getNote() : null);
    entity.persist();

    return Response.status(Response.Status.CREATED).entity(mapper.toProto(entity)).build();
  }

  @DELETE
  @Path("/{id}")
  @Transactional
  @Operation(summary = "Delete a balance correction")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Deleted")
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response delete(@PathParam("id") String id) {
    UUID userId = currentUser.id();
    RecordEntity entity = RecordEntity.findOwned(userId, Ids.parse("correction", id));
    // Not found either because the id is unknown/not the caller's, or it names a real record of
    // theirs that just isn't a correction — RecordResource, not this endpoint, owns that one.
    if (entity == null || !entity.isCorrection) {
      throw PrudentException.notFound("correction", id);
    }
    entity.delete();
    return Response.noContent().build();
  }

  /**
   * Both {@code title} and {@code note} are optional wire fields; a blank value is stored as
   * absent, matching {@code RecordResource}'s own rule.
   */
  private static String blankToNull(String value) {
    if (value == null) {
      return null;
    }
    String trimmed = value.trim();
    return trimmed.isEmpty() ? null : trimmed;
  }

  /**
   * Parses the ISO-8601 civil date the contract carries. Same strict behaviour as {@code
   * RecordResource.parseDate} — an impossible date is refused rather than rolled forward.
   */
  private static LocalDate parseDate(String date) {
    if (date == null || date.isBlank()) {
      throw PrudentException.invalid("A correction needs a date, as ISO-8601 YYYY-MM-DD.");
    }
    try {
      return LocalDate.parse(date);
    } catch (DateTimeParseException malformed) {
      throw PrudentException.invalid(
          "'" + date + "' is not an ISO-8601 date. Expected YYYY-MM-DD.");
    }
  }
}
