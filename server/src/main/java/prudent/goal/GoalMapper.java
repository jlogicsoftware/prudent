package prudent.goal;

import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import prudent.proto.v1.Goal;
import prudent.proto.v1.GoalStatus;
import prudent.proto.v1.ListGoalsResponse;

/**
 * Maps {@link GoalEntity} to its wire {@link Goal} proto. Entity → proto only; the other direction
 * is validation, and lives in {@link GoalResource}.
 *
 * <p>Hand-written rather than MapStruct: the status is an enum on each side under a different type
 * and the date is optional, and there are eight fields.
 */
@ApplicationScoped
public class GoalMapper {

  public Goal toProto(GoalEntity entity) {
    Goal.Builder builder =
        Goal.newBuilder()
            .setId(entity.id.toString())
            .setName(entity.name)
            .setCurrency(entity.currency)
            .setTargetAmountMinor(entity.targetAmountMinor)
            .setStatus(toWire(entity.status))
            .setCreatedAtMs(entity.createdAt.toEpochMilli())
            .setStatusChangedAtMs(entity.statusChangedAt.toEpochMilli());
    if (entity.targetDate != null) {
      builder.setTargetDate(entity.targetDate.toString());
    }
    return builder.build();
  }

  /** The list response, in the order the entity query returned. */
  public ListGoalsResponse toListResponse(List<GoalEntity> entities) {
    ListGoalsResponse.Builder builder = ListGoalsResponse.newBuilder();
    for (GoalEntity entity : entities) {
      builder.addGoals(toProto(entity));
    }
    return builder.build();
  }

  static GoalStatus toWire(GoalState state) {
    return switch (state) {
      case ACTIVE -> GoalStatus.GOAL_STATUS_ACTIVE;
      case COMPLETED -> GoalStatus.GOAL_STATUS_COMPLETED;
      case ARCHIVED -> GoalStatus.GOAL_STATUS_ARCHIVED;
    };
  }
}
