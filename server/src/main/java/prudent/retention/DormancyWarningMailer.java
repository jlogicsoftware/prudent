package prudent.retention;

import io.quarkus.qute.i18n.Localized;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;
import zen.core.i18n.ZenLocales;
import zen.email.EmailService;
import zen.email.LocalizedEmail;
import zen.identity.event.AccountDeletionWarning;
import zen.identity.event.AccountDeletionWarning.Stage;

/**
 * Tells the owner of a dormant account that their data is about to be deleted, and says so to the
 * retention cycle only when the mail really left.
 *
 * <p><strong>This observer is what makes dormancy erasure possible at all.</strong> {@code
 * UserRetentionJob} stamps a warning — and so moves an account toward anonymisation — only if some
 * observer of {@link AccountDeletionWarning} confirms the {@code DeliveryReceipt}. Until Prudent
 * had one, no warning was ever confirmed, no account ever advanced, and the cascade of ADR-019 and
 * ADR-022 was correct and unreachable. Warning a person is the whole basis for erasing what they
 * left behind, so the confirmation is bound to {@link EmailService#send}'s own return value and to
 * nothing else: a relay that refuses, a template that is missing or an address that is rejected
 * all return {@code false}, the receipt stays unconfirmed, and the account is found again at the
 * next cycle instead of ageing toward deletion unwarned.
 *
 * <p><strong>What the mail carries.</strong> The recipient's own address (so a person with several
 * can tell which account is meant), the number of days left and a link to the app. No name, no
 * account, no amount, nothing from the person's ledger — {@code event} does not even hold any. The
 * recipient is named in logs by user id only, here and in {@link EmailService}, which logs the
 * {@code recipientRef} and never the address.
 *
 * <p><strong>The language.</strong> {@link EmailService} picks the body template from the
 * recipient's {@code users.language} resolved against {@code zen.i18n.supported}, and the subject
 * must come out in the same language as the body it heads. The framework's {@code
 * ZenLocales.resolve(tag)} resolves against jZen's own two languages and would send a Polish body
 * under an English subject, so this class resolves against the same configured set — the set is
 * read here from the same property because {@code EmailService} does not expose the language it
 * chose.
 */
@ApplicationScoped
public class DormancyWarningMailer {

  private static final Logger LOG = Logger.getLogger(DormancyWarningMailer.class);

  /** Locale-free template bases; {@link EmailService} appends {@code _<locale>}. */
  static final String FIRST_WARNING_TEMPLATE = "dormancy_first_warning";

  static final String FINAL_WARNING_TEMPLATE = "dormancy_final_warning";

  private final EmailService emailService;
  private final RetentionMessages english;
  private final RetentionMessages ukrainian;
  private final RetentionMessages polish;
  private final String siteUrl;
  private final Optional<List<String>> supportedLocales;

  @Inject
  public DormancyWarningMailer(
      EmailService emailService,
      RetentionMessages english,
      @Localized("uk") RetentionMessages ukrainian,
      @Localized("pl") RetentionMessages polish,
      @ConfigProperty(name = "site.url") String siteUrl,
      @ConfigProperty(name = "zen.i18n.supported") Optional<List<String>> supportedLocales) {
    this.emailService = emailService;
    this.english = english;
    this.ukrainian = ukrainian;
    this.polish = polish;
    this.siteUrl = siteUrl;
    this.supportedLocales = supportedLocales;
  }

  /**
   * Synchronous on purpose: the cycle reads the receipt as soon as {@code fire} returns, so an
   * asynchronous observer could not answer it.
   */
  void onAccountDeletionWarning(@Observes AccountDeletionWarning event) {
    boolean isFinal = event.stage() == Stage.FINAL;
    int days = event.daysUntilAnonymisation();
    RetentionMessages bundle = bundle(event.language());
    boolean sent =
        emailService.send(
            new LocalizedEmail(
                event.email(),
                event.language(),
                isFinal ? FINAL_WARNING_TEMPLATE : FIRST_WARNING_TEMPLATE,
                isFinal ? bundle.finalWarningSubject(days) : bundle.firstWarningSubject(days),
                Map.of("email", event.email(), "siteUrl", siteUrl, "days", days),
                event.userId().toString()));
    if (sent) {
      event.receipt().confirm();
      LOG.infof("Dormancy %s warning delivered to account %s", event.stage(), event.userId());
    } else {
      LOG.warnf(
          "Dormancy %s warning to account %s was not delivered; it stays where it is and is"
              + " retried at the next cycle",
          event.stage(), event.userId());
    }
  }

  /** The subject bundle for a stored language tag, resolved the way the body's template is. */
  private RetentionMessages bundle(String language) {
    // An empty value counts as unconfigured, exactly as in EmailService.send.
    List<String> supported =
        supportedLocales.filter(set -> !set.isEmpty()).orElse(ZenLocales.SHIPPED);
    return switch (ZenLocales.resolve(language, supported)) {
      case "uk" -> ukrainian;
      case "pl" -> polish;
      default -> english;
    };
  }
}
