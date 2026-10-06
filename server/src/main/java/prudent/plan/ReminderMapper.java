package prudent.plan;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import prudent.proto.v1.DueReminder;
import prudent.proto.v1.ListRemindersResponse;

/** Maps an occurrence that has a reminder to its wire {@link DueReminder}. Entity → proto only. */
@ApplicationScoped
public class ReminderMapper {

  @Inject OccurrenceMapper occurrenceMapper;

  /**
   * One reminder, reckoned as of the plan's {@code today}.
   *
   * @param occurrence a planned occurrence that is within its plan's lead time
   * @param plan the occurrence's plan, with its reminder enabled
   */
  public DueReminder toProto(PlanOccurrenceEntity occurrence, PlanEntity plan, LocalDate today) {
    int leadDays = plan.reminder().leadDays();
    return DueReminder.newBuilder()
        .setOccurrence(occurrenceMapper.toProto(occurrence, plan, today))
        .setRemindOn(
            occurrence.occurrenceDate.minusDays(leadDays).format(DateTimeFormatter.ISO_LOCAL_DATE))
        .setLeadDays(leadDays)
        .setRead(occurrence.isReminderRead())
        .build();
  }

  /** The list response, in the order given. */
  public ListRemindersResponse toListResponse(List<DueReminder> reminders) {
    return ListRemindersResponse.newBuilder().addAllReminders(reminders).build();
  }
}
