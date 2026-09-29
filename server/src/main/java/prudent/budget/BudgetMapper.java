package prudent.budget;

import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import prudent.proto.v1.Budget;
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
}
