package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.enterprise.inject.Instance;
import jakarta.inject.Inject;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import zen.jobs.JobState;
import zen.jobs.ZenJob;

/**
 * The sweep that deletes unconfirmed statement rows is reachable by the scheduler (ADR-089): the job
 * is a discovered {@link ZenJob}, jZen's scheduler registered it with its interval at boot, and
 * running it does what {@link ImportWorkflow#expireDue()} does. {@code JobScheduler} runs exactly
 * the {@code Instance<ZenJob>} asserted here, so a job missing from it is a job that never runs.
 */
@QuarkusTest
class ImportSessionExpiryJobTest {

  @Inject Instance<ZenJob> jobs;

  @BeforeEach
  void clean() {
    PrudentTest.reset();
  }

  @Test
  void theJobIsDiscoveredOnceWithTheDocumentedIdAndInterval() {
    long matching = jobs.stream().filter(job -> ImportSessionExpiryJob.JOB_ID.equals(job.id())).count();
    assertEquals(1, matching);
    ZenJob job =
        jobs.stream().filter(j -> ImportSessionExpiryJob.JOB_ID.equals(j.id())).findFirst().orElseThrow();
    assertTrue(job instanceof ImportSessionExpiryJob || job.getClass().getName().contains("ImportSessionExpiryJob"));
    assertEquals(Duration.ofHours(1), job.defaultInterval());
  }

  @Test
  void theSchedulerSeededARowForItAtBoot() {
    JobState row =
        QuarkusTransaction.requiringNew().call(() -> JobState.byId(ImportSessionExpiryJob.JOB_ID));
    assertNotNull(row, "JobScheduler.seedRegisteredJobs found no ZenJob with this id");
    assertTrue(row.enabled);
  }

  @Test
  void runningTheJobExpiresOverdueSessionsAndLeavesLiveOnes() {
    UUID overdue =
        PrudentTest.seedImportSession(
            PrudentTest.ALICE, ImportState.PARSED, Instant.now().minusSeconds(5));
    UUID live =
        PrudentTest.seedImportSession(
            PrudentTest.ALICE, ImportState.PARSED, Instant.now().plusSeconds(3600));

    jobs.stream()
        .filter(job -> ImportSessionExpiryJob.JOB_ID.equals(job.id()))
        .findFirst()
        .orElseThrow()
        .run();

    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              assertEquals(
                  ImportState.EXPIRED, ImportSessionEntity.<ImportSessionEntity>findById(overdue).state);
              assertEquals(
                  ImportState.PARSED, ImportSessionEntity.<ImportSessionEntity>findById(live).state);
            });
    assertEquals(0, ImportRowEntity.count("sessionId", overdue));
    assertEquals(1, ImportRowEntity.count("sessionId", live));
  }
}
