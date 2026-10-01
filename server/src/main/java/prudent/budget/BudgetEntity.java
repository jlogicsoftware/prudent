package prudent.budget;

import io.quarkus.hibernate.orm.panache.Panache;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * The {@code prudent_budget} table — the amount a user may spend in one category, in one calendar
 * month, in one currency (M3, jlogicsoftware/prudent#36, ADR-043). Active-record Panache entity.
 *
 * <p><strong>Not a record and not a plan.</strong> Nothing that computes a balance, an analytics
 * total or planned cash flow reads this table. See {@code proto/prudent/v1/budgets.proto}.
 *
 * <p>A budget is identified by its <em>slot</em> — {@code (userId, categoryId, month, currency)} —
 * which the database holds unique. The {@link #id} is not on the wire; it exists so a later audit
 * trail can name a row that survives an edit of its amount. Rows are written only through {@link
 * #upsert}, so the unique slot is filled by one statement rather than by a read and a write that
 * two requests could interleave.
 */
@Entity
@Table(name = "prudent_budget")
public class BudgetEntity extends PanacheEntityBase {

  @Id public UUID id;

  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Column(name = "category_id", nullable = false)
  public UUID categoryId;

  /** The first day of the budgeted month; the schema refuses any other day. */
  @Column(name = "budget_month", nullable = false)
  public LocalDate monthStart;

  // char(3), matching the migration, so Hibernate's schema validation stays honest.
  @Column(nullable = false, length = 3, columnDefinition = "char(3)")
  public String currency;

  /** Positive minor units: what may be spent, not a signed transaction amount. */
  @Column(name = "amount_minor", nullable = false)
  public long amountMinor;

  /** The budgeted month as the value the wire spells {@code YYYY-MM}. */
  public YearMonth month() {
    return YearMonth.from(monthStart);
  }

  /**
   * Sets a slot's amount, creating the row if the slot is empty. One {@code INSERT ... ON
   * CONFLICT DO UPDATE} against the unique slot, so two requests filling the same empty slot leave
   * one row holding the later amount instead of one of them failing on the constraint.
   *
   * <p>Native, and therefore invisible to the persistence context: an entity of this slot loaded
   * earlier in the same transaction is stale afterwards. Callers work from the values they passed
   * in rather than re-reading.
   */
  public static void upsert(
      UUID userId, UUID categoryId, YearMonth month, String currency, long amountMinor) {
    Panache.getEntityManager()
        .createNativeQuery(
            "INSERT INTO prudent_budget"
                + " (id, user_id, category_id, budget_month, currency, amount_minor)"
                + " VALUES (:id, :userId, :categoryId, :month, :currency, :amount)"
                + " ON CONFLICT ON CONSTRAINT prudent_budget_unique_slot"
                + " DO UPDATE SET amount_minor = EXCLUDED.amount_minor")
        .setParameter("id", UUID.randomUUID())
        .setParameter("userId", userId)
        .setParameter("categoryId", categoryId)
        .setParameter("month", month.atDay(1))
        .setParameter("currency", currency)
        .setParameter("amount", amountMinor)
        .executeUpdate();
  }

  /** One slot's budget, but only if the caller owns it — ownership is part of the lookup. */
  public static BudgetEntity findSlot(
      UUID userId, UUID categoryId, YearMonth month, String currency) {
    return find(
            "userId = ?1 and categoryId = ?2 and monthStart = ?3 and currency = ?4",
            userId, categoryId, month.atDay(1), currency)
        .firstResult();
  }

  /** Removes one slot's budget; the number of rows removed is 0 when the slot was empty. */
  public static long deleteSlot(
      UUID userId, UUID categoryId, YearMonth month, String currency) {
    return delete(
        "userId = ?1 and categoryId = ?2 and monthStart = ?3 and currency = ?4",
        userId, categoryId, month.atDay(1), currency);
  }

  /**
   * The caller's budgets, optionally narrowed to one month and/or one category. The order is
   * total — the slot is unique — so a list does not reshuffle between identical requests.
   */
  public static List<BudgetEntity> listOwnedBy(UUID userId, YearMonth month, UUID categoryId) {
    StringBuilder query = new StringBuilder("userId = ?1");
    List<Object> params = new ArrayList<>();
    params.add(userId);
    if (month != null) {
      params.add(month.atDay(1));
      query.append(" and monthStart = ?").append(params.size());
    }
    if (categoryId != null) {
      params.add(categoryId);
      query.append(" and categoryId = ?").append(params.size());
    }
    query.append(" order by monthStart, currency, categoryId");
    return list(query.toString(), params.toArray());
  }

  /**
   * The caller's budgets for one month in one currency, ordered by category id — the rows a budget
   * summary is calculated from. The currency is part of the query, not a filter applied after it,
   * so no other currency's budget is ever read into a calculation.
   */
  public static List<BudgetEntity> listForMonthAndCurrency(
      UUID userId, YearMonth month, String currency) {
    return list(
        "userId = ?1 and monthStart = ?2 and currency = ?3 order by categoryId",
        userId, month.atDay(1), currency);
  }

  /**
   * The caller's budgets in one currency for the given categories in every month before {@code
   * month} — the rows a carry-over is calculated from. Currency is part of the query, as in {@link
   * #listForMonthAndCurrency}.
   */
  public static List<BudgetEntity> listEarlier(
      UUID userId, YearMonth month, String currency, java.util.Collection<UUID> categoryIds) {
    if (categoryIds.isEmpty()) {
      return List.of();
    }
    return list(
        "userId = ?1 and monthStart < ?2 and currency = ?3 and categoryId in ?4"
            + " order by monthStart, categoryId",
        userId, month.atDay(1), currency, categoryIds);
  }

  /** Whether any of the caller's budgets is still set for this category. */
  public static boolean existsForCategory(UUID userId, UUID categoryId) {
    return count("userId = ?1 and categoryId = ?2", userId, categoryId) > 0;
  }
}
