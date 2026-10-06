package prudent.plan;

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
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.error.PrudentException;
import prudent.proto.v1.ConfirmOccurrenceRequest;
import prudent.proto.v1.ConfirmOccurrenceResponse;
import prudent.proto.v1.PlanOccurrence;
import prudent.record.RecordEntity;
import prudent.record.RecordMapper;
import prudent.record.RecordWriter;
import zen.core.http.ZenStatus;

/**
 * Planned occurrences: {@code /api/v1/occurrences} (M2, jlogicsoftware/prudent#56, ADR-039).
 *
 * <p>The two <em>views</em> — {@code /upcoming} and {@code /overdue} — the two <em>state
 * changes</em> a user can make on their own, {@code skip} and {@code restore}, and {@code confirm}
 * (jlogicsoftware/prudent#57, ADR-040), which completes an occurrence by creating the actual
 * transaction in the same act. There is deliberately no route that marks one completed without
 * one.
 *
 * <p><strong>Only confirming moves money.</strong> An occurrence is not a record, so skipping,
 * restoring or merely listing changes no balance and no analytics total; confirming writes exactly
 * one record, and that record is what a balance and a total then see.
 *
 * <p><strong>Listing materialises.</strong> No job generates occurrences (ADR-038 left the trigger
 * to the views), so each view first makes sure every plan has its window — from {@link
 * #LOOKBACK_DAYS} back to the view's horizon — via {@link OccurrenceGenerator}, which is idempotent
 * and safe to race. A {@code GET} that writes is therefore harmless to repeat: the second call
 * finds everything already there.
 */
