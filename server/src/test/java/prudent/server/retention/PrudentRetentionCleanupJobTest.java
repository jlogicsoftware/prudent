package prudent.server.retention;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.time.OffsetDateTime;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.server.PrudentTest;
import prudent.server.account.AccountEntity;
import prudent.server.category.CategoryEntity;
import prudent.server.record.RecordEntity;
import prudent.server.settings.SettingsEntity;
import zen.identity.user.User;
import zen.identity.user.UserRole;

/**
 * Proves the half of "delete a user, delete their financial records" that
 * {@code UserRetentionCleanupJob}'s own class comment says the framework cannot do: a user whose
 * {@code users} row carries the anonymisation marker
 * {@code UserRetentionService} writes must lose every Prudent row still keyed to their id, and
 * running the sweep twice must be exactly as harmless as running it once.
 */
@QuarkusTest
class PrudentRetentionCleanupJobTest {

  @Inject PrudentRetentionCleanupJob job;

  private static final UUID ANONYMISED_USER = UUID.randomUUID();
  private static final String ANONYMISED_EMAIL = "anon_" + ANONYMISED_USER + "@deleted.invalid";

  @BeforeEach
  void reset() {
    PrudentTest.reset();
  }

  @Test
  void sweepsEveryRowOwnedByAnAnonymisedUser() {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User anonymised = new User();
              anonymised.id = ANONYMISED_USER;
              anonymised.email = ANONYMISED_EMAIL;
              anonymised.role = UserRole.USER;
              anonymised.createdAt = OffsetDateTime.now();
              anonymised.persist();
            });
    UUID accountId = PrudentTest.seedAccount(ANONYMISED_USER.toString(), "Dormant checking", "PLN");
    UUID categoryId = PrudentTest.seedCategory(ANONYMISED_USER.toString(), "Food");
    PrudentTest.seedSettings(ANONYMISED_USER.toString(), "PLN");
    UUID recordId = PrudentTest.seedRecord(ANONYMISED_USER.toString(), accountId, categoryId, -500L, "PLN");

    job.run();

    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              assertNull(RecordEntity.findById(recordId), "the record must be gone");
              assertNull(AccountEntity.findById(accountId), "the account must be gone");
              assertNull(CategoryEntity.findById(categoryId), "the category must be gone");
              assertNull(
                  SettingsEntity.findById(ANONYMISED_USER), "the settings row must be gone");
              // The users row itself is zen-identity's to keep or remove; this job never touches it.
              assertEquals(1, User.count("id", ANONYMISED_USER));
            });
  }

  @Test
  void runningTwiceIsHarmless() {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User anonymised = new User();
              anonymised.id = ANONYMISED_USER;
              anonymised.email = ANONYMISED_EMAIL;
              anonymised.role = UserRole.USER;
              anonymised.createdAt = OffsetDateTime.now();
              anonymised.persist();
            });
    UUID accountId = PrudentTest.seedAccount(ANONYMISED_USER.toString(), "Dormant checking", "PLN");

    job.run();
    job.run(); // must not throw, and must not find anything left to delete

    QuarkusTransaction.requiringNew()
        .run(() -> assertNull(AccountEntity.findById(accountId)));
  }

  @Test
  void aLiveUserLikeAliceIsUntouched() {
    UUID accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Alice checking", "PLN");

    job.run();

    QuarkusTransaction.requiringNew()
        .run(
            () ->
                assertEquals(
                    accountId,
                    AccountEntity.<AccountEntity>findById(accountId).id,
                    "a live user's data must not be swept"));
  }
}
