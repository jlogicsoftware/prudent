package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.error.PrudentException;

/**
 * Requests that race for one session (ADR-089): the workflow takes the session's row lock before it
 * decides anything, so exactly one of two conflicting phase changes wins, the loser is a 409 and
 * not a lost update or a deadlock, and the end state is the winner's. The workflow is driven
 * directly from threads, each call its own transaction, as concurrent requests would be.
 */
@QuarkusTest
class ImportConcurrencyTest {

  private static final UUID ALICE = UUID.fromString(PrudentTest.ALICE);

  @Inject ImportWorkflow workflow;
  @Inject EntityManager entityManager;

  private UUID account;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    account = PrudentTest.seedAccount(PrudentTest.ALICE, "Checking", "PLN");
  }

  /** Runs every task at once and returns, per task, null for success or what it threw. */
  private static List<Throwable> race(List<Callable<Object>> tasks) throws Exception {
    ExecutorService pool = Executors.newFixedThreadPool(tasks.size());
    try {
      CountDownLatch go = new CountDownLatch(1);
      List<Future<Object>> futures = new ArrayList<>();
      for (Callable<Object> task : tasks) {
        futures.add(
            pool.submit(
                () -> {
                  go.await();
                  return task.call();
                }));
      }
      go.countDown();
      List<Throwable> outcomes = new ArrayList<>();
      for (Future<Object> future : futures) {
        try {
          future.get(60, TimeUnit.SECONDS);
          outcomes.add(null);
        } catch (ExecutionException failed) {
          outcomes.add(failed.getCause());
        }
      }
      return outcomes;
    } finally {
      pool.shutdownNow();
    }
  }

  private UUID previewedSession() {
    byte[] content = "PLN\n2026-11-01;-500;TEST a;x\n2026-11-02;700;TEST b;x\n".getBytes(StandardCharsets.UTF_8);
    UUID id =
        UUID.fromString(
            workflow.create(ALICE, TestStatementImporter.FORMAT, content, null).session().id.toString());
    workflow.preview(ALICE, id, account);
    return id;
  }

  private static void assertConflict(Throwable thrown) {
    assertTrue(thrown instanceof PrudentException, String.valueOf(thrown));
    assertEquals(PrudentException.CONFLICT, ((PrudentException) thrown).code());
  }

  private ImportState stateOf(UUID id) {
    return QuarkusTransaction.requiringNew()
        .call(() -> ImportSessionEntity.<ImportSessionEntity>findById(id).state);
  }

  @Test
  void twoCommitsOfOneSession_bothSucceedAndTheLedgerIsWrittenOnce() throws Exception {
    ImportTestSupport.RecordingCommitter committer = ImportTestSupport.installRecordingCommitter(300);
    UUID id = previewedSession();

    List<Throwable> outcomes =
        race(
            List.of(
                () -> workflow.commit(ALICE, id, 2),
                () -> workflow.commit(ALICE, id, 2)));

    // The loser is a retry of a commit that went through (ADR-092): the same success, not a 409.
    assertEquals(2, outcomes.stream().filter(o -> o == null).count(), outcomes.toString());
    assertEquals(1, committer.calls.size(), "the committer must run exactly once");
    assertEquals(ImportState.COMMITTED, stateOf(id));
    assertEquals(0, ImportRowEntity.count("sessionId", id));
  }

  @Test
  void aCommitRacingADiscard_endsInTheWinnersStateWithTheLoserARefusal() throws Exception {
    ImportTestSupport.RecordingCommitter committer = ImportTestSupport.installRecordingCommitter(50);
    for (int round = 0; round < 6; round++) {
      UUID id = previewedSession();
      int before = committer.calls.size();

      List<Throwable> outcomes =
          race(
              List.of(
                  () -> workflow.commit(ALICE, id, 2),
                  () -> workflow.discard(ALICE, id)));

      assertEquals(1, outcomes.stream().filter(o -> o == null).count(), outcomes.toString());
      boolean commitWon = outcomes.get(0) == null;
      assertConflict(outcomes.get(commitWon ? 1 : 0));
      assertEquals(commitWon ? ImportState.COMMITTED : ImportState.DISCARDED, stateOf(id));
      assertEquals(commitWon ? before + 1 : before, committer.calls.size());
      assertEquals(0, ImportRowEntity.count("sessionId", id), "rows end with the session");
    }
  }

  @Test
  void theSweepRacingAReadOfTheSameOverdueSession_leavesItExpiredOnce() throws Exception {
    for (int round = 0; round < 6; round++) {
      UUID id =
          PrudentTest.seedImportSession(
              PrudentTest.ALICE, ImportState.PREVIEWED, Instant.now().minusSeconds(5));
      List<ImportWorkflow.SessionView> read = new ArrayList<>();
      int[] swept = new int[1];

      List<Throwable> outcomes =
          race(
              List.of(
                  () -> {
                    swept[0] = workflow.expireDue();
                    return null;
                  },
                  () -> {
                    synchronized (read) {
                      read.add(workflow.get(ALICE, id));
                    }
                    return null;
                  }));

      assertNull(outcomes.get(0), String.valueOf(outcomes.get(0)));
      assertNull(outcomes.get(1), String.valueOf(outcomes.get(1)));
      assertEquals(ImportState.EXPIRED, read.get(0).session().state);
      assertTrue(read.get(0).rows().isEmpty(), "a read never shows rows that should be gone");
      assertTrue(swept[0] <= 1, "the sweep cannot expire one session twice");
      assertEquals(ImportState.EXPIRED, stateOf(id));
      assertEquals(0, ImportRowEntity.count("sessionId", id));
      assertEquals(0, workflow.expireDue(), "nothing is left for a later sweep");
    }
  }
}
