/*
 * Prudent's schema: accounts (and the currencies each holds), categories, records, settings.
 *
 * VERSION IS A UTC TIMESTAMP, not a number from a reserved band (docs/DECISIONS.md ADR-002).
 * zen-identity ships its own migrations to this same db/migration classpath location and they run
 * into THIS database, so two independent authors are numbering against one schema history. A band
 * prevents collisions but cannot guarantee a new migration sorts ABOVE everything already applied,
 * and Flyway answers an out-of-order migration by refusing to start the application. A timestamp
 * gives both properties by construction and cannot be got wrong by omission.
 *
 * THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS. Flyway checksums the whole file, so
 * fixing a typo in this header stops every database that already ran it from booting. Corrections
 * go in a new migration.
 *
 * NO FOREIGN KEY TO SUPABASE'S auth.users, anywhere below. The Dev Services database every
 * @QuarkusTest runs against is plain PostgreSQL with no auth schema, and Supabase owns that table's
 * lifecycle regardless. zen-identity's own users table has no such FK for exactly this reason; see
 * ../jZen/docs/architecture/BLUEPRINT.md, "Reconciling with Supabase auth.users".
 *
 * WHY user_id IS NOT A FOREIGN KEY TO public.users EITHER. It could be, and it is deliberately not:
 * zen-identity owns that table and its retention job deletes from it, so an FK here would make a
 * framework-owned deletion fail on application-owned rows the framework knows nothing about. The
 * ownership column is enforced by every query instead, which is where it has to be enforced anyway.
 *
 * ROW-LEVEL SECURITY IS ENABLED BELOW AND THE POLICIES ARE NOT HERE. That split is required rather
 * than stylistic, and R__prudent_row_level_security.sql explains it at the point where someone
 * would otherwise "fix" it by moving them back.
 */

-- ---------------------------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------------------------
CREATE TABLE prudent_account (
    id                  UUID        PRIMARY KEY,
    user_id             UUID        NOT NULL,
    name                TEXT        NOT NULL,
    -- The enum NAME, not its ordinal. An ordinal is a position in a Java source file: adding a
    -- constant in the middle would silently re-label every existing row, and nothing would fail at
    -- the point of the mistake. Deliberately NOT a Postgres ENUM type -- adding a value to one is
    -- a DDL migration in every environment, and the set is the application's to decide.
    kind                TEXT        NOT NULL,
    is_default          BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    include_in_total    BOOLEAN     NOT NULL DEFAULT TRUE,
    include_in_overview BOOLEAN     NOT NULL DEFAULT TRUE
);

CREATE INDEX prudent_account_user_idx ON prudent_account (user_id);

/*
 * The currencies an account holds, one row each (ADR-008: an account holds several currencies at
 * once). Money is an INTEGER COUNT OF MINOR UNITS -- 1234 is 12.34 PLN -- never a float: binary
 * floating point cannot represent 0.10, and an expense tracker sums thousands of values.
 *
 * NO FX ANYWHERE. These balances are independent, nothing converts between them, and summing
 * across them is refused rather than done at a rate nobody chose.
 */
CREATE TABLE prudent_account_balance (
    account_id   UUID     NOT NULL REFERENCES prudent_account (id) ON DELETE CASCADE,
    currency     CHAR(3)  NOT NULL,
    amount_minor BIGINT   NOT NULL,
    -- The @OrderColumn backing the declared order of an account's currencies. The client renders
    -- the order the server sent, so it is stored rather than left to whatever order rows return in.
    position     INTEGER  NOT NULL,
    PRIMARY KEY (account_id, position),
    -- At most one balance per currency per account, enforced here rather than only by the
    -- validator above it: a duplicate would silently split one currency's money across two rows,
    -- and every total computed from them would be wrong without being obviously wrong.
    CONSTRAINT prudent_account_balance_unique_currency UNIQUE (account_id, currency)
);

-- ---------------------------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------------------------
CREATE TABLE prudent_category (
    id          UUID   PRIMARY KEY,
    user_id     UUID   NOT NULL,
    title       TEXT   NOT NULL,
    -- A STABLE KEY, never an icon code point. Flutter's --tree-shake-icons only works when every
    -- IconData constant is statically known, and building one from a number the server sent
    -- defeats it -- the whole Material icon font then ships in every bundle on every platform.
    -- Validated against a known set server-side (prudent.category.IconKeys).
    icon_key    TEXT   NOT NULL,
    description TEXT   NOT NULL DEFAULT '',
    -- BIGINT, not INTEGER, because the wire type is uint32: a colour with a non-zero alpha exceeds
    -- INTEGER's range and a signed column would store it as a negative number that reads as
    -- corruption in any SQL client.
    color_argb  BIGINT NOT NULL
);

