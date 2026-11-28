package prudent;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;

/**
 * The instant to stamp on a row: now, cut to the microsecond a {@code TIMESTAMPTZ} column keeps
 * (ADR-139, jlogicsoftware/prudent#284).
 *
 * <p><strong>Why it must be cut here.</strong> A write is answered from the entity still in memory,
 * a later read from the database, and the wire carries milliseconds. The system clock can give finer
 * than microseconds (it does on Linux), which the database <em>rounds</em> while the wire mapping
 * <em>cuts</em>: in the last half microsecond of a millisecond the stored value lands in the next
 * one, and the same row reads 1 ms later than the answer that created it. A value already at the
 * column's precision is stored as it is.
 *
 * <p>Take every instant that is both stored and answered from here, not from {@code Instant.now()}.
 */
@ApplicationScoped
public class StoredClock {

  @Inject Clock clock;

  public Instant now() {
    return raw().truncatedTo(ChronoUnit.MICROS);
  }

  /** The clock's own reading, at whatever precision it has; overridden only by tests. */
  protected Instant raw() {
    return clock.instant();
  }
}
