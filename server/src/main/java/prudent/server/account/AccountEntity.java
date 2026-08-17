package prudent.server.account;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.CascadeType;
import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OrderColumn;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * The {@code prudent_account} table — where the money is (active-record Panache entity).
 *
 * <p><strong>Why the name carries an {@code Entity} suffix.</strong> The wire model generated from
 * {@code proto/prudent/v1/accounts.proto} is already called {@code prudent.proto.v1.Account}, and a
 * mapper has both types in scope at once. Two types named {@code Account} distinguished only by
 * import order is a reader's trap and a compiler's ambiguity, so the persistent side takes the
 * suffix. The same applies to every entity in this server.
 *
 * <p><strong>{@code userId} is the ownership column and is never on the wire.</strong> It is
 * resolved from the authenticated identity on every create, read, update, delete and list — never
 * read from a request body, because a client that can name an owner can name someone else's. There
 * is deliberately <em>no</em> foreign key to Supabase's {@code auth.users}: the Dev Services
 * database is plain PostgreSQL with no {@code auth} schema, and Supabase owns that table's
 * lifecycle. {@code zen-identity}'s own {@code users} table has none for the same reason.
 *
 * <p><strong>An account holds several currencies at once</strong> (docs/DECISIONS.md ADR-008), so
 * the balance is a collection rather than a column pair. There is no FX anywhere in Prudent: the
 * balances are independent, nothing converts between them, and summing across them is refused
 * rather than done at a rate nobody chose.
 */
@Entity
@Table(name = "prudent_account")
public class AccountEntity extends PanacheEntityBase {

  /** Server-minted. A create request carries no id: an id from an untrusted client is not identity. */
  @Id public UUID id;

  /**
   * The owning user — {@code zen-identity}'s {@code users.id}, which is the Supabase identity id
   * and the JWT {@code sub}. Not a foreign key; see the class comment.
   */
  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Column(nullable = false)
  public String name;

  /**
   * Stored as the enum NAME, not its ordinal. An ordinal is a position in a Java source file: adding
   * a constant in the middle silently re-labels every existing row, and nothing fails at the point
   * of the mistake.
   */
  @Enumerated(EnumType.STRING)
  @Column(nullable = false)
  public AccountKind kind;

  /** Exactly one per user is true; the server clears the flag on the previous holder. */
  @Column(name = "is_default", nullable = false)
  public boolean isDefault;

  /** An inactive account is kept for its history rather than deleted. */
  @Column(name = "is_active", nullable = false)
  public boolean isActive;

  @Column(name = "include_in_total", nullable = false)
  public boolean includeInTotal;

  /**
   * Two flags rather than one: a savings account a user wants visible but excluded from spendable
   * funds needs them to differ.
   */
  @Column(name = "include_in_overview", nullable = false)
  public boolean includeInOverview;

  /**
   * The currencies this account holds, one entry each. Never empty — an account holding no currency
   * cannot receive a record, and the server rejects an empty list rather than creating one nothing
   * can be spent from.
   *
   * <p><strong>An {@code @ElementCollection}, not an entity association.</strong> A balance has no
   * identity of its own and no life outside its account: it is a value the account owns, which is
   * exactly what an element collection models. {@code orphanRemoval} semantics come free, so the
   * full-replacement {@code PUT} that drops a currency actually deletes its row.
   *
   * <p><strong>The unique constraint is on (account, currency)</strong>, which is the rule ADR-008
   * states, enforced by the database rather than only by the validator above it. The
   * {@code @OrderColumn} is separate and does a different job: the client renders the order the
   * server sent, so the declared order is preserved rather than left to whatever order the rows
   * happen to come back in.
   */
  @ElementCollection(fetch = FetchType.EAGER)
  @CollectionTable(
      name = "prudent_account_balance",
      joinColumns = @JoinColumn(name = "account_id"),
      uniqueConstraints =
          @UniqueConstraint(
              name = "prudent_account_balance_unique_currency",
              columnNames = {"account_id", "currency"}))
  @OrderColumn(name = "position")
  public List<AccountBalance> balances = new ArrayList<>();

  /** Every account owned by one user, in a stable order. */
  public static List<AccountEntity> listOwnedBy(UUID userId) {
    return list("userId = ?1 order by name", userId);
  }

  /**
   * One account, but only if the caller owns it. Ownership is part of the LOOKUP rather than a check
   * after it: a find-then-compare can be written without the compare, and the version without it
   * still returns a row.
   */
  public static AccountEntity findOwned(UUID userId, UUID id) {
    return find("id = ?1 and userId = ?2", id, userId).firstResult();
  }

  /**
   * Clears the default flag on every other account of this user. Called before setting it here, so
   * "exactly one default" is maintained by the server rather than trusted from the client.
   */
  public static void clearDefaultExcept(UUID userId, UUID keepId) {
    update("isDefault = false where userId = ?1 and isDefault = true and id <> ?2", userId, keepId);
  }
}
