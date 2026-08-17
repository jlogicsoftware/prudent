package prudent.server.settings;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.util.UUID;

/**
 * The {@code prudent_settings} table — one row per user (active-record Panache entity).
 *
 * <p><strong>A singleton per user, which the schema states rather than merely assumes:</strong> the
 * primary key <em>is</em> {@code user_id}. There is no separate id column, because a second key
 * would make "two settings rows for one user" a representable state that something would then have
 * to be trusted not to create. The URL carries no id for the same reason — on a singleton the token
 * is the entire addressing scheme.
 *
 * <p>The row is created on first login by {@link prudent.server.onboarding.NewUserSetup}, never by
 * a client.
 */
@Entity
@Table(name = "prudent_settings")
public class SettingsEntity extends PanacheEntityBase {

  /**
   * The owning user, and the primary key. {@code zen-identity}'s {@code users.id} — the Supabase
   * identity id and the JWT {@code sub}. Not a foreign key, for the reason given on
   * {@link prudent.server.account.AccountEntity}.
   */
  @Id
  @Column(name = "user_id")
  public UUID userId;

  /**
   * The user's main currency — ISO-4217, upper case.
   *
   * <p><strong>A LABEL, NOT A CONVERSION TARGET</strong> (docs/DECISIONS.md ADR-009). It selects
   * which currency a record form pre-selects, which per-currency total the overview shows first,
   * and what an empty state names. It is never used to convert one currency into another or to sum
   * across them, because Prudent does no FX: a single total across PLN, EUR and USD needs a rate
   * source, a base currency and a rate <em>date</em> on every record, and a 2024 purchase converted
   * at today's rate is a wrong number that looks right.
   *
   * <p>Not required to be a currency any of the user's accounts holds — it is a display preference,
   * and a user who chose PLN before opening their first account is a normal state rather than an
   * inconsistency to reject.
   *
   * <p>{@code NOT NULL} in the schema: the column always holds a real currency, because the empty
   * string that means "reset to the default" on a request is resolved to
   * {@link #DEFAULT_MAIN_CURRENCY} before it is ever written. That is what lets a {@code GET}
   * promise it never answers with an empty currency.
   */
  @Column(name = "main_currency", nullable = false, length = 3)
  public String mainCurrency;

  /**
   * The currency a user gets before they choose one.
   *
   * <p>PLN because Prudent is a Polish-market product. This is the value the empty string on a
   * request resolves to, and the value {@link prudent.server.onboarding.NewUserSetup} writes for a
   * new user — one constant rather than two literals that could drift apart.
   */
  public static final String DEFAULT_MAIN_CURRENCY = "PLN";

  /** The settings of one user, or {@code null} if the row does not exist yet. */
  public static SettingsEntity findOwned(UUID userId) {
    return findById(userId);
  }
}
