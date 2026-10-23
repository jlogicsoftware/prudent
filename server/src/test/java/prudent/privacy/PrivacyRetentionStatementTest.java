package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.time.OffsetDateTime;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.account.AccountEntity;
import zen.identity.user.User;
import zen.identity.user.UserRetentionJob;
import zen.identity.user.UserRetentionService;
import zen.identity.user.UserRole;

/**
 * Pins the one sentence of {@code docs/privacy-policy.md} that is a statement about the
 * <em>absence</em> of behaviour: <strong>an account that goes dormant is not erased</strong>,
 * because the framework only anonymises an account after a warning was confirmed delivered, and
 * Prudent assembles no mail sender that could confirm one.
 *
 * <p>That is a fact about the deployment's wiring and not a choice anyone made, which is exactly
 * why it is asserted: the day Prudent observes {@code AccountDeletionWarning} and starts warning
 * people, this test goes red and sends the person who made the change to the policy paragraph that
 * has just become wrong — in the direction that would otherwise be silent, a retention promise
 * quietly stronger than the text published about it.
 *
 * <p>{@code PrudentRetentionCleanupTest} proves the cascade <em>if</em> the framework anonymises;
 * it seeds a delivered final warning directly, so it cannot say whether one is ever delivered. This
 * is the other half.
 */
@QuarkusTest
class PrivacyRetentionStatementTest {

  @Inject UserRetentionJob retention;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
  }

  @Test
  void aLongDormantAccountIsNotErasedBecauseNoWarningIsEverDelivered() {
    UUID dormant = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = new User();
              user.id = dormant;
              user.email = "dormant-" + dormant + "@example.test";
              user.role = UserRole.USER;
              user.createdAt = OffsetDateTime.now().minusYears(11);
              user.lastLoginAt = OffsetDateTime.now().minusYears(10);
              user.persist();
            });
    UUID account = PrudentTest.seedAccount(dormant.toString(), "Left alone", "PLN");

    // Twice, because the second cycle is where an account that had been stamped would advance.
    QuarkusTransaction.requiringNew().call(retention::runCycle);
    int anonymised = QuarkusTransaction.requiringNew().call(retention::runCycle);

    assertEquals(
        0,
        anonymised,
        "an account was anonymised: warnings are now delivered, so docs/privacy-policy.md's"
            + " 'How long it is kept' is wrong — update it, then update this test");
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = User.findById(dormant);
              assertFalse(UserRetentionService.isAnonymised(user));
              assertNull(
                  user.deletionWarningSentAt, "a warning was stamped delivered; see the message above");
              assertNotNull(AccountEntity.findById(account), "the dormant user's data was erased");
            });
  }
}
