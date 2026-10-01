package prudent.goal;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import prudent.proto.v1.GoalAllocationKind;

/** Which goals an envelope entry names, by kind (M4, jlogicsoftware/prudent#64, ADR-050). */
class AllocationKindTest {

  @Test
  void anAllocationHasOnlyATarget() {
    assertFalse(AllocationKind.ALLOCATE.hasSource());
    assertTrue(AllocationKind.ALLOCATE.hasTarget());
  }

  @Test
  void aWithdrawalHasOnlyASource() {
    assertTrue(AllocationKind.WITHDRAW.hasSource());
    assertFalse(AllocationKind.WITHDRAW.hasTarget());
  }

  @Test
  void aMoveHasBoth() {
    assertTrue(AllocationKind.MOVE.hasSource());
    assertTrue(AllocationKind.MOVE.hasTarget());
  }

  @ParameterizedTest
  @EnumSource(AllocationKind.class)
  void everyKindIsOnTheWireAndBack(AllocationKind kind) {
    GoalAllocationKind wire = GoalAllocationMapper.toWire(kind);

    assertEquals(kind, GoalAllocationResource.parseKind(wire));
  }
}
