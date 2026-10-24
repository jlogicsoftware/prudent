package prudent.privacy;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.util.UUID;
import zen.identity.user.User;

/**
 * Anonymises one person's {@code users} row on request — the identity half of an erasure that the
 * person asked for, written to be indistinguishable from the one dormancy retention performs.
 *
 * <p><strong>Why Prudent writes this at all.</strong> {@code UserRetentionService} anonymises only
 * in batches, of accounts that have run out their warnings; it offers no "anonymise this one now",
 * and its marker constants are package-private. So the person's own request has no framework call
 * to make. The shape written here — the address becomes {@code anon_<id>@deleted.invalid}, the
 * nickname "Deleted User", the other personal fields cleared — is the framework's, copied, and a
 * copy of a convention is exactly the coupling ADR-022 warned about: if jZen changes it, nothing
 * here would notice. {@code PrivacyErasureTest} therefore asks the framework's own
 * {@code UserRetentionService.isAnonymised} whether the row this class wrote counts as anonymised,
 * which fails the moment the two disagree. The gap is reported upstream in {@code docs/jzen/}.
 *
 * <p><strong>What this does not reach: the sign-in credential.</strong> The address a person signs
 * in with is also held by Supabase in {@code auth.users}, which is Supabase's table and not this
 * row. {@link SignInRecordEraser} deletes it through Supabase's admin API, in the same transaction,
 * for the two request routes (ADR-075); dormancy anonymisation does not reach it yet.
 *
 * <p>Joins the caller's transaction ({@code MANDATORY}): the identity change and the deletion of
 * the person's financial rows must commit together or not at all.
 */
@ApplicationScoped
public class PrudentIdentityAnonymiser {

  /** The framework's anonymisation marker, see the class comment on why it is copied. */
  static final String EMAIL_PREFIX = "anon_";

  static final String EMAIL_DOMAIN = "@deleted.invalid";
  static final String NICKNAME = "Deleted User";

  /**
   * Anonymises the {@code users} row of {@code userId}, if there is one.
   *
   * @param userId the person being erased
   * @return whether a row existed to anonymise
   */
  @Transactional(Transactional.TxType.MANDATORY)
  public boolean anonymise(UUID userId) {
    User user = User.findById(userId);
    if (user == null) {
      return false;
    }
    user.email = EMAIL_PREFIX + user.id + EMAIL_DOMAIN;
    user.nickname = NICKNAME;
    user.displayName = null;
    user.avatarUrl = null;
    user.emailVerified = false;
    return true;
  }
}
