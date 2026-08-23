package prudent.server.retention;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.time.Duration;
import zen.identity.user.UserRetentionJob;
import zen.jobs.ZenJob;

/**
 * Registers the framework's GDPR Art. 5(1)(e) retention cycle as a scheduled job for Prudent.
 * Same shape as {@code ../jZen/apps/zen_demo/zen_demo_server}'s {@code UserRetentionZenJob}:
 * {@code zen-identity} offers {@link UserRetentionJob#runCycle()} as a plain callable and knows
 * nothing about scheduling, {@code zen-jobs} knows how to run things when they are due and
 * nothing about users — Prudent, the only party that knows it wants dormant accounts erased,
 * joins them.
 *
 * <p><strong>Prudent's own cascade is no longer a second job</strong> and no longer depends on
 * ordering at all: {@link PrudentRetentionCleanup} observes {@code UserAnonymised}, fired inside
 * this cycle's own transaction (ADR-022). What follows is kept because the ordering question it
 * answers is the one a reader will ask next — it is now moot, and that is worth saying rather
 * than leaving the reasoning to be reconstructed. Ordering was
 * something either job depends on — both are read the framework's own way (idempotent, safe in
 * any order or interleaving), but this one is what actually produces the anonymised accounts the
 * other sweeps for, so a fresh deployment's first tick anonymises before it has anything to
 * clean up. The next tick catches up.
 */
@ApplicationScoped
public class UserRetentionZenJob implements ZenJob {

  static final String JOB_ID = "user-retention";

  /** Daily — the retention windows are measured in hundreds of days (ADR-008 upstream). */
  private static final Duration INTERVAL = Duration.ofDays(1);

  private final UserRetentionJob retention;

  @Inject
  public UserRetentionZenJob(UserRetentionJob retention) {
    this.retention = retention;
  }

  @Override
  public String id() {
    return JOB_ID;
  }

  @Override
  public Duration defaultInterval() {
    return INTERVAL;
  }

  @Override
  public void run() {
    retention.runCycle();
  }
}
