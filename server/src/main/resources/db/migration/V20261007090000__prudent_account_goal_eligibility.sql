-- Which accounts may fund goals (M4, jlogicsoftware/prudent#65, ADR-051).
--
-- ONE FLAG ON THE ACCOUNT, and the user's own choice. An account counts toward the money a goal can
-- draw on only when this is true and the account is active; the sum of those accounts' balances in
-- a currency is that currency's eligible money, calculated on every read. Nothing here stores an
-- amount, so there is no figure to drift away from the balances behind it.
--
-- DEFAULT FALSE, with no backfill. An existing account is not drawn on until its owner says so: a
-- guess made from its type or from include_in_total would earmark money the user never offered, and
-- the cost of the opposite error is one switch.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

ALTER TABLE prudent_account
    ADD COLUMN eligible_for_goals BOOLEAN NOT NULL DEFAULT FALSE;
