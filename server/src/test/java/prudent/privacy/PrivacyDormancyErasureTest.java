package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.mailer.Mail;
import io.quarkus.mailer.MockMailbox;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import zen.identity.auth.SupabaseSessionResponse.UserPayload;
import zen.identity.user.User;
import zen.identity.user.UserRetentionJob;
import zen.identity.user.UserRetentionService;
import zen.identity.user.UserRole;
import zen.identity.user.UserStore;

/**
 * The retention promise in {@code docs/privacy-policy.md} ("How long it is kept"), driven the way
 * it happens: a dormant account is warned, warned again, and then anonymised — by the framework's
 * own {@link UserRetentionJob}, the same call {@code UserRetentionZenJob} makes — and afterwards
 * <strong>nothing of Prudent's data for that person is left</strong>.
 *
 * <p><strong>What this replaces.</strong> {@code PrivacyRetentionStatementTest} asserted that no
 * account was ever anonymised, because no warning could be delivered. That was a test of an
 * absence, kept red-on-change on purpose; the change it was waiting for is this one. The other
 * retention test, {@code PrudentRetentionCleanupTest}, proves Prudent's cascade by seeding a
 * delivered final warning ten years old — it can say what happens <em>if</em> the framework
 * anonymises, and never whether a warning is delivered. This is the half that does.
 *
 * <p>Time is moved by rewriting the stamps, not by a clock: the offsets between the stages are
 * read from the same configuration the framework reads, so nothing here repeats 330, 23 or 7.
 * What the stamps are <em>for</em> is left to the framework — a stamp is written only by the cycle,
 * after the mail was handed over, and the test only ever ages one the cycle wrote.
 *
 * <p>The tables are discovered from the schema, as in {@code PrivacyCoverageTest}, so a table
 * added tomorrow cannot be forgotten by the dormancy route while the self-service route learns it.
 */
@QuarkusTest
class PrivacyDormancyErasureTest {

  @ConfigProperty(name = "zen.identity.retention.warning-days")
  int warningDays;

  @ConfigProperty(name = "zen.identity.retention.final-warning-offset-days")
  int finalWarningOffsetDays;

  @ConfigProperty(name = "zen.identity.retention.anonymise-offset-days")
  int anonymiseOffsetDays;

