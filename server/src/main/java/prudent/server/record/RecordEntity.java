package prudent.server.record;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * The {@code prudent_record} table — the individual transactions (active-record Panache entity).
 *
 * <p><strong>The {@code Entity} suffix is not optional here.</strong> Beyond the collision with the
 * generated {@code prudent.proto.v1.Record}, a class called {@code Record} would shadow
 * {@code java.lang.Record} inside its own package — every {@code record} declaration in this
 * package would then fail to resolve its supertype in a way whose error message names neither this
 * class nor the language feature.
 *
 * <p>{@code userId} is the ownership column and never appears on the wire in either direction.
 */
@Entity
@Table(name = "prudent_record")
public class RecordEntity extends PanacheEntityBase {

  /** Server-minted. A create request carries no id. */
  @Id public UUID id;

  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Column(nullable = false)
  public String title;

  /**
   * Minor units, exact under addition. See {@link prudent.server.account.AccountBalance} for why
   * money is never a floating-point type here.
   */
  @Column(name = "amount_minor", nullable = false)
  public long amountMinor;

  /**
   * Which of the owning account's currencies this record is denominated in. ISO-4217, upper case.
   *
   * <p>Client-supplied and required. When an account held exactly one currency a record could
   * inherit it, and inheritance was the stronger design because it made disagreement impossible to
   * <em>express</em>. An account now holds several currencies (ADR-008), so there is nothing to
   * inherit and only the record knows which balance it moved. What replaces inheritance is a
   * refusal — the server rejects a currency the owning account does not hold — and that is a
   * weaker guarantee held by a validation rule rather than by an unsayable state.
   */
  @Column(nullable = false, length = 3)
  public String currency;

  /**
   * A CIVIL DATE, not an instant — {@code DATE} in Postgres, {@link LocalDate} here.
   *
   * <p>A purchase happens on a calendar day. An epoch timestamp would force every reader to pick a
   * timezone to render in, and at the first daylight-saving boundary a record would shift a day —
   * at a month edge, into the wrong month, which in a budget app is a wrong total rather than a
   * cosmetic slip.
   */
  @Column(name = "record_date", nullable = false)
  public LocalDate date;

  /** The owning category, by id. Validated as the caller's own on write. */
  @Column(name = "category_id", nullable = false)
  public UUID categoryId;

  /**
   * The owning account, by id. Required — a record with no account is money that left no account,
   * and a balance computed over such records is arithmetic with a hole in it.
   */
  @Column(name = "account_id", nullable = false)
  public UUID accountId;

  /**
   * Every record owned by one user.
   *
   * <p>UNPAGINATED IN v1, which the contract settles rather than this class: a personal expense
   * tracker's record list is bounded by one person's spending, and a page parameter no screen sends
   * and no test exercises is ceremony. When a real list gets long enough to need it, the page
   * parameters are query parameters on the {@code GET} and the response message gains its page
   * metadata — a backward-compatible proto3 addition. See {@code proto/prudent/v1/records.proto}.
   *
   * <p>Ordered newest first, then by id so the order is total: two records on the same day would
   * otherwise come back in whatever order the database chose, and a list that reshuffles between
   * identical requests reads as data changing.
   */
  public static List<RecordEntity> listOwnedBy(UUID userId) {
    return list("userId = ?1 order by date desc, id", userId);
  }

  /**
   * One record, but only if the caller owns it. Ownership is part of the lookup rather than a check
   * after it — a find-then-compare can be written without the compare, and the version without it
   * still returns a row.
   */
  public static RecordEntity findOwned(UUID userId, UUID id) {
    return find("id = ?1 and userId = ?2", id, userId).firstResult();
  }

  /** Whether any record still points at this account. Guards the account delete. */
  public static boolean existsForAccount(UUID userId, UUID accountId) {
    return count("userId = ?1 and accountId = ?2", userId, accountId) > 0;
  }

  /** Whether any record still points at this category. Guards the category delete. */
  public static boolean existsForCategory(UUID userId, UUID categoryId) {
    return count("userId = ?1 and categoryId = ?2", userId, categoryId) > 0;
  }

