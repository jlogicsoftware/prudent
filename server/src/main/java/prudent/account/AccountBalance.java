package prudent.account;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;

/**
 * One currency an account holds, and how much of it — a row of {@code prudent_account_balance}.
 *
 * <p><strong>Money is an integer count of minor units</strong> ({@code 1234} is 12.34 PLN), never a
 * float and never a {@code double}. Binary floating point cannot represent 0.10, and an expense
 * tracker sums thousands of values; a balance wrong by cents is wrong. {@code BIGINT} is exact
 * under addition and needs no decimal library on either side of the wire.
 *
 * <p>An {@code @Embeddable} rather than an entity: a balance has no identity of its own and no life
 * outside the account that owns it.
 */
@Embeddable
public class AccountBalance {

  /**
   * ISO-4217 alphabetic code, stored as {@code CHAR(3)} and always upper case — the resource
   * normalises before persisting, so "pln" and "PLN" cannot become two balances of one account.
   */
  // char(3), not varchar: an ISO-4217 code is always exactly three characters, so the
  // migration fixed the width. columnDefinition keeps Hibernate's schema validation honest.
  @Column(name = "currency", nullable = false, length = 3, columnDefinition = "char(3)")
  public String currency;

  @Column(name = "amount_minor", nullable = false)
  public long amountMinor;

  /** JPA requires a no-arg constructor. */
  public AccountBalance() {}

  public AccountBalance(String currency, long amountMinor) {
    this.currency = currency;
    this.amountMinor = amountMinor;
  }
}