@Path("/api/v1/occurrences")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class OccurrenceResource {

  /**
   * How far back the views look for occurrences that were never generated. A plan opened for the
   * first time after months away would otherwise show nothing overdue for the months it missed;
   * beyond a year, an unresolved commitment is history rather than something to act on. Occurrences
   * generated earlier stay overdue for as long as they are unresolved, whatever their age.
   */
  public static final int LOOKBACK_DAYS = 366;

  /** The upcoming window when {@code days} is omitted. */
  public static final int DEFAULT_UPCOMING_DAYS = 30;

  /** The widest upcoming window. */
  public static final int MAX_UPCOMING_DAYS = 366;

  @Inject CurrentUser currentUser;
  @Inject OccurrenceGenerator generator;
  @Inject OccurrenceMapper mapper;
  @Inject PlanClock clock;
  @Inject RecordWriter writer;
  @Inject RecordMapper recordMapper;

  @GET
  @Path("/upcoming")
  @Transactional
  @Operation(
      summary = "Occurrences from today onward, in any state",
      description =
          "Every occurrence dated from today (in its plan's time zone) to `days` ahead, whether"
              + " planned, completed or skipped, so what was resolved early stays visible."
              + " Overdue ones are on /overdue.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListOccurrencesResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "`days` is not between 1 and " + MAX_UPCOMING_DAYS,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response upcoming(@QueryParam("days") Integer days) {
    int horizon = days == null ? DEFAULT_UPCOMING_DAYS : days;
    if (horizon < 1 || horizon > MAX_UPCOMING_DAYS) {
      throw PrudentException.invalid(
          "days must be between 1 and " + MAX_UPCOMING_DAYS + ", not " + horizon + ".");
    }
    return view(horizon, false);
  }

  @GET
  @Path("/overdue")
  @Transactional
  @Operation(
      summary = "Planned occurrences whose date has passed",
      description =
          "Every occurrence still planned whose date is before today in its plan's time zone."
              + " Skipped and completed ones are resolved and are not listed.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListOccurrencesResponse")))
  public Response overdue() {
    return view(0, true);
  }

  @POST
  @Path("/{id}/skip")
  @Transactional
  @Operation(summary = "Skip an occurrence: the user decided it will not happen")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "PlanOccurrence")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The occurrence is not planned or overdue, so it cannot be skipped",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response skip(@PathParam("id") String id) {
    return transition(id, OccurrenceState.SKIPPED);
  }

  @POST
  @Path("/{id}/restore")
  @Transactional
  @Operation(summary = "Restore a skipped occurrence to planned")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "PlanOccurrence")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The occurrence is not skipped, so there is nothing to restore",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response restore(@PathParam("id") String id) {
    return transition(id, OccurrenceState.PLANNED);
  }

  @POST
  @Path("/{id}/confirm")
  @Transactional
  @Operation(
      summary = "Confirm an occurrence: it happened, so record the actual transaction",
      description =
          "Completes the occurrence and creates exactly one record from it, dated, amounted,"
              + " filed and posted as the plan says unless the body overrides date, amountMinor,"
              + " accountId or categoryId for this transaction alone. Send `{}` to confirm exactly as"
              + " planned. The record keeps planId and planOccurrenceId. Works on a planned occurrence whether"
              + " its date is past, today or ahead; a skipped one must be restored first.")
  @RequestBody(content = @Content(schema = @Schema(ref = "ConfirmOccurrenceRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "ConfirmOccurrenceResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "A malformed date, a zero amount, or an account or category that is not the caller's, or"
              + " an account that does not hold the plan's currency",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The occurrence is skipped or already completed, so it cannot be confirmed",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response confirm(@PathParam("id") String id, ConfirmOccurrenceRequest request) {
    UUID userId = currentUser.id();
    // Locked for the transaction, so two confirmations of one occurrence -- a double tap, a
    // retry, two devices -- are serialised: the second waits, then finds it COMPLETED and is
    // refused. The unique index on prudent_record.plan_occurrence_id is the backstop behind this.
    PlanOccurrenceEntity occurrence =
        PlanOccurrenceEntity.findOwnedForUpdate(userId, Ids.parse("occurrence", id));
    if (occurrence == null) {
      throw PrudentException.notFound("occurrence", id);
    }
    // Before any validation: an occurrence that cannot be confirmed is a 409 whatever the body says.
    occurrence.transitionTo(OccurrenceState.COMPLETED);

    PlanEntity plan = PlanEntity.findOwned(userId, occurrence.planId);
    RecordEntity record = new RecordEntity();
    record.id = UUID.randomUUID();
    record.userId = userId;
    record.planId = plan.id;
    record.planOccurrenceId = occurrence.id;
    // The same rules as a record typed in by hand, so what a plan allowed can still be refused
    // here if the world moved (the account lost the currency) and an edit cannot slip past them.
    // A rejection throws, which rolls the transition back with it: an occurrence is never left
    // COMPLETED without its record.
    writer.apply(
        record,
        userId,
        plan.title,
        request.hasAmountMinor() ? request.getAmountMinor() : plan.amountMinor,
        request.hasDate()
            ? request.getDate()
            : occurrence.occurrenceDate.format(DateTimeFormatter.ISO_LOCAL_DATE),
        request.hasCategoryId() ? request.getCategoryId() : plan.categoryId.toString(),
        request.hasAccountId() ? request.getAccountId() : plan.accountId.toString(),
        plan.currency,
        plan.payee,
        plan.note);
    record.persist();

    LocalDate today = plan.rule().today(clock.now());
    return Response.status(Response.Status.CREATED)
        .entity(
            ConfirmOccurrenceResponse.newBuilder()
                .setOccurrence(mapper.toProto(occurrence, plan, today))
                .setRecord(recordMapper.toProto(record))
                .build())
        .build();
  }

  private Response transition(String id, OccurrenceState target) {
    UUID userId = currentUser.id();
    PlanOccurrenceEntity occurrence =
        PlanOccurrenceEntity.findOwnedForUpdate(userId, Ids.parse("occurrence", id));
    if (occurrence == null) {
      throw PrudentException.notFound("occurrence", id);
    }
    occurrence.transitionTo(target);
    PlanEntity plan = PlanEntity.findOwned(userId, occurrence.planId);
    LocalDate today = plan.rule().today(clock.now());
    return Response.ok(mapper.toProto(occurrence, plan, today)).build();
  }

  /**
   * Materialises every plan's window, then lists what the view is about.
   *
   * @param horizon days ahead of each plan's today to include (upcoming only)
   * @param overdueOnly whether this is the overdue view
   */
  private Response view(int horizon, boolean overdueOnly) {
    UUID userId = currentUser.id();
    Instant now = clock.now();
    List<PlanEntity> plans = PlanEntity.listOwnedBy(userId);

    // "Today" is per plan, because it is per time zone: a Warsaw plan and a Honolulu plan are on
    // different calendar days for most of every day.
    Map<UUID, PlanEntity> byId = new HashMap<>();
    Map<UUID, LocalDate> todays = new HashMap<>();
    LocalDate earliestToday = null;
    LocalDate latestToday = null;
    for (PlanEntity plan : plans) {
      LocalDate today = plan.rule().today(now);
      byId.put(plan.id, plan);
      todays.put(plan.id, today);
      earliestToday = earliestToday == null || today.isBefore(earliestToday) ? today : earliestToday;
      latestToday = latestToday == null || today.isAfter(latestToday) ? today : latestToday;
      generator.ensureWindow(plan, today, LOOKBACK_DAYS, horizon);
    }
    if (plans.isEmpty()) {
      return Response.ok(mapper.toListResponse(List.of())).build();
    }

    // One query over the union of the plans' windows, then each row is judged against its own
    // plan's today. The bounds are widened by the spread between zones, so nothing is missed.
    List<PlanOccurrenceEntity> candidates =
        overdueOnly
            ? PlanOccurrenceEntity.listOwnedBetween(
                userId, OccurrenceState.PLANNED, null, latestToday.minusDays(1))
            : PlanOccurrenceEntity.listOwnedBetween(
                userId, null, earliestToday, latestToday.plusDays(horizon));

    List<PlanOccurrenceEntity> included = new ArrayList<>();
    for (PlanOccurrenceEntity occurrence : candidates) {
      LocalDate today = todays.get(occurrence.planId);
      LocalDate date = occurrence.occurrenceDate;
      boolean in =
          overdueOnly
              ? date.isBefore(today)
              : !date.isBefore(today) && !date.isAfter(today.plusDays(horizon));
      if (in) {
        included.add(occurrence);
      }
    }
    included.sort(
        Comparator.comparing((PlanOccurrenceEntity o) -> o.occurrenceDate)
            .thenComparing(o -> o.id));

    List<PlanOccurrence> messages = new ArrayList<>(included.size());
    for (PlanOccurrenceEntity occurrence : included) {
      messages.add(
          mapper.toProto(
              occurrence, byId.get(occurrence.planId), todays.get(occurrence.planId)));
    }
    return Response.ok(mapper.toListResponse(messages)).build();
  }
}
