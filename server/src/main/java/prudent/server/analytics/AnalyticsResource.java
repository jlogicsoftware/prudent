package prudent.server.analytics;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.proto.v1.CategorySpend;
import prudent.proto.v1.Granularity;
import prudent.proto.v1.PeriodSpend;
import prudent.proto.v1.SpendByCategoryResponse;
import prudent.proto.v1.SpendByPeriodResponse;
import prudent.server.Currencies;
import prudent.server.CurrentUser;
import prudent.server.PrudentException;
import prudent.server.record.RecordEntity;
import zen.core.http.ZenStatus;

/**
 * Prudent's analytics: {@code /api/v1/analytics}, read-only.
 *
 * <p>The resource shape is set out on {@link prudent.server.category.CategoryResource}. Two
 * things are specific to this resource:
 *
 * <ul>
 *   <li><strong>{@code currency} is a required query parameter on both endpoints, never
 *       inferred.</strong> Prudent does no FX (accounts.proto), so a total is always a total in
 *       one currency. Requiring the caller to name it makes cross-currency summing structurally
 *       impossible here rather than a rule this resource would otherwise have to enforce at
 *       runtime.
 *   <li><strong>Both compute in Java over {@link RecordEntity#expenseRows}, not in SQL.</strong>
 *       A personal expense tracker's row count makes that cheap, and it keeps the query free of a
 *       database-specific date-truncation function.
 * </ul>
 */
@Path("/api/v1/analytics")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class AnalyticsResource {

  private static final DateTimeFormatter MONTH_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM");
  private static final DateTimeFormatter YEAR_FORMAT = DateTimeFormatter.ofPattern("yyyy");

  @Inject CurrentUser currentUser;

  @GET
  @Path("/spend-by-category")
  @Operation(
      summary = "Spend by category, in one currency, for a year or one month of it",
      description =
          "Query parameters: currency (required, ISO-4217), year (required), month (optional,"
              + " 1-12 — a single month; omitted means the whole year).")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "SpendByCategoryResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A missing/invalid currency, a missing year, or an out-of-range month",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response spendByCategory(
      @QueryParam("currency") String currency,
      @QueryParam("year") Integer year,
      @QueryParam("month") Integer month) {
    UUID userId = currentUser.id();
    String normalizedCurrency = requireCurrency(currency);
    if (year == null) {
      throw PrudentException.invalid("spend-by-category needs a year.");
    }

    LocalDate from;
    LocalDate to;
    if (month != null) {
      if (month < 1 || month > 12) {
        throw PrudentException.invalid("month must be 1-12.");
      }
      from = LocalDate.of(year, month, 1);
      to = from.withDayOfMonth(from.lengthOfMonth());
    } else {
      from = LocalDate.of(year, 1, 1);
      to = LocalDate.of(year, 12, 31);
    }

    // A TreeMap so the response order is deterministic rather than whatever the database
    // returned rows in — not a promise the contract makes, but a promise a test can rely on
    // without also asserting an order nobody documented.
    Map<UUID, Long> totals = new TreeMap<>();
    for (Object[] row : RecordEntity.expenseRows(userId, normalizedCurrency, from, to)) {
      UUID categoryId = (UUID) row[0];
      long amountMinor = (Long) row[2];
      // amountMinor is negative (an expense); negated once, here, so "spend" is a positive
      // magnitude everywhere downstream of this line.
      totals.merge(categoryId, -amountMinor, Long::sum);
    }

    SpendByCategoryResponse.Builder builder =
        SpendByCategoryResponse.newBuilder().setCurrency(normalizedCurrency);
    for (Map.Entry<UUID, Long> entry : totals.entrySet()) {
      builder.addItems(
          CategorySpend.newBuilder()
              .setCategoryId(entry.getKey().toString())
              .setAmountMinor(entry.getValue())
              .build());
    }
    return Response.ok(builder.build()).build();
  }

  @GET
  @Path("/spend-by-period")
  @Operation(
      summary = "Spend by period, in one currency, over a trailing window of buckets",
      description =
          "Query parameters: currency (required, ISO-4217), granularity (required, MONTH or"
              + " YEAR), count (required, 1-60 — the number of trailing buckets, ending at the"
              + " current period resolved in UTC).")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "SpendByPeriodResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A missing/invalid currency, granularity, or an out-of-range count",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response spendByPeriod(
      @QueryParam("currency") String currency,
      @QueryParam("granularity") String granularityParam,
      @QueryParam("count") Integer count) {
    UUID userId = currentUser.id();
    String normalizedCurrency = requireCurrency(currency);
    Granularity granularity = parseGranularity(granularityParam);
    if (count == null || count < 1 || count > 60) {
      throw PrudentException.invalid("count must be between 1 and 60.");
    }

    // THE UTC ANCHOR (docs/DECISIONS.md ADR-014): "the current period" is resolved once, here, in
    // UTC — not the request's timezone, which this API is never told, and not the server host's
    // local zone, which would make the same request answer differently depending on where it
    // happened to run.
    LocalDate anchor = LocalDate.now(ZoneOffset.UTC);
    LocalDate from;
    LocalDate to;
    DateTimeFormatter periodFormat;
    if (granularity == Granularity.GRANULARITY_MONTH) {
      LocalDate currentBucket = anchor.withDayOfMonth(1);
      from = currentBucket.minusMonths(count - 1L);
      to = currentBucket.plusMonths(1).minusDays(1);
      periodFormat = MONTH_FORMAT;
    } else {
      LocalDate currentBucket = LocalDate.of(anchor.getYear(), 1, 1);
      from = currentBucket.minusYears(count - 1L);
      to = LocalDate.of(anchor.getYear(), 12, 31);
      periodFormat = YEAR_FORMAT;
    }

    // A TreeMap over the "yyyy-MM" / "yyyy" period string: both sort lexicographically in
    // calendar order, so this is the ordering the contract promises ("oldest to newest") rather
    // than a coincidence of insertion order.
    Map<String, Long> totals = new TreeMap<>();
    for (Object[] row : RecordEntity.expenseRows(userId, normalizedCurrency, from, to)) {
      LocalDate date = (LocalDate) row[1];
      long amountMinor = (Long) row[2];
      totals.merge(date.format(periodFormat), -amountMinor, Long::sum);
    }

    SpendByPeriodResponse.Builder builder =
        SpendByPeriodResponse.newBuilder()
            .setCurrency(normalizedCurrency)
            .setGranularity(granularity);
    for (Map.Entry<String, Long> entry : totals.entrySet()) {
      builder.addPeriods(
          PeriodSpend.newBuilder()
              .setPeriod(entry.getKey())
              .setAmountMinor(entry.getValue())
              .build());
    }
    return Response.ok(builder.build()).build();
  }

  private String requireCurrency(String currency) {
    String normalized = Currencies.normalize(currency);
    if (!Currencies.isValid(normalized)) {
      throw PrudentException.invalid(
          "A currency is required and must be ISO-4217; Prudent never sums analytics across"
              + " currencies.");
    }
    return normalized;
  }

  private Granularity parseGranularity(String raw) {
    if ("MONTH".equalsIgnoreCase(raw)) {
      return Granularity.GRANULARITY_MONTH;
    }
    if ("YEAR".equalsIgnoreCase(raw)) {
      return Granularity.GRANULARITY_YEAR;
    }
    throw PrudentException.invalid("granularity must be MONTH or YEAR.");
  }
}
