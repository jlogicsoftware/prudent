package prudent.retention;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import prudent.privacy.PrudentDataEraser;
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
 * <p><strong>What "all of Prudent's rows" means is {@link PrudentDataEraser}'s</strong>, shared with
 * the person who asks to be erased rather than waits for dormancy to do it, so the two routes cannot
 * disagree about which tables hold a user's data (ADR-071).
 */
@ApplicationScoped
public class PrudentRetentionCleanup {

  private final PrudentDataEraser eraser;

  @Inject
  public PrudentRetentionCleanup(PrudentDataEraser eraser) {
    this.eraser = eraser;
  }

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
    eraser.erase(event.userId());
  }
}
