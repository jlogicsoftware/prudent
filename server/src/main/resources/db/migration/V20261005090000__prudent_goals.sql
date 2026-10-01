-- Savings goals (M4, jlogicsoftware/prudent#38, ADR-049).
--
-- A NEW TABLE, for the reason prudent_plan and prudent_budget give: a goal is something the user
-- wants to save for, not money that moved, so it must not be able to reach a balance or an
-- analytics total. A goal is never a prudent_record and nothing that sums records reads this table.
--
-- GOALS ARE RETIRED, NEVER DELETED. The allocation history that M4's next task adds will point at a
-- goal, and a goal that could vanish would take the meaning of that history with it. So the table
-- carries a lifecycle state instead of a delete route; the retention cascade for an anonymised user
-- is the only thing that removes rows.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

CREATE TABLE prudent_goal (
    id                   UUID         PRIMARY KEY,
    user_id              UUID         NOT NULL,
    name                 TEXT         NOT NULL,
    currency             CHAR(3)      NOT NULL,
    -- POSITIVE minor units: the amount to reach, not a signed transaction amount.
    target_amount_minor  BIGINT       NOT NULL,
    -- A civil date, not an instant: "by 1 March" is a calendar day. NULL is an open-ended goal.
    target_date          DATE,
    -- Persisted by NAME (see prudent.goal.GoalStatus), so the CHECK below is the list of states the
    -- application may write and a typo in a future writer is refused rather than stored.
    status               TEXT         NOT NULL DEFAULT 'ACTIVE',
    created_at           TIMESTAMPTZ  NOT NULL,
    status_changed_at    TIMESTAMPTZ  NOT NULL,

    -- Each of these names a row that would make the arithmetic meaningless, so the database -- the
    -- one place that sees every writer -- holds them as well as the resource, as prudent_budget does.
    CONSTRAINT prudent_goal_target_positive CHECK (target_amount_minor > 0),
    CONSTRAINT prudent_goal_name_not_blank CHECK (length(btrim(name)) > 0),
    -- "pln" and "PLN" would otherwise be two currencies for one goal.
    CONSTRAINT prudent_goal_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT prudent_goal_status_known CHECK (status IN ('ACTIVE', 'COMPLETED', 'ARCHIVED'))
);

-- The list is the caller's goals in creation order, optionally narrowed to one state.
CREATE INDEX prudent_goal_user_status_idx ON prudent_goal (user_id, status, created_at);

-- A table in public is exposed to the Supabase Data API until RLS says otherwise; see the init
-- migration. The zen_runtime policy is in R__prudent_row_level_security.sql, which lists this table
-- in the same change.
ALTER TABLE prudent_goal ENABLE ROW LEVEL SECURITY;
