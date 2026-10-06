package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.plan.Frequency;
import prudent.plan.OccurrenceState;
import prudent.plan.PlanClock;
import prudent.plan.PlanEntity;
import prudent.plan.PlanOccurrenceEntity;
import prudent.plan.RecurrenceRule;
import prudent.plan.ReminderSetting;
import prudent.proto.v1.DueReminder;
import prudent.proto.v1.ListRemindersResponse;
import prudent.proto.v1.OccurrenceStatus;
import zen.proto.v1.ZenError;

/**
 * The in-app reminder centre (M5, jlogicsoftware/prudent#68, ADR-055): which occurrences have a
 * reminder and in which state, the read flag, and that none of it is stored beyond that flag.
 *
 * <p>"Now" is pinned to {@value #NOW}, so a test can say which day it is — and, in the time-zone
 * test, which day it is <em>somewhere else</em>.
 */
@QuarkusTest
class ReminderResourceTest {

  private static final String NOW = "2026-10-15T10:00:00Z";
  private static final LocalDate TODAY = LocalDate.of(2026, 10, 15);
  private static final String REMINDERS = "/api/v1/reminders";

  private UUID walletId;
  private UUID rentId;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    walletId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    rentId = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
    QuarkusMock.installMockForType(
        new PlanClock() {
          @Override
          public Instant now() {
            return Instant.parse(NOW);
          }
        },
        PlanClock.class);
  }

  private static LocalDate d(String iso) {
    return LocalDate.parse(iso);
  }

  /** A plan on {@code rule} whose reminder is on with {@code leadDays} — unless it is {@code -1}. */
  private UUID plan(RecurrenceRule rule, int leadDays) {
    UUID id = PrudentTest.seedPlan(PrudentTest.ALICE, walletId, rentId, -100_00L, "PLN", rule);
    if (leadDays >= 0) {
      setReminder(id, new ReminderSetting(true, leadDays));
    }
    return id;
  }

  private static void setReminder(UUID planId, ReminderSetting setting) {
    QuarkusTransaction.requiringNew()
        .run(() -> PlanEntity.<PlanEntity>findById(planId).setReminder(setting));
  }

  /** Monthly on the 10th from August, Warsaw: 8/10, 9/10 and 10/10 are behind, 11/10 ahead. */
  private UUID monthlyOnTheTenth(int leadDays) {
    return plan(
        new RecurrenceRule(
            Frequency.MONTHLY, 1, d("2026-08-10"), ZoneId.of("Europe/Warsaw"), null, null),
        leadDays);
  }

  private static ListRemindersResponse list(String mode) throws Exception {
    Response response = PrudentTest.request(mode).when().get(REMINDERS).andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, ListRemindersResponse.newBuilder()).build();
  }

  private static List<String> dates(ListRemindersResponse response) {
    return response.getRemindersList().stream()
        .map(r -> r.getOccurrence().getOccurrenceDate())
        .toList();
  }

  private static Response post(String mode, String path) {
    return PrudentTest.request(mode).when().post(path).andReturn();
  }

  private static DueReminder reminder(String mode, Response response) throws Exception {
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, DueReminder.newBuilder()).build();
  }

  private static ZenError refused(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  private static Instant readAt(UUID occurrenceId) {
    return QuarkusTransaction.requiringNew()
        .call(() -> PlanOccurrenceEntity.<PlanOccurrenceEntity>findById(occurrenceId).reminderReadAt);
  }

  private static long rows() {
    return QuarkusTransaction.requiringNew().call(() -> PlanOccurrenceEntity.count());
  }

  // --- Which occurrences have a reminder -------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void aDueOccurrenceIsListedUnreadWithItsPlansFieldsAndLeadTime(String mode) throws Exception {
    UUID planId =
        plan(
            new RecurrenceRule(
                Frequency.ONCE, 1, d("2026-10-17"), ZoneId.of("Europe/Warsaw"), null, null),
            2);

    ListRemindersResponse reminders = list(mode);

    assertEquals(1, reminders.getRemindersCount());
    DueReminder due = reminders.getReminders(0);
    assertEquals("2026-10-17", due.getOccurrence().getOccurrenceDate());
    assertEquals(OccurrenceStatus.OCCURRENCE_STATUS_PLANNED, due.getOccurrence().getStatus());
    assertEquals(planId.toString(), due.getOccurrence().getPlanId());
    assertEquals("Seeded plan", due.getOccurrence().getTitle());
    assertEquals(-100_00L, due.getOccurrence().getAmountMinor());
    assertEquals("2026-10-15", due.getRemindOn(), "the occurrence's date less the 2-day lead time");
    assertEquals(2, due.getLeadDays());
    assertFalse(due.getRead());
    assertFalse(due.getOccurrence().getId().isBlank());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aPlanWhoseReminderIsOffHasNoRemindersEvenWhenOverdue() throws Exception {
    monthlyOnTheTenth(-1);

    assertEquals(0, list(PrudentTest.JSON).getRemindersCount());
    assertEquals(0, rows(), "an off plan is not even generated for");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aPlanWhoseReminderWasSwitchedOffStopsRemindingAndKeepsItsReadState() throws Exception {
    UUID planId = monthlyOnTheTenth(1);
    String overdueId = list(PrudentTest.JSON).getReminders(0).getOccurrence().getId();
    assertEquals(200, post(PrudentTest.JSON, REMINDERS + "/" + overdueId + "/read").statusCode());

    setReminder(planId, new ReminderSetting(false, 1));
    assertEquals(0, list(PrudentTest.JSON).getRemindersCount());
    setReminder(planId, new ReminderSetting(true, 1));

    DueReminder back = list(PrudentTest.JSON).getReminders(0);
    assertEquals(overdueId, back.getOccurrence().getId());
    assertTrue(back.getRead(), "switching a reminder off and on again forgets nothing");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void overdueOccurrencesLeadOldestFirstAndAreMarkedOverdue() throws Exception {
    monthlyOnTheTenth(1);

    ListRemindersResponse reminders = list(PrudentTest.JSON);

    // 11/10 is 26 days away: outside a one-day lead time.
    assertEquals(List.of("2026-08-10", "2026-09-10", "2026-10-10"), dates(reminders));
    assertTrue(
        reminders.getRemindersList().stream()
            .allMatch(r -> r.getOccurrence().getStatus() == OccurrenceStatus.OCCURRENCE_STATUS_OVERDUE));
    assertEquals(
        List.of("2026-08-09", "2026-09-09", "2026-10-09"),
        reminders.getRemindersList().stream().map(DueReminder::getRemindOn).toList());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aReminderFallsDueExactlyOnTheLeadDay() throws Exception {
    // Today is 10/15. A 7-day lead time reaches 10/22 and not 10/23.
    plan(
        new RecurrenceRule(Frequency.ONCE, 1, d("2026-10-22"), ZoneId.of("Europe/Warsaw"), null, null),
        7);
    plan(
        new RecurrenceRule(Frequency.ONCE, 1, d("2026-10-23"), ZoneId.of("Europe/Warsaw"), null, null),
        7);
    // A lead time of 0 is the day itself — and today is within it, tomorrow is not.
    plan(new RecurrenceRule(Frequency.ONCE, 1, TODAY, ZoneId.of("Europe/Warsaw"), null, null), 0);
    plan(
        new RecurrenceRule(Frequency.ONCE, 1, TODAY.plusDays(1), ZoneId.of("Europe/Warsaw"), null, null),
        0);

    assertEquals(List.of("2026-10-15", "2026-10-22"), dates(list(PrudentTest.JSON)));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void resolvedOccurrencesHaveNoReminder() throws Exception {
    UUID planId = monthlyOnTheTenth(1);
    PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2026-08-10"), OccurrenceState.COMPLETED);
    PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2026-09-10"), OccurrenceState.SKIPPED);

    assertEquals(List.of("2026-10-10"), dates(list(PrudentTest.JSON)));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aReminderFollowsItsPlansOwnCalendarDayNotTheServers() throws Exception {
    // 10:00Z on 10/15: it is already 10/16 in Kiritimati (UTC+14) and still 10/14 in Pago Pago
    // (UTC-11). An occurrence on 10/16 with no lead time is due in the first zone, not the second.
    UUID early =
        plan(
            new RecurrenceRule(
                Frequency.ONCE, 1, d("2026-10-16"), ZoneId.of("Pacific/Kiritimati"), null, null),
            0);
    plan(
        new RecurrenceRule(
            Frequency.ONCE, 1, d("2026-10-16"), ZoneId.of("Pacific/Pago_Pago"), null, null),
        0);

    ListRemindersResponse reminders = list(PrudentTest.JSON);

    assertEquals(1, reminders.getRemindersCount());
    assertEquals(early.toString(), reminders.getReminders(0).getOccurrence().getPlanId());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void listingIsIdempotent() throws Exception {
    monthlyOnTheTenth(3);

    ListRemindersResponse first = list(PrudentTest.JSON);
    long afterFirst = rows();
    ListRemindersResponse second = list(PrudentTest.JSON);

    assertEquals(first, second, "same reminders, same ids");
    assertEquals(afterFirst, rows(), "the second listing generates nothing new");
  }

  // --- Reading ---------------------------------------------------------------------------------

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void readAndUnreadFlipOneReminderAndNoOther(String mode) throws Exception {
    monthlyOnTheTenth(1);
    List<DueReminder> before = list(mode).getRemindersList();
    String id = before.get(0).getOccurrence().getId();

    DueReminder read = reminder(mode, post(mode, REMINDERS + "/" + id + "/read"));
    assertTrue(read.getRead());
    assertEquals(id, read.getOccurrence().getId());
    assertEquals(
        List.of(true, false, false),
        list(mode).getRemindersList().stream().map(DueReminder::getRead).toList());

    DueReminder unread = reminder(mode, post(mode, REMINDERS + "/" + id + "/unread"));
    assertFalse(unread.getRead());
    assertEquals(
        List.of(false, false, false),
        list(mode).getRemindersList().stream().map(DueReminder::getRead).toList());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void readingTwiceKeepsTheFirstTimeAndUnreadingUnreadIsHarmless() throws Exception {
    monthlyOnTheTenth(1);
    UUID id = UUID.fromString(list(PrudentTest.JSON).getReminders(0).getOccurrence().getId());

    assertNull(readAt(id));
    assertEquals(200, post(PrudentTest.JSON, REMINDERS + "/" + id + "/unread").statusCode());
    assertNull(readAt(id));
    assertEquals(200, post(PrudentTest.JSON, REMINDERS + "/" + id + "/read").statusCode());
    Instant first = readAt(id);
    assertEquals(Instant.parse(NOW), first);
    assertEquals(200, post(PrudentTest.JSON, REMINDERS + "/" + id + "/read").statusCode());
    assertEquals(first, readAt(id));
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void readAllMarksEveryCurrentReminderReadAndAnswersWithTheList(String mode) throws Exception {
    monthlyOnTheTenth(1);
    String one = list(mode).getReminders(1).getOccurrence().getId();
    assertEquals(200, post(mode, REMINDERS + "/" + one + "/read").statusCode());
    Instant firstTime = readAt(UUID.fromString(one));

    Response response = post(mode, REMINDERS + "/read-all");
    assertEquals(200, response.statusCode(), response.asString());
    ListRemindersResponse answered =
        PrudentTest.decode(mode, response, ListRemindersResponse.newBuilder()).build();

    assertEquals(3, answered.getRemindersCount());
    assertTrue(answered.getRemindersList().stream().allMatch(DueReminder::getRead));
    assertEquals(answered, list(mode));
    assertEquals(firstTime, readAt(UUID.fromString(one)), "an earlier reading is not overwritten");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void readAllWithNothingDueIsAnEmptyList() throws Exception {
    Response response = post(PrudentTest.JSON, REMINDERS + "/read-all");

    assertEquals(200, response.statusCode(), response.asString());
    assertEquals(
        0,
        PrudentTest.decode(PrudentTest.JSON, response, ListRemindersResponse.newBuilder())
            .build()
            .getRemindersCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void readAllLeavesOccurrencesWithoutAReminderUnmarked() throws Exception {
    UUID planId = monthlyOnTheTenth(1);
    UUID resolved =
        PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2026-12-10"), OccurrenceState.SKIPPED);
    UUID notYet = PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2027-01-10"));

    assertEquals(200, post(PrudentTest.JSON, REMINDERS + "/read-all").statusCode());

    assertNull(readAt(resolved));
    assertNull(readAt(notYet));
  }

  // --- Refusals --------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anOccurrenceWithNoReminderRightNowIsRefusedWithAConflictAndChangesNothing() throws Exception {
    UUID planId = monthlyOnTheTenth(1);
    UUID notYet = PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2026-12-10"));
    UUID skipped =
        PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2026-11-10"), OccurrenceState.SKIPPED);
    UUID offPlan =
        PrudentTest.seedPlan(
            PrudentTest.ALICE,
            walletId,
            rentId,
            -1L,
            "PLN",
            new RecurrenceRule(Frequency.ONCE, 1, d("2026-10-01"), ZoneId.of("Europe/Warsaw"), null, null));
    UUID offOccurrence = PrudentTest.seedOccurrence(PrudentTest.ALICE, offPlan, d("2026-10-01"));

    for (UUID id : List.of(notYet, skipped, offOccurrence)) {
      for (String action : new String[] {"read", "unread"}) {
        Response response = post(PrudentTest.JSON, REMINDERS + "/" + id + "/" + action);
        assertEquals("conflict", refused(response, 409).getCode(), action + " on " + id);
      }
      assertNull(readAt(id));
    }
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anUnknownOrMalformedIdIsNotFound() throws Exception {
    for (String id : new String[] {UUID.randomUUID().toString(), "not-a-uuid"}) {
      for (String action : new String[] {"read", "unread"}) {
        assertEquals(
            "not_found",
            refused(post(PrudentTest.JSON, REMINDERS + "/" + id + "/" + action), 404).getCode());
      }
    }
  }

  @Test
  @TestSecurity(user = PrudentTest.BOB)
  void aUserSeesAndTouchesOnlyTheirOwnReminders() throws Exception {
    UUID planId = monthlyOnTheTenth(1);
    // Alice's own overdue occurrence, which has a reminder — for Alice.
    UUID alicesOccurrence = PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, d("2026-10-10"));

    assertEquals(0, list(PrudentTest.JSON).getRemindersCount());
    assertEquals(
        "not_found",
        refused(post(PrudentTest.JSON, REMINDERS + "/" + alicesOccurrence + "/read"), 404).getCode());
    assertEquals(200, post(PrudentTest.JSON, REMINDERS + "/read-all").statusCode());
    assertNull(readAt(alicesOccurrence), "Bob's read-all touched nothing of Alice's");
  }

  @Test
  void anUnauthenticatedCallerIsRefused() {
    assertEquals(401, PrudentTest.request(PrudentTest.JSON).when().get(REMINDERS).statusCode());
    assertEquals(
        401, PrudentTest.request(PrudentTest.JSON).when().post(REMINDERS + "/read-all").statusCode());
  }

  // --- A reminder ends with its occurrence -----------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void skippingEndsAReminderAndRestoringBringsItBackWithItsReadState() throws Exception {
    monthlyOnTheTenth(1);
    String id = list(PrudentTest.JSON).getReminders(0).getOccurrence().getId();
    assertEquals(200, post(PrudentTest.JSON, REMINDERS + "/" + id + "/read").statusCode());

    assertEquals(200, post(PrudentTest.JSON, "/api/v1/occurrences/" + id + "/skip").statusCode());
    assertEquals(List.of("2026-09-10", "2026-10-10"), dates(list(PrudentTest.JSON)));

    assertEquals(200, post(PrudentTest.JSON, "/api/v1/occurrences/" + id + "/restore").statusCode());
    ListRemindersResponse back = list(PrudentTest.JSON);
    assertEquals(id, back.getReminders(0).getOccurrence().getId());
    assertTrue(back.getReminders(0).getRead());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void confirmingEndsAReminderAndMovesNoMoneyUntilThen() throws Exception {
    monthlyOnTheTenth(1);
    long recordsBefore = QuarkusTransaction.requiringNew().call(() -> prudent.record.RecordEntity.count());
    list(PrudentTest.JSON);
    assertEquals(
        recordsBefore,
        (long) QuarkusTransaction.requiringNew().call(() -> prudent.record.RecordEntity.count()),
        "listing and reading reminders create no record");

    String id = list(PrudentTest.JSON).getReminders(2).getOccurrence().getId();
    Response confirmed =
        PrudentTest.request(PrudentTest.JSON)
            .body("{}")
            .when()
            .post("/api/v1/occurrences/" + id + "/confirm")
            .andReturn();
    assertEquals(201, confirmed.statusCode(), confirmed.asString());

    assertEquals(List.of("2026-08-10", "2026-09-10"), dates(list(PrudentTest.JSON)));
  }
}
