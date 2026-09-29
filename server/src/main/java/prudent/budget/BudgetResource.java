package prudent.budget;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.YearMonth;
import java.time.format.DateTimeParseException;
import java.util.UUID;
import java.util.regex.Pattern;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.Currencies;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.category.CategoryEntity;
import prudent.error.PrudentException;
import prudent.record.RecordEntity;
import prudent.proto.v1.Budget;
import prudent.proto.v1.SetBudgetRequest;
import zen.core.http.ZenStatus;

/**
 * Prudent's monthly category budgets: {@code /api/v1/budgets} (M3, jlogicsoftware/prudent#36,
 * ADR-043).
 *
 * <p>A budget is the amount the user may spend in one category, in one month, in one currency. It
 * is <strong>addressed by that slot</strong> — {@code /{categoryId}/{month}/{currency}} — so there
 * is no create/replace distinction for a client to get wrong and no id to invent: {@code PUT} fills
 * the slot, and the slot holds at most one amount. Saving, editing or deleting a budget touches
 * only {@code prudent_budget}; no balance, record or analytics total moves.
 *
 * <p>{@code GET /summary} is the read side (jlogicsoftware/prudent#59, ADR-044): plan, actual and
 * remaining amount per budgeted category for one month in one currency, calculated on each request
 * from the budgets and the ledger and stored nowhere.
 *
 * <p>The resource shape is set out on {@link prudent.category.CategoryResource}.
 */