CREATE INDEX prudent_category_user_idx ON prudent_category (user_id);

-- ---------------------------------------------------------------------------------------------
-- Records
-- ---------------------------------------------------------------------------------------------
CREATE TABLE prudent_record (
    id           UUID    PRIMARY KEY,
    user_id      UUID    NOT NULL,
    title        TEXT    NOT NULL,
    amount_minor BIGINT  NOT NULL,
    -- Which of the owning account's currencies this record is denominated in. The server rejects a
    -- currency the account does not hold -- a refusal rather than an unsayable state, which is the
    -- price of multi-currency accounts (ADR-008).
    currency     CHAR(3) NOT NULL,
    -- A CIVIL DATE, not an instant. A purchase happens on a calendar day; an epoch timestamp would
    -- force every reader to pick a timezone, and at a daylight-saving boundary a record would shift
    -- a day -- at a month edge, into the wrong month, which in a budget app is a wrong total.
    -- Named record_date because DATE is reserved enough to be a nuisance unquoted.
    record_date  DATE    NOT NULL,
    category_id  UUID    NOT NULL REFERENCES prudent_category (id),
    -- REQUIRED. A record with no account is money that left no account, and a balance computed over
    -- such records is arithmetic with a hole in it.
    account_id   UUID    NOT NULL REFERENCES prudent_account (id)
);

/*
 * NO ON DELETE CASCADE on either reference above, deliberately, and it is the delete SEMANTICS
 * decision made structural: deleting an account or category that still has records is REFUSED at
 * 409 rather than silently taking the records with it. The same reasoning ADR-008 applies to
 * dropping a currency that has records -- it would orphan money that left an account no longer
 * admitting it exists -- applies identically here, so it gets the identical answer rather than a
 * second philosophy. The database enforces it as a last resort; the resource refuses first, with a
 * message a user can act on.
 *
 * Deletes are HARD. A soft delete would let Phase 4's analytics still read the rows, which is
 * exactly the problem: a user who deletes a mistyped 5,000 PLN entry and still sees it in a total
 * is looking at a wrong number that looks right -- the class of defect the integer money type
 * exists to prevent. A soft delete the product gives no way to undo is a table that grows.
 */
CREATE INDEX prudent_record_user_idx ON prudent_record (user_id);
CREATE INDEX prudent_record_account_idx ON prudent_record (account_id);
CREATE INDEX prudent_record_category_idx ON prudent_record (category_id);

-- ---------------------------------------------------------------------------------------------
-- Settings -- one row per user
-- ---------------------------------------------------------------------------------------------
/*
 * user_id IS the primary key. A separate id column would make "two settings rows for one user" a
 * representable state that something would then have to be trusted not to create; the schema
 * refuses it instead. The URL carries no id for the matching reason -- on a singleton the token is
 * the entire addressing scheme.
 *
 * main_currency is a LABEL, NEVER A CONVERSION TARGET (ADR-009). NOT NULL because the empty string
 * that means "reset to the default" on a request is resolved before it is ever written, which is
 * what lets a GET promise it never answers with an empty currency.
 */
CREATE TABLE prudent_settings (
    user_id       UUID    PRIMARY KEY,
    main_currency CHAR(3) NOT NULL
);

-- ---------------------------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------------------------
/*
 * A TABLE CREATED IN public IS EXPOSED TO THE SUPABASE DATA API UNTIL SOMETHING SAYS OTHERWISE.
 * PostgREST serves the public schema to anyone holding the project's anon key -- a key Supabase
 * publishes on purpose and treats as public -- and Supabase's default privileges grant anon and
 * authenticated full DML on tables created there. So a migration that adds a table and stops is a
 * migration that publishes it, and nothing in the build, the suite or the application says so.
 *
 * On THESE tables that is every user's complete financial history, readable and writable by anyone
 * who asks.
 *
 * NO FORCE ROW LEVEL SECURITY, deliberately: the table owner must keep bypassing. Migrations run as
 * the owner, and forcing would let this file lock the schema out of its own tables.
 *
 * THE POLICIES THAT MAKE THIS SAFE FOR THE APPLICATION ARE IN R__prudent_row_level_security.sql,
 * and they cannot be here. Read that file before concluding this one is incomplete.
 */
ALTER TABLE prudent_account         ENABLE ROW LEVEL SECURITY;
ALTER TABLE prudent_account_balance ENABLE ROW LEVEL SECURITY;
ALTER TABLE prudent_category        ENABLE ROW LEVEL SECURITY;
ALTER TABLE prudent_record          ENABLE ROW LEVEL SECURITY;
ALTER TABLE prudent_settings        ENABLE ROW LEVEL SECURITY;
