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
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.error.PrudentException;
import prudent.proto.v1.DueReminder;
import zen.core.http.ZenStatus;

/**
 * The in-app reminder centre: {@code /api/v1/reminders} (M5, jlogicsoftware/prudent#68, ADR-055).
 *
 * <p><strong>A reminder is an occurrence, not a row.</strong> A planned occurrence of a plan whose
 * reminder is on ({@link ReminderSetting}) has a reminder from {@code leadDays} before its date,
 * and keeps it — as an overdue one — until it is confirmed or skipped. All of that is worked out
 * here on every read, in the plan's own calendar day, so there is no job to miss and no stale
 * reminder to find; it is the reason overdue is never stored either (ADR-039). The only stored
 * fact is that the user has read one ({@link PlanOccurrenceEntity#reminderReadAt}).
 *
 * <p><strong>Reading moves no money and changes no state.</strong> Read, unread and read-all touch
 * one timestamp. An occurrence is resolved on {@code /api/v1/occurrences}, and doing so ends its
 * reminder by itself.
 *
 * <p><strong>Listing materialises</strong>, as the occurrence views do (ADR-039): no job generates
 * occurrences, so a reminder whose occurrence was never generated would otherwise never appear.
 * Generation is idempotent and safe to race, so a {@code GET} that writes is harmless to repeat.
 */
@Path("/api/v1/reminders")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class ReminderResource {

  @Inject CurrentUser currentUser;
  @Inject OccurrenceGenerator generator;
  @Inject ReminderMapper mapper;
  @Inject PlanClock clock;

  @GET
  @Transactional
  @Operation(
      summary = "Due and overdue reminders, with their read state",
      description =
          "Every still-planned occurrence of a plan whose reminder is on that is within its lead"
              + " time or past its date, in its plan's calendar day. Oldest date first, so the most"
              + " overdue lead. Confirmed and skipped occurrences have no reminder.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListRemindersResponse")))
  public Response list() {
    return Response.ok(mapper.toListResponse(protos(current(currentUser.id())))).build();
  }

  @POST
  @Path("/read-all")
  @Transactional
  @Operation(
      summary = "Mark every current reminder read",
      description =
          "Marks each reminder that is due or overdue now as read, keeping the time of any that"
              + " were already read, and answers with the list.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListRemindersResponse")))
  public Response readAll() {
    Instant now = clock.now();
    List<Due> due = current(currentUser.id());
    for (Due entry : due) {
      entry.occurrence().markReminderRead(now);
    }
    return Response.ok(mapper.toListResponse(protos(due))).build();
  }

  @POST
  @Path("/{occurrenceId}/read")
  @Transactional
  @Operation(summary = "Mark one reminder read")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "DueReminder")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The occurrence has no reminder right now",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response read(@PathParam("occurrenceId") String occurrenceId) {
    Due due = findCurrent(occurrenceId);
    due.occurrence().markReminderRead(clock.now());
    return Response.ok(mapper.toProto(due.occurrence(), due.plan(), due.today())).build();
  }

  @POST
  @Path("/{occurrenceId}/unread")
  @Transactional
  @Operation(summary = "Mark one reminder unread again")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "DueReminder")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The occurrence has no reminder right now",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response unread(@PathParam("occurrenceId") String occurrenceId) {
    Due due = findCurrent(occurrenceId);
    due.occurrence().markReminderUnread();
    return Response.ok(mapper.toProto(due.occurrence(), due.plan(), due.today())).build();
  }

  /** An occurrence that has a reminder, with what it is judged against. */
  private record Due(PlanOccurrenceEntity occurrence, PlanEntity plan, LocalDate today) {}

  /**
   * The one occurrence a read or unread is about, locked for the transaction so a read racing a
   * confirmation sees the confirmation's result, or refuses — never a reminder that has just ended.
   */
  private Due findCurrent(String occurrenceId) {
    UUID userId = currentUser.id();
    PlanOccurrenceEntity occurrence =
        PlanOccurrenceEntity.findOwnedForUpdate(userId, Ids.parse("occurrence", occurrenceId));
    if (occurrence == null) {
      throw PrudentException.notFound("occurrence", occurrenceId);
    }
    PlanEntity plan = PlanEntity.findOwned(userId, occurrence.planId);
    LocalDate today = plan.rule().today(clock.now());
    if (!hasReminder(occurrence, plan, today)) {
      throw PrudentException.conflict(
          "That occurrence has no reminder right now: its plan's reminder is off, it is already"
              + " confirmed or skipped, or it is not yet within the plan's lead time.");
    }
    return new Due(occurrence, plan, today);
  }

  /**
   * Whether the occurrence is a reminder as of the plan's {@code today}: still planned, its plan's
   * reminder on, and no further ahead than the lead time. Past its date it stays one — overdue.
   * The single place that says so, shared by the list's query bound and the single-row routes.
   */
  private static boolean hasReminder(PlanOccurrenceEntity occurrence, PlanEntity plan, LocalDate today) {
    ReminderSetting setting = plan.reminder();
    return setting.enabled()
        && occurrence.state == OccurrenceState.PLANNED
        && !occurrence.occurrenceDate.isAfter(today.plusDays(setting.leadDays()));
  }

  /** Every reminder the caller has now, oldest occurrence first, then by id. */
  private List<Due> current(UUID userId) {
    Instant now = clock.now();
    List<Due> due = new ArrayList<>();
    for (PlanEntity plan : PlanEntity.listOwnedBy(userId)) {
      ReminderSetting setting = plan.reminder();
      if (!setting.enabled()) {
        continue;
      }
      LocalDate today = plan.rule().today(now);
      // The window reaches as far ahead as the lead time, so an occurrence that has just come
      // within it exists to be found even if no view has generated that far yet.
      generator.ensureWindow(plan, today, OccurrenceResource.LOOKBACK_DAYS, setting.leadDays());
      for (PlanOccurrenceEntity occurrence :
          PlanOccurrenceEntity.listPlannedOfPlanUpTo(
              userId, plan.id, today.plusDays(setting.leadDays()))) {
        if (hasReminder(occurrence, plan, today)) {
          due.add(new Due(occurrence, plan, today));
        }
      }
    }
    due.sort(
        Comparator.comparing((Due d) -> d.occurrence().occurrenceDate)
            .thenComparing(d -> d.occurrence().id));
    return due;
  }

  private List<DueReminder> protos(List<Due> due) {
    List<DueReminder> messages = new ArrayList<>(due.size());
    for (Due entry : due) {
      messages.add(mapper.toProto(entry.occurrence(), entry.plan(), entry.today()));
    }
    return messages;
  }
}
