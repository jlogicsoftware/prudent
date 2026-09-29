-- Monthly category budgets (M3, jlogicsoftware/prudent#36, ADR-043).
--
-- A NEW TABLE, for the reason prudent_plan gives (V20260928090000): a budget is an amount the user
-- may spend, not money that moved, so it must not be able to reach a balance or an analytics total.
-- A budget is never a prudent_record and nothing that sums records reads this table.
--
-- ONE AMOUNT PER SLOT. A slot is (user, category, month, currency), and the unique constraint below
-- is the guarantee -- not the resource, which upserts against it, so two requests racing to fill an
-- empty slot leave one row rather than two.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

CREATE TABLE prudent_budget (
    -- Not on the wire (a budget is addressed by its slot). It exists so a later audit trail can
    -- point at a row that survives an amount edit.
    id           UUID     PRIMARY KEY,
    user_id      UUID     NOT NULL,
    -- NO ON DELETE CASCADE, for the reason the init migration gives for prudent_record: deleting a
    -- category that budgets still point at is REFUSED at 409 by the resource, and this is the
    -- last-resort backstop behind it.
    category_id  UUID     NOT NULL REFERENCES prudent_category (id),
    -- The FIRST DAY of the month. A civil date rather than a text "YYYY-MM" so a range of months is
    -- a range of dates, and the CHECK below keeps two spellings of one month from being two slots.
    budget_month DATE     NOT NULL,
    currency     CHAR(3)  NOT NULL,
    -- POSITIVE minor units: what may be spent, not a signed transaction amount.
    amount_minor BIGINT   NOT NULL,

    CONSTRAINT prudent_budget_unique_slot UNIQUE (user_id, category_id, budget_month, currency),
    -- Each of these names a row that would make the slot ambiguous or the arithmetic meaningless,
    -- so the database is the one place that sees every writer -- the reason prudent_plan holds its
    -- structural invariants here as well as in the resource.
    CONSTRAINT prudent_budget_amount_positive CHECK (amount_minor > 0),
    CONSTRAINT prudent_budget_month_is_first CHECK (EXTRACT(DAY FROM budget_month) = 1),
    -- "pln" and "PLN" would otherwise be two slots for one currency.
    CONSTRAINT prudent_budget_currency_upper CHECK (currency = upper(currency))
);

CREATE INDEX prudent_budget_category_idx ON prudent_budget (category_id);

-- A table in public is exposed to the Supabase Data API until RLS says otherwise; see the init
-- migration. The zen_runtime policy is in R__prudent_row_level_security.sql, which lists this table
-- in the same change.
ALTER TABLE prudent_budget ENABLE ROW LEVEL SECURITY;
