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
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.error.PrudentException;
import prudent.proto.v1.PlanOccurrence;
import zen.core.http.ZenStatus;

/**
 * Planned occurrences: {@code /api/v1/occurrences} (M2, jlogicsoftware/prudent#56, ADR-039).
 *
 * <p>The two <em>views</em> — {@code /upcoming} and {@code /overdue} — and the two <em>state
 * changes</em> a user can make on their own, {@code skip} and {@code restore}. Completing an
 * occurrence is confirmation's job (jlogicsoftware/prudent#57), which creates the actual
 * transaction; there is deliberately no route here that marks one completed without one.
 *
 * <p><strong>Nothing here moves money.</strong> An occurrence is not a record, so skipping,
 * restoring or merely listing changes no balance and no analytics total.
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

      LocalDate from = today.minusDays(LOOKBACK_DAYS);
      if (from.isBefore(plan.rule().startDate())) {
        from = plan.rule().startDate();
      }
      LocalDate to = today.plusDays(horizon);
      if (!to.isBefore(from)) {
        generator.generate(plan, from, to);
      }
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
