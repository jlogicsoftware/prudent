package prudent.retention;

import io.quarkus.qute.i18n.Message;
import io.quarkus.qute.i18n.MessageBundle;

/**
 * The subject lines of the two dormancy warnings, as a typed Qute {@code @MessageBundle}. English
 * is the default bundle; {@link RetentionMessagesUk} and {@link RetentionMessagesPl} are the other
 * two languages Prudent ships. The bodies are the matching {@code templates/mail/} files.
 *
 * <p>No subject names an amount, an account or a category: a mail is stored by third parties for
 * as long as they like, and the only fact about a person's finances it may carry is that they have
 * some.
 *
 * <p>The Ukrainian and Polish subjects say "days left: N" rather than "in N days", because both
 * languages decline the noun by the number and the number comes from configuration — a sentence
 * that is right for 30 and 7 is wrong for 21 or 2.
 */
@MessageBundle("retentionmail")
public interface RetentionMessages {

  /** Subject of the first warning: the account has been dormant, deletion is {@code days} away. */
  @Message("Prudent: your data will be deleted in {days} days unless you sign in")
  String firstWarningSubject(int days);

  /** Subject of the final warning. */
  @Message("Last notice: your Prudent data will be deleted in {days} days")
  String finalWarningSubject(int days);
}