  /**
   * Which of an account's currencies still have records. Guards the account update: a currency with
   * records cannot be dropped, because doing so would orphan money that left an account no longer
   * admitting it exists.
   */
  public static Set<String> currenciesInUse(UUID userId, UUID accountId) {
    return Set.copyOf(
        getEntityManager()
            .createQuery(
                "select distinct r.currency from RecordEntity r"
                    + " where r.userId = :userId and r.accountId = :accountId",
                String.class)
            .setParameter("userId", userId)
            .setParameter("accountId", accountId)
            .getResultList());
  }

  /**
   * The net of one account's records, by currency — what {@link prudent.server.account.AccountMapper}
   * adds to the opening balance to answer an account's CURRENT derived balance
   * (docs/DECISIONS.md ADR-014). {@code amount_minor} is signed (negative expense, positive
   * income), so a plain {@code sum} is the whole formula: no separate sign flip anywhere here.
   *
   * <p>A currency with no records for this account is simply absent from the map — the caller adds
   * zero by not finding an entry, rather than this method inventing a zero row for every currency
   * the account happens to hold.
   */
  public static Map<String, Long> netByAccount(UUID userId, UUID accountId) {
    Map<String, Long> net = new HashMap<>();
    for (Object[] row :
        getEntityManager()
            .createQuery(
                "select r.currency, sum(r.amountMinor) from RecordEntity r"
                    + " where r.userId = :userId and r.accountId = :accountId"
                    + " group by r.currency",
                Object[].class)
            .setParameter("userId", userId)
            .setParameter("accountId", accountId)
            .getResultList()) {
      net.put((String) row[0], (Long) row[1]);
    }
    return net;
  }

  /**
   * The same net as {@link #netByAccount}, for every account of one user in a single query — what
   * {@link prudent.server.account.AccountMapper} uses to answer {@code GET /api/v1/accounts}
   * without one query per account in the list.
   */
  /**
   * The expense rows (negative {@code amountMinor}) one user has in one currency within a civil
   * date range, inclusive on both ends — the raw material for
   * {@link prudent.server.analytics.AnalyticsResource}'s two endpoints. Each row is
   * {@code {categoryId, date, amountMinor}}.
   *
   * <p><strong>Income is excluded here, not filtered by the caller.</strong> "Spend by category"
   * and "spend by period" both mean expense only (proto/prudent/v1/analytics.proto); putting the
   * {@code amountMinor < 0} filter in the one query both endpoints share is what keeps that
   * meaning from being re-decided differently at each call site.
   *
   * <p>Bucketing (by category, by month, by year) happens in Java rather than in SQL: the
   * personal-finance row counts this application deals with make that cheap, and it avoids a
   * database-specific date-truncation function that would tie the query to Postgres.
   */
  public static List<Object[]> expenseRows(
      UUID userId, String currency, LocalDate from, LocalDate to) {
    return getEntityManager()
        .createQuery(
            "select r.categoryId, r.date, r.amountMinor from RecordEntity r"
                + " where r.userId = :userId and r.currency = :currency and r.amountMinor < 0"
                + " and r.date >= :from and r.date <= :to",
            Object[].class)
        .setParameter("userId", userId)
        .setParameter("currency", currency)
        .setParameter("from", from)
        .setParameter("to", to)
        .getResultList();
  }

  public static Map<UUID, Map<String, Long>> netByAccountForUser(UUID userId) {
    Map<UUID, Map<String, Long>> net = new HashMap<>();
    for (Object[] row :
        getEntityManager()
            .createQuery(
                "select r.accountId, r.currency, sum(r.amountMinor) from RecordEntity r"
                    + " where r.userId = :userId"
                    + " group by r.accountId, r.currency",
                Object[].class)
            .setParameter("userId", userId)
            .getResultList()) {
      net.computeIfAbsent((UUID) row[0], id -> new HashMap<>()).put((String) row[1], (Long) row[2]);
    }
    return net;
  }
}
