package prudent.goal;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.LockModeType;
import jakarta.persistence.Table;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import prudent.error.PrudentException;

/**
 * The {@code prudent_goal} table — something the user wants to save for (M4,
 * jlogicsoftware/prudent#38, ADR-049). Active-record Panache entity.
 *
 * <p><strong>Not an account and not a record.</strong> Nothing that computes a balance or an
 * analytics total reads this table. See {@code proto/prudent/v1/goals.proto}.
 *
 * <p>A goal is retired, never deleted: there is no delete method here and no route for one, so the
 * envelope history ({@link GoalAllocationEntity}) always has a goal to be read through.
 */
@Entity
@Table(name = "prudent_goal")
public class GoalEntity extends PanacheEntityBase {

  /** Server-minted. A create request carries no id. */
  @Id public UUID id;

  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Column(nullable = false)
  public String name;

  // char(3), matching the migration, so Hibernate's schema validation stays honest. Never changed
  // after creation: money set aside for the goal is held in this currency.
  @Column(nullable = false, length = 3, columnDefinition = "char(3)")
  public String currency;

  /** Positive minor units: the amount to reach. */
  @Column(name = "target_amount_minor", nullable = false)
  public long targetAmountMinor;

  /** The day to have reached it by, or {@code null} for an open-ended goal. */
  @Column(name = "target_date")
  public LocalDate targetDate;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false)
  public GoalState status = GoalState.ACTIVE;

  @Column(name = "created_at", nullable = false)
  public Instant createdAt;

  /** When {@link #status} last changed; {@link #createdAt} until it first does. */
  @Column(name = "status_changed_at", nullable = false)
  public Instant statusChangedAt;

  /**
   * Moves the goal to {@code target}, or refuses (409) if {@link GoalState} does not allow it from
   * the current state. The only writer of {@link #status} after creation.
   */
  public void transitionTo(GoalState target, Instant at) {
    if (!status.canMoveTo(target)) {
      throw PrudentException.conflict(
          "A goal that is " + status + " cannot be made " + target + ".");
    }
    status = target;
    statusChangedAt = at;
  }

  /**
   * The caller's goals, optionally narrowed to one state, oldest first and then by id so the order
   * is total and a list does not reshuffle between identical requests.
   */
  public static List<GoalEntity> listOwnedBy(UUID userId, GoalState status) {
    if (status == null) {
      return list("userId = ?1 order by createdAt, id", userId);
    }
    return list("userId = ?1 and status = ?2 order by createdAt, id", userId, status);
  }

  /** One goal, but only if the caller owns it — ownership is part of the lookup. */
  public static GoalEntity findOwned(UUID userId, UUID id) {
    return find("id = ?1 and userId = ?2", id, userId).firstResult();
  }

  /**
   * One goal, but only if the caller owns it, locked for the rest of the transaction. Whatever
   * decides something from a goal's envelope — an entry that must not take it below zero, an
   * archive that needs it empty — locks the goal first, so two requests cannot both read the same
   * balance and both act on it. Callers locking more than one goal do so in id order.
   */
  public static GoalEntity findOwnedForUpdate(UUID userId, UUID id) {
    return find("id = ?1 and userId = ?2", id, userId)
        .withLock(LockModeType.PESSIMISTIC_WRITE)
        .firstResult();
  }
}
