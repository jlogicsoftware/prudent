package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.mailer.Mail;
import io.quarkus.mailer.Mailer;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import jakarta.enterprise.inject.Alternative;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.persistence.EntityManager;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.logging.Handler;
import java.util.logging.LogRecord;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import zen.identity.user.User;
import zen.identity.user.UserRetentionJob;
import zen.identity.user.UserRetentionService;
import zen.identity.user.UserRole;

/**
 * The other half of the retention promise: <strong>a warning that did not go out never moves an
 * account toward erasure</strong>, and the failure does not put the person's address into a log.
 *
 * <p>This is the case that matters most about the observer. A mail relay that is down, misconfigured
 * or refusing is not a rare event, and the framework's answer to it is to stop the clock — but only
 * if the observer does not confirm. So the relay here always throws, as an SMTP server that refuses
 * connections would, and the account must stay exactly where it is for as long as it does.
 *
 * <p>It is the real {@code EmailService} and the real observer running over a mailer that fails;
 * nothing in between is replaced, so a regression that confirms the receipt on any other condition
 * than a send that returned {@code true} fails here.
 */
@QuarkusTest
@TestProfile(PrivacyDormancyUnreachableMailerTest.UnreachableMailerProfile.class)
class PrivacyDormancyUnreachableMailerTest {

  @ConfigProperty(name = "zen.identity.retention.warning-days")
  int warningDays;

  @Inject UserRetentionJob retention;
  @Inject EntityManager entityManager;

  private final CopyOnWriteArrayList<String> logged = new CopyOnWriteArrayList<>();
  private Handler capture;

  @BeforeEach
  void captureLogs() {
    PrudentTest.reset();
    capture =
        new Handler() {
          @Override
          public void publish(LogRecord record) {
            // Formatted as the log line would be, with its parameters and its exception.
            String line = record.getMessage();
            Object[] params = record.getParameters();
            if (params != null && params.length > 0) {
              try {
                line = String.format(record.getMessage(), params);
              } catch (RuntimeException notPrintf) {
                line = record.getMessage() + " " + java.util.Arrays.toString(params);
              }
            }
            logged.add(line + (record.getThrown() == null ? "" : " " + record.getThrown()));
          }

          @Override
          public void flush() {}

          @Override
          public void close() {}
        };
    java.util.logging.Logger.getLogger("").addHandler(capture);
  }

  @AfterEach
  void releaseLogs() {
    java.util.logging.Logger.getLogger("").removeHandler(capture);
  }

  @Test
  void aWarningThatCouldNotBeSentDoesNotStartTheCountdownHoweverOftenTheCycleRuns() {
    UUID dormant = UUID.randomUUID();
    String address = "unreachable-" + dormant + "@example.test";
    persistDormantUser(dormant, address);
    PrivacySeed.everythingFor(dormant.toString());

    int anonymised = 0;
    for (int i = 0; i < 4; i++) {
      anonymised += QuarkusTransaction.requiringNew().call(retention::runCycle);
    }

    User after = QuarkusTransaction.requiringNew().call(() -> User.findById(dormant));
    assertEquals(0, anonymised);
    assertNull(after.deletionWarningSentAt, "an undelivered warning started the countdown");
    assertNull(after.finalWarningSentAt);
    assertFalse(UserRetentionService.isAnonymised(after));
    assertTrue(rowsOfEveryTable(dormant.toString()) > 0, "data was erased without a warning");
  }

  @Test
  void anAccountWhoseFinalWarningCouldNotBeSentIsNotErased() {
    UUID dormant = UUID.randomUUID();
    String address = "unreachable-final-" + dormant + "@example.test";
    persistDormantUser(dormant, address);
    PrivacySeed.everythingFor(dormant.toString());
    // Warned once, long ago — the stamp a delivered first warning would have left.
    QuarkusTransaction.requiringNew()
        .run(
            () ->
                User.<User>findById(dormant).deletionWarningSentAt =
                    OffsetDateTime.now().minusYears(1));

    for (int i = 0; i < 4; i++) {
      QuarkusTransaction.requiringNew().call(retention::runCycle);
    }

    User after = QuarkusTransaction.requiringNew().call(() -> User.findById(dormant));
    assertNull(after.finalWarningSentAt, "an undelivered final warning counted as delivered");
    assertFalse(UserRetentionService.isAnonymised(after), "an unwarned account was erased");
    assertTrue(rowsOfEveryTable(dormant.toString()) > 0);
  }

  @Test
  void aFailedSendNamesTheAccountByIdAndNeverByAddress() {
    UUID dormant = UUID.randomUUID();
    // Not derived from the user id: the id is expected in the log, the address is not.
    String address = "log-check-" + UUID.randomUUID() + "@example.test";
    persistDormantUser(dormant, address);

    QuarkusTransaction.requiringNew().call(retention::runCycle);

    List<String> about = logged.stream().filter(l -> l.contains(dormant.toString())).toList();
    assertFalse(about.isEmpty(), "the failure was not logged against the account's id");
    String localPart = address.substring(0, address.indexOf('@'));
    for (String line : logged) {
      assertFalse(line.contains(address), "an address reached a log: " + line);
      assertFalse(line.contains(localPart), "an address's local part reached a log: " + line);
    }
  }

  // --- helpers ---------------------------------------------------------------------------------

  private void persistDormantUser(UUID id, String email) {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = new User();
              user.id = id;
              user.email = email;
              user.language = "en";
              user.role = UserRole.USER;
              user.createdAt = OffsetDateTime.now().minusDays(warningDays + 30L);
              user.lastLoginAt = OffsetDateTime.now().minusDays(warningDays + 1L);
              user.persist();
            });
  }

  private long rowsOfEveryTable(String userId) {
    return UserOwnedRows.totalRows(entityManager, userId);
  }

  /** Enables {@link UnreachableMailer} for this class only, leaving the other suites unaffected. */
  public static class UnreachableMailerProfile implements QuarkusTestProfile {
    @Override
    public Set<Class<?>> getEnabledAlternatives() {
      return Set.of(UnreachableMailer.class);
    }
  }

  /** A mailer that behaves like an SMTP relay refusing connections. */
  @Alternative
  @Singleton
  public static class UnreachableMailer implements Mailer {
    @Override
    public void send(Mail... mails) {
      throw new IllegalStateException("relay unavailable");
    }
  }
}
