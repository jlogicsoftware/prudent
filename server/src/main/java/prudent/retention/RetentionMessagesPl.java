package prudent.retention;

import io.quarkus.qute.i18n.Localized;
import io.quarkus.qute.i18n.Message;

/** Polish variant of {@link RetentionMessages}. */
@Localized("pl")
public interface RetentionMessagesPl extends RetentionMessages {

  @Override
  @Message("Prudent: Twoje dane zostaną usunięte, jeśli się nie zalogujesz (dni do usunięcia: {days})")
  String firstWarningSubject(int days);

  @Override
  @Message("Ostatnie powiadomienie: Twoje dane w Prudent zostaną usunięte (dni do usunięcia: {days})")
  String finalWarningSubject(int days);
}
