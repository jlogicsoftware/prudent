package prudent.plan;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.LocalDate;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import prudent.error.PrudentException;
import prudent.proto.v1.OccurrenceStatus;

/**
 * The occurrence lifecycle (M2, jlogicsoftware/prudent#56, ADR-039). The transition table is
 * asserted <em>whole</em>, every pair, so adding a state or a move without deciding it here fails.
 */
class OccurrenceStateTest {

  @Test
  void theTransitionTableIsExactlyThis() {
    assertEquals(
        Set.of(OccurrenceState.SKIPPED, OccurrenceState.COMPLETED),
        OccurrenceState.PLANNED.successors());
    assertEquals(Set.of(OccurrenceState.PLANNED), OccurrenceState.SKIPPED.successors());
    assertEquals(Set.of(), OccurrenceState.COMPLETED.successors(), "completed is terminal");
  }

  @ParameterizedTest
  @EnumSource(OccurrenceState.class)
  void aStateIsNeverItsOwnSuccessor(OccurrenceState state) {
    assertFalse(state.canTransitionTo(state), "a repeat is refused, not quietly accepted");
  }

  @Test
  void transitionToMovesTheStateOrRefusesWithAConflict() {
    PlanOccurrenceEntity occurrence = new PlanOccurrenceEntity();
    assertEquals(OccurrenceState.PLANNED, occurrence.state, "a new occurrence is planned");

    occurrence.transitionTo(OccurrenceState.SKIPPED);
    assertEquals(OccurrenceState.SKIPPED, occurrence.state);

    PrudentException repeat =
        assertThrows(
            PrudentException.class, () -> occurrence.transitionTo(OccurrenceState.SKIPPED));
    assertEquals(PrudentException.CONFLICT, repeat.code());
    assertEquals(OccurrenceState.SKIPPED, occurrence.state, "a refused move changes nothing");

    occurrence.transitionTo(OccurrenceState.PLANNED);
    occurrence.transitionTo(OccurrenceState.COMPLETED);
    for (OccurrenceState target : EnumSet.allOf(OccurrenceState.class)) {
      assertThrows(PrudentException.class, () -> occurrence.transitionTo(target));
    }
    assertEquals(OccurrenceState.COMPLETED, occurrence.state);
  }

  @Test
  void overdueIsDerivedFromAPlannedStateAndAPastDateNeverStored() {
    LocalDate today = LocalDate.of(2026, 10, 15);
    LocalDate yesterday = today.minusDays(1);

    assertEquals(
        OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE,
        OccurrenceMapper.status(OccurrenceState.PLANNED, yesterday, today));
    assertEquals(
        OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
        OccurrenceMapper.status(OccurrenceState.PLANNED, today, today),
        "due today is not yet overdue");
    assertEquals(
        OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
        OccurrenceMapper.status(OccurrenceState.PLANNED, today.plusDays(1), today));
    // Resolved occurrences are never overdue, however old.
    assertEquals(
        OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED,
        OccurrenceMapper.status(OccurrenceState.SKIPPED, yesterday, today));
    assertEquals(
        OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED,
        OccurrenceMapper.status(OccurrenceState.COMPLETED, yesterday, today));
    assertTrue(
        Arrays.stream(OccurrenceState.values()).noneMatch(state -> state.name().equals("OVERDUE")),
        "OVERDUE must not become a stored state");
  }
}
