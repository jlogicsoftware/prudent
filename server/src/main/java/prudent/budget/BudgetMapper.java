package prudent.budget;

import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import prudent.proto.v1.Budget;
import prudent.proto.v1.BudgetCarryOverReset;
import prudent.proto.v1.ListBudgetCarryOverResetsResponse;
import prudent.proto.v1.ListBudgetsResponse;

/**
 * Maps {@link BudgetEntity} to its wire {@link Budget} proto. Entity → proto only; the other
 * direction is validation, and lives in {@link BudgetResource}.
 *
 * <p>Hand-written rather than MapStruct: the month is a first-of-month date on one side and a
 * {@code YYYY-MM} string on the other, and there are four fields.
 */
@ApplicationScoped
public class BudgetMapper {

  public Budget toProto(BudgetEntity entity) {
    return Budget.newBuilder()
        .setCategoryId(entity.categoryId.toString())
        .setMonth(entity.month().toString())
        .setCurrency(entity.currency)
        .setAmountMinor(entity.amountMinor)
        .build();
  }

  /** The list response, in the order the entity query returned. */
  public ListBudgetsResponse toListResponse(List<BudgetEntity> entities) {
    ListBudgetsResponse.Builder builder = ListBudgetsResponse.newBuilder();
    for (BudgetEntity entity : entities) {
      builder.addBudgets(toProto(entity));
    }
    return builder.build();
  }

  public BudgetCarryOverReset toProto(BudgetCarryResetEntity entity) {
    BudgetCarryOverReset.Builder builder =
        BudgetCarryOverReset.newBuilder()
            .setId(entity.id.toString())
            .setCategoryId(entity.categoryId.toString())
            .setMonth(entity.month().toString())
            .setCurrency(entity.currency)
            .setDiscardedMinor(entity.discardedMinor)
            .setNote(entity.note)
            .setCreatedBy(entity.createdBy.toString())
            .setCreatedAtMs(entity.createdAt.toEpochMilli());
    if (entity.isRevoked()) {
      builder.setRevokedBy(entity.revokedBy.toString()).setRevokedAtMs(entity.revokedAt.toEpochMilli());
    }
    return builder.build();
  }

  /** The history, in the order the entity query returned. */
  public ListBudgetCarryOverResetsResponse toHistoryResponse(
      List<BudgetCarryResetEntity> entities) {
    ListBudgetCarryOverResetsResponse.Builder builder =
        ListBudgetCarryOverResetsResponse.newBuilder();
    for (BudgetCarryResetEntity entity : entities) {
      builder.addResets(toProto(entity));
    }
    return builder.build();
  }
}
