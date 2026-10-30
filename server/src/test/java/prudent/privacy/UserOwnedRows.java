package prudent.privacy;

import io.quarkus.narayana.jta.QuarkusTransaction;
import jakarta.persistence.EntityManager;
import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Reads, through the schema itself, which tables hold a person's rows and how many they hold — so
 * a privacy suite finds a table nobody remembered to add to the export or the eraser.
 *
 * <p>A table name cannot be a bind parameter, so {@link #rowsOf} puts it into the statement text.
 * The name comes from {@code information_schema}, never from a request, but it is still checked
 * against the shape of a Prudent table name and quoted: a table whose name fails that check stops
 * the suite loudly instead of becoming part of a query.
 */
final class UserOwnedRows {

  private static final Pattern IDENTIFIER = Pattern.compile("[a-z][a-z0-9_]*");

  private UserOwnedRows() {}

  /** Every table in the public schema that has a {@code user_id} column. */
  static List<String> tables(EntityManager entityManager) {
    @SuppressWarnings("unchecked")
    List<String> tables =
        QuarkusTransaction.requiringNew()
            .call(
                () ->
                    entityManager
                        .createNativeQuery(
                            "select table_name from information_schema.columns"
                                + " where table_schema = 'public' and column_name = 'user_id'"
                                + " order by table_name")
                        .getResultList());
    return tables;
  }

  /** How many rows of {@code table} belong to {@code userId}. */
  static long rowsOf(EntityManager entityManager, String table, String userId) {
    if (!IDENTIFIER.matcher(table).matches()) {
      throw new IllegalArgumentException("not a table name this suite will query: " + table);
    }
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                ((Number)
                        entityManager
                            .createNativeQuery(
                                "select count(*) from \"" + table + "\" where user_id = ?1")
                            .setParameter(1, UUID.fromString(userId))
                            .getSingleResult())
                    .longValue());
  }

  /** The rows {@code userId} owns, summed over every user-owned table. */
  static long totalRows(EntityManager entityManager, String userId) {
    return tables(entityManager).stream()
        .mapToLong(table -> rowsOf(entityManager, table, userId))
        .sum();
  }
}
