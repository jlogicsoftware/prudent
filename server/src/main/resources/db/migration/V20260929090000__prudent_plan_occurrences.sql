-- Generated occurrences of a plan (M2, jlogicsoftware/prudent#55, ADR-038).
--
-- An occurrence is one dated instance of a plan's recurrence rule. The rule (prudent_plan) is the
-- source of truth for WHEN; this table holds the instances that have been materialised so that
-- they can later carry their own state (planned, completed, skipped -- jlogicsoftware/prudent#56)
-- and be confirmed into a record (jlogicsoftware/prudent#57) without a second rule evaluation.
--
-- NOT prudent_record, for the reason prudent_plan gives: an occurrence is money that has not
-- moved, so it must not be a row that a balance or an analytics query could read.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

CREATE TABLE prudent_plan_occurrence (
    id              UUID PRIMARY KEY,
    user_id         UUID NOT NULL,
    -- NO ON DELETE CASCADE, as on every other reference in this schema: the resource deletes a
    -- plan's occurrences explicitly, and this is the last-resort backstop behind it.
    plan_id         UUID NOT NULL REFERENCES prudent_plan (id),
    -- A CIVIL DATE, exactly as the RecurrenceRule computes it. Zone-free by design.
    occurrence_date DATE NOT NULL,

    -- THE IDEMPOTENCY KEY. A plan has at most one occurrence on any date, so generating the same
    -- window again -- or two generators racing over it -- can only ever land on this constraint,
    -- and the writer answers it with ON CONFLICT DO NOTHING. It is held here rather than checked
    -- in Java first because a read-then-insert races: two callers both find the date missing and
    -- both insert. The database is the one place that serialises them.
    CONSTRAINT prudent_plan_occurrence_unique_date UNIQUE (plan_id, occurrence_date)
);

CREATE INDEX prudent_plan_occurrence_user_idx ON prudent_plan_occurrence (user_id);

-- A table in public is exposed to the Supabase Data API until RLS says otherwise; see the init
-- migration. The zen_runtime policy is in R__prudent_row_level_security.sql, which lists this table
-- in the same change.
ALTER TABLE prudent_plan_occurrence ENABLE ROW LEVEL SECURITY;
