package prudent.budget;

import io.quarkus.hibernate.orm.panache.Panache;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.UUID;

/**
 * The {@code prudent_budget_carry_reset} table — one carry-over reset and, because rows are never
 * deleted, one entry of its audit history (M3, jlogicsoftware/prudent#61, ADR-046). Active-record
 * Panache entity.
 *
 * <p>A live row (not revoked) is a boundary for {@link BudgetCalculator#carryOver}: months before
 * {@link #monthStart} stop counting toward that category's carry-over in that currency. A revoked
 * row stays, names who revoked it and when, and bounds nothing.
 *
 * <p>Rows are created only through {@link #insertLive} and changed only through {@link #revoke}, so
 * the one-live-reset-per-slot rule is decided by the database's partial unique index in a single
 * statement rather than by a read and a write that two requests could interleave.
 */
@Entity
@Table(name = "prudent_budget_carry_reset")
public class BudgetCarryResetEntity extends PanacheEntityBase {

  @Id public UUID id;

  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Column(name = "category_id", nullable = false)
  public UUID categoryId;

  /** The first day of the month the reset takes effect in; the schema refuses any other day. */
  @Column(name = "reset_month", nullable = false)
  public LocalDate monthStart;

  // char(3), matching the migration, so Hibernate's schema validation stays honest.
  @Column(nullable = false, length = 3, columnDefinition = "char(3)")
  public String currency;

  /** The carry-over into the reset month just before this reset: signed minor units. */
  @Column(name = "discarded_minor", nullable = false)
  public long discardedMinor;

  @Column(nullable = false)
  public String note;

  @Column(name = "created_at", nullable = false)
  public Instant createdAt;

  @Column(name = "created_by", nullable = false)
  public UUID createdBy;

  @Column(name = "revoked_at")
  public Instant revokedAt;

  @Column(name = "revoked_by")
  public UUID revokedBy;

  /** The reset month as the value the wire spells {@code YYYY-MM}. */
  public YearMonth month() {
    return YearMonth.from(monthStart);
  }

  public boolean isRevoked() {
    return revokedAt != null;
  }

  /**
   * Writes a live reset unless the slot already has one, and answers whether it did. One {@code
   * INSERT ... ON CONFLICT DO NOTHING} against the live-slot partial index, so two requests
   * resetting the same slot at once leave one row and one of them is told {@code false}.
   *
   * <p>Native, and therefore invisible to the persistence context: callers build their response
   * from the values they passed in.
   */
  public static boolean insertLive(
      UUID id,
      UUID userId,
      UUID categoryId,
      YearMonth month,
      String currency,
      long discardedMinor,
      String note,
      Instant createdAt) {
    return Panache.getEntityManager()
            .createNativeQuery(
                "INSERT INTO prudent_budget_carry_reset"
                    + " (id, user_id, category_id, reset_month, currency, discarded_minor, note,"
                    + " created_at, created_by)"
                    + " VALUES (:id, :userId, :categoryId, :month, :currency, :discarded, :note,"
                    + " :createdAt, :userId)"
                    + " ON CONFLICT (user_id, category_id, reset_month, currency)"
                    + " WHERE revoked_at IS NULL DO NOTHING")
            .setParameter("id", id)
            .setParameter("userId", userId)
            .setParameter("categoryId", categoryId)
            .setParameter("month", month.atDay(1))
            .setParameter("currency", currency)
            .setParameter("discarded", discardedMinor)
            .setParameter("note", note)
            .setParameter("createdAt", createdAt)
            .executeUpdate()
        > 0;
  }

  /**
   * Marks one of the caller's live resets revoked, and answers whether it did — {@code false} when
   * the entry is not the caller's or was already revoked. The condition is part of the statement,
   * so two revocations racing leave the first one's name and time on the row.
   */
  public static boolean revoke(UUID userId, UUID id, Instant at) {
    return update(
            "revokedAt = ?1, revokedBy = ?2 where id = ?3 and userId = ?2 and revokedAt is null",
            at, userId, id)
        > 0;
  }

  /** One entry, but only if the caller owns it — ownership is part of the lookup. */
  public static BudgetCarryResetEntity findOwned(UUID userId, UUID id) {
    return find("userId = ?1 and id = ?2", userId, id).firstResult();
  }

  /**
   * The caller's whole reset history, revoked entries included, optionally narrowed to one category
   * and/or one currency. Newest first, then by id, so the order is total.
   */
  public static List<BudgetCarryResetEntity> history(
      UUID userId, UUID categoryId, String currency) {
    StringBuilder query = new StringBuilder("userId = ?1");
    List<Object> params = new ArrayList<>();
    params.add(userId);
    if (categoryId != null) {
      params.add(categoryId);
      query.append(" and categoryId = ?").append(params.size());
    }
    if (currency != null) {
      params.add(currency);
      query.append(" and currency = ?").append(params.size());
    }
    query.append(" order by createdAt desc, id");
    return list(query.toString(), params.toArray());
  }

  /**
   * The caller's live resets in one currency for the given categories, effective at or before
   * {@code month} — the boundaries a carry-over into {@code month} is calculated with. A reset
   * after the month is not read: it says nothing about a month before it. Currency is part of the
   * query, as in {@link BudgetEntity#listEarlier}.
   */
  public static List<BudgetCarryResetEntity> listLive(
      UUID userId, YearMonth month, String currency, Collection<UUID> categoryIds) {
    if (categoryIds.isEmpty()) {
      return List.of();
    }
    return list(
        "userId = ?1 and monthStart <= ?2 and currency = ?3 and categoryId in ?4"
            + " and revokedAt is null",
        userId, month.atDay(1), currency, categoryIds);
  }

  /** Whether the category has any reset history, live or revoked. */
  public static boolean existsForCategory(UUID userId, UUID categoryId) {
    return count("userId = ?1 and categoryId = ?2", userId, categoryId) > 0;
  }
}
