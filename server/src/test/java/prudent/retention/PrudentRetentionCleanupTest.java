package prudent.retention;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.time.OffsetDateTime;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.account.AccountEntity;
import prudent.category.CategoryEntity;
import prudent.record.RecordEntity;
import prudent.settings.SettingsEntity;
import zen.identity.user.User;
import zen.identity.user.UserRetentionService;
import zen.identity.user.UserRole;

/**
 * Proves the half of "delete a user, delete their financial records" that the framework cannot do
 * for Prudent — and proves it <strong>against the framework's real anonymisation path</strong>,
 * which is the entire point of this file.
 *
 * <p><strong>What the previous version of this test could not catch.</strong> It fabricated a
 * {@code users} row carrying the anonymisation marker, spelled out as a literal in the test, and
 * then asserted that a job matching that same literal swept it. Both sides were Prudent's own
 * assumption about jZen, so the test asserted a tautology: had the framework changed the marker,
 * the sweep would have stopped matching real anonymised users, the GDPR cascade would have
 * silently stopped, and this test would have stayed green. A test that cannot fail when the thing
 * it depends on changes is not evidence about that thing.
 *
 * <p>So nothing here fabricates an anonymised user. The test makes a genuinely expired account —
 * final warning delivered long ago, not premium, not already anonymised, which is exactly what
 * {@code UserRetentionService.anonymiseExpiredAccounts()} selects on — and calls the framework's
 * own service. If jZen changes how anonymisation works, when it fires, or what it fires, this
 * goes red on the next {@code JZEN_REF} bump, which is the only moment it can matter.
 */
@QuarkusTest
class PrudentRetentionCleanupTest {

  @Inject UserRetentionService retention;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
  }

  /**
   * An account whose final warning was delivered ten years ago is expired under any configured
   * offset, so the test does not have to know {@code zen.identity.retention.anonymise-offset-days}
   * — a value it would otherwise duplicate, which is the mistake this file exists to stop making.
   */
  private UUID seedExpiredAccount() {
    UUID userId = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User dormant = new User();
              dormant.id = userId;
              dormant.email = "dormant-" + userId + "@example.test";
              dormant.role = UserRole.USER;
              dormant.createdAt = OffsetDateTime.now().minusYears(11);
              dormant.lastLoginAt = OffsetDateTime.now().minusYears(10);
              dormant.deletionWarningSentAt = OffsetDateTime.now().minusYears(10);
              dormant.finalWarningSentAt = OffsetDateTime.now().minusYears(10);
              dormant.isPremium = false;
              dormant.persist();
            });
    return userId;
  }

  @Test
  void theFrameworkAnonymisingAnAccountRemovesEveryPrudentRowItOwned() {
    UUID userId = seedExpiredAccount();
    UUID accountId = PrudentTest.seedAccount(userId.toString(), "Dormant checking", "PLN");
    UUID categoryId = PrudentTest.seedCategory(userId.toString(), "Food");
    PrudentTest.seedSettings(userId.toString(), "PLN");
    UUID recordId =
        PrudentTest.seedRecord(userId.toString(), accountId, categoryId, -500L, "PLN");

    int anonymised = QuarkusTransaction.requiringNew().call(retention::anonymiseExpiredAccounts);

    assertTrue(
        anonymised >= 1,
        "the framework did not anonymise the expired account, so this test proved nothing about"
            + " the cascade — check what UserRetentionService now selects on");

    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              assertNull(RecordEntity.findById(recordId), "the record must be gone");
              assertNull(AccountEntity.findById(accountId), "the account must be gone");
              assertNull(CategoryEntity.findById(categoryId), "the category must be gone");
              assertNull(SettingsEntity.findById(userId), "the settings row must be gone");
              // The users row itself is zen-identity's to keep or remove; Prudent never touches it.
              assertNotNull(User.findById(userId));
            });
  }

  @Test
  void aLiveUserIsUntouchedByTheSameCycle() {
    UUID accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Alice checking", "PLN");
    seedExpiredAccount(); // something for the cycle to do, so it is not a no-op run

    QuarkusTransaction.requiringNew().call(retention::anonymiseExpiredAccounts);

    QuarkusTransaction.requiringNew()
        .run(
            () ->
                assertEquals(
                    accountId,
                    AccountEntity.<AccountEntity>findById(accountId).id,
                    "a live user's data must not be swept"));
  }

  /**
   * Delivery of the framework's job trigger is at-least-once, so the cycle may run again over the
   * same data. The second pass must find nothing to anonymise and must not fail.
   */
  @Test
  void runningTheCycleTwiceIsHarmless() {
    UUID userId = seedExpiredAccount();
    UUID accountId = PrudentTest.seedAccount(userId.toString(), "Dormant checking", "PLN");

    QuarkusTransaction.requiringNew().call(retention::anonymiseExpiredAccounts);
    int second = QuarkusTransaction.requiringNew().call(retention::anonymiseExpiredAccounts);

    assertEquals(0, second, "an already-anonymised account must not be anonymised twice");
    QuarkusTransaction.requiringNew().run(() -> assertNull(AccountEntity.findById(accountId)));
  }
}
