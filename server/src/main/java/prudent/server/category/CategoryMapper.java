package prudent.server.category;

import java.util.List;
import java.util.UUID;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.Named;
import prudent.proto.v1.Category;
import prudent.proto.v1.ListCategoriesResponse;

/**
 * Maps {@link CategoryEntity} to its wire {@link Category} proto, so a resource method only ever
 * names the domain model.
 *
 * <p><strong>Why this is an abstract class and not an interface.</strong> Protobuf-generated
 * messages are immutable types built through a builder, with no JavaBeans setters and no accessible
 * constructor — MapStruct cannot target one. So the mapping is split the way {@code zen-identity}'s
 * {@code IdentityMapper} splits it: MapStruct implements {@link #toView}, the field-by-field
 * conversion into a flat record it <em>can</em> populate, and the concrete {@link #toProto}
 * assembles the builder from that view. Writing it as an abstract class is what lets the two live
 * in one bean.
 *
 * <p><strong>Only entity → proto is defined.</strong> The reverse has no use: a create or update
 * request is not a category, it is a request to make one, and the fields it may set are a strict
 * subset chosen deliberately — no id, no {@code user_id}. Generating a proto → entity mapping would
 * produce exactly the method that could write a client-supplied owner, which is the defect the
 * contract is shaped to prevent. The resources apply request fields by hand for that reason.
 */
@Mapper(componentModel = "cdi")
public abstract class CategoryMapper {

  /** Flat view of the wire-relevant entity fields; MapStruct fills it in. */
  public record CategoryView(
      String id, String title, String iconKey, String description, int colorArgb) {}

  @Mapping(target = "id", source = "id", qualifiedByName = "uuidToString")
  @Mapping(target = "colorArgb", source = "colorArgb", qualifiedByName = "toUint32")
  abstract CategoryView toView(CategoryEntity entity);

  /** Assembles the immutable {@link Category} proto from the mapped view. */
  public Category toProto(CategoryEntity entity) {
    if (entity == null) {
      return Category.getDefaultInstance();
    }
    CategoryView view = toView(entity);
    return Category.newBuilder()
        .setId(view.id() != null ? view.id() : "")
        .setTitle(view.title() != null ? view.title() : "")
        .setIconKey(view.iconKey() != null ? view.iconKey() : "")
        .setDescription(view.description() != null ? view.description() : "")
        .setColorArgb(view.colorArgb())
        .build();
  }

  /** The list response, in the order the entity query returned. */
  public ListCategoriesResponse toListResponse(List<CategoryEntity> entities) {
    ListCategoriesResponse.Builder builder = ListCategoriesResponse.newBuilder();
    for (CategoryEntity entity : entities) {
      builder.addCategories(toProto(entity));
    }
    return builder.build();
  }

  @Named("uuidToString")
  static String uuidToString(UUID id) {
    return id == null ? null : id.toString();
  }

  /**
   * Narrows the stored colour to the {@code int} a proto {@code uint32} setter takes.
   *
   * <p>Not a lossy cast, despite looking like one. Protobuf represents {@code uint32} as a Java
   * {@code int} whose bit pattern <em>is</em> the unsigned value — {@code 0xFF000000} arrives as a
   * negative {@code int} and is written to the wire as 4278190080. The column is {@code BIGINT}
   * only so that the same number reads correctly in a SQL client, where a negative colour would
   * look like corruption. The cast reverses that widening exactly.
   */
  @Named("toUint32")
  static int toUint32(long colorArgb) {
    return (int) colorArgb;
  }
}
