package prudent;

import io.quarkus.test.junit.QuarkusMock;
import java.time.Instant;

/**
 * A {@link StoredClock} whose underlying reading is finer than the database keeps, as a Linux clock
 * is and a macOS one is not. The default reading is in the last half microsecond of its millisecond:
 * stored uncut, the database rounds it into the next millisecond (ADR-139).
 */
public final class FineStoredClock extends StoredClock {

  /** The millisecond every default reading is in, and so the one every answer and read must show. */
  public static final long EPOCH_MILLI = Instant.parse("2026-11-28T10:15:30.650Z").toEpochMilli();

  private static final Instant LAST_HALF_MICROSECOND =
      Instant.parse("2026-11-28T10:15:30.650999700Z");

  @Override
  protected Instant raw() {
    return LAST_HALF_MICROSECOND;
  }

  /** Replaces the application's clock until the running test ends. */
  public static void install() {
    QuarkusMock.installMockForType(new FineStoredClock(), StoredClock.class);
  }
}