@Path("/api/v1/budgets")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class BudgetResource {

  /**
   * {@code YYYY-MM} and nothing else. {@link YearMonth#parse} alone would also accept a signed or
   * five-digit year, which is a typo here rather than a month the user meant.
   */
  private static final Pattern MONTH = Pattern.compile("\\d{4}-\\d{2}");

  @Inject CurrentUser currentUser;
  @Inject BudgetMapper mapper;

  @GET
  @Operation(
      summary = "List the authenticated user's budgets",
      description =
          "Optionally narrowed by month (YYYY-MM) and categoryId (UUID), ordered by month, then"
              + " currency, then category.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListBudgetsResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A malformed month or categoryId",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response list(
      @QueryParam("month") String month, @QueryParam("categoryId") String categoryId) {
    YearMonth parsedMonth = month == null || month.isBlank() ? null : parseMonth(month);
    UUID parsedCategory =
        categoryId == null || categoryId.isBlank() ? null : Ids.parseInBody("category", categoryId);
    return Response.ok(
            mapper.toListResponse(
                BudgetEntity.listOwnedBy(currentUser.id(), parsedMonth, parsedCategory)))
        .build();
  }

  @GET
  @Path("/summary")
  @Operation(
      summary = "Plan, actual and remaining amount per budgeted category, for one month",
      description =
          "Query parameters: month (required, YYYY-MM) and currency (required, ISO-4217). Actual"
              + " is net spending from posted records in that currency, refunds included; a"
              + " planned occurrence is not counted until it is confirmed. Never summed across"
              + " currencies.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "BudgetSummaryResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A missing or malformed month, or a missing or non-ISO-4217 currency",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response summary(
      @QueryParam("month") String month, @QueryParam("currency") String currency) {
    UUID userId = currentUser.id();
    YearMonth parsedMonth = parseMonth(month);
    if (currency == null || currency.isBlank()) {
      // Required, never inferred: a summary that guessed the currency would be a total the user
      // did not ask for.
      throw PrudentException.invalid(
          "A currency is required; Prudent never sums a budget across currencies.");
    }
    String normalized = parseCurrency(currency);

    return Response.ok(
            BudgetCalculator.summarize(
                parsedMonth,
                normalized,
                BudgetEntity.listForMonthAndCurrency(userId, parsedMonth, normalized),
                RecordEntity.netByCategory(
                    userId, normalized, parsedMonth.atDay(1), parsedMonth.atEndOfMonth())))
        .build();
  }

  @GET
  @Path("/{categoryId}/{month}/{currency}")
  @Operation(summary = "Read the budget for one category, month and currency")
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Budget")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A malformed month or currency",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "No such category, or no budget set for that month and currency",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response get(
      @PathParam("categoryId") String categoryId,
      @PathParam("month") String month,
      @PathParam("currency") String currency) {
    UUID userId = currentUser.id();
    UUID category = requireCategory(userId, categoryId);
    YearMonth parsedMonth = parseMonth(month);
    String normalized = parseCurrency(currency);
    BudgetEntity entity = BudgetEntity.findSlot(userId, category, parsedMonth, normalized);
    if (entity == null) {
      throw notSet(categoryId, parsedMonth, normalized);
    }
    return Response.ok(mapper.toProto(entity)).build();
  }

  @PUT
  @Path("/{categoryId}/{month}/{currency}")
  @Transactional
  @Operation(
      summary = "Set the budget for one category, month and currency",
      description =
          "Creates the budget (201) or replaces its amount (200). The slot holds at most one.")
  @RequestBody(content = @Content(schema = @Schema(ref = "SetBudgetRequest")))
  @APIResponse(
      responseCode = ZenStatus.OK,
      description = "The slot already held a budget; its amount was replaced",
      content = @Content(schema = @Schema(ref = "Budget")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      description = "The slot was empty",
      content = @Content(schema = @Schema(ref = "Budget")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "A malformed month, a currency that is not ISO-4217, or an amount that is not positive",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "No such category for this user",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response set(
      @PathParam("categoryId") String categoryId,
      @PathParam("month") String month,
      @PathParam("currency") String currency,
      SetBudgetRequest request) {
    UUID userId = currentUser.id();
    UUID category = requireCategory(userId, categoryId);
    YearMonth parsedMonth = parseMonth(month);
    String normalized = parseCurrency(currency);
    long amountMinor = request.getAmountMinor();
    // Positive, not merely nonzero: a budget is what may be spent, and "spend nothing" or a
    // negative amount is not a budget. Zero is also what an omitted field decodes to, so refusing
    // it is what keeps a body that forgot the amount from silently becoming a real one.
    if (amountMinor <= 0) {
      throw PrudentException.invalid(
          "A budget needs a positive amount. To have no budget for a month, delete it.");
    }

    boolean existed = BudgetEntity.findSlot(userId, category, parsedMonth, normalized) != null;
    BudgetEntity.upsert(userId, category, parsedMonth, normalized, amountMinor);

    // Built from the values just written: the upsert is native, so an entity read now could be the
    // stale one loaded above.
    Budget budget =
        Budget.newBuilder()
            .setCategoryId(category.toString())
            .setMonth(parsedMonth.toString())
            .setCurrency(normalized)
            .setAmountMinor(amountMinor)
            .build();
    return Response.status(existed ? Response.Status.OK : Response.Status.CREATED)
        .entity(budget)
        .build();
  }

  @DELETE
  @Path("/{categoryId}/{month}/{currency}")
  @Transactional
  @Operation(summary = "Delete the budget for one category, month and currency")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Deleted")
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A malformed month or currency",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "No such category, or no budget set for that month and currency",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response delete(
      @PathParam("categoryId") String categoryId,
      @PathParam("month") String month,
      @PathParam("currency") String currency) {
    UUID userId = currentUser.id();
    UUID category = requireCategory(userId, categoryId);
    YearMonth parsedMonth = parseMonth(month);
    String normalized = parseCurrency(currency);
    // A hard delete, and a harmless one: a budget is not money that moved, so removing it changes
    // no balance and no total.
    if (BudgetEntity.deleteSlot(userId, category, parsedMonth, normalized) == 0) {
      throw notSet(categoryId, parsedMonth, normalized);
    }
    return Response.noContent().build();
  }

  /**
   * The category a path names, but only as the caller's own — "not yours" and "does not exist" are
   * one answer, as everywhere else. A malformed id is a 404 for the reason {@link Ids#parse} gives.
   */
  private static UUID requireCategory(UUID userId, String categoryId) {
    CategoryEntity category = CategoryEntity.findOwned(userId, Ids.parse("category", categoryId));
    if (category == null) {
      throw PrudentException.notFound("category", categoryId);
    }
    return category.id;
  }

  private static PrudentException notSet(String categoryId, YearMonth month, String currency) {
    return PrudentException.notFound(
        "budget", "category " + categoryId + ", " + month + ", " + currency);
  }

  /**
   * A calendar month, strictly {@code YYYY-MM}. Refused rather than corrected: a month that parses
   * to something the user did not type is a budget filed in the wrong month.
   */
  static YearMonth parseMonth(String month) {
    if (month == null || !MONTH.matcher(month).matches()) {
      throw PrudentException.invalid("'" + month + "' is not a month. Expected YYYY-MM.");
    }
    try {
      return YearMonth.parse(month);
    } catch (DateTimeParseException impossible) {
      // Well-formed digits that are not a month, such as 2026-13: answered as a refusal, not a 500.
      throw PrudentException.invalid("'" + month + "' is not a month. Expected YYYY-MM.");
    }
  }

  private static String parseCurrency(String currency) {
    String normalized = Currencies.normalize(currency);
    if (!Currencies.isValid(normalized)) {
      throw PrudentException.invalid("'" + currency + "' is not an ISO-4217 currency.");
    }
    return normalized;
  }
}
