-- Carry-over resets and their audit history (M3, jlogicsoftware/prudent#61, ADR-046).
--
-- A RESET IS A BOUNDARY, NOT AN EDIT. ADR-045 calculates a category's carry-over as a sum over every
-- earlier budgeted month; a reset row says "stop counting before this month" for one category in one
-- currency. Nothing in prudent_budget or prudent_record is touched, so no earlier budget is deleted
-- and no earlier month's own plan, actual or remaining changes.
--
-- THE ROW IS ITS OWN AUDIT ENTRY. It records who wrote it, when, what it erased (discarded_minor,
-- the carry-over into reset_month as the user saw it at that moment) and an optional note. Rows are
-- never deleted by the application: undoing a reset sets revoked_at/revoked_by on the same row, so
-- the history still shows that the reset happened and who took it back.
--
-- created_by is the authenticated caller, which is user_id today because only the owner can write
-- here. It is a column anyway: the day a second kind of writer exists, history already written
-- cannot be backfilled truthfully, so the column has to exist from the first row.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

CREATE TABLE prudent_budget_carry_reset (
    id              UUID         PRIMARY KEY,
    user_id         UUID         NOT NULL,
    -- NO ON DELETE CASCADE, as for prudent_budget: a category that still has reset history is
    -- refused at 409 by the resource, and this is the last-resort backstop behind it. History is
    -- never deleted as a side effect of deleting a category.
    category_id     UUID         NOT NULL REFERENCES prudent_category (id),
    -- The FIRST DAY of the month the reset takes effect in: carry-over INTO this month is zero.
    reset_month     DATE         NOT NULL,
    currency        CHAR(3)      NOT NULL,
    -- Signed minor units: what carry-over into reset_month was just before this reset (positive
    -- underspend, negative overspend). A snapshot of what the user chose to discard; later edits to
    -- earlier budgets or records do not rewrite it.
    discarded_minor BIGINT       NOT NULL,
    note            TEXT         NOT NULL DEFAULT '',
    created_at      TIMESTAMPTZ  NOT NULL,
    created_by      UUID         NOT NULL,
    revoked_at      TIMESTAMPTZ,
    revoked_by      UUID,

    CONSTRAINT prudent_budget_carry_reset_month_is_first CHECK (EXTRACT(DAY FROM reset_month) = 1),
    CONSTRAINT prudent_budget_carry_reset_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT prudent_budget_carry_reset_note_length CHECK (char_length(note) <= 500),
    -- A revocation names both when and by whom, or neither: half a revocation is an audit gap.
    CONSTRAINT prudent_budget_carry_reset_revocation_whole
        CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);

-- At most one LIVE reset per slot. Revoked rows stay and do not count, so a reset can be undone and
-- made again without losing either entry. The resource inserts against this index, so two requests
-- racing to reset the same slot leave one live row rather than two.
CREATE UNIQUE INDEX prudent_budget_carry_reset_live_slot
    ON prudent_budget_carry_reset (user_id, category_id, reset_month, currency)
    WHERE revoked_at IS NULL;

CREATE INDEX prudent_budget_carry_reset_category_idx ON prudent_budget_carry_reset (category_id);

-- See the init migration: a table in public is exposed to the Supabase Data API until RLS says
-- otherwise. The zen_runtime policy is in R__prudent_row_level_security.sql.
ALTER TABLE prudent_budget_carry_reset ENABLE ROW LEVEL SECURITY;
