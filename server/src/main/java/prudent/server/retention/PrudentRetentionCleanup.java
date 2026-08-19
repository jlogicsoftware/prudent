package prudent.server.retention;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.transaction.Transactional;
import java.util.List;
import java.util.UUID;
import org.jboss.logging.Logger;
import prudent.server.account.AccountEntity;
import prudent.server.category.CategoryEntity;
import prudent.server.record.RecordEntity;
import prudent.server.settings.SettingsEntity;
import zen.identity.event.UserAnonymised;

/**
 * Deletes Prudent's own rows for a user {@code zen-identity}'s GDPR retention cycle has just
 * anonymised — the half of "delete a user, delete their financial records" the framework cannot do
 * on Prudent's behalf, because it knows only that an identity was anonymised and nothing about
 * Prudent's tables (jZen ADR-007's split).
 *
 * <p>Without it, an anonymised user's {@code users} row would read "Deleted User" while their
 * accounts, categories and records sat under the same {@code user_id} — unreachable by any
 * authenticated caller, since the id no longer belongs to a live session, and present in the
 * database indefinitely. For an application whose entire content is financial history that is a
 * data-protection defect, not an untidiness.
 *
 * <p><strong>Why this is an observer and no longer a scanning job.</strong> Until jZen fired this
 * event, Prudent swept by matching the anonymisation marker {@code UserRetentionService} writes
 * ({@code anon_<uuid>@deleted.invalid}), a literal that was package-private upstream and therefore
 * duplicated here. That coupling could break in complete silence: a rename on the framework side
 * would have left the sweep matching nothing, deleting nothing, and reporting success, with the
 * test that "proved" it green — because the test built its fixture from the same literal the job
 * matched on, so it asserted Prudent's assumption about jZen rather than jZen's behaviour. The
 * event removes the literal, and the test below now drives the framework's real anonymisation
 * path, so the coupling is asserted against what the framework actually does.
 *
 * <p><strong>The transaction is the framework's, and joining it is deliberate.</strong>
 * {@code UserAnonymised} is fired synchronously from inside the transaction that anonymises the
 * row, before it commits, so this cascade is part of the same unit of work: if it throws, the
 * anonymisation rolls back with it rather than leaving an anonymised identity and orphaned
 * financial data. {@code MANDATORY} states that requirement rather than assuming it — an event
 * fired outside a transaction fails loudly here instead of quietly committing on its own.
 *
 * <p><strong>Deletion order is FK-driven, not arbitrary</strong>: records first (the migration
 * carries no {@code ON DELETE CASCADE} on either the account or category reference — ADR-010 — so
 * a record row must go before the rows it points to), then accounts and categories, then the
 * singleton settings row. Accounts are deleted entity-by-entity rather than by a bulk query so
 * Hibernate cascades the {@code @ElementCollection} balances ({@code prudent_account_balance}) it
 * owns; a bulk HQL delete bypasses the persistence context and would leave orphaned balance rows.
 */
@ApplicationScoped
public class PrudentRetentionCleanup {

  private static final Logger LOG = Logger.getLogger(PrudentRetentionCleanup.class);

  /**
   * Cascades Prudent's own deletion for one anonymised account.
   *
   * <p>Idempotent, because {@code ZenJob} delivery upstream is at-least-once and an account may be
   * anonymised once but observed more than once across retries: a user already swept has nothing
   * left to delete, so a second delivery does nothing extra rather than failing.
   *
   * @param event the account {@code zen-identity} has anonymised
   */
  @Transactional(Transactional.TxType.MANDATORY)
  public void onUserAnonymised(@Observes UserAnonymised event) {
    UUID userId = event.userId();

    long records = RecordEntity.delete("userId", userId);

    List<AccountEntity> accounts = AccountEntity.list("userId", userId);
    accounts.forEach(AccountEntity::delete);

    long categories = CategoryEntity.delete("userId", userId);
    long settings = SettingsEntity.delete("userId", userId);

    if (records > 0 || !accounts.isEmpty() || categories > 0 || settings > 0) {
      LOG.infof(
          "Retention cascade for %s: %d record(s), %d account(s), %d category(ies), %d settings row(s)",
          userId, records, accounts.size(), categories, settings);
    }
  }
}
