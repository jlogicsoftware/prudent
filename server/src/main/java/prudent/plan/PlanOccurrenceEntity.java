package prudent.plan;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * The {@code prudent_plan_occurrence} table — one materialised, dated instance of a plan (M2,
 * jlogicsoftware/prudent#55, ADR-038). Active-record Panache entity.
 *
 * <p>Rows are written by {@link OccurrenceGenerator} and by nothing else: it inserts with {@code ON
 * CONFLICT DO NOTHING}, which an entity {@code persist()} cannot express, and a persist here would
 * race the generator into the very duplicate the table's unique constraint exists to refuse.
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

  /** A plan's occurrences in date order, for the caller who owns it. */
  public static List<PlanOccurrenceEntity> listForPlan(UUID userId, UUID planId) {
    return list("userId = ?1 and planId = ?2 order by occurrenceDate", userId, planId);
  }

  /** Removes every occurrence of one plan, returning how many there were. */
  public static long deleteForPlan(UUID planId) {
    return delete("planId", planId);
  }
}
