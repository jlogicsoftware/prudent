package prudent.plan;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.error.PrudentException;
import prudent.proto.v1.Reminder;

/**
 * A plan's reminder setting and its validation (M5, jlogicsoftware/prudent#40, ADR-054), as a plain
 * unit test: the setting is a value, so none of this needs a database or a running application.
 */
class ReminderSettingTest {

  @Test
  void theDefaultIsOffWithAOneDayLeadTime() {
    assertFalse(ReminderSetting.DEFAULT.enabled());
    assertEquals(1, ReminderSetting.DEFAULT.leadDays());
  }

  @Test
  void anAbsentReminderIsTheDefaultRatherThanAnError() {
    assertEquals(
        ReminderSetting.DEFAULT, ReminderSetting.fromProto(Reminder.getDefaultInstance(), false));
  }

  @ParameterizedTest
  @ValueSource(ints = {0, 1, 2, 3, 7})
  void everySupportedLeadTimeIsAccepted(int days) {
    ReminderSetting setting =
        ReminderSetting.fromProto(
            Reminder.newBuilder().setEnabled(true).setLeadDays(days).build(), true);

    assertTrue(setting.enabled());
    assertEquals(days, setting.leadDays());
  }

  @Test
  void zeroDaysIsARealLeadTimeNotAnOmittedOne() {
    // proto3 decodes an omitted number to 0; presence is what tells "the day itself" from "unset".
    ReminderSetting explicit =
        ReminderSetting.fromProto(Reminder.newBuilder().setEnabled(true).setLeadDays(0).build(), true);
    ReminderSetting omitted =
        ReminderSetting.fromProto(Reminder.newBuilder().setEnabled(true).build(), true);

    assertEquals(0, explicit.leadDays());
    assertEquals(ReminderSetting.DEFAULT_LEAD_DAYS, omitted.leadDays());
  }

  @Test
  void aDisabledReminderKeepsItsLeadTime() {
    ReminderSetting setting =
        ReminderSetting.fromProto(Reminder.newBuilder().setEnabled(false).setLeadDays(7).build(), true);

    assertFalse(setting.enabled());
    assertEquals(7, setting.leadDays());
  }

  @ParameterizedTest
  @ValueSource(ints = {4, 5, 6, 8, 14, 30, 365, 366, Integer.MAX_VALUE})
  void anUnsupportedLeadTimeIsRefusedNotRounded(int days) {
    Reminder reminder = Reminder.newBuilder().setEnabled(true).setLeadDays(days).build();

    refused(() -> ReminderSetting.fromProto(reminder, true));
  }

  @Test
  void aLeadTimeBeyondTheSignedRangeIsRefusedNotWrapped() {
    // 0xFFFFFFFF as a uint32 is -1 when read as an int; it must not slip through as "negative".
    Reminder reminder = Reminder.newBuilder().setLeadDays(-1).build();

    refused(() -> ReminderSetting.fromProto(reminder, true));
  }

  @Test
  void aNegativeLeadTimeCannotBeConstructed() {
    refused(() -> new ReminderSetting(true, -1));
  }

  @Test
  void theRefusalNamesTheSupportedLeadTimes() {
    PrudentException refused =
        assertThrows(PrudentException.class, () -> new ReminderSetting(true, 4));

    assertTrue(refused.getMessage().contains("[0, 1, 2, 3, 7]"), refused.getMessage());
  }

  private static void refused(org.junit.jupiter.api.function.Executable executable) {
    PrudentException refused = assertThrows(PrudentException.class, executable);
    assertEquals(PrudentException.INVALID, refused.code());
  }
}
