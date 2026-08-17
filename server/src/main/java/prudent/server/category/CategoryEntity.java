package prudent.server.category;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.util.List;
import java.util.UUID;

/**
 * The {@code prudent_category} table (active-record Panache entity).
 *
 * <p>Named with an {@code Entity} suffix because the wire model generated from
 * {@code proto/prudent/v1/categories.proto} is already {@code prudent.proto.v1.Category}; see
 * {@link prudent.server.account.AccountEntity} for the full reasoning.
 *
 * <p>{@code userId} is the ownership column and never appears on the wire in either direction.
 */
@Entity
@Table(name = "prudent_category")
public class CategoryEntity extends PanacheEntityBase {

  /** Server-minted. A create request carries no id. */
  @Id public UUID id;

  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Column(nullable = false)
  public String title;

  /**
   * A STABLE KEY, never an icon code point, and this is load-bearing rather than stylistic.
   * Flutter's {@code --tree-shake-icons} only works when every {@code IconData} constant is
   * statically known, and building one from a number the server sent defeats it — the whole
   * Material icon font then ships in every bundle on every platform.
   *
   * <p>Validated against {@link IconKeys} on write, so the contract stays honest about what a
   * client can be asked to render.
   */
  @Column(name = "icon_key", nullable = false)
  public String iconKey;

  /** Free text. Unlike the account's dropped description this one is real — the form sets it. */
  @Column(nullable = false)
  public String description;

  /**
   * A colour is a value and ARGB (0xAARRGGBB) is its portable form, so it survives a user picking
   * outside today's ten-swatch palette.
   *
   * <p>Stored as {@code BIGINT} rather than {@code INTEGER} because the wire type is
   * {@code uint32}: a colour with a non-zero alpha exceeds {@link Integer#MAX_VALUE}, and a signed
   * 32-bit column would store it as a negative number that reads as garbage in any SQL client. The
   * Java field is a {@code long} for the same reason.
   */
  @Column(name = "color_argb", nullable = false)
  public long colorArgb;

  /** Every category owned by one user, in a stable order. */
  public static List<CategoryEntity> listOwnedBy(UUID userId) {
    return list("userId = ?1 order by title", userId);
  }

  /**
   * One category, but only if the caller owns it. Ownership is part of the lookup rather than a
   * check after it — a find-then-compare can be written without the compare.
   */
  public static CategoryEntity findOwned(UUID userId, UUID id) {
    return find("id = ?1 and userId = ?2", id, userId).firstResult();
  }
}
