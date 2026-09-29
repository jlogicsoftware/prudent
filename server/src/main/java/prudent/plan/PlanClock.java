package prudent.plan;

import jakarta.enterprise.context.ApplicationScoped;
import java.time.Instant;

/**
 * The instant "now" for plan logic, behind a bean so a test can decide what day it is.
 *
 * <p>Whether an occurrence is overdue depends on the current calendar day in its plan's time zone
 * ({@link RecurrenceRule#today}), and a test that read the wall clock could not pin the moment
 * either side of a zone's midnight — the one case that decides whether the time zone is honoured at
 * all. Nothing else in Prudent reads the clock through this; it exists for plans.
 */
@ApplicationScoped
public class PlanClock {

  /** The current instant. */
  public Instant now() {
    return Instant.now();
  }
}
