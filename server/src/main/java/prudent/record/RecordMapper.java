package prudent.record;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.Named;
import prudent.proto.v1.ListRecordsResponse;
import prudent.proto.v1.Record;

/**
 * Maps {@link RecordEntity} to its wire {@link Record} proto.
 *
 * <p>Abstract class rather than interface, and entity → proto only. See
 * {@link prudent.category.CategoryMapper} for both reasons.
 */
@Mapper(componentModel = "cdi")
public abstract class RecordMapper {

  /** Flat view of the wire-relevant entity fields; MapStruct fills it in. */
  public record RecordView(
      String id,
      String title,
      long amountMinor,
      String currency,
      String date,
      String categoryId,
      String accountId) {}

  @Mapping(target = "id", source = "id", qualifiedByName = "uuidToString")
  @Mapping(target = "date", source = "date", qualifiedByName = "isoDate")
  @Mapping(target = "categoryId", source = "categoryId", qualifiedByName = "uuidToString")
  @Mapping(target = "accountId", source = "accountId", qualifiedByName = "uuidToString")
  abstract RecordView toView(RecordEntity entity);

  /** Assembles the immutable {@link Record} proto from the mapped view. */
  public Record toProto(RecordEntity entity) {
    if (entity == null) {
      return Record.getDefaultInstance();
    }
    RecordView view = toView(entity);
    return Record.newBuilder()
        .setId(view.id() != null ? view.id() : "")
        .setTitle(view.title() != null ? view.title() : "")
        .setAmountMinor(view.amountMinor())
        .setCurrency(view.currency() != null ? view.currency() : "")
        .setDate(view.date() != null ? view.date() : "")
        .setCategoryId(view.categoryId() != null ? view.categoryId() : "")
        .setAccountId(view.accountId() != null ? view.accountId() : "")
        .build();
  }

  /** The list response, in the order the entity query returned. */
  public ListRecordsResponse toListResponse(List<RecordEntity> entities) {
    ListRecordsResponse.Builder builder = ListRecordsResponse.newBuilder();
    for (RecordEntity entity : entities) {
      builder.addRecords(toProto(entity));
    }
    return builder.build();
  }

  @Named("uuidToString")
  static String uuidToString(UUID id) {
    return id == null ? null : id.toString();
  }

  /**
   * Renders the civil date as ISO-8601 {@code YYYY-MM-DD}.
   *
   * <p>{@link DateTimeFormatter#ISO_LOCAL_DATE} rather than {@code toString()}: they agree for
   * every date this application will hold, but {@code LocalDate.toString()} is documented to expand
   * to a five-digit year with a sign beyond year 9999, and a format that changes shape at an
   * arbitrary boundary is not one a wire contract should rest on.
   */
  @Named("isoDate")
  static String isoDate(LocalDate date) {
    return date == null ? null : date.format(DateTimeFormatter.ISO_LOCAL_DATE);
  }
}
