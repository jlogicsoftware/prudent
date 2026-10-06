package prudent.plan;

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
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import prudent.error.PrudentException;

/**
 * The {@code prudent_plan_occurrence} table — one materialised, dated instance of a plan (M2,
 * jlogicsoftware/prudent#55, ADR-038). Active-record Panache entity.
 *
 * <p>Rows are <em>created</em> by {@link OccurrenceGenerator} and by nothing else: it inserts with
 * {@code ON CONFLICT DO NOTHING}, which an entity {@code persist()} cannot express, and a persist
 * here would race the generator into the very duplicate the table's unique constraint exists to
 * refuse. Once a row exists, {@link #transitionTo} is the only way its {@link #state} changes.
 *
 * <p>Not a record: nothing that computes a balance or an analytics total reads this table.
 */
@Entity
@Table(name = "prudent_plan_occurrence")
public class PlanOccurrenceEntity extends PanacheEntityBase {

  @Id public UUID id;

  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Column(name = "plan_id", nullable = false)
  public UUID planId;

  @Column(name = "occurrence_date", nullable = false)
  public LocalDate occurrenceDate;

  /**
   * What became of this occurrence. Written only through {@link #transitionTo}; the generator's
   * insert names no state, so a new row takes the column's {@code PLANNED} default.
   */
  @Enumerated(EnumType.STRING)
  @Column(nullable = false)
  public OccurrenceState state = OccurrenceState.PLANNED;

  /**
   * When the user read this occurrence's reminder, or {@code null} while they have not (M5,
   * ADR-055). The only stored fact about a reminder: whether one is due is calculated on every read.
   * Written only through {@link #markReminderRead} and {@link #markReminderUnread}.
   */
  @Column(name = "reminder_read_at")
  public Instant reminderReadAt;

  /** Whether the user has read this occurrence's reminder. */
  public boolean isReminderRead() {
    return reminderReadAt != null;
  }

  /** Marks the reminder read at {@code now}; reading it again keeps the first time. */
  public void markReminderRead(Instant now) {
    if (reminderReadAt == null) {
      reminderReadAt = now;
    }
  }

  /** Marks the reminder unread again. */
  public void markReminderUnread() {
    reminderReadAt = null;
  }

  /**
   * Moves this occurrence to {@code target}, or refuses.
   *
   * @throws prudent.error.PrudentException 409 if {@link OccurrenceState} does not allow the move
   */
  public void transitionTo(OccurrenceState target) {
    if (!state.canTransitionTo(target)) {
      throw PrudentException.conflict(
          "An occurrence that is " + state + " cannot become " + target + ".");
    }
    state = target;
  }

  /**
   * Returns a completed occurrence to {@link OccurrenceState#PLANNED} because the transaction that
   * completed it has been deleted.
   *
   * <p>This is <em>not</em> a {@link #transitionTo} and is not in {@link
   * OccurrenceState#successors()}, on purpose: no route may reopen a completed occurrence on the
   * user's say-so, because that would leave the transaction and the promise of it both standing.
   * The only legitimate cause is the transaction itself going away, and the only caller is the
   * record delete that removes it.
   *
   * @throws prudent.error.PrudentException 409 if the occurrence is not completed
   */
  public void reopen() {
    if (state != OccurrenceState.COMPLETED) {
      throw PrudentException.conflict(
          "An occurrence that is " + state + " has no transaction to reopen from.");
    }
    state = OccurrenceState.PLANNED;
  }

  /** A plan's occurrences in date order, for the caller who owns it. */
  public static List<PlanOccurrenceEntity> listForPlan(UUID userId, UUID planId) {
    return list("userId = ?1 and planId = ?2 order by occurrenceDate", userId, planId);
  }

  /**
   * One occurrence, but only if the caller owns it, <em>locked for the transaction</em> so two
   * concurrent transitions (a skip racing a restore, or later a confirmation) are serialised and
   * the second sees the first's result rather than acting on a state it has already left.
   */
  public static PlanOccurrenceEntity findOwnedForUpdate(UUID userId, UUID id) {
    return find("id = ?1 and userId = ?2", id, userId)
        .withLock(LockModeType.PESSIMISTIC_WRITE)
        .firstResult();
  }

  /**
   * The caller's occurrences in one state dated within {@code [from, to]}, oldest first then by id.
   * Pass {@code state == null} for every state. Either bound may be {@code null} for open-ended.
   */
  public static List<PlanOccurrenceEntity> listOwnedBetween(
      UUID userId, OccurrenceState state, LocalDate from, LocalDate to) {
    StringBuilder query = new StringBuilder("userId = ?1");
    List<Object> params = new ArrayList<>();
    params.add(userId);
    if (state != null) {
      params.add(state);
      query.append(" and state = ?").append(params.size());
    }
    if (from != null) {
      params.add(from);
      query.append(" and occurrenceDate >= ?").append(params.size());
    }
    if (to != null) {
      params.add(to);
      query.append(" and occurrenceDate <= ?").append(params.size());
    }
    query.append(" order by occurrenceDate, id");
    return list(query.toString(), params.toArray());
  }

  /**
   * One plan's still-planned occurrences dated on or before {@code to}, oldest first then by id —
   * what a reminder is calculated from (ADR-055).
   */
  public static List<PlanOccurrenceEntity> listPlannedOfPlanUpTo(
      UUID userId, UUID planId, LocalDate to) {
    return list(
        "userId = ?1 and planId = ?2 and state = ?3 and occurrenceDate <= ?4"
            + " order by occurrenceDate, id",
        userId,
        planId,
        OccurrenceState.PLANNED,
        to);
  }

  /** Removes every occurrence of one plan, returning how many there were. */
  public static long deleteForPlan(UUID planId) {
    return delete("planId", planId);
  }

  /** The dates a plan already has an occurrence on within {@code [from, to]}, in any state. */
  public static List<LocalDate> datesForPlanBetween(UUID planId, LocalDate from, LocalDate to) {
    return getEntityManager()
        .createQuery(
            "select o.occurrenceDate from PlanOccurrenceEntity o"
                + " where o.planId = :planId and o.occurrenceDate >= :from"
                + " and o.occurrenceDate <= :to",
            LocalDate.class)
        .setParameter("planId", planId)
        .setParameter("from", from)
        .setParameter("to", to)
        .getResultList();
  }

  /** The dates of a plan's still-planned occurrences, oldest first. */
  public static List<LocalDate> plannedDatesForPlan(UUID planId) {
    return getEntityManager()
        .createQuery(
            "select o.occurrenceDate from PlanOccurrenceEntity o"
                + " where o.planId = :planId and o.state = :state order by o.occurrenceDate",
            LocalDate.class)
        .setParameter("planId", planId)
        .setParameter("state", OccurrenceState.PLANNED)
        .getResultList();
  }

  /**
   * Removes the plan's <em>still-planned</em> occurrences on any of {@code dates}, returning how
   * many went. Completed and skipped ones are decisions the user made and are never touched.
   */
  public static long deletePlannedOn(UUID planId, Collection<LocalDate> dates) {
    if (dates.isEmpty()) {
      return 0;
    }
    return delete(
        "planId = ?1 and state = ?2 and occurrenceDate in ?3",
        planId,
        OccurrenceState.PLANNED,
        dates);
  }
}
