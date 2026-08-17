package prudent.server.account;

import java.util.List;
import java.util.UUID;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.Named;
import prudent.proto.v1.Account;
import prudent.proto.v1.AccountType;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.ListAccountsResponse;

/**
 * Maps {@link AccountEntity} to its wire {@link Account} proto.
 *
 * <p>Abstract class rather than interface, and entity → proto only. See
 * {@link prudent.server.category.CategoryMapper} for both reasons — in particular why no reverse
 * mapping is generated, which is that it would be exactly the method able to write a
 * client-supplied owner.
 */
@Mapper(componentModel = "cdi")
public abstract class AccountMapper {

  /**
   * Flat view of the wire-relevant entity fields; MapStruct fills it in.
   *
   * <p>{@code balances} is deliberately absent: a repeated proto field is populated with
   * {@code addAllBalances} rather than a setter, so it is assembled in {@link #toProto} alongside
   * the rest of the builder.
   */
  public record AccountView(
      String id,
      String name,
      boolean isDefault,
      boolean isActive,
      boolean includeInTotal,
      boolean includeInOverview) {}

  @Mapping(target = "id", source = "id", qualifiedByName = "uuidToString")
  abstract AccountView toView(AccountEntity entity);

  /** Assembles the immutable {@link Account} proto from the mapped view. */
  public Account toProto(AccountEntity entity) {
    if (entity == null) {
      return Account.getDefaultInstance();
    }
    AccountView view = toView(entity);
    Account.Builder builder =
        Account.newBuilder()
            .setId(view.id() != null ? view.id() : "")
            .setName(view.name() != null ? view.name() : "")
            .setIsDefault(view.isDefault())
            .setIsActive(view.isActive())
            .setIncludeInTotal(view.includeInTotal())
            .setIncludeInOverview(view.includeInOverview());

    // The kind is mapped through AccountKind rather than by name, because the entity enum
    // deliberately has no member for UNSPECIFIED or UNRECOGNIZED. A null kind cannot be persisted,
    // so this branch is unreachable through the resources; it answers with the proto's own zero
    // value rather than throwing, because a mapper is not where a data defect should first surface.
    builder.setType(
        entity.kind != null ? entity.kind.toProto() : AccountType.ACCOUNT_TYPE_UNSPECIFIED);

    // Order is preserved from the entity's @OrderColumn: the client renders the order the server
    // sent, so a list that reshuffled between requests would read as data changing.
    for (AccountBalance balance : entity.balances) {
      builder.addBalances(
          CurrencyBalance.newBuilder()
              .setCurrency(balance.currency != null ? balance.currency : "")
              .setAmountMinor(balance.amountMinor)
              .build());
    }
    return builder.build();
  }

  /** The list response, in the order the entity query returned. */
  public ListAccountsResponse toListResponse(List<AccountEntity> entities) {
    ListAccountsResponse.Builder builder = ListAccountsResponse.newBuilder();
    for (AccountEntity entity : entities) {
      builder.addAccounts(toProto(entity));
    }
    return builder.build();
  }

  @Named("uuidToString")
  static String uuidToString(UUID id) {
    return id == null ? null : id.toString();
  }
}
