/*
 * "At most one balance per currency per account" is checked when a transaction COMMITS, not after
 * each statement (jlogicsoftware/prudent#261).
 *
 * The rows of one account are an ordered list: (account_id, position) is the primary key, and
 * replacing the list rewrites the rows position by position. When a currency moves to another
 * position -- a reorder, or a drop that shifts later currencies up -- it is briefly held by two
 * rows, until the row it left is rewritten too. An immediate constraint refuses that middle state
 * although the finished list is valid. The rule itself is unchanged: a transaction that would
 * leave a duplicate behind still fails, at its commit.
 *
 * The primary key stays immediate: no write gives two rows the same position.
 *
 * Postgres cannot make an existing unique constraint deferrable in place, so it is dropped and
 * added again under the same name, in one statement.
 */
ALTER TABLE prudent_account_balance
    DROP CONSTRAINT prudent_account_balance_unique_currency,
    ADD CONSTRAINT prudent_account_balance_unique_currency
        UNIQUE (account_id, currency) DEFERRABLE INITIALLY DEFERRED;
