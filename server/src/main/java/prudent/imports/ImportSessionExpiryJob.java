package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.time.Duration;
import zen.jobs.ZenJob;

/**
 * Runs {@link ImportWorkflow#expireDue()} on a schedule, so the rows of an import nobody confirmed
 * — which carry personal data — are deleted soon after their session's time runs out and not only
 * when someone happens to read it (ADR-089). Same shape as {@code UserRetentionZenJob}.
 */
@ApplicationScoped
public class ImportSessionExpiryJob implements ZenJob {

  static final String JOB_ID = "import-session-expiry";

  /** Hourly: sessions live for hours (the default is 24), so a coarser sweep would double that. */
  private static final Duration INTERVAL = Duration.ofHours(1);

  private final ImportWorkflow workflow;

  @Inject
  public ImportSessionExpiryJob(ImportWorkflow workflow) {
    this.workflow = workflow;
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
    workflow.expireDue();
  }
}
