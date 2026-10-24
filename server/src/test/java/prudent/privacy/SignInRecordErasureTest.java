package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.protobuf.util.JsonFormat;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.logging.Handler;
import java.util.logging.LogRecord;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.PrudentTest;
import prudent.privacy.FakeGoTrueAdmin.Call;
import prudent.proto.v1.EraseAccountRequest;
import prudent.record.RecordEntity;
import zen.identity.user.User;
import zen.identity.user.UserRole;
import zen.proto.v1.ZenError;

/**
 * Both erasure routes delete the person's sign-in record at Supabase (ADR-075): what they send,
 * that "already gone" is success, and that any other answer is a 503 with <em>nothing</em> erased —
 * the rows, the profile and the record all as they were.
 *
 * <p>Supabase is played by {@link FakeGoTrueAdmin}. That the real GoTrue accepts this exact call is
 * proven against the local stack by {@code client/integration_test/e2e_test.dart}.
 */
@QuarkusTest
class SignInRecordErasureTest {

  /** {@code %test.prudent.supabase.service-role-key}. */
  private static final String KEY = "test-service-role-key";

  private final CopyOnWriteArrayList<String> logged = new CopyOnWriteArrayList<>();
  private Handler capture;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    FakeGoTrueAdmin.reset();
    PrivacySeed.everythingFor(PrudentTest.ALICE);
    PrivacySeed.everythingFor(PrudentTest.BOB);
    capture =
        new Handler() {
          @Override
          public void publish(LogRecord record) {
            logged.add(record.getMessage() + " " + Arrays.toString(record.getParameters()));
          }

          @Override
          public void flush() {}

          @Override
          public void close() {}
        };
    java.util.logging.Logger.getLogger("").addHandler(capture);
  }

  @AfterEach
  void release() {
    java.util.logging.Logger.getLogger("").removeHandler(capture);
    FakeGoTrueAdmin.reset();
  }

  private Response eraseSelf(String mode) throws Exception {
    return PrudentTest.body(
            PrudentTest.request(mode),
            mode,
            EraseAccountRequest.newBuilder().setConfirmEmail("alice@example.com").build())
        .when()
        .post("/api/v1/privacy/erase")
        .andReturn();
  }

  private Response eraseByOperator(String userId) {
    return PrudentTest.request(PrudentTest.JSON)
        .when()
        .post("/api/v1/admin/privacy/users/" + userId + "/erase")
        .andReturn();
  }

  private static long records(String userId) {
    return QuarkusTransaction.requiringNew()
        .call(() -> RecordEntity.count("userId", UUID.fromString(userId)));
  }

  private static String email(String userId) {
    return QuarkusTransaction.requiringNew()
        .call(() -> ((User) User.findById(UUID.fromString(userId))).email);
  }

  private static ZenError error(Response response) throws Exception {
    ZenError.Builder b = ZenError.newBuilder();
    JsonFormat.parser().merge(response.getBody().asString(), b);
    return b.build();
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void aPersonsOwnErasureDeletesTheirSignInRecordWithTheServiceRoleKey(String mode)
      throws Exception {
    assertEquals(204, eraseSelf(mode).statusCode());

    assertEquals(List.of(new Call(PrudentTest.ALICE, KEY, "Bearer " + KEY)), FakeGoTrueAdmin.calls());
    assertEquals(0, records(PrudentTest.ALICE));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRecordThatIsAlreadyGoneIsNotAnError() throws Exception {
    // Deleted in the dashboard first, as the operator was told to do before ADR-075.
    FakeGoTrueAdmin.answer(404);

    assertEquals(204, eraseSelf(PrudentTest.JSON).statusCode());
    assertEquals(0, records(PrudentTest.ALICE));
  }

  /**
   * 401/403 is a wrong or anon key, 500/503 a Supabase that is down. All four leave the person as
   * they were: the transaction is rolled back, so the address they would confirm a retry with is
   * still theirs.
   */
  @ParameterizedTest
  @ValueSource(ints = {401, 403, 500, 503})
  @TestSecurity(user = PrudentTest.ALICE)
  void anyOtherAnswerIsReportedAndErasesNothing(int status) throws Exception {
    long before = records(PrudentTest.ALICE);
    FakeGoTrueAdmin.answer(status);

    Response response = eraseSelf(PrudentTest.JSON);

    assertEquals(503, response.statusCode(), response.asString());
    ZenError error = error(response);
    assertEquals("unavailable", error.getCode());
    assertTrue(error.getMessage().contains("nothing was erased"), error.getMessage());
    assertEquals(before, records(PrudentTest.ALICE), "rows were deleted although the call failed");
    assertEquals("alice@example.com", email(PrudentTest.ALICE), "the profile was anonymised");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRetryAfterAFailureSucceeds() throws Exception {
    FakeGoTrueAdmin.answer(503);
    assertEquals(503, eraseSelf(PrudentTest.JSON).statusCode());

    FakeGoTrueAdmin.answer(200);
    assertEquals(204, eraseSelf(PrudentTest.JSON).statusCode());
    assertEquals(0, records(PrudentTest.ALICE));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRefusedConfirmationNeverReachesSupabase() throws Exception {
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                EraseAccountRequest.newBuilder().setConfirmEmail("bob@example.com").build())
            .when()
            .post("/api/v1/privacy/erase")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertEquals(List.of(), FakeGoTrueAdmin.calls());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theLogNamesThePersonAndTheStatusAndNeverTheKey() throws Exception {
    FakeGoTrueAdmin.answer(500);
    assertEquals(503, eraseSelf(PrudentTest.JSON).statusCode());

    assertTrue(
        logged.stream().anyMatch(l -> l.contains(PrudentTest.ALICE) && l.contains("500")),
        "no line names the person and Supabase's status: " + logged);
    assertFalse(logged.stream().anyMatch(l -> l.contains(KEY)), "the key reached a log line");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE, roles = UserRole.Names.ADMIN)
  void anOperatorErasureDeletesTheSignInRecordToo() {
    assertEquals(204, eraseByOperator(PrudentTest.BOB).statusCode());

    assertEquals(List.of(new Call(PrudentTest.BOB, KEY, "Bearer " + KEY)), FakeGoTrueAdmin.calls());
    assertEquals(0, records(PrudentTest.BOB));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE, roles = UserRole.Names.ADMIN)
  void anOperatorErasureThatSupabaseRefusesErasesNothing() {
    long before = records(PrudentTest.BOB);
    FakeGoTrueAdmin.answer(500);

    assertEquals(503, eraseByOperator(PrudentTest.BOB).statusCode());
    assertEquals(before, records(PrudentTest.BOB));
    assertEquals("bob@example.com", email(PrudentTest.BOB));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE, roles = UserRole.Names.ADMIN)
  void anOperatorErasureOfAStrangerOrThemselvesNeverReachesSupabase() {
    assertEquals(404, eraseByOperator(UUID.randomUUID().toString()).statusCode());
    assertEquals(400, eraseByOperator(PrudentTest.ALICE).statusCode());

    assertEquals(List.of(), FakeGoTrueAdmin.calls());
    QuarkusTransaction.requiringNew()
        .run(() -> assertNotNull(User.findById(UUID.fromString(PrudentTest.ALICE))));
  }
}
