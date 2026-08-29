package prudent;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.ObservesAsync;
import jakarta.transaction.Transactional;
import java.util.List;
import java.util.UUID;
import org.jboss.logging.Logger;
import prudent.category.CategoryEntity;
import prudent.settings.SettingsEntity;
import zen.identity.event.UserRegistered;

/**
 * What a new user finds waiting for them: a settings row and a starter set of categories.
 *
 * <p><strong>Why an event observer rather than a migration.</strong> This is per-user data, not
 * schema — Flyway runs once per database, and a new user arrives long after it did. The framework
 * publishes {@link UserRegistered} for exactly this split (jZen ADR-007): the framework knows
 * <em>that</em> a user registered, and only the application knows what should happen next. Nothing
 * here is hand-rolled onto the auth path; the mechanism already existed and this supplies the
 * content.
 *
 * <p><strong>Why any defaults at all.</strong> An empty categories screen on first launch is a dead
 * end: it asks a user to invent a taxonomy before recording anything, when the thing they came to
 * do is record something. These are ordinary rows — deletable, editable, in no way special — because
 * a default a user cannot clear stops being a default and becomes clutter.
 *
 * <p><strong>The icon keys are the ones the client ships</strong>
 * ({@link prudent.category.IconKeys}). Seeding a category whose key the client has no
 * {@code IconData} for would render the fallback icon on day one, which is the fallback doing its
 * job in a situation nobody needed to create.
 */
@ApplicationScoped
public class NewUserSetup {

  private static final Logger LOG = Logger.getLogger(NewUserSetup.class);

  /**
   * The starter categories, as (title, icon key, ARGB colour).
   *
   * <p>English titles, and that is a known gap rather than a decision: Prudent ships {en, uk, pl}
   * and these rows are created from a server with the registering user's language already in hand
   * ({@link UserRegistered#language()}). Localising them means a server-side message bundle, which
   * is the same machinery Prudent needs for mail and has no other caller yet. Named here so it is
   * picked up with that work rather than discovered by a Polish user.
   */
  private static final List<Starter> STARTERS =
      List.of(
          new Starter("Food", "food", 0xFF4CAF50L),
          new Starter("Restaurant", "restaurant", 0xFFFF9800L),
          new Starter("Leisure", "leisure", 0xFF9C27B0L),
          new Starter("Health", "medicine", 0xFFF44336L),
          new Starter("Work", "work", 0xFF2196F3L));

  private record Starter(String title, String iconKey, long colorArgb) {}

  /**
   * Creates the new user's settings row and starter categories.
   *
   * <p>{@code @ObservesAsync} because the framework fires it asynchronously, after the profile row
   * is committed — so this runs on another thread with no persistence context of its own, which is
   * why the method carries its own {@code @Transactional}.
   *
   * <p><strong>Idempotent by check, not by assumption.</strong> An event delivered twice must not
   * double the starter set, and "the framework fires it once" is a property of code in another
   * repository that this one cannot enforce. The check is cheap and the alternative is a user with
   * ten categories and no idea why.
   *
   * <p><strong>Failure is logged and not rethrown, and that is deliberate here specifically.</strong>
   * The observer runs after registration has already succeeded and committed; throwing would not
   * un-register the user, it would only lose the exception into the async dispatcher. What the user
   * would experience is an account with no starter categories — recoverable by making one — so the
   * honest handling is to record the fault loudly and leave the account usable, rather than to fail
   * a registration that has already happened. This is the one place in this server that catches
   * broadly, and the reason is that there is no caller left to return an error to.
   */
  @Transactional
  public void onUserRegistered(@ObservesAsync UserRegistered event) {
    UUID userId = event.userId();
    try {
      if (SettingsEntity.findOwned(userId) == null) {
        SettingsEntity settings = new SettingsEntity();
        settings.userId = userId;
        settings.mainCurrency = SettingsEntity.DEFAULT_MAIN_CURRENCY;
        settings.persist();
      }

      if (CategoryEntity.count("userId", userId) == 0) {
        for (Starter starter : STARTERS) {
          CategoryEntity category = new CategoryEntity();
          category.id = UUID.randomUUID();
          category.userId = userId;
          category.title = starter.title();
          category.iconKey = starter.iconKey();
          category.description = "";
          category.colorArgb = starter.colorArgb();
          category.persist();
        }
        LOG.infof("Seeded %d starter categories for user %s", STARTERS.size(), userId);
      }
    } catch (RuntimeException failure) {
      LOG.errorf(
          failure,
          "Could not set up defaults for newly registered user %s. The account exists and is"
              + " usable; it has no starter categories or settings row until one is created.",
          userId);
    }
  }
}
