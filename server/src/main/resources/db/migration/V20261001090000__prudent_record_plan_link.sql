-- The link from an actual transaction back to the plan occurrence it confirmed (M2,
-- jlogicsoftware/prudent#57, ADR-040).
--
-- Confirming a planned occurrence writes one prudent_record. These columns are how that record
-- remembers where it came from, and the unique index below is how the database refuses to let one
-- occurrence become two transactions.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

-- NULL for every record that was not confirmed from a plan -- all of them, before this migration.
-- NO ON DELETE CASCADE, as on every other reference in this schema: a ledger row must never vanish
-- because something it points at was removed. Deleting a plan instead detaches its records
-- (plan_id and plan_occurrence_id set to NULL) in the resource, and deleting a record reopens its
-- occurrence; this reference is the last-resort backstop behind both.
ALTER TABLE prudent_record
    ADD COLUMN plan_id            UUID REFERENCES prudent_plan (id),
    ADD COLUMN plan_occurrence_id UUID REFERENCES prudent_plan_occurrence (id),
    -- The two travel together. plan_id is derivable from the occurrence, and is stored so a list of
    -- records can say which plan each came from without a join per row; the CHECK is what stops the
    -- copy from being half-written.
    ADD CONSTRAINT prudent_record_plan_link_paired
        CHECK ((plan_id IS NULL) = (plan_occurrence_id IS NULL));

-- THE "EXACTLY ONE TRANSACTION" GUARANTEE. An occurrence has at most one record confirming it, so
-- two confirmations racing each other -- a double tap, a retried request, two devices -- can only
-- ever land on this index. The resource also serialises them by locking the occurrence row, so this
-- is the backstop for a writer that does not go through it, not the primary defence. Partial,
-- because the great majority of records have no plan and NULLs must not collide.
CREATE UNIQUE INDEX prudent_record_plan_occurrence_unique
    ON prudent_record (plan_occurrence_id)
    WHERE plan_occurrence_id IS NOT NULL;

-- Deleting a plan looks up the records it confirmed.
CREATE INDEX prudent_record_plan_idx ON prudent_record (plan_id) WHERE plan_id IS NOT NULL;
