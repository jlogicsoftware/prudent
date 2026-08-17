package prudent.server.settings;

import org.mapstruct.Mapper;
import prudent.proto.v1.Settings;

/**
 * Maps {@link SettingsEntity} to its wire {@link Settings} proto.
 *
 * <p><strong>No {@code @Mapping} and no view record here, unlike the other three mappers.</strong>
 * The message has one field and it needs no conversion, so the view indirection would be structure
 * standing in for work that does not exist. It is still a MapStruct {@code @Mapper} rather than a
 * plain CDI bean so that the four resources inject their mapper the same way — a reader who has
 * seen one knows where to look for the others, and the day this message grows a second field the
 * mapper is already in the right shape to gain a view.
 *
 * <p>Entity → proto only, for the reason given on {@link prudent.server.category.CategoryMapper}.
 */
@Mapper(componentModel = "cdi")
public abstract class SettingsMapper {

  /**
   * Assembles the immutable {@link Settings} proto.
   *
   * <p><strong>A response never carries an empty {@code main_currency}.</strong> proto3 has no
   * presence for a string, so {@code ""} and "unset" are the same bytes on the wire; rather than
   * leave a client to guess which it received, the default is resolved here as the last line of
   * defence. The column is {@code NOT NULL} and the resource resolves the default before writing,
   * so this branch should be unreachable — it is kept because "should be unreachable" and "is
   * unreachable" differ by one future migration, and the cost of being wrong is a client rendering
   * a blank currency label with no error anywhere.
   */
  public Settings toProto(SettingsEntity entity) {
    if (entity == null) {
      return Settings.getDefaultInstance();
    }
    String currency =
        entity.mainCurrency == null || entity.mainCurrency.isBlank()
            ? SettingsEntity.DEFAULT_MAIN_CURRENCY
            : entity.mainCurrency;
    return Settings.newBuilder().setMainCurrency(currency).build();
  }
}
