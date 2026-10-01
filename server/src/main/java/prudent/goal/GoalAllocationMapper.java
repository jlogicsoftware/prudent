package prudent.goal;

import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import prudent.proto.v1.GoalAllocation;
import prudent.proto.v1.GoalAllocationKind;
import prudent.proto.v1.CurrencyFreeMoney;
import prudent.proto.v1.GetFreeMoneyResponse;
import prudent.proto.v1.GoalEnvelope;
import prudent.proto.v1.ListGoalAllocationsResponse;
import prudent.proto.v1.ListGoalEnvelopesResponse;

/**
 * Maps {@link GoalAllocationEntity} and the calculated envelopes to their wire protos. Entity →
 * proto only; the other direction is validation, and lives in {@link GoalAllocationResource}.
 *
 * <p>Hand-written rather than MapStruct, for the reason {@link GoalMapper} gives: an enum on each
 * side under a different type, and two optional ids.
 */
@ApplicationScoped
public class GoalAllocationMapper {

  public GoalAllocation toProto(GoalAllocationEntity entity) {
    GoalAllocation.Builder builder =
        GoalAllocation.newBuilder()
            .setId(entity.id.toString())
            .setKind(toWire(entity.kind))
            .setCurrency(entity.currency)
            .setAmountMinor(entity.amountMinor)
            .setNote(entity.note)
            .setCreatedAtMs(entity.createdAt.toEpochMilli())
            .setCreatedBy(entity.createdBy.toString());
    if (entity.sourceGoalId != null) {
      builder.setSourceGoalId(entity.sourceGoalId.toString());
    }
    if (entity.targetGoalId != null) {
      builder.setTargetGoalId(entity.targetGoalId.toString());
    }
    return builder.build();
  }

  /** The history, in the order the entity query returned. */
  public ListGoalAllocationsResponse toListResponse(List<GoalAllocationEntity> entities) {
    ListGoalAllocationsResponse.Builder builder = ListGoalAllocationsResponse.newBuilder();
    for (GoalAllocationEntity entity : entities) {
      builder.addAllocations(toProto(entity));
    }
    return builder.build();
  }

  /**
   * One envelope per goal, in the goals' order. A goal with no history holds nothing, so it is
   * listed at zero rather than left out: a client never has to guess what absence means.
   */
  public ListGoalEnvelopesResponse toEnvelopesResponse(
      List<GoalEntity> goals, Map<UUID, Long> balances) {
    ListGoalEnvelopesResponse.Builder builder = ListGoalEnvelopesResponse.newBuilder();
    for (GoalEntity goal : goals) {
      builder.addEnvelopes(
          GoalEnvelope.newBuilder()
              .setGoalId(goal.id.toString())
              .setCurrency(goal.currency)
              .setAmountMinor(balances.getOrDefault(goal.id, 0L)));
    }
    return builder.build();
  }

  /** One entry per currency, in the order the calculation produced them (currency code). */
  public GetFreeMoneyResponse toFreeMoneyResponse(Map<String, FreeMoney.Position> positions) {
    GetFreeMoneyResponse.Builder builder = GetFreeMoneyResponse.newBuilder();
    for (FreeMoney.Position position : positions.values()) {
      CurrencyFreeMoney.Builder entry =
          CurrencyFreeMoney.newBuilder()
              .setCurrency(position.currency())
              .setEligibleMinor(position.eligibleMinor())
              .setAllocatedMinor(position.allocatedMinor())
              .setFreeMinor(position.freeMinor());
      for (UUID accountId : position.eligibleAccountIds()) {
        entry.addEligibleAccountIds(accountId.toString());
      }
      builder.addCurrencies(entry);
    }
    return builder.build();
  }

  static GoalAllocationKind toWire(AllocationKind kind) {
    return switch (kind) {
      case ALLOCATE -> GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE;
      case WITHDRAW -> GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW;
      case MOVE -> GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE;
    };
  }
}