  @Inject UserRetentionJob retention;
  @Inject MockMailbox mailbox;
  @Inject EntityManager entityManager;
  @Inject UserStore userStore;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    mailbox.clear();
  }

  @Test
  void aDormantAccountIsWarnedTwiceThenErasedAndNothingOfItsDataRemains() {
    UUID dormant = UUID.randomUUID();
    String address = "dormant-" + dormant + "@example.test";
    persistDormantUser(dormant, address, "pl");
    PrivacySeed.everythingFor(dormant.toString());
    PrivacySeed.everythingFor(PrudentTest.ALICE);
    long aliceBefore = rowsOfEveryTable(PrudentTest.ALICE);
    assertTrue(rowsOfEveryTable(dormant.toString()) > 0, "the dormant user has no data to erase");

    // --- the first warning -------------------------------------------------------------------
    assertEquals(0, cycle(), "nothing is anonymised by a first warning");

    List<Mail> first = mailbox.getMailsSentTo(address);
    assertEquals(1, first.size(), "exactly one first warning");
    assertTrue(
        first.get(0).getSubject().contains("Twoje dane"),
        "the subject follows the account's language: " + first.get(0).getSubject());
    assertTrue(first.get(0).getHtml().contains("lang=\"pl\""), "and so does the body");
    assertTrue(
        first.get(0).getHtml().contains("<strong>" + (finalWarningOffsetDays + anonymiseOffsetDays)),
        "the body says how many days are left");
    User afterFirst = reload(dormant);
    assertNotNull(afterFirst.deletionWarningSentAt, "a delivered first warning is stamped");
    assertNull(afterFirst.finalWarningSentAt);
    assertTrue(rowsOfEveryTable(dormant.toString()) > 0, "warned is not erased");

    // The job runs daily and delivery of the trigger is at-least-once: running it again changes
    // nothing and warns nobody twice.
    cycle();
    assertEquals(1, mailbox.getMailsSentTo(address).size(), "a warning is not repeated");

    // --- the final warning -------------------------------------------------------------------
    ageStamp(dormant, "deletionWarningSentAt", finalWarningOffsetDays + 1);
    assertEquals(0, cycle(), "nothing is anonymised by a final warning either");

    List<Mail> both = mailbox.getMailsSentTo(address);
    assertEquals(2, both.size(), "the final warning is the second mail");
    assertTrue(both.get(1).getSubject().contains("Ostatnie powiadomienie"), both.get(1).getSubject());
    assertNotNull(reload(dormant).finalWarningSentAt, "a delivered final warning is stamped");
    assertTrue(rowsOfEveryTable(dormant.toString()) > 0, "warned twice is still not erased");

    // --- anonymisation -----------------------------------------------------------------------
    ageStamp(dormant, "finalWarningSentAt", anonymiseOffsetDays + 1);
    assertEquals(1, cycle(), "the account is anonymised once its final warning has run out");

    assertTrue(UserRetentionService.isAnonymised(reload(dormant)), "the profile is anonymised");
    assertEquals(2, mailbox.getMailsSentTo(address).size(), "and no third mail is sent");
    for (String table : userOwnedTables()) {
      assertEquals(
          0, rowsOf(table, dormant.toString()), table + " still holds rows for an erased account");
    }
    assertEquals(
        aliceBefore,
        rowsOfEveryTable(PrudentTest.ALICE),
        "an account that was not dormant lost something");
    assertEquals(0, cycle(), "a second cycle finds nothing left to do");
  }

  @Test
  void anAccountThatSignsInAfterTheFirstWarningIsNeverWarnedAgainOrErased() {
    UUID returning = UUID.randomUUID();
    String address = "returning-" + returning + "@example.test";
    persistDormantUser(returning, address, "en");
    PrivacySeed.everythingFor(returning.toString());
    cycle();
    assertEquals(1, mailbox.getMailsSentTo(address).size());
    assertNotNull(reload(returning).deletionWarningSentAt);

    // The real sign-in path: the framework's own upsert on login, which is what clears the stamps.
    // A test that cleared them itself would prove only that the test can clear them.
    QuarkusTransaction.requiringNew()
        .run(
            () ->
                userStore.upsertOnLogin(
                    new UserPayload(
                        returning.toString(), address, "authenticated", "2026-01-01T00:00:00Z", Map.of()),
                    "en"));
    assertNull(reload(returning).deletionWarningSentAt, "signing in did not reset the countdown");

    // Long enough that, had the countdown survived, both later stages would have run.
    for (int i = 0; i < 3; i++) {
      cycle();
    }

    assertEquals(1, mailbox.getMailsSentTo(address).size(), "a person who came back was warned again");
    assertFalse(UserRetentionService.isAnonymised(reload(returning)), "a returning user was erased");
    assertTrue(rowsOfEveryTable(returning.toString()) > 0, "a returning user lost their data");
  }

  @Test
  void theMailSubjectAndBodyAreInTheSameLanguageForEveryShippedLanguageAndTheFallback() {
    String[][] cases = {
      {"en", "Prudent: your data will be deleted", "lang=\"en\""},
      {"uk", "ваші дані буде видалено", "lang=\"uk\""},
      {"pl", "Twoje dane zostaną usunięte", "lang=\"pl\""},
      {"pl-PL", "Twoje dane zostaną usunięte", "lang=\"pl\""},
      {"de", "Prudent: your data will be deleted", "lang=\"en\""},
      {null, "Prudent: your data will be deleted", "lang=\"en\""},
    };
    for (String[] c : cases) {
      UUID id = UUID.randomUUID();
      String address = "lang-" + id + "@example.test";
      persistDormantUser(id, address, c[0]);
      cycle();
      Mail mail = mailbox.getMailsSentTo(address).get(0);
      assertTrue(mail.getSubject().contains(c[1]), c[0] + ": " + mail.getSubject());
      assertTrue(mail.getHtml().contains(c[2]), c[0] + ": body is not " + c[2]);
    }
  }

  @Test
  void neitherWarningCarriesAnythingFromThePersonsLedger() {
    UUID dormant = UUID.randomUUID();
    // Not derived from the user id, so the id can be searched for on its own below.
    String address = "ledger-" + UUID.randomUUID() + "@example.test";
    persistDormantUser(dormant, address, "en");
    PrivacySeed.everythingFor(dormant.toString());
    cycle();
    ageStamp(dormant, "deletionWarningSentAt", finalWarningOffsetDays + 1);
    cycle();

    List<Mail> sent = mailbox.getMailsSentTo(address);
    assertEquals(2, sent.size());
    for (Mail mail : sent) {
      String everything = mail.getSubject() + "\n" + mail.getHtml();
      for (String ledger :
          List.of(
              "Checking of", "Food of", "Old of", "Holiday of", "Old goal of", "PLN", "EUR",
              dormant.toString(),
              // Template commentary is Qute comment, not HTML: it must not be in the mail.
              "DormancyWarningMailer",
              "{!")) {
        assertFalse(everything.contains(ledger), "the mail mentions '" + ledger + "'");
      }
      assertEquals(List.of(address), mail.getTo(), "a warning goes to the account's own address");
    }
  }

  @Test
  void thePolicyStatesTheWindowsTheFrameworkIsConfiguredWith() throws IOException {
    // The policy is a promise to people, and the numbers in it are the framework's configuration.
    // Reading the file here is what makes changing one without the other a red build, not a
    // discovery by someone who was told their data lasts a year.
    String policy = Files.readString(Path.of("..", "docs", "privacy-policy.md"));
    for (int days : List.of(warningDays, finalWarningOffsetDays, anonymiseOffsetDays)) {
      assertTrue(
          policy.contains("**" + days + " days**"),
          "docs/privacy-policy.md ('How long it is kept') does not state the window of " + days
              + " days that zen.identity.retention is configured with");
    }
    assertTrue(
        policy.contains("deleted in " + (finalWarningOffsetDays + anonymiseOffsetDays) + " days"),
        "the policy does not say how many days the first warning gives");
  }

  // --- helpers ---------------------------------------------------------------------------------

  private int cycle() {
    return QuarkusTransaction.requiringNew().call(retention::runCycle);
  }

  private void persistDormantUser(UUID id, String email, String language) {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = new User();
              user.id = id;
              user.email = email;
              user.language = language;
              user.role = UserRole.USER;
              user.createdAt = OffsetDateTime.now().minusDays(warningDays + 30L);
              user.lastLoginAt = OffsetDateTime.now().minusDays(warningDays + 1L);
              user.persist();
            });
  }

  /** Moves one of the stamps the cycle wrote back in time, the way the passing of days would. */
  private void ageStamp(UUID id, String field, int days) {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = User.<User>findById(id);
              if ("deletionWarningSentAt".equals(field)) {
                user.deletionWarningSentAt = user.deletionWarningSentAt.minusDays(days);
              } else {
                user.finalWarningSentAt = user.finalWarningSentAt.minusDays(days);
              }
            });
  }

  private User reload(UUID id) {
    return QuarkusTransaction.requiringNew().call(() -> User.findById(id));
  }

  private List<String> userOwnedTables() {
    return UserOwnedRows.tables(entityManager);
  }

  private long rowsOf(String table, String userId) {
    return UserOwnedRows.rowsOf(entityManager, table, userId);
  }

  private long rowsOfEveryTable(String userId) {
    return userOwnedTables().stream().mapToLong(table -> rowsOf(table, userId)).sum();
  }
}
