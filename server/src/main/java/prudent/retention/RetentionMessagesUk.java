package prudent.retention;

import io.quarkus.qute.i18n.Localized;
import io.quarkus.qute.i18n.Message;

/** Ukrainian variant of {@link RetentionMessages}. */
@Localized("uk")
public interface RetentionMessagesUk extends RetentionMessages {

  @Override
  @Message("Prudent: ваші дані буде видалено, якщо ви не увійдете (днів до видалення: {days})")
  String firstWarningSubject(int days);

  @Override
  @Message("Останнє сповіщення: ваші дані в Prudent буде видалено (днів до видалення: {days})")
  String finalWarningSubject(int days);
}
