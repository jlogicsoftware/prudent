package prudent.plan;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * The {@code prudent_plan} table — expected income and spending, one-off or recurring (M2,
 * jlogicsoftware/prudent#34, ADR-037). Active-record Panache entity.
 *
 * <p><strong>Not a record.</strong> Nothing that computes a balance or an analytics total reads
 * this table; that is the whole reason it is a table of its own rather than a flag on {@code
 * prudent_record}. See {@code proto/prudent/v1/plans.proto}.
 *
 * <p>The recurrence rule is stored flat on the row, and {@link #rule()} / {@link #setRule} are the
 * only way in or out of it, so the columns can never be written in a combination {@link
 * RecurrenceRule} has not validated. The reminder setting is the same: {@link #reminder()} /
 * {@link #setReminder} (M5, ADR-054).
 */
@Entity
@Table(name = "prudent_plan")
public class PlanEntity extends PanacheEntityBase {

  /** Server-minted. A create request carries no id. */
  @Id public UUID id;

  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Column(nullable = false)
  public String title;

  /** Signed minor units, exactly as {@code RecordEntity.amountMinor}. */
  @Column(name = "amount_minor", nullable = false)
  public long amountMinor;

  // char(3), matching the migration, so Hibernate's schema validation stays honest.
  @Column(nullable = false, length = 3, columnDefinition = "char(3)")
  public String currency;

  @Column(name = "account_id", nullable = false)
  public UUID accountId;

  @Column(name = "category_id", nullable = false)
  public UUID categoryId;

  @Column public String payee;

  @Column public String note;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false)
  Frequency frequency;

  @Column(name = "recurrence_interval", nullable = false)
  int recurrenceInterval;

  @Column(name = "start_date", nullable = false)
  LocalDate startDate;

  /** The IANA id as the client sent it and {@link RecurrenceRule#parseZone} accepted it. */
  @Column(name = "time_zone", nullable = false)
  String timeZone;

  @Column(name = "until_date")
  LocalDate untilDate;

  @Column(name = "occurrence_count")
  Integer occurrenceCount;

  // Defaults match the migration's, so a row that never had a setting reads as the default.
  @Column(name = "reminder_enabled", nullable = false)
  boolean reminderEnabled;

  @Column(name = "reminder_lead_days", nullable = false)
  int reminderLeadDays = ReminderSetting.DEFAULT_LEAD_DAYS;

  /** The stored reminder setting, as the validated value. */
  public ReminderSetting reminder() {
    return new ReminderSetting(reminderEnabled, reminderLeadDays);
  }

  /** Replaces the stored reminder setting with an already-validated one. */
  public void setReminder(ReminderSetting reminder) {
    reminderEnabled = reminder.enabled();
    reminderLeadDays = reminder.leadDays();
  }

  /** The stored recurrence, as the validated value the date arithmetic runs on. */
  public RecurrenceRule rule() {
    return new RecurrenceRule(
        frequency, recurrenceInterval, startDate, ZoneId.of(timeZone), untilDate, occurrenceCount);
  }

  /** Replaces the stored recurrence with an already-validated one. */
  public void setRule(RecurrenceRule rule) {
    frequency = rule.frequency();
    recurrenceInterval = rule.interval();
    startDate = rule.startDate();
    timeZone = rule.timeZone().getId();
    untilDate = rule.untilDate();
    occurrenceCount = rule.occurrenceCount();
  }

  /**
   * Every plan owned by one user, earliest start first, then by id so the order is total and a list
   * does not reshuffle between identical requests.
   */
  public static List<PlanEntity> listOwnedBy(UUID userId) {
    return list("userId = ?1 order by startDate, id", userId);
  }

  /** One plan, but only if the caller owns it — ownership is part of the lookup. */
  public static PlanEntity findOwned(UUID userId, UUID id) {
    return find("id = ?1 and userId = ?2", id, userId).firstResult();
  }

  /** Whether any of the caller's plans still expects money to move in this account. */
  public static boolean existsForAccount(UUID userId, UUID accountId) {
    return count("userId = ?1 and accountId = ?2", userId, accountId) > 0;
  }

  /** Whether any of the caller's plans is still filed under this category. */
  public static boolean existsForCategory(UUID userId, UUID categoryId) {
    return count("userId = ?1 and categoryId = ?2", userId, categoryId) > 0;
  }

  /**
   * The currencies this account's plans are denominated in. An account cannot drop one of them,
   * for the same reason it cannot drop a currency its records use: the plan would name a balance
   * the account no longer admits it has.
   */
  public static Set<String> currenciesInUse(UUID userId, UUID accountId) {
    return Set.copyOf(
        getEntityManager()
            .createQuery(
                "select distinct p.currency from PlanEntity p"
                    + " where p.userId = :userId and p.accountId = :accountId",
                String.class)
            .setParameter("userId", userId)
            .setParameter("accountId", accountId)
            .getResultList());
  }
}
