package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.EnumSet;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import prudent.error.PrudentException;

/** The session state machine (ADR-089), asserted as a whole graph so an added edge is noticed. */
class ImportStateTest {

  @Test
  void theGraphIsExactlyTheDocumentedOne() {
    assertEquals(
        EnumSet.of(ImportState.PREVIEWED, ImportState.DISCARDED, ImportState.EXPIRED),
        ImportState.PARSED.successors());
    assertEquals(
        EnumSet.of(
            ImportState.PREVIEWED,
            ImportState.COMMITTED,
            ImportState.DISCARDED,
            ImportState.EXPIRED),
        ImportState.PREVIEWED.successors());
    for (ImportState terminal :
        EnumSet.of(ImportState.COMMITTED, ImportState.DISCARDED, ImportState.EXPIRED)) {
      assertTrue(terminal.successors().isEmpty(), terminal + " must be terminal");
    }
  }

  @Test
  void commitIsReachableOnlyThroughPreview() {
    assertFalse(ImportState.PARSED.canMoveTo(ImportState.COMMITTED));
    assertTrue(ImportState.PREVIEWED.canMoveTo(ImportState.COMMITTED));
    for (ImportState state : ImportState.values()) {
      assertFalse(state.canMoveTo(ImportState.PARSED), "nothing moves back into PARSED");
      // The one edge onto itself is a repeated preview; every other state staying put is refused.
      assertEquals(state == ImportState.PREVIEWED, state.canMoveTo(state), state.toString());
    }
  }

  @Test
  void onlyOpenSessionsHoldRows() {
    assertTrue(ImportState.PARSED.holdsRows());
    assertTrue(ImportState.PREVIEWED.holdsRows());
    assertFalse(ImportState.COMMITTED.holdsRows());
    assertFalse(ImportState.DISCARDED.holdsRows());
    assertFalse(ImportState.EXPIRED.holdsRows());
  }

  @Test
  void anEntityRefusesAnEdgeThatIsNotInTheGraphWithAConflict() {
    ImportSessionEntity session = new ImportSessionEntity();
    session.id = UUID.randomUUID();
    session.state = ImportState.PARSED;

    PrudentException refused =
        assertThrows(
            PrudentException.class, () -> session.transitionTo(ImportState.COMMITTED, Instant.now()));
    assertEquals(PrudentException.CONFLICT, refused.code());
    assertEquals(ImportState.PARSED, session.state, "a refused move changes nothing");

    session.transitionTo(ImportState.PREVIEWED, Instant.EPOCH);
    assertEquals(ImportState.PREVIEWED, session.state);
    assertEquals(Instant.EPOCH, session.stateChangedAt);
  }
}
