package prudent.plan;

import jakarta.enterprise.context.ApplicationScoped;
import java.time.format.DateTimeFormatter;
import java.util.List;
import prudent.proto.v1.ListPlansResponse;
import prudent.proto.v1.Plan;
import prudent.proto.v1.Recurrence;
import prudent.proto.v1.Reminder;

/**
 * Maps {@link PlanEntity} to its wire {@link Plan} proto. Entity → proto only; the other direction
 * is validation, and lives in {@link PlanResource} and {@link RecurrenceRule#fromProto}.
 *
 * <p>Hand-written rather than MapStruct: the recurrence is flat columns on one side and a nested
 * message with a {@code oneof} on the other, and a generated mapper would need as much
 * configuration as this class has code.
 */
@ApplicationScoped
public class PlanMapper {

  /** Assembles the immutable {@link Plan} proto. Optional fields are set only when present. */
  public Plan toProto(PlanEntity entity) {
    Plan.Builder builder =
        Plan.newBuilder()
            .setId(entity.id.toString())
            .setTitle(entity.title)
            .setAmountMinor(entity.amountMinor)
            .setCurrency(entity.currency)
            .setAccountId(entity.accountId.toString())
            .setCategoryId(entity.categoryId.toString())
            .setRecurrence(toProto(entity.rule()))
            .setReminder(toProto(entity.reminder()));
    if (entity.payee != null) {
      builder.setPayee(entity.payee);
    }
    if (entity.note != null) {
      builder.setNote(entity.note);
    }
    return builder.build();
  }

  /** The list response, in the order the entity query returned. */
  public ListPlansResponse toListResponse(List<PlanEntity> entities) {
    ListPlansResponse.Builder builder = ListPlansResponse.newBuilder();
    for (PlanEntity entity : entities) {
      builder.addPlans(toProto(entity));
    }
    return builder.build();
  }

  /** Always sets {@code lead_days}: a response states the setting in force, never "default". */
  private static Reminder toProto(ReminderSetting setting) {
    return Reminder.newBuilder()
        .setEnabled(setting.enabled())
        .setLeadDays(setting.leadDays())
        .build();
  }

  private static Recurrence toProto(RecurrenceRule rule) {
    Recurrence.Builder builder =
        Recurrence.newBuilder()
            .setFrequency(rule.frequency().toProto())
            .setInterval(rule.interval())
            .setStartDate(rule.startDate().format(DateTimeFormatter.ISO_LOCAL_DATE))
            .setTimeZone(rule.timeZone().getId());
    if (rule.untilDate() != null) {
      builder.setUntilDate(rule.untilDate().format(DateTimeFormatter.ISO_LOCAL_DATE));
    }
    if (rule.occurrenceCount() != null) {
      builder.setOccurrenceCount(rule.occurrenceCount());
    }
    return builder.build();
  }
}
