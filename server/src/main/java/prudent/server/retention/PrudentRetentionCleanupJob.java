package prudent.server.retention;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Duration;
import java.util.List;
import java.util.UUID;
import org.jboss.logging.Logger;
import prudent.server.account.AccountEntity;
import prudent.server.category.CategoryEntity;
import prudent.server.record.RecordEntity;
import prudent.server.settings.SettingsEntity;
import zen.identity.user.User;
import zen.jobs.ZenJob;

/**
 * Deletes Prudent's own rows for every user {@code zen-identity}'s GDPR retention cycle has
 * anonymised — the half of "delete a user, delete their financial records" that the framework
 * cannot do on Prudent's behalf, because it knows nothing about Prudent's tables.
 *
 * <p><strong>Why this exists at all, stated plainly.</strong> {@code UserRetentionService}
 * (jZen) anonymises a dormant account's identity fields directly, in its own transaction, and
 * fires no event an application could observe — unlike {@code UserRegistered}, which exists for
 * exactly the symmetric case on the way in (jZen ADR-007). Without this job, an anonymised user's
 * {@code users} row would say "Deleted User" while their accounts, categories and records sat in
 * Prudent's own tables under the same {@code user_id}, unreachable by any authenticated caller
 * (the id no longer belongs to a live session) but present in the database indefinitely — a data-
 * protection defect, not a cosmetic one, for a budget app whose whole content is financial
 * history. This is reported as a jZen-side finding (docs/jzen/README.md): the retention service
 * has no hook symmetric to {@code UserRegistered} for the application half of "a user is gone".
 *
 * <p><strong>The mechanism, until that hook exists.</strong> This job scans for {@code users}
 * rows matching the anonymisation marker {@code UserRetentionService} writes
 * ({@code anon_<uuid>@deleted.invalid} — package-private there, so the literal is duplicated
 * here rather than referenced; a rename on the framework side would silently stop matching,
 * which is exactly the kind of coupling the finding above asks the framework to remove) and,
 * for each one, deletes every Prudent row still keyed to that user id. Idempotent by
 * construction: a user already swept has nothing left to delete, so running this job twice, or
 * concurrently with itself, does nothing extra the second time — the same contract every
 * {@link ZenJob} must satisfy.
 *
 * <p><strong>Deletion order matters and is FK-driven, not arbitrary</strong>: records first (the
 * migration carries no {@code ON DELETE CASCADE} on either the account or category reference —
 * ADR-010 — so a record row is what has to go before the row it points to can), then accounts and
 * categories, then the singleton settings row. Accounts are deleted entity-by-entity rather than
 * by a bulk query so Hibernate cascades the {@code @ElementCollection} balances
 * ({@code prudent_account_balance}) it owns — a bulk HQL delete bypasses the persistence context
 * and would leave orphaned balance rows behind.
 */
@ApplicationScoped
public class PrudentRetentionCleanupJob implements ZenJob {

  private static final Logger LOG = Logger.getLogger(PrudentRetentionCleanupJob.class);

  static final String JOB_ID = "prudent-retention-cleanup";

  /** Same cadence as the anonymisation cycle it sweeps after — no reason to check more often. */
  private static final Duration INTERVAL = Duration.ofDays(1);

  @Override
  public String id() {
    return JOB_ID;
  }

  @Override
  public Duration defaultInterval() {
    return INTERVAL;
  }

  @Override
  @Transactional
  public void run() {
    List<User> anonymised =
        User.find("email like 'anon\\_%@deleted.invalid' escape '\\'").list();
    int swept = 0;
    for (User user : anonymised) {
      if (deleteRowsFor(user.id)) {
        swept++;
      }
    }
    if (swept > 0) {
      LOG.infof("Retention cleanup: removed Prudent rows for %d anonymised user(s)", swept);
    }
  }

  /** @return whether anything was actually deleted for this user (for the log line above only). */
  private boolean deleteRowsFor(UUID userId) {
    long recordsDeleted = RecordEntity.delete("userId", userId);

    List<AccountEntity> accounts = AccountEntity.list("userId", userId);
    accounts.forEach(AccountEntity::delete);

    long categoriesDeleted = CategoryEntity.delete("userId", userId);
    long settingsDeleted = SettingsEntity.delete("userId", userId);

    return recordsDeleted > 0
        || !accounts.isEmpty()
        || categoriesDeleted > 0
        || settingsDeleted > 0;
  }
}
