package prudent.plan;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.error.PrudentException;

/**
 * Occurrence generation (M2, jlogicsoftware/prudent#55, ADR-038): a bounded window yields the same
 * unique occurrences however often, and however concurrently, it is run.
 *
 * <p>Assertions read the rows back from the table, not the generator's return value — a generator
 * that reported the right count while writing duplicates would otherwise pass.
 */
@QuarkusTest
class OccurrenceGeneratorTest {

  @Inject OccurrenceGenerator generator;

  private UUID accountId;
  private UUID categoryId;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
  }

  private UUID plan(RecurrenceRule rule) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              PlanEntity entity = new PlanEntity();
              entity.id = id;
              entity.userId = UUID.fromString(PrudentTest.ALICE);
              entity.title = "Rent";
              entity.amountMinor = -100L;
              entity.currency = "PLN";
              entity.accountId = accountId;
              entity.categoryId = categoryId;
              entity.setRule(rule);
              entity.persist();
            });
    return id;
  }

  private static RecurrenceRule rule(
      Frequency frequency, int interval, LocalDate start, LocalDate until, Integer count) {
    return new RecurrenceRule(frequency, interval, start, ZoneId.of("Europe/Warsaw"), until, count);
  }

  private OccurrenceGenerator.Result generate(UUID planId, LocalDate from, LocalDate to) {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                generator.generate(
                    PlanEntity.<PlanEntity>findById(planId), from, to));
  }

  private List<LocalDate> stored(UUID planId) {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                PlanOccurrenceEntity.listForPlan(UUID.fromString(PrudentTest.ALICE), planId)
                    .stream()
                    .map(o -> o.occurrenceDate)
                    .toList());
  }

  private static LocalDate d(String iso) {
    return LocalDate.parse(iso);
  }

  @Test
  void aWindowProducesExactlyTheRulesDates() {
    UUID planId = plan(rule(Frequency.MONTHLY, 1, d("2026-01-31"), null, null));

    OccurrenceGenerator.Result result = generate(planId, d("2026-01-01"), d("2026-04-30"));

    // Computed from the anchor: the month-end recovers after February instead of drifting to 28.
    assertEquals(
        List.of(d("2026-01-31"), d("2026-02-28"), d("2026-03-31"), d("2026-04-30")),
        stored(planId));
    assertEquals(4, result.inWindow());
    assertEquals(4, result.created());
  }

  @Test
  void runningTheSameWindowAgainCreatesNothingAndChangesNothing() {
    UUID planId = plan(rule(Frequency.WEEKLY, 1, d("2026-10-05"), null, null));

    OccurrenceGenerator.Result first = generate(planId, d("2026-10-01"), d("2026-12-31"));
    List<LocalDate> afterFirst = stored(planId);
    OccurrenceGenerator.Result second = generate(planId, d("2026-10-01"), d("2026-12-31"));
    OccurrenceGenerator.Result third = generate(planId, d("2026-10-01"), d("2026-12-31"));

    assertEquals(13, first.created());
    assertEquals(13, second.inWindow(), "the window still holds them");
    assertEquals(0, second.created());
    assertEquals(0, third.created());
    assertEquals(afterFirst, stored(planId));
    assertEquals(
        13L,
        QuarkusTransaction.requiringNew().call(() -> PlanOccurrenceEntity.count()),
        "no duplicate rows");
  }

  @Test
  void overlappingWindowsAgreeOnTheOverlap() {
    UUID planId = plan(rule(Frequency.DAILY, 1, d("2026-10-01"), null, null));

    generate(planId, d("2026-10-01"), d("2026-10-10"));
    OccurrenceGenerator.Result overlapping = generate(planId, d("2026-10-06"), d("2026-10-15"));

    assertEquals(10, overlapping.inWindow());
    assertEquals(5, overlapping.created(), "only 11-15 were new");
    List<LocalDate> expected = new ArrayList<>();
    for (int day = 1; day <= 15; day++) {
      expected.add(LocalDate.of(2026, 10, day));
    }
    assertEquals(expected, stored(planId));
  }

  @Test
  void concurrentRunsOverTheSameWindowCreateEachOccurrenceOnce() throws Exception {
    UUID planId = plan(rule(Frequency.DAILY, 1, d("2026-10-01"), null, null));
    int runners = 8;
    ExecutorService pool = Executors.newFixedThreadPool(runners);
    CountDownLatch ready = new CountDownLatch(runners);
    CountDownLatch go = new CountDownLatch(1);
    try {
      List<Future<OccurrenceGenerator.Result>> runs = new ArrayList<>();
      for (int i = 0; i < runners; i++) {
        runs.add(
            pool.submit(
                () -> {
                  ready.countDown();
                  go.await();
                  return generate(planId, d("2026-10-01"), d("2026-12-31"));
                }));
      }
      ready.await();
      go.countDown();

      int created = 0;
      for (Future<OccurrenceGenerator.Result> run : runs) {
        OccurrenceGenerator.Result result = run.get();
        assertEquals(92, result.inWindow());
        created += result.created();
      }
      // Each date was inserted by exactly one of the runners, whichever won it.
      assertEquals(92, created);
    } finally {
      pool.shutdownNow();
    }

    List<LocalDate> rows = stored(planId);
    assertEquals(92, rows.size());
    assertEquals(92, rows.stream().distinct().count(), "no date may appear twice");
  }

  @Test
  void concurrentRunsOverOverlappingWindowsNeitherDeadlockNorDuplicate() throws Exception {
    UUID planId = plan(rule(Frequency.DAILY, 1, d("2026-10-01"), null, null));
    ExecutorService pool = Executors.newFixedThreadPool(4);
    try {
      List<Future<OccurrenceGenerator.Result>> runs = new ArrayList<>();
      for (int i = 0; i < 4; i++) {
        LocalDate from = d("2026-10-01").plusDays(i * 10L);
        runs.add(pool.submit(() -> generate(planId, from, from.plusDays(39))));
      }
      for (Future<OccurrenceGenerator.Result> run : runs) {
        run.get();
      }
    } finally {
      pool.shutdownNow();
    }

    List<LocalDate> rows = stored(planId);
    // 1 Oct through 9 Nov (the last window starts on 31 Oct and runs 40 days).
    assertEquals(70, rows.size());
    assertEquals(70, rows.stream().distinct().count());
  }

  @Test
  void aWindowOutsideTheRulesLifeIsEmpty() {
    UUID planId = plan(rule(Frequency.DAILY, 1, d("2026-10-01"), d("2026-10-05"), null));

    assertEquals(0, generate(planId, d("2026-09-01"), d("2026-09-30")).inWindow());
    assertEquals(0, generate(planId, d("2026-10-06"), d("2026-12-31")).inWindow());
    assertEquals(List.of(), stored(planId));
  }

  @Test
  void anOccurrenceCountBoundsTheRuleEvenInAWiderWindow() {
    UUID planId = plan(rule(Frequency.MONTHLY, 1, d("2026-10-15"), null, 3));

    OccurrenceGenerator.Result result = generate(planId, d("2026-01-01"), d("2030-12-31"));

    assertEquals(
        List.of(d("2026-10-15"), d("2026-11-15"), d("2026-12-15")), stored(planId));
    assertEquals(3, result.created());
  }

  @Test
  void aOneOffPlanHasExactlyOneOccurrenceHoweverOftenAskedFor() {
    UUID planId = plan(rule(Frequency.ONCE, 1, d("2026-10-15"), null, null));

    generate(planId, d("2026-10-01"), d("2026-10-31"));
    generate(planId, d("2026-10-15"), d("2026-10-15"));
    generate(planId, d("2026-01-01"), d("2027-01-01"));

    assertEquals(List.of(d("2026-10-15")), stored(planId));
  }

  @Test
  void aWindowIsBoundedAndOrdered() {
    UUID planId = plan(rule(Frequency.DAILY, 1, d("2026-10-01"), null, null));
    LocalDate from = d("2026-10-01");

    PrudentException inverted =
        assertThrows(PrudentException.class, () -> generate(planId, from, from.minusDays(1)));
    assertEquals(PrudentException.INVALID, inverted.code());
    // Exactly the limit is accepted; one day more is not.
    assertEquals(
        OccurrenceGenerator.MAX_WINDOW_DAYS,
        generate(planId, from, from.plusDays(OccurrenceGenerator.MAX_WINDOW_DAYS - 1)).created());
    PrudentException tooWide =
        assertThrows(
            PrudentException.class,
            () -> generate(planId, from, from.plusDays(OccurrenceGenerator.MAX_WINDOW_DAYS)));
    assertEquals(PrudentException.INVALID, tooWide.code());
    assertThrows(PrudentException.class, () -> generate(planId, null, from));
  }

  @Test
  void aFailureLeavesNoPartialWindowBehind() {
    UUID planId = plan(rule(Frequency.DAILY, 1, d("2026-10-01"), null, null));

    assertThrows(
        RuntimeException.class,
        () ->
            QuarkusTransaction.requiringNew()
                .run(
                    () -> {
                      generator.generate(
                          PlanEntity.<PlanEntity>findById(planId), d("2026-10-01"), d("2026-10-10"));
                      throw new IllegalStateException("caller failed after generating");
                    }));

    assertEquals(List.of(), stored(planId), "generation joins the caller's transaction");
  }

  // --- Reconciling after a rule change (jlogicsoftware/prudent#56, ADR-039) --------------------

  private void setState(UUID planId, LocalDate date, OccurrenceState state) {
    QuarkusTransaction.requiringNew()
        .run(
            () ->
                PlanOccurrenceEntity.<PlanOccurrenceEntity>find(
                        "planId = ?1 and occurrenceDate = ?2", planId, date)
                    .firstResult()
                    .state = state);
  }

  @Test
  void dropStaleRemovesOnlyPlannedOccurrencesTheCurrentRuleNoLongerProduces() {
    UUID planId = plan(rule(Frequency.DAILY, 1, d("2026-10-01"), null, null));
    generate(planId, d("2026-10-01"), d("2026-10-06"));
    setState(planId, d("2026-10-02"), OccurrenceState.SKIPPED);
    setState(planId, d("2026-10-04"), OccurrenceState.COMPLETED);

    // Every other day from the same anchor: 1, 3, 5. So 2, 4 and 6 are no longer produced.
    long dropped =
        QuarkusTransaction.requiringNew()
            .call(
                () -> {
                  PlanEntity plan = PlanEntity.findById(planId);
                  plan.setRule(rule(Frequency.DAILY, 2, d("2026-10-01"), null, null));
                  return generator.dropStale(plan);
                });

    assertEquals(1, dropped, "only 6 is planned and stale; 2 was skipped and 4 completed");
    assertEquals(
        List.of(d("2026-10-01"), d("2026-10-02"), d("2026-10-03"), d("2026-10-04"), d("2026-10-05")),
        stored(planId));
  }

  @Test
  void dropStaleIsANoOpWhenNothingIsStaleAndWhenNothingIsGenerated() {
    UUID planId = plan(rule(Frequency.DAILY, 1, d("2026-10-01"), null, null));
    assertEquals(0, dropStale(planId), "no occurrences at all");

    generate(planId, d("2026-10-01"), d("2026-10-05"));

    assertEquals(0, dropStale(planId), "the rule is unchanged");
    assertEquals(5, stored(planId).size());
  }

  private long dropStale(UUID planId) {
    return QuarkusTransaction.requiringNew()
        .call(() -> generator.dropStale(PlanEntity.<PlanEntity>findById(planId)));
  }

  @Test
  void generationNeverTouchesTheStateOfWhatAlreadyExists() {
    UUID planId = plan(rule(Frequency.DAILY, 1, d("2026-10-01"), null, null));
    generate(planId, d("2026-10-01"), d("2026-10-03"));
    setState(planId, d("2026-10-02"), OccurrenceState.SKIPPED);

    OccurrenceGenerator.Result again = generate(planId, d("2026-10-01"), d("2026-10-05"));

    assertEquals(2, again.created(), "only 4 and 5 are new");
    OccurrenceState state =
        QuarkusTransaction.requiringNew()
            .call(
                () ->
                    PlanOccurrenceEntity.<PlanOccurrenceEntity>find(
                            "planId = ?1 and occurrenceDate = ?2", planId, d("2026-10-02"))
                        .firstResult()
                        .state);
    assertEquals(OccurrenceState.SKIPPED, state, "regenerating a window does not reopen a skip");
  }
}
