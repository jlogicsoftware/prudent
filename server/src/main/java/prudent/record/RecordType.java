package prudent.record;

import prudent.error.PrudentException;

/**
 * The four shapes a {@link RecordEntity} can take, for the {@code type} query parameter on
 * {@code GET /api/v1/records} (jlogicsoftware/prudent#52, jlogicsoftware/prudent#53). Not
 * proto-backed — query params are a REST-layer concern in this codebase, matching
 * {@code AnalyticsResource}'s own params.
 *
 * <p>{@code EXPENSE} and {@code INCOME} reuse the exact split {@link RecordEntity#expenseRows}
 * already uses for analytics ({@code amountMinor} sign, excluding transfer legs and corrections),
 * so a record's type here never disagrees with what the analytics screens call it.
 */
enum RecordType {
  INCOME,
  EXPENSE,
  TRANSFER,
  CORRECTION;

  /**
   * Parses the query parameter's value, case-insensitively. {@code null} means the caller sent no
   * {@code type} filter, so it is returned as-is rather than rejected.
   */
  static RecordType parse(String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    try {
      return RecordType.valueOf(value.trim().toUpperCase());
    } catch (IllegalArgumentException notAType) {
      throw PrudentException.invalid(
          "'" + value + "' is not a record type. Expected income, expense, transfer, or"
              + " correction.");
    }
  }
}
