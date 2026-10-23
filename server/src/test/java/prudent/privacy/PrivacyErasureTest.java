package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.PrudentTest;
import prudent.account.AccountEntity;
import prudent.privacy.PrivacySeed.Seeded;
import prudent.proto.v1.EraseAccountRequest;
import prudent.record.RecordEntity;
import zen.identity.user.User;
import zen.identity.user.UserRetentionService;

/**
 * {@code POST /api/v1/privacy/erase}: the confirmation that stands between a stray request and a
 * person's whole financial history, what the erasure removes, what it deliberately leaves, and that
 * it leaves every other user alone.
 *
 * <p>That <em>every table</em> is emptied — including a table added next year — is not asserted
 * here; {@link PrivacyCoverageTest} derives it from the database's own schema.
 */
@QuarkusTest
class PrivacyErasureTest {

  private Seeded alice;
  private Seeded bob;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    alice = PrivacySeed.everythingFor(PrudentTest.ALICE);
    bob = PrivacySeed.everythingFor(PrudentTest.BOB);
  }

  private Response erase(String mode, String confirmEmail) throws Exception {
    return PrudentTest.body(
            PrudentTest.request(mode),
            mode,
            EraseAccountRequest.newBuilder().setConfirmEmail(confirmEmail).build())
        .when()
        .post("/api/v1/privacy/erase")
        .andReturn();
  }

  private long aliceRecords() {
    return QuarkusTransaction.requiringNew()
        .call(() -> RecordEntity.count("userId", UUID.fromString(PrudentTest.ALICE)));
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void erasesTheUsersDataWhenTheirAddressIsConfirmed(String mode) throws Exception {
    // Case-insensitive, and trimmed: an address typed on a phone keyboard arrives capitalised.
    Response response = erase(mode, "  Alice@Example.COM ");

    assertEquals(204, response.statusCode(), response.asString());
    assertEquals(0, aliceRecords());
    QuarkusTransaction.requiringNew()
        .run(() -> assertNull(AccountEntity.findById(alice.account())));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void leavesEveryOtherUsersDataAlone() throws Exception {
    assertEquals(204, erase(PrudentTest.JSON, "alice@example.com").statusCode());

    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              assertNotNull(AccountEntity.findById(bob.account()), "Bob's account was erased");
              assertNotNull(RecordEntity.findById(bob.record()), "Bob's record was erased");
              User bobsProfile = User.findById(UUID.fromString(PrudentTest.BOB));
              assertEquals("bob@example.com", bobsProfile.email);
            });
  }

  /**
   * The profile row is kept, as the framework keeps it for dormancy, and made to read exactly as
   * the framework's own anonymisation does — asserted by asking the framework, not by comparing
   * against a literal of ours, which is the tautology ADR-022 retired.
   */
  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anonymisesTheProfileTheWayTheFrameworkDoes() throws Exception {
    assertEquals(204, erase(PrudentTest.JSON, "alice@example.com").statusCode());

    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User profile = User.findById(UUID.fromString(PrudentTest.ALICE));
              assertNotNull(profile, "the profile row is kept, as it is for dormancy");
              assertTrue(
                  UserRetentionService.isAnonymised(profile),
                  "the framework does not recognise this row as anonymised, so the two erasure"
                      + " routes now disagree — compare with UserRetentionService."
                      + "anonymiseExpiredAccounts()");
              assertFalse(profile.email.contains("alice"), "the address survived");
              assertNull(profile.displayName);
              assertFalse(profile.emailVerified);
            });
  }

  @ParameterizedTest
  @ValueSource(strings = {"", "   ", "bob@example.com", "alice@example.org"})
  @TestSecurity(user = PrudentTest.ALICE)
  void refusesWithoutTheRightAddressAndDeletesNothing(String wrong) throws Exception {
    long before = aliceRecords();

    Response response = erase(PrudentTest.JSON, wrong);

    assertEquals(400, response.statusCode(), response.asString());
    assertEquals(before, aliceRecords(), "a refused erasure deleted data");
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              assertNotNull(AccountEntity.findById(alice.account()));
              User profile = User.findById(UUID.fromString(PrudentTest.ALICE));
              assertEquals("alice@example.com", profile.email);
            });
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aSecondErasureIsRefusedBecauseTheAddressNoLongerMatches() throws Exception {
    assertEquals(204, erase(PrudentTest.JSON, "alice@example.com").statusCode());

    // Not a failure to be fixed: the first call anonymised the address, so "confirm the address"
    // has nothing left to match. What matters is that it deleted nothing and did not 500.
    assertEquals(400, erase(PrudentTest.JSON, "alice@example.com").statusCode());
  }

  @Test
  void anAnonymousCallerIsRefused() throws Exception {
    assertEquals(401, erase(PrudentTest.JSON, "alice@example.com").statusCode());
    assertTrue(aliceRecords() > 0);
  }
}
