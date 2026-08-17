/*
 * The application policies for Prudent's tables, and the ordering fact that forces them to live
 * here rather than in the versioned migration that enabled RLS.
 *
 * ============================================================================================
 * WHY THIS IS REPEATABLE (R__) AND NOT PART OF V20260817090000__prudent_init.sql
 * ============================================================================================
 *
 * The policies below are granted TO zen_runtime. That role is created by zen-identity's
 * R__identity_application_role.sql, which is itself REPEATABLE -- and Flyway runs every repeatable
 * AFTER every versioned migration. So on a fresh database the order is:
 *
 *     V1, V2, ... V20260817090000 (Prudent's tables + RLS)     <- versioned, first
 *     R__identity_application_role  (CREATE ROLE zen_runtime)  <- repeatables, after
 *     R__prudent_row_level_security (these policies)
 *
 * A CREATE POLICY ... TO zen_runtime inside the versioned migration would therefore reference a
 * role that DOES NOT EXIST YET, and the migration would fail outright on any fresh database --
 * including every @QuarkusTest run, which provisions one per run. Prudent's ADR-002 says "every new
 * table ships RLS and a zen_runtime policy in the same migration"; the intent of that rule is that
 * the two never ship in separate RELEASES, and it is honoured here by both files landing together.
 * The mechanism had to change because the role's own migration is repeatable. This is recorded as
 * a Prudent ADR rather than left as a silent divergence.
 *
 * Repeatables are keyed by DESCRIPTION rather than version, so the name carries the owning module
 * (prudent_) the way a version band otherwise would. ../jZen/server/zen-jobs/.../
 * R__jobs_row_level_security.sql and its zen-ratelimit twin are the pattern this follows.
 *
 * ============================================================================================
 * THE POLICY IS NOT OPTIONAL, AND ITS ABSENCE DOES NOT RAISE
 * ============================================================================================
 *
 * This is the trap worth naming rather than rediscovering. Once the application connects as
 * zen_runtime it is no longer the table owner, so RLS applies to it. Enabling RLS with no policy
 * for that role makes every SELECT return ZERO ROWS -- not an error. Prudent would show every user
 * an empty account list, an empty record list and no categories, report success on every request,
 * and log nothing. A smoke test that only checks for the absence of errors passes.
 *
 * PrudentRowLevelSecurityTest reads a row back THROUGH a zen_runtime connection for exactly this
 * reason: asserting that an insert did not throw proves nothing here.
 *
 * ============================================================================================
 * WHAT THESE POLICIES DO AND DO NOT DO
 * ============================================================================================
 *
 * They are USING (true) WITH CHECK (true) -- they permit the application everything. That is not a
 * weakness, it is the correct scope, and jZen ADR-031 settles the reasoning: RLS here exists to
 * constrain PostgREST's anon/authenticated roles, whose identity Postgres genuinely knows per
 * request. It is NOT the application's authorization. Prudent reaches Postgres over a pooled JDBC
 * connection carrying no Supabase JWT claim, so auth.uid() is NULL on that path and any policy
 * written in terms of it would match nothing and return zero rows.
 *
 * PER-USER SCOPING IS ENFORCED IN THE QUERIES, not here -- every lookup filters on the
 * authenticated user's id as part of the lookup itself. Do not be tempted to "strengthen" these
 * policies with a user predicate: there is no request-scoped user identity on this connection to
 * write one against.
 *
 * NO FORCE ROW LEVEL SECURITY, for the owner-bypass reason in the versioned migration.
 *
 * Every statement below is idempotent, which is the obligation a repeatable carries: this file
 * re-runs whenever its checksum changes.
 */

DO $$
DECLARE
    target_table text;
BEGIN
    /*
     * Guarded on the role existing rather than assuming it. Prudent depends on zen-identity today,
     * so zen_runtime will be there -- but a guard STATES the dependency instead of resting on
     * alphabetical luck (identity_ does precede prudent_, and that is not a thing to rely on).
     *
     * The NOTICE branch matters: without it, a database where the role is missing would get RLS
     * with no policy and read empty forever, which is the exact silent failure this file exists to
     * prevent. A notice in the boot log is the only warning available at this point.
     */
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zen_runtime') THEN
        RAISE NOTICE
            'No zen_runtime role; Prudent tables have RLS and no application policy yet. '
            'If the application connects as a non-owner in this state it will read ZERO ROWS '
            'from every table without raising.';
        RETURN;
    END IF;

    FOREACH target_table IN ARRAY ARRAY[
        'prudent_account',
        'prudent_account_balance',
        'prudent_category',
        'prudent_record',
        'prudent_settings'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE tablename = target_table
              AND policyname = target_table || '_application'
        ) THEN
            EXECUTE format(
                'CREATE POLICY %I ON %I FOR ALL TO zen_runtime USING (true) WITH CHECK (true)',
                target_table || '_application', target_table);
        END IF;
    END LOOP;
END $$;
