package prudent.server.account;

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
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.proto.v1.AccountType;
import prudent.proto.v1.CreateAccountRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.UpdateAccountRequest;
import prudent.server.Currencies;
import prudent.server.CurrentUser;
import prudent.server.Ids;
import prudent.server.PrudentException;
import prudent.server.record.RecordEntity;
import zen.core.http.ZenStatus;

/**
 * Prudent's accounts: {@code /api/v1/accounts}.
 *
 * <p>The resource shape — {@code Response} returns, schemas by {@code $ref}, {@code @Authenticated},
 * no wire format named — is set out on {@link prudent.server.category.CategoryResource} and is the
 * same here.
 *
 * <p><strong>This resource carries the multi-currency rules</strong> that ADR-008 could not express
 * in the message itself, and each is a refusal rather than a best-effort repair. They are gathered
 * in {@link #applyBalances} so that create and update cannot enforce them differently.
 */
@Path("/api/v1/accounts")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class AccountResource {

  @Inject CurrentUser currentUser;
  @Inject AccountMapper mapper;

  @GET
  @Operation(summary = "List the authenticated user's accounts")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListAccountsResponse")))
  public Response list() {
    UUID userId = currentUser.id();
    return Response.ok(mapper.toListResponse(AccountEntity.listOwnedBy(userId))).build();
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Read one account")
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Account")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response get(@PathParam("id") String id) {
    UUID userId = currentUser.id();
    return Response.ok(mapper.toProto(require(userId, id))).build();
  }

  @POST
  @Transactional
  @Operation(summary = "Create an account")
  // Declared by reference so SmallRye does not introspect the protobuf parameter; see
  // CategoryResource.create.
  @RequestBody(content = @Content(schema = @Schema(ref = "CreateAccountRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "Account")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A blank name, an unspecified type, or an empty/duplicate/unknown currency set",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response create(CreateAccountRequest request) {
    UUID userId = currentUser.id();
    AccountEntity entity = new AccountEntity();
    // Server-minted; the request message has no id field.
    entity.id = UUID.randomUUID();
    entity.userId = userId;
    applyScalars(entity, request.getName(), request.getType(), request.getIsDefault(),
        request.getIsActive(), request.getIncludeInTotal(), request.getIncludeInOverview());
    applyBalances(entity, request.getBalancesList(), Set.of());
    entity.persist();
    enforceSingleDefault(userId, entity);
    return Response.status(Response.Status.CREATED).entity(mapper.toProto(entity)).build();
  }

  @PUT
  @Path("/{id}")
  @Transactional
  @Operation(summary = "Replace an account")
  @RequestBody(content = @Content(schema = @Schema(ref = "UpdateAccountRequest")))
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Account")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The update drops a currency that still has records",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response replace(@PathParam("id") String id, UpdateAccountRequest request) {
    UUID userId = currentUser.id();
    AccountEntity entity = require(userId, id);
    applyScalars(entity, request.getName(), request.getType(), request.getIsDefault(),
        request.getIsActive(), request.getIncludeInTotal(), request.getIncludeInOverview());
    // The currencies that must survive this update, because records are denominated in them.
    applyBalances(entity, request.getBalancesList(), RecordEntity.currenciesInUse(userId, entity.id));
    enforceSingleDefault(userId, entity);
    return Response.ok(mapper.toProto(entity)).build();
  }

  @DELETE
  @Path("/{id}")
  @Transactional
  @Operation(summary = "Delete an account")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Deleted")
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The account still has records",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response delete(@PathParam("id") String id) {
    UUID userId = currentUser.id();
    AccountEntity entity = require(userId, id);
    // Refused rather than cascaded — see the same rule on categories, and ADR-008's reasoning about
    // money that left an account no longer admitting it exists.
    if (RecordEntity.existsForAccount(userId, entity.id)) {
      throw PrudentException.conflict(
          "This account still has records. Delete or move them first.");
    }
    entity.delete();
    return Response.noContent().build();
  }

  private AccountEntity require(UUID userId, String id) {
    AccountEntity entity = AccountEntity.findOwned(userId, Ids.parse("account", id));
    if (entity == null) {
      throw PrudentException.notFound("account", id);
    }
    return entity;
  }

  private void applyScalars(
      AccountEntity entity,
      String name,
      AccountType type,
      boolean isDefault,
      boolean isActive,
      boolean includeInTotal,
      boolean includeInOverview) {
    if (name == null || name.isBlank()) {
      throw PrudentException.invalid("An account needs a name.");
    }
    AccountKind kind = AccountKind.fromProto(type);
    if (kind == null) {
      // UNSPECIFIED is what proto3 decodes an omitted field to, and cash is a valid answer — so
      // defaulting here would make "the client forgot" indistinguishable from "the client meant
      // cash". Refusing is the only answer that does not invent data.
      throw PrudentException.invalid(
          "An account needs a type. ACCOUNT_TYPE_UNSPECIFIED is what an omitted field decodes to,"
              + " and it is not a kind of account.");
    }
    entity.name = name.trim();
    entity.kind = kind;
    entity.isDefault = isDefault;
    entity.isActive = isActive;
    entity.includeInTotal = includeInTotal;
    entity.includeInOverview = includeInOverview;
  }

  /**
   * Replaces the account's currency set, enforcing the three rules ADR-008 states.
   *
   * <p>A full replacement like every other field: an entry the client omits is an entry it is
   * asking to remove. The {@code protectedCurrencies} argument is what makes the removal safe —
   * empty on create (nothing can have records yet), and the set actually in use on update.
   *
   * @param protectedCurrencies currencies that must appear in the new set because records use them
   */
  private void applyBalances(
      AccountEntity entity, List<CurrencyBalance> requested, Set<String> protectedCurrencies) {
    if (requested.isEmpty()) {
      throw PrudentException.invalid(
          "An account must hold at least one currency; one holding none can receive no records.");
    }

    List<AccountBalance> balances = new ArrayList<>();
    Set<String> seen = new LinkedHashSet<>();
    for (CurrencyBalance balance : requested) {
      String currency = Currencies.normalize(balance.getCurrency());
      if (!Currencies.isValid(currency)) {
        throw PrudentException.invalid("'" + balance.getCurrency() + "' is not an ISO-4217 currency.");
      }
      if (!seen.add(currency)) {
        // Rejected rather than merged. Merging would silently pick one amount and discard the
        // other, and the user would see a balance they never entered.
        throw PrudentException.invalid(
            "The currency " + currency + " appears more than once in this account's balances.");
      }
      balances.add(new AccountBalance(currency, balance.getAmountMinor()));
    }

    // A currency with records cannot be dropped: doing so would orphan money that left an account
    // no longer admitting it exists. There is also no rename — dropping PLN and adding EUR is two
    // operations, and this rule catches the case where it would have silently reinterpreted
    // 100 PLN as 100 EUR.
    for (String inUse : protectedCurrencies) {
      if (!seen.contains(inUse)) {
        throw PrudentException.conflict(
            "Cannot drop " + inUse + ": this account still has records denominated in it.");
      }
    }

    // Cleared and refilled rather than reassigned: Hibernate tracks THIS list instance as the
    // element collection, and replacing the reference would leave the orphaned rows behind.
    entity.balances.clear();
    entity.balances.addAll(balances);
  }

  /**
   * Keeps "exactly one default account per user" true, by clearing the flag elsewhere rather than
   * trusting the client to have done so.
   *
   * <p>Only ever clears. Promoting some other account when the last default is un-set is a product
   * decision nobody has made — and picking one arbitrarily would mean a user who deliberately
   * cleared their default silently got a new one.
   */
  private void enforceSingleDefault(UUID userId, AccountEntity entity) {
    if (entity.isDefault) {
      AccountEntity.clearDefaultExcept(userId, entity.id);
    }
  }
}
