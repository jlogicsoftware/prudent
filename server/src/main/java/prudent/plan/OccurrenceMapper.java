package prudent.plan;

import jakarta.enterprise.context.ApplicationScoped;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import prudent.proto.v1.ListOccurrencesResponse;
import prudent.proto.v1.OccurrenceStatus;
import prudent.proto.v1.PlanOccurrence;

/**
 * Maps {@link PlanOccurrenceEntity} to its wire {@link PlanOccurrence}. Entity → proto only: an
 * occurrence is never created or edited from a message, only generated and transitioned.
 */
@ApplicationScoped
public class OccurrenceMapper {

  /**
   * The status a client sees: the stored state, except that a planned occurrence dated before
   * {@code today} is {@code OVERDUE}. "Today" is the plan's, in the plan's time zone — see {@link
   * RecurrenceRule#today}.
   */
  public static OccurrenceStatus status(OccurrenceState state, LocalDate date, LocalDate today) {
    return switch (state) {
      case PLANNED ->
          date.isBefore(today)
              ? OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE
              : OccurrenceStatus.OCCURRENCE_STATUS_PLANNED;
      case COMPLETED -> OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED;
      case SKIPPED -> OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED;
    };
  }

  /** One occurrence with its plan's fields alongside, reckoned as of the plan's {@code today}. */
  public PlanOccurrence toProto(PlanOccurrenceEntity occurrence, PlanEntity plan, LocalDate today) {
    return PlanOccurrence.newBuilder()
        .setId(occurrence.id.toString())
        .setPlanId(plan.id.toString())
        .setOccurrenceDate(occurrence.occurrenceDate.format(DateTimeFormatter.ISO_LOCAL_DATE))
        .setStatus(status(occurrence.state, occurrence.occurrenceDate, today))
        .setTitle(plan.title)
        .setAmountMinor(plan.amountMinor)
        .setCurrency(plan.currency)
        .setAccountId(plan.accountId.toString())
        .setCategoryId(plan.categoryId.toString())
        .build();
  }

  /** The list response, in the order given. */
  public ListOccurrencesResponse toListResponse(List<PlanOccurrence> occurrences) {
    return ListOccurrencesResponse.newBuilder().addAllOccurrences(occurrences).build();
  }
}
