-- Envelope allocation history (M4, jlogicsoftware/prudent#64, ADR-050).
--
-- AN ENVELOPE IS NOT A COLUMN. The money set aside for a goal is the sum of the entries below that
-- put money in, less the entries that took it out, calculated on every read. There is no stored
-- balance to drift away from the history, and no second place to keep right.
--
-- A NEW TABLE, for the reason prudent_goal gives: an allocation is money RESERVED, not money that
-- moved, so it must not be able to reach a bank balance or an analytics total. It is never a
-- prudent_record and nothing that sums records reads this table.
--
-- THE ROWS ARE IMMUTABLE. An entry says what happened and is never rewritten: a mistake is corrected
-- by another entry (a withdrawal or a move). The application has no update or delete route, and the
-- trigger below refuses an UPDATE from any writer, so the guarantee does not rest on the resource
-- alone. DELETE is deliberately not blocked: the retention cascade for an anonymised user must be
-- able to remove a person's history, and erasure outranks the history's own never-deleted rule (see
-- ADR-046 for the same reasoning about resets).
--
-- created_by is the authenticated caller, which is user_id today because only the owner can write
-- here. It is a column anyway, for the reason prudent_budget_carry_reset gives.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

-- Lets an allocation reference a goal TOGETHER WITH ITS CURRENCY, so the database itself refuses an
-- entry whose currency is not its goal's -- including the second goal of a move. A goal's currency
-- never changes (ADR-049), so the pair is as stable as the id.
ALTER TABLE prudent_goal ADD CONSTRAINT prudent_goal_id_currency_unique UNIQUE (id, currency);

CREATE TABLE prudent_goal_allocation (
    id              UUID         PRIMARY KEY,
    user_id         UUID         NOT NULL,
    -- Persisted by NAME (see prudent.goal.GoalAllocationKind); the CHECK below lists the kinds the
    -- application may write, so a typo in a future writer is refused rather than stored.
    kind            TEXT         NOT NULL,
    -- The goal money left (WITHDRAW, MOVE) and the goal money entered (ALLOCATE, MOVE). NO ON
    -- DELETE CASCADE: a goal is never deleted through the API (ADR-049), and this is the last-resort
    -- backstop behind that, so history is never removed as a side effect of removing a goal.
    source_goal_id  UUID,
    target_goal_id  UUID,
    -- The currency of every goal the entry names; the composite keys below tie it to each of them.
    currency        CHAR(3)      NOT NULL,
    -- POSITIVE minor units. The direction is the kind, not the sign.
    amount_minor    BIGINT       NOT NULL,
    note            TEXT         NOT NULL DEFAULT '',
    created_at      TIMESTAMPTZ  NOT NULL,
    created_by      UUID         NOT NULL,

    CONSTRAINT prudent_goal_allocation_source_fk
        FOREIGN KEY (source_goal_id, currency) REFERENCES prudent_goal (id, currency),
    CONSTRAINT prudent_goal_allocation_target_fk
        FOREIGN KEY (target_goal_id, currency) REFERENCES prudent_goal (id, currency),
    CONSTRAINT prudent_goal_allocation_kind_known CHECK (kind IN ('ALLOCATE', 'WITHDRAW', 'MOVE')),
    -- Which goals an entry names follows from what it did. A MOVE to itself would be an entry that
    -- moved nothing, so it is refused here as well as by the resource.
    CONSTRAINT prudent_goal_allocation_shape CHECK (
        (kind = 'ALLOCATE' AND target_goal_id IS NOT NULL AND source_goal_id IS NULL)
        OR (kind = 'WITHDRAW' AND source_goal_id IS NOT NULL AND target_goal_id IS NULL)
        OR (kind = 'MOVE' AND source_goal_id IS NOT NULL AND target_goal_id IS NOT NULL
            AND source_goal_id <> target_goal_id)
    ),
    CONSTRAINT prudent_goal_allocation_amount_positive CHECK (amount_minor > 0),
    CONSTRAINT prudent_goal_allocation_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT prudent_goal_allocation_note_length CHECK (char_length(note) <= 500)
);

-- The history is the caller's entries newest first; an envelope is read through either side.
CREATE INDEX prudent_goal_allocation_user_idx ON prudent_goal_allocation (user_id, created_at DESC);
CREATE INDEX prudent_goal_allocation_source_idx ON prudent_goal_allocation (source_goal_id)
    WHERE source_goal_id IS NOT NULL;
CREATE INDEX prudent_goal_allocation_target_idx ON prudent_goal_allocation (target_goal_id)
    WHERE target_goal_id IS NOT NULL;

CREATE FUNCTION prudent_goal_allocation_refuse_update() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'prudent_goal_allocation is an append-only history: entry % cannot be changed',
        OLD.id
        USING ERRCODE = 'restrict_violation';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prudent_goal_allocation_immutable
    BEFORE UPDATE ON prudent_goal_allocation
    FOR EACH ROW EXECUTE FUNCTION prudent_goal_allocation_refuse_update();

-- See the init migration: a table in public is exposed to the Supabase Data API until RLS says
-- otherwise. The zen_runtime policy is in R__prudent_row_level_security.sql, which lists this table
-- in the same change.
ALTER TABLE prudent_goal_allocation ENABLE ROW LEVEL SECURITY;
