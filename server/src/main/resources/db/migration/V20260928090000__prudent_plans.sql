-- Plans and their recurrence rules (M2, jlogicsoftware/prudent#34, ADR-037).
--
-- A NEW TABLE, NOT A FLAG ON prudent_record. Balance is derived from prudent_record (ADR-014) and
-- analytics reads the same rows, so a planned row living there would move the balance and the
-- spend totals before anything happened -- and every existing query would need a new exclusion to
-- stop it, with the one that forgot being silently wrong. A separate table cannot leak into either.
--
-- The recurrence is stored as columns on the plan rather than as a child table: a plan has exactly
-- one rule, so a second table would be a one-to-one join with nothing to gain.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

CREATE TABLE prudent_plan (
    id                  UUID    PRIMARY KEY,
    user_id             UUID    NOT NULL,
    title               TEXT    NOT NULL,
    -- SIGNED minor units, exactly as prudent_record.amount_minor: negative is planned spending,
    -- positive planned income.
    amount_minor        BIGINT  NOT NULL,
    currency            CHAR(3) NOT NULL,
    -- NO ON DELETE CASCADE on either reference, for the reason the init migration gives for
    -- prudent_record: deleting an account or category that plans still point at is REFUSED at 409
    -- by the resource, and this is the last-resort backstop behind it.
    account_id          UUID    NOT NULL REFERENCES prudent_account (id),
    category_id         UUID    NOT NULL REFERENCES prudent_category (id),
    payee               TEXT,
    note                TEXT,

    -- The enum NAME (ONCE, DAILY, WEEKLY, MONTHLY, YEARLY), with no CHECK listing them, for the
    -- reason the init migration gives for prudent_account.kind: the set is the application's to
    -- decide, and widening a CHECK is a DDL migration in every environment.
    frequency           TEXT    NOT NULL,
    -- "interval" is a Postgres type name; the prefix keeps it unquoted everywhere.
    recurrence_interval INTEGER NOT NULL,
    -- The first occurrence and the anchor every later one is computed from. A CIVIL DATE.
    start_date          DATE    NOT NULL,
    -- An IANA zone id. Decides which calendar day is "today" for the plan -- not when a date is.
    time_zone           TEXT    NOT NULL,
    -- The end condition: at most one of these two. Both null means the plan never ends.
    until_date          DATE,
    occurrence_count    INTEGER,

    /*
     * The structural invariants of a recurrence rule, held here as well as in the resource. These
     * are not duplicated validation for its own sake: each one names a row the date arithmetic
     * cannot give a single answer for -- two end conditions that disagree, an interval that never
     * advances, an end before the beginning -- so a row that breaks one is corrupt rather than
     * merely unusual, and the database is the one place that sees every writer.
     */
    CONSTRAINT prudent_plan_interval_positive CHECK (recurrence_interval BETWEEN 1 AND 1000),
    CONSTRAINT prudent_plan_count_positive CHECK (occurrence_count IS NULL OR occurrence_count BETWEEN 1 AND 10000),
    CONSTRAINT prudent_plan_single_end CHECK (until_date IS NULL OR occurrence_count IS NULL),
    CONSTRAINT prudent_plan_until_not_before_start CHECK (until_date IS NULL OR until_date >= start_date),
    -- A one-off plan has one occurrence by definition, so an interval or an end condition on it
    -- would be a second, contradictory statement of the same fact.
    CONSTRAINT prudent_plan_once_is_single CHECK (
        frequency <> 'ONCE'
        OR (recurrence_interval = 1 AND until_date IS NULL AND occurrence_count IS NULL))
);

CREATE INDEX prudent_plan_user_idx ON prudent_plan (user_id);
CREATE INDEX prudent_plan_account_idx ON prudent_plan (account_id);
CREATE INDEX prudent_plan_category_idx ON prudent_plan (category_id);

-- A table in public is exposed to the Supabase Data API until RLS says otherwise; see the init
-- migration. The zen_runtime policy is in R__prudent_row_level_security.sql, which lists this table
-- in the same change.
ALTER TABLE prudent_plan ENABLE ROW LEVEL SECURITY;
