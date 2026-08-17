package prudent.server.account;

import prudent.proto.v1.AccountType;

/**
 * What kind of account this is, as the database stores it.
 *
 * <p><strong>Why this exists beside the generated {@code AccountType}.</strong> Two reasons, and
 * the second is the load-bearing one:
 *
 * <ul>
 *   <li>The wire enum is already named {@code AccountType} and a mapper holds both in scope.
 *   <li>More importantly, a protobuf-generated enum carries constants the persistence layer must
 *       never store: {@code UNRECOGNIZED}, which protobuf synthesises for forward compatibility,
 *       and {@code ACCOUNT_TYPE_UNSPECIFIED}, which proto3 decodes every omission to. Persisting
 *       the generated enum directly would make "the client forgot the field" and "the client meant
 *       cash" storable as the same row unless something upstream refused it. This enum has no
 *       member for either, so the refusal is structural: there is no value to write.
 * </ul>
 *
 * <p>The conversion is therefore total in one direction and partial in the other, which is stated
 * here rather than discovered: every {@code AccountKind} has a wire form, and not every wire value
 * has an {@code AccountKind}.
 */
public enum AccountKind {
  CASH,
  CARD,
  CHECKING,
  SAVINGS;

  /**
   * The wire value this kind is sent as. Total — every constant maps.
   *
   * @return the generated proto enum constant
   */
  public AccountType toProto() {
    return switch (this) {
      case CASH -> AccountType.ACCOUNT_TYPE_CASH;
      case CARD -> AccountType.ACCOUNT_TYPE_CARD;
      case CHECKING -> AccountType.ACCOUNT_TYPE_CHECKING;
      case SAVINGS -> AccountType.ACCOUNT_TYPE_SAVINGS;
    };
  }

  /**
   * The kind a wire value names, or {@code null} if it names none.
   *
   * <p>Returns {@code null} rather than a default for {@code UNSPECIFIED} and {@code UNRECOGNIZED}
   * — defaulting to {@code CASH} would make a client that omitted the field indistinguishable from
   * one that meant cash, and cash is a valid answer. The caller turns the {@code null} into a
   * refusal; nothing here quietly invents an account kind.
   *
   * @param type the wire value, possibly {@code null}
   * @return the matching kind, or {@code null} when the wire value names none
   */
  public static AccountKind fromProto(AccountType type) {
    if (type == null) {
      return null;
    }
    return switch (type) {
      case ACCOUNT_TYPE_CASH -> CASH;
      case ACCOUNT_TYPE_CARD -> CARD;
      case ACCOUNT_TYPE_CHECKING -> CHECKING;
      case ACCOUNT_TYPE_SAVINGS -> SAVINGS;
      case ACCOUNT_TYPE_UNSPECIFIED, UNRECOGNIZED -> null;
    };
  }
}
