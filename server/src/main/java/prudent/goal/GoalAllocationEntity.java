package prudent.goal;

import io.quarkus.hibernate.orm.panache.Panache;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The {@code prudent_goal_allocation} table — one entry of the envelope history (M4,
 * jlogicsoftware/prudent#64, ADR-050). Active-record Panache entity.
 *
 * <p><strong>Append-only.</strong> Rows are inserted and read, never changed: there is no setter
 * path, no update method and no route for either, and the database refuses an {@code UPDATE}. An
 * envelope has no stored amount — {@link #balance} and {@link #balances} calculate it from these
 * entries every time, so the figure cannot disagree with the history behind it.
 *
 * <p><strong>Not a record.</strong> Nothing that computes an account balance or an analytics total
 * reads this table. See {@code proto/prudent/v1/goal_allocations.proto}.
 */
@Entity
@Table(name = "prudent_goal_allocation")
public class GoalAllocationEntity extends PanacheEntityBase {

  /** Server-minted. A create request carries no id. */
  @Id public UUID id;

  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false)
  public AllocationKind kind;

  /** The goal money left, or {@code null} for an {@link AllocationKind#ALLOCATE}. */
  @Column(name = "source_goal_id")
  public UUID sourceGoalId;

  /** The goal money entered, or {@code null} for a {@link AllocationKind#WITHDRAW}. */
  @Column(name = "target_goal_id")
  public UUID targetGoalId;

  // char(3), matching the migration, so Hibernate's schema validation stays honest.
  @Column(nullable = false, length = 3, columnDefinition = "char(3)")
  public String currency;

  /** Positive minor units: how much moved. The direction is the kind, not the sign. */
  @Column(name = "amount_minor", nullable = false)
  public long amountMinor;

  @Column(nullable = false)
  public String note;

  @Column(name = "created_at", nullable = false)
  public Instant createdAt;

  @Column(name = "created_by", nullable = false)
  public UUID createdBy;

  /** One entry, but only if the caller owns it — ownership is part of the lookup. */
  public static GoalAllocationEntity findOwned(UUID userId, UUID id) {
    return find("id = ?1 and userId = ?2", id, userId).firstResult();
  }

  /**
   * The caller's history, optionally narrowed to the entries that put money into or took it out of
   * one goal. Newest first, then by id, so the order is total.
   */
  public static List<GoalAllocationEntity> history(UUID userId, UUID goalId) {
    if (goalId == null) {
      return list("userId = ?1 order by createdAt desc, id", userId);
    }
    return list(
        "userId = ?1 and (sourceGoalId = ?2 or targetGoalId = ?2) order by createdAt desc, id",
        userId, goalId);
  }

  /** Whether the goal has any history at all. */
  public static boolean existsForGoal(UUID userId, UUID goalId) {
    return count("userId = ?1 and (sourceGoalId = ?2 or targetGoalId = ?2)", userId, goalId) > 0;
  }

  /**
   * What one goal's envelope holds: the entries that put money in, less the entries that took it
   * out. Zero for a goal with no history. Summed in the database, where the running totals cannot
   * overflow a {@code long} even when the net fits in one.
   */
  public static long balance(UUID userId, UUID goalId) {
    return balances(userId, goalId).getOrDefault(goalId, 0L);
  }

  /** Every envelope the caller has history for, by goal id. A goal with none is absent. */
  public static Map<UUID, Long> balances(UUID userId) {
    return balances(userId, null);
  }

  private static Map<UUID, Long> balances(UUID userId, UUID goalId) {
    var query =
        Panache.getEntityManager()
            .createNativeQuery(
                "SELECT goal_id, SUM(delta) FROM ("
                    + " SELECT target_goal_id AS goal_id, amount_minor AS delta"
                    + "   FROM prudent_goal_allocation"
                    + "  WHERE user_id = :userId AND target_goal_id IS NOT NULL"
                    + " UNION ALL"
                    + " SELECT source_goal_id, -amount_minor"
                    + "   FROM prudent_goal_allocation"
                    + "  WHERE user_id = :userId AND source_goal_id IS NOT NULL"
                    + ") entries"
                    + (goalId == null ? "" : " WHERE goal_id = :goalId")
                    + " GROUP BY goal_id")
            .setParameter("userId", userId);
    if (goalId != null) {
      query.setParameter("goalId", goalId);
    }
    Map<UUID, Long> balances = new HashMap<>();
    for (Object row : query.getResultList()) {
      Object[] columns = (Object[]) row;
      balances.put((UUID) columns[0], ((BigDecimal) columns[1]).longValueExact());
    }
    return balances;
  }
}
