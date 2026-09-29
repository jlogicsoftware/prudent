package prudent.plan;

import io.quarkus.hibernate.orm.panache.Panache;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;
import prudent.error.PrudentException;

/**
 * Materialises a plan's occurrences inside a bounded window (M2, jlogicsoftware/prudent#55,
 * ADR-038).
 *
 * <p><strong>Idempotent, and safe to race.</strong> Which dates a window holds is a pure function
 * of the plan's {@link RecurrenceRule} ({@link RecurrenceRule#occurrencesBetween}), so two runs
 * over the same window agree on what should exist. What makes them agree on what <em>does</em>
 * exist is the database: every row is inserted with {@code ON CONFLICT DO NOTHING} against the
 * {@code (plan_id, occurrence_date)} unique constraint. A check-then-insert in Java would let two
 * concurrent generators both see a date as missing and both write it; here the second one blocks on
 * the first's key until it commits and then does nothing. Dates are written in ascending order, so
 * two generators overlapping on different windows take their locks in the same order and cannot
 * deadlock.
 *
 * <p>Generation only ever adds. It never removes or rewrites an occurrence, so extending a window
 * later cannot disturb the ones already generated — and, once occurrences carry state (#56), cannot
 * discard a confirmed one.
 *
 * <p>Nothing here moves money: an occurrence is a row in its own table, not a record.
 */
@ApplicationScoped
public class OccurrenceGenerator {

  /**
   * The widest window accepted, in days from the first date to the last inclusive. Ten years: past
   * any horizon a person plans to, and small enough that even a daily rule is a few thousand rows,
   * so an unbounded rule (no end date, no count) can never be asked for "all of it".
   */
  public static final long MAX_WINDOW_DAYS = 3660;

  /**
   * What one run did.
   *
   * @param inWindow how many occurrences the rule places in the window
   * @param created how many of them this run inserted; the rest already existed
   */
  public record Result(int inWindow, int created) {}

  /**
   * Ensures every occurrence of {@code plan} in {@code [from, to]} exists.
   *
   * <p>Joins the caller's transaction if there is one, and otherwise runs in its own, so a caller
   * that wants the plan lookup and the generation to commit together can have that.
   *
   * @param plan a plan the caller has already established belongs to the user
   * @param from the first date of the window, inclusive
   * @param to the last date of the window, inclusive
   * @return how many occurrences the window holds and how many this run had to create
   * @throws PrudentException 400 if the window is inverted or wider than {@link #MAX_WINDOW_DAYS}
   */
  @Transactional
  public Result generate(PlanEntity plan, LocalDate from, LocalDate to) {
    if (from == null || to == null) {
      throw PrudentException.invalid("A generation window needs both a from and a to date.");
    }
    if (to.isBefore(from)) {
      throw PrudentException.invalid(
          "The generation window ends (" + to + ") before it starts (" + from + ").");
    }
    if (ChronoUnit.DAYS.between(from, to) + 1 > MAX_WINDOW_DAYS) {
      throw PrudentException.invalid(
          "A generation window is at most " + MAX_WINDOW_DAYS + " days.");
    }

    List<LocalDate> dates = plan.rule().occurrencesBetween(from, to);
    int created = 0;
    for (LocalDate date : dates) {
      created += insertIfAbsent(plan, date);
    }
    return new Result(dates.size(), created);
  }

  /** 1 if this call inserted the occurrence, 0 if it was already there. */
  private int insertIfAbsent(PlanEntity plan, LocalDate date) {
    return Panache.getEntityManager()
        .createNativeQuery(
            "INSERT INTO prudent_plan_occurrence (id, user_id, plan_id, occurrence_date)"
                + " VALUES (:id, :userId, :planId, :date)"
                + " ON CONFLICT (plan_id, occurrence_date) DO NOTHING")
        .setParameter("id", UUID.randomUUID())
        .setParameter("userId", plan.userId)
        .setParameter("planId", plan.id)
        .setParameter("date", date)
        .executeUpdate();
  }
}
