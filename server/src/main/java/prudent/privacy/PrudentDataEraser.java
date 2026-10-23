package prudent.privacy;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.util.List;
import java.util.UUID;
import org.jboss.logging.Logger;
import prudent.account.AccountEntity;
import prudent.budget.BudgetCarryResetEntity;
import prudent.budget.BudgetEntity;
import prudent.category.CategoryEntity;
import prudent.goal.GoalAllocationEntity;
import prudent.goal.GoalEntity;
import prudent.plan.PlanEntity;
import prudent.plan.PlanOccurrenceEntity;
import prudent.record.RecordEntity;
import prudent.settings.SettingsEntity;

/**
 * Deletes every row Prudent keeps for one user — <strong>the single place that knows what "all of a
 * user's Prudent data" means</strong>.
 *
 * <p>Two paths end here and must never disagree about it: the person asking to be erased
 * ({@link PrivacyResource}) and the framework's dormancy retention having anonymised an account
 * ({@link prudent.retention.PrudentRetentionCleanup}). Before this class the list lived only in the
 * second; a second copy in the first would be the drift this exists to prevent — a table added to
 * one and not the other is an erasure that leaves a person's data behind on exactly one of the two
 * routes, and nothing would say so. {@code PrivacyCoverageTest} asserts the list against the
 * database's own schema, so a new {@code user_id} table that is missing here fails a test instead of
 * a regulator's letter.
 *
 * <p><strong>Deletion order is FK-driven, not arbitrary</strong>: records first (the migration
 * carries no {@code ON DELETE CASCADE} on either the account or category reference — ADR-010 — so a
 * record row must go before the rows it points to), then plan occurrences and plans for the same
 * reason (ADR-037, ADR-038), then budgets (ADR-043) and carry-over resets (ADR-046), then envelope
 * entries and goals (ADR-049, ADR-050), then accounts and categories, then the singleton settings
 * row. Accounts are deleted entity-by-entity rather than by a bulk query so Hibernate cascades the
 * {@code @ElementCollection} balances ({@code prudent_account_balance}) it owns; a bulk HQL delete
 * bypasses the persistence context and would leave orphaned balance rows.
 *
 * <p><strong>It joins the caller's transaction and does not start one.</strong> {@code MANDATORY}
 * states that requirement: the retention path needs the cascade to commit or roll back with the
 * framework's anonymisation, and the self-service path needs it to commit or roll back with the
 * identity change that follows. An erasure that half-completed and reported success would be the
 * worst outcome this class can produce, so a call outside a transaction fails loudly.
 *
 * <p>Idempotent: a user already erased has nothing left, so a second call deletes nothing and does
 * not fail — {@code ZenJob} delivery upstream is at-least-once, and a person may press the button
 * twice.
 */
@ApplicationScoped
public class PrudentDataEraser {

  private static final Logger LOG = Logger.getLogger(PrudentDataEraser.class);

  /** How many rows of each kind one erasure removed — what a log line and a test can state. */
  public record Erased(
      long records,
      long occurrences,
      long plans,
      long budgets,
      long carryOverResets,
      long envelopeEntries,
      long goals,
      long accounts,
      long categories,
      long settings) {

    /** Whether anything at all was deleted. */
    public boolean any() {
      return records > 0
          || occurrences > 0
          || plans > 0
          || budgets > 0
          || carryOverResets > 0
          || envelopeEntries > 0
          || goals > 0
          || accounts > 0
          || categories > 0
          || settings > 0;
    }
  }

  /**
   * Deletes every Prudent row owned by {@code userId}.
   *
   * @param userId the person whose data goes
   * @return what was removed, so the caller can say so
   */
  @Transactional(Transactional.TxType.MANDATORY)
  public Erased erase(UUID userId) {
    long records = RecordEntity.delete("userId", userId);
    // Occurrences before their plans, and both before accounts and categories, like records: none
    // of those references carries a cascade.
    long occurrences = PlanOccurrenceEntity.delete("userId", userId);
    // Before accounts and categories, like records: a plan references both, without a cascade.
    long plans = PlanEntity.delete("userId", userId);
    // Before categories, like plans: a budget references its category without a cascade (ADR-043).
    long budgets = BudgetEntity.delete("userId", userId);
    // The audit history goes with the user it belongs to: erasure of a person's data outranks the
    // history's own never-deleted rule, which is a promise to the user, not to the system (ADR-046).
    long resets = BudgetCarryResetEntity.delete("userId", userId);
    // Goals are never deleted through the API (ADR-049); like the reset history, they go here
    // because erasing a person outranks that promise. The envelope history is just as permanent
    // and references goals with no cascade (ADR-050), so it goes first.
    long allocations = GoalAllocationEntity.delete("userId", userId);
    long goals = GoalEntity.delete("userId", userId);

    List<AccountEntity> accounts = AccountEntity.list("userId", userId);
    accounts.forEach(AccountEntity::delete);

    long categories = CategoryEntity.delete("userId", userId);
    long settings = SettingsEntity.delete("userId", userId);

    Erased erased =
        new Erased(
            records,
            occurrences,
            plans,
            budgets,
            resets,
            allocations,
            goals,
            accounts.size(),
            categories,
            settings);
    if (erased.any()) {
      // Counts and the opaque id only — a log line is not a private place, and what a person owned
      // is the very thing being erased.
      LOG.infof(
          "Erased Prudent data for %s: %d record(s), %d occurrence(s), %d plan(s), %d budget(s),"
              + " %d carry-over reset(s), %d envelope entry(ies), %d goal(s), %d account(s),"
              + " %d category(ies), %d settings row(s)",
          userId, records, occurrences, plans, budgets, resets, allocations, goals,
          accounts.size(), categories, settings);
    }
    return erased;
  }
}
