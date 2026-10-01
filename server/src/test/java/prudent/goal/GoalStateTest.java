package prudent.goal;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.EnumSet;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

/** The goal lifecycle table (M4, jlogicsoftware/prudent#38, ADR-049), with no framework around it. */
class GoalStateTest {

  @Test
  void anActiveGoalCanBeCompletedOrArchived() {
    assertEquals(EnumSet.of(GoalState.COMPLETED, GoalState.ARCHIVED), GoalState.ACTIVE.successors());
  }

  @Test
  void aCompletedGoalCanBeArchivedOrReactivatedButNotCompletedAgain() {
    assertEquals(EnumSet.of(GoalState.ACTIVE, GoalState.ARCHIVED), GoalState.COMPLETED.successors());
    assertFalse(GoalState.COMPLETED.canMoveTo(GoalState.COMPLETED));
  }

  @Test
  void anArchivedGoalCanOnlyBeReactivated() {
    assertEquals(Set.of(GoalState.ACTIVE), GoalState.ARCHIVED.successors());
    assertFalse(GoalState.ARCHIVED.canMoveTo(GoalState.COMPLETED));
  }

  @ParameterizedTest
  @EnumSource(GoalState.class)
  void staying_in_a_state_is_never_a_transition(GoalState state) {
    assertFalse(state.canMoveTo(state));
  }

  @ParameterizedTest
  @EnumSource(GoalState.class)
  void nothing_is_terminal_because_nothing_is_deleted(GoalState state) {
    assertTrue(!state.successors().isEmpty());
  }

  @Test
  void moneyGoesIntoAnActiveGoalOnly() {
    assertTrue(GoalState.ACTIVE.acceptsMoney());
    assertFalse(GoalState.COMPLETED.acceptsMoney());
    assertFalse(GoalState.ARCHIVED.acceptsMoney());
  }

  @Test
  void moneyComesOutOfAnyGoalThatIsNotArchived() {
    assertTrue(GoalState.ACTIVE.releasesMoney());
    assertTrue(GoalState.COMPLETED.releasesMoney());
    assertFalse(GoalState.ARCHIVED.releasesMoney());
  }
}
