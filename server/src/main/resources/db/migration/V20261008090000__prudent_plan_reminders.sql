-- Reminder settings on a plan (M5, jlogicsoftware/prudent#40, ADR-054).
--
-- TWO COLUMNS ON THE PLAN, NOT A TABLE. A plan has exactly one reminder setting, so a second table
-- would be a one-to-one join with nothing to gain (the reason prudent_plan gives for its
-- recurrence). This is a SETTING: no reminder is stored here, and nothing reads these columns to
-- move a balance or a total.
--
-- OFF BY DEFAULT, WITH NO BACKFILL. A plan that already exists was saved before the user could ask
-- for a reminder, so it gets none; switching one on is the user's act, and it is also the moment a
-- platform may ask for notification permission. The one-day lead time is only what the setting
-- holds until the user picks another.
--
-- THE SUPPORTED LEAD TIMES ARE THE APPLICATION'S TO DECIDE, so there is no CHECK listing them -- the
-- reason prudent_account.kind has none. The CHECK is structural only: a lead time is a number of
-- whole days, never negative, and bounded so that "days before" can never be a date out of range.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

ALTER TABLE prudent_plan
    ADD COLUMN reminder_enabled   BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN reminder_lead_days INTEGER NOT NULL DEFAULT 1,
    ADD CONSTRAINT prudent_plan_reminder_lead_days_range CHECK (reminder_lead_days BETWEEN 0 AND 365);
