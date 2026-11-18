# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository.

## What Prudent is

Prudent is a **minimalist personal-finance application** — accounts, categories, records
(transactions), an overview and analytics. It is its own product and its own git repository.

Prudent is built on **jZen**, a framework/platform for full-stack applications (Java/Quarkus
server + Dart/Flutter client + a contract in Protobuf). Prudent is jZen's *consumer*, not part of
it: jZen's libraries arrive here as declared dependencies, and no work in this repository ever
edits the jZen checkout.

**[`docs/zen-architecture.md`](docs/zen-architecture.md) is Prudent's cornerstone** — the design
philosophy this product is built on. Read it before non-trivial work. It is Prudent's own and it is
permanent: it holds whether jZen arrives as a sibling checkout, as a published package, or not at
all.

**Prudent's rules are Prudent's.** They live in `docs/` and `docs/DECISIONS.md` (Prudent's own ADR
numbering, from ADR-001). jZen's documents constrain this repository only where Prudent actually
consumes the framework — the contract, the transport seam, auth, migrations — and they are read
from the `../jZen` checkout rather than copied here, so they cannot drift.
[`docs/jzen/README.md`](docs/jzen/README.md) is the index of pointers; jZen's ADR archive
(`../jZen/docs/architecture/DECISIONS.md`) wins on conflict with jZen's other documents. Where a
jZen rule and a Prudent rule conflict on something **Prudent** owns, Prudent's wins and the
divergence is recorded as a Prudent ADR.

## Current state: Phases 0-5 have landed; a real deploy has not (deliberately)

As of 2026-08-23 the repository has a **language-neutral root over four tiers**: `client/` (the
server-connected Flutter app, whose screens now live in the shared package `packages/prudent_ui`, ADR-108), `server/` (a Quarkus backend), `admin/` (the react-admin panel),
`proto/prudent/v1/` (the wire contract), and a `Taskfile.yml` that includes jZen's. The contract,
its generate/verify loop and the round-trip suite that proves it are in place —
`task verify:contracts` (the drift gate; `task generate` regenerates without it) and
`task zen:test:client` are the commands that check them. Run the client suite through that task (or
with `--dart-define=ZEN_ENV=local --dart-define=ZEN_PLATFORM=<platform>`): a bare `flutter test` has no
`ZEN_PLATFORM`, so `popup_test.dart` skips itself and names this command instead of failing. The whole loop is consumed from jZen's
`Taskfile.app.yml`, not hand-rolled: ADR-027 (jZen #74) finished the migration ADR-007 began, and
`server/openapi.json` is no longer tracked — the admin panel's `schema.generated.ts` is the
tracked artifact the gate watches.

Built and merged: the backend (`AccountResource`, `CategoryResource`, `RecordResource`,
`SettingsResource`, `AnalyticsResource`, `HealthResource` over four Panache entities), the Flyway
migration and its row-level security, and the client rewired onto `ZenClient` with auth and the
navigation shell. Screens and providers depend on the abstract `PrudentRepository` (`packages/prudent_ui/lib/prudent_repository.dart`); `ServerPrudentRepository` (`client/lib/server_prudent_repository.dart`) is its HTTP implementation and only `main.dart` names it (ADR-105). The third-party backend call the
conversion existed to remove is gone.

**The shared package (ADR-108, unit 2 of `docs/implemented-plans/PRUDENT-LOCAL-PLAN.md`).** `packages/prudent_ui` holds every screen, view model, provider,
the money formatting, `PrudentRepository`, the notification code and the `{en, uk, pl}` ARB files with `l10n.yaml`, imported as
`package:prudent_ui/<folder>/<file>.dart`. The generated wire messages are **not** there since ADR-111: they are the pure-Dart package
`packages/prudent_proto` (`package:prudent_proto/generated/prudent/v1/<file>.pb.dart`, `PROTO_DART_OUT`), which `prudent_ui`, `client/` and
Prudent Local's store all depend on. `client/` keeps `main.dart`, `app.dart`, `app_root.dart`, `auth/`,
`ServerPrudentRepository` and the Polish identity wording, consumes the package by `path:`, and still holds **all** the tests (the package has
its own in `packages/prudent_ui/test/`). The package **must not import or depend on** `zen_transport`, `zen_identity`, `zen_ui_identity` or
`zen_secure_store` — `task verify:boundaries` check E fails when it does — so a failure's code is read with `failureCode(error)`
(`ZenError.internalData['code']`), the profile page and sign-out reach Settings as a `SettingsSession?` that `client/` provides
(`identitySettingsSession`), and a record filter's query string is `client/lib/record_filter_query.dart`. Every gate covers both packages
(`DART_ROOTS` on the include; `verify:controls` and `verify:analyze` name the package). Nothing consumes the
package but `client/` yet; `local/prudent_local_client` (ADR-101) will. Where this file says `client/lib/<folder>` for a screen, the folder
is now under `packages/prudent_ui/lib/`.

The client's overlays (add/edit account, correction, record, category, filter) all open through jZen's
`zen_ui_widgets` `showAdaptivePresentation` (ADR-041) — a sheet on native mobile, a dialog on desktop
and web — so no screen carries its own `showDialog`/`showModalBottomSheet` block. No screen
carries a raw Material button, select, switch row, segmented control or date picker either, and
`task verify:controls` (ADR-059) fails the build when one returns (see "Client UI" below).
A goal's detail, an occurrence's detail and a category's records open beside their list from 720 px of the
host's width and as a page below it (`showZenDetail`, ADR-061); so, since ADR-062
(jlogicsoftware/prudent#144), do Accounts, Categories and Profile (from Settings; Accounts also from Overview)
and the reminder centre (from the bell on Overview). Since ADR-063 (jZen at `b67a549`) each destination sits in a
`Navigator` of its own, so that page stays inside the content area and the navigation sidebar stays at every width;
a page that must cover the shell asks for `rootNavigator: true`, and switching tab discards the stack of the one left.
The chart by category is a second view of Analytics, not a screen of its own. Analytics holds its toggle, month navigator, chart and legend in one centred column of at most 720 px
(`AnalyticsColumn`, jlogicsoftware/prudent#194); the legend rows are divided and, like the bar chart's month labels, set at the
body size, which on a narrow chart thins the labels rather than the type. The app-wide cap is jlogicsoftware/prudent#195. There are still six tabs; any push
is a `ZenPageRoute`, so macOS fades rather than slides (seen in slow motion on the native macOS app, ADR-064; Chrome
on a Mac is not yet looked at, jlogicsoftware/prudent#145).

M2 (planned and recurring transactions) is under way: `PlanResource` over `PlanEntity` and
`RecurrenceRule` (ADR-037) model plans and their recurrence, separately from records;
`OccurrenceGenerator` (ADR-038) materialises a bounded window of a plan's occurrences
idempotently; and `OccurrenceResource` (ADR-039) gives each occurrence a lifecycle
(planned/completed/skipped, with overdue derived) and the `upcoming` / `overdue` views, which
generate what they read. Skip, restore and confirm are the only state changes there is a route for.
Confirmation (`POST /api/v1/occurrences/{id}/confirm`, ADR-040) is the only thing that completes
an occurrence, and it does so by creating exactly one actual record that carries `plan_id` and
`plan_occurrence_id`; deleting that record reopens the occurrence, deleting the plan detaches its
records. The overview shows planned cash flow (ADR-042) — expected income and spending per currency,
kept apart from the balances and hideable with a switch — but no client screen lists or edits plans
or occurrences; the client otherwise has only the repository methods. That completes M2's backlog;
a plans screen is new scope, not missing work.

M3 (budgets) has begun: `BudgetResource` over `BudgetEntity` (ADR-043) stores at most one positive
amount per category, month and currency, addressed by that slot at
`/api/v1/budgets/{categoryId}/{month}/{currency}`, and `GET /api/v1/budgets/summary` (ADR-044,
jlogicsoftware/prudent#59) calculates plan, actual and remaining per budgeted category for one month
and currency on each request — actual is net spending from posted ledger records, refunds included.
Carry-over (ADR-045, jlogicsoftware/prudent#60) is calculated the same way: the sum of
`plan − actual` over a category's earlier budgeted months in that currency, passing unchanged across
months with no budget and recalculating when an earlier budget or record is edited; the summary's
`remaining` includes it. A reset (ADR-046, jlogicsoftware/prudent#61) restarts one category's
carry-over in one currency from a chosen month: `BudgetCarryOverResetResource` over `BudgetCarryResetEntity` at
`/api/v1/budget-carry-over-resets` is a boundary the sum stops at, not an edit, so prior budgets and
earlier months are untouched. Every reset is an audit entry that is never deleted — who, when, the
carry-over it discarded, a note — and taking one back marks it revoked rather than removing it; the
summary names the reset behind each carry-over. Category lifecycle (ADR-047, jlogicsoftware/prudent#62):
a category that has been used is archived, not deleted — `POST /api/v1/categories/{id}/archive` and
`/restore` flip `Category.archived`; an archived category stays listed and changes no figure, and refuses
only *new* references (a record, plan or budget slot, or a confirmation, filed under it), while delete is
refused for as long as any record, plan, budget or reset points at the category. The client's monthly budget
overview (ADR-048, jlogicsoftware/prudent#63) is the "Budgets" tab: navigate months, one currency at a
time, and see plan, carry-over, spent, remaining and percentage per category and in total, with distinct
overspent and empty states. Nothing yet audits budget edits, and no client screen sets, edits or deletes
a budget or a reset — the repository methods exist, the screens do not (jlogicsoftware/prudent#35) — and
the record form no longer offers an archived category.

M4 (virtual goal envelopes) has begun: `GoalResource` over `GoalEntity` (ADR-049,
jlogicsoftware/prudent#38) stores a goal — name, currency, positive target amount, optional target date —
at `/api/v1/goals`, in one of three states (`ACTIVE`, `COMPLETED`, `ARCHIVED`) that
`/complete`, `/archive` and `/reactivate` move between. A goal is retired, never deleted: there is no
`DELETE` route, and an archived goal is read-only until reactivated. Money is set aside for a goal by
`GoalAllocationResource` over `GoalAllocationEntity` (ADR-050, jlogicsoftware/prudent#64) at
`/api/v1/goal-allocations`: `ALLOCATE`, `WITHDRAW` and `MOVE` (between goals in one currency) are each one
immutable, append-only history entry — no update or delete route, and the database refuses an `UPDATE`. A goal's
envelope has no stored amount: it is the sum of its entries, calculated on every read
(`GET /api/v1/goal-allocations/envelopes`), and it is virtual — no account balance, record or analytics total
reads it. Money goes into an active goal and comes out of an active or completed one, an entry cannot take an
envelope below zero, and a goal that still holds money cannot be archived. Eligible and free money
(ADR-051, jlogicsoftware/prudent#65): an account funds goals only when the user marks it `eligible_for_goals`
(default off) and it is active; per currency, free money is those accounts' current balances less every envelope
in that currency, calculated on every read (`GET /api/v1/goal-allocations/free-money`) and possibly negative after
a later spend, and an `ALLOCATE` above it is refused (409) — a `WITHDRAW` or `MOVE` never is. The two account forms
carry the switch. Progress and contribution guidance (ADR-052, jlogicsoftware/prudent#66) are calculated per goal
on every read at `GET /api/v1/goals/progress`: allocated, remaining (never negative), a whole percent rounded
down (so 100 means reached) and — for an active goal with money left and a target date that has not passed — the
monthly contribution rounded up over the calendar months from the as-of month through the target month, both
inclusive. A `GoalGuidance` says why a contribution is absent (not active, reached, no date, overdue); `asOf` names
today and defaults to the server's UTC date. The client's "Goals" tab (ADR-053, jlogicsoftware/prudent#67) shows
free money per currency, then active, completed or archived goals with progress and guidance; a goal opens to its
envelope history and the actions its state allows (add, withdraw, move, edit, complete, archive, reactivate).
Every envelope amount is drawn by `EnvelopeAmount` — an envelope icon on the tertiary container colour, read out as
"set aside for goals" — so it is never mistaken for an account balance. That completes M4's backlog.

An account can be deleted together with all of its transactions (ADR-081, jlogicsoftware/prudent#201):
`DELETE /api/v1/accounts/{id}?deleteRecords=true` removes the account and every record touching it —
both legs of a transfer — in one transaction, reopening any occurrence a deleted record had confirmed;
without the flag the refusal stands, and a plan still refuses either way. The client asks twice, the
second time for a typed phrase (`DeleteAccountForm`).

M5 (local reminders) has begun: a plan carries a reminder setting (ADR-054, jlogicsoftware/prudent#40) —
`Plan.reminder`, `enabled` plus `lead_days` — on `prudent_plan`. It is a setting only: nothing stores,
schedules or sends a reminder yet. It is off by default (existing plans too), the lead time is one of 0, 1, 2, 3
or 7 days and anything else is refused (400) rather than rounded, `lead_days` is kept while the reminder is off,
and `PUT` is a full replacement, so an absent `reminder` resets it. Changing it never touches a plan's
occurrences. No client screen sets it — the repository methods carry it, as they do the rest of a plan.
The in-app reminder centre (ADR-055, jlogicsoftware/prudent#68) reads it: `ReminderResource` at `/api/v1/reminders`
finds, on every read, the still-planned occurrences of a plan whose reminder is on that are within its lead time or
past their date (in the plan's own calendar day) — nothing about a reminder is stored except that the user has read
it, `prudent_plan_occurrence.reminder_read_at`. `read` / `unread` / `read-all` set it; a reminder ends when its
occurrence is confirmed or skipped. The client's bell on the overview opens the centre — overdue, then due soon, unread
said in words — and a reminder opens `OccurrenceDetailScreen`, the first client screen for an occurrence, where it can
be confirmed as planned, skipped or restored. Local-device notifications (ADR-056, jlogicsoftware/prudent#69) are
scheduled by `packages/prudent_ui/lib/notification/` on sign-in: each still-planned occurrence in the next 30 days whose plan's
reminder is on and whose reminder date is still ahead becomes one notification at 09:00 device time, with no amount in
its text, and the platform permission is asked for only when one is waiting (never at launch). It works on Android, iOS,
macOS and Windows; the web and Linux report `unsupported`. Reconciliation (ADR-057, jlogicsoftware/prudent#70) makes the pending
notifications match what the server says now — each pass schedules what is wanted and cancels what is not — on every
sign-in or launch (so after an app update too) and after a skip, restore or confirmation, a plan created, edited or
deleted through `PlanActions`, or a confirming record deleted. An unsupported platform or a refusal (ADR-058,
jlogicsoftware/prudent#71) is explained by a notice above the reminder centre's list, which still lists everything; a refusal
is remembered across launches (`shared_preferences`) so the prompt is not repeated. That completes M5's backlog. No notification
has been seen to fire on a device. With no plan screen
yet nothing in the UI switches a reminder on.

M0's health and error reporting (ADR-072, jlogicsoftware/prudent#49): `GET /api/v1/health/ready` is a readiness probe that runs
`SELECT 1` and answers 503 (`ZenError`, `unavailable`) when the database is away, beside the liveness `/api/v1/health`, which touches
nothing; `verify:deploy` checks both. Every response carries `X-Request-ID` (`RequestIdFilter`), and an unhandled server failure is
logged by `UnhandledExceptionMapper` as one line — request id, handler, exception classes, SQLSTATE, first `prudent.*` frame — never as
the exception, whose message can quote a database row. Nothing is sent to an error-tracking service and the client does not show the id.

M0's privacy task (ADR-071, jlogicsoftware/prudent#48) is built: `GET /api/v1/privacy/export` answers one `DataExport` with
every row a user owns in any lifecycle state (readable JSON, never cached), and `POST /api/v1/privacy/erase` deletes them all and
anonymises the profile in one transaction, refused unless the body repeats the account's address. The deletion is
`PrudentDataEraser`, shared with the retention observer; `PrivacyCoverageTest` derives its coverage from the database's own schema, so
a table with a `user_id` that the exporter and eraser do not know fails the suite. Settings has a "Privacy and data" detail (copy to
the clipboard, save to a file, delete). The export also carries each imported record's statement key beside the record (`record_import_keys`, ADR-110,
unit 10a), so a statement imported before a move to Prudent Local is still recognised; "Save to a file" warns first that the file is not encrypted, and is
offered on every platform through jZen's `zen_save_file` (`zenSaveFile`, jZenDev/jZen#246 fixed by PR #254, ADR-117; `JZEN_REF` `4fa887a`), and the sheet has not been seen on a real device (unit 12). `docs/privacy-policy.md` is the server-connected app's published policy (its "Save to a file" sentence is stale, jlogicsoftware/prudent#286); Prudent Local's is `docs/privacy-policy-local.md` (ADR-128). Both request routes delete the person's Supabase sign-in
record too (ADR-075, jlogicsoftware/prudent#173): `SignInRecordEraser` calls GoTrue's admin delete with `SUPABASE_SECRET_KEY`,
last in the erasure's transaction, so a refusal is a 503 with nothing erased; a dormancy-erased person keeps theirs (the operator
deletes it). `task test:e2e` proves the deletion against a real local Supabase; no deployed service has the key yet. Dormancy erasure
(ADR-073) runs: `DormancyWarningMailer` observes the framework's `AccountDeletionWarning`, sends the first and final warning
through `zen-email` (en/uk/pl, no ledger data, the recipient logged by id only) and confirms the receipt only when the relay
accepted the message, so an unwarned account never advances; `PrivacyDormancyErasureTest` drives warnings then anonymisation and
checks nothing of Prudent's remains. It needs a mail relay in every deployment (`SMTP_HOST`, `SMTP_FROM`, `SMTP_PORT` public;
`SMTP_USERNAME`, `SMTP_PASSWORD` secrets) and **has not been run against a real relay**. No deployed read of the export has been
done (#159). For a person who cannot sign in, `POST /api/v1/admin/privacy/users/{userId}/erase` (`OperatorErasureResource`, ADR-074,
jlogicsoftware/prudent#172) runs the same eraser, anonymiser and sign-in deletion for an `admin`-role session (401/403 otherwise, 404 for an id with nothing
behind it, 400 for the caller's own); it has not been run against a deployed service.

M6 (Erste Polska CSV import, epic jlogicsoftware/prudent#41) is built through its failure matrix; it began with its contract (ADR-088,
jlogicsoftware/prudent#42): `docs/erste-csv-contract.md` records the format of one real export, kept outside the
repository, with its open questions, and `server/src/test/resources/import/erste/` holds synthetic fixtures.
`task verify:import-fixtures` (CI) refuses values that cannot be synthetic and is weak by design (see its summary).
The bank's export steps are recorded in the contract (ADR-095: reported by the user from the bank's web UI on 2026-11-15, comma separator required), which completes #42.
The workflow is built (ADR-089, jlogicsoftware/prudent#72): `ImportSessionResource` at `/api/v1/import-sessions` over
`prudent.imports` parses, previews and commits as three enforced phases (`PARSED -> PREVIEWED -> COMMITTED`, plus
`DISCARDED` and `EXPIRED`), behind a `StatementImporter` boundary keyed by format id. A statement is read once and never
stored; a session keeps only normalised rows, which are deleted when it ends, and expires after 24 hours (a read ends an
overdue one at once; the hourly sweep deletes the rest). A preview can be repeated (`PREVIEWED -> PREVIEWED`) to change the
destination account, which is validated wherever it is set and again at commit: the caller's, active, holding the session's
currency, and accepted by `StatementImporter.checkDestination` against an opaque identity token (a digest the importer
produces, kept only while the session is open). Committing is real (ADR-092, jlogicsoftware/prudent#76): `LedgerImportCommitter` locks the destination account's row and writes one
ordinary record per row through `RecordWriter`, in one transaction, copying the duplicate key onto it; a repeated commit of a
committed session answers with its stored counts (`committed_written`, `committed_already_imported`), and two sessions of one file
write it once. Each row needs a category before commit: its own, or the session's default for its direction
(`POST /api/v1/import-sessions/{id}/defaults`); `POST .../rows/{rowNumber}` sets a row's category, note (500 characters) and
includes a duplicate under the next free occurrence, and answers with the row and the counts only. A session with no accepted
rows can be committed (zero written). An incoming own-account transfer becomes a plain record of the destination only and its
row carries `hint_code = transfer.own_account` (the other side must be recorded as a plain expense, never a Transfer). Statements are bounded (rows, field length, open sessions per user, list
size; `prudent.import.*`). The Erste importer exists (ADR-090, jlogicsoftware/prudent#73): `ErsteStatementImporter` registers
`erste-pl-csv`, validates the whole file against the contract before returning anything (encoding, line ending, delimiter, header,
field count, dates, decimals, currency, sequence numbers, account identity) and rejects with a rule code and bounded row
numbers, never text; a row with no known meaning is returned rejected instead. `Account` has an optional `account_number`
(normalised, unique per user; `AccountNew` and `AccountEdit` have the field), and Erste's `checkDestination` refuses an account without one
(`account.number_missing`) or with another (`account.identity_mismatch`). An own-account transfer is a row whose description is
`ErsteStatementImporter.OWN_TRANSFER_DESCRIPTION` and whose counterparty account is the other account's number. The bank's sequence
number is returned as a hint only. Duplicate detection exists (ADR-091, jlogicsoftware/prudent#75): `ImportDuplicateStage` keys each row with
`RowFingerprints` (a versioned SHA-256 of account, format, currency, date, signed amount and normalised description and
counterparty fields, plus an occurrence number for identical rows in one file), marks rows whose key a ledger record of the
destination account already holds `DUPLICATE` (`duplicate.already_imported`), and leaves the key on the import row for the
committer to copy onto `prudent_record.import_fingerprint` / `import_occurrence`, which are unique per account. The bank's
sequence number is not used as an identifier (`StatementImporter.stableExternalId()` is the switch, false for Erste). The parser has been run on the
synthetic fixtures and, locally and by counts only, on one real export; nothing has run it in a deployed service.
**No real statement is ever committed.**

The client's import flow exists (ADR-093, jlogicsoftware/prudent#74), in `packages/prudent_ui/lib/imports/`: an "Import a statement" action on the Accounts
page opens `ImportStatementScreen` (active account, CSV file through `file_selector`, upload; an account without a bank number is refused with a
button that opens `AccountEdit`, and unfinished sessions are listed to continue or discard), which is replaced by `ImportPreviewScreen`
(destination, default categories, three groups of rows with a per-row category and note, an explicit "Import anyway" switch on duplicates, rejected
rows explained and not editable, the `transfer.own_account` warning, confirm that sends the server's own accepted count, then the result). Every
server refusal is shown as a localized sentence chosen by its rule code and row numbers (`ImportFailure`, `importRuleMessage`; never the server's text,
unknown codes get a generic sentence naming the code). It is covered by widget tests over a mock server and has **been seen only in a browser, over an
in-memory stand-in for the server with synthetic rows**: not against the real server, not on a device, no native file picker, and the iOS and macOS
runners have not been built with the new plugin.
Leaving an open import by Back asks "Leave this import?" first; for an import opened as a pane's root (the case jZen#222/#224 guards, ADR-096) so do
a side pane's Close, Escape and a second detail replacing the pane. The real path is a nested page (Overview or Settings opens Accounts as the pane root and Accounts
opens the import from inside it), and since jZen#226 (PR #227, ADR-097) the pane asks every page on its stack, so Escape and a second detail ask there too; a nested page has Back and no Close button,
by jZen's design. Switching tab cannot be vetoed; the session stays open and is listed under "Unfinished imports". The guard and the whole flow have since been driven in the built app by `client/integration_test/app_import_test.dart` (macOS, and an iOS simulator; ADR-098), which CI does not run; the native file picker was seen by hand on the iOS simulator only, and the macOS panel not at all.

M6's backlog is complete in code (ADR-094, jlogicsoftware/prudent#77): a failure and drift matrix of about 220 statements (45 rule codes the client has a sentence for) (`ImportFailureCatalogue`, run by
`ImportFailureMatrixTest` through the real HTTP API) proves each malformed, structurally changed, mixed-currency, oversized, misdirected or flagged file is refused
or flagged with a rule code and bounded row numbers, quotes no statement text in an answer or a log line, and leaves every record, session, row and account of both users
as it was; `ImportCommitFailureTest` does the same for a category, account, session or phase that fails between the preview and the commit (three rule codes,
`commit.category_unavailable`, `commit.account_unavailable` and `commit.row_refused`, replace a "Row N cannot be written" that explained nothing); `ErsteFormatDriftTest` pins the
fixtures to their exact parsed rows and the contract's rules to the importer's; `ImportRuleCatalogueTest` fails when the importer's sources can emit a rule that no case
proves. A file whose amount column has moved (a positive card or BLIK row, or the column disagreeing with the card text on half or more of at least two card rows) is refused whole as `layout.amount_column`, never read through the balance column; an empty or oversized upload, too many rows and an unknown destination are rule codes too (`statement.empty_upload`, `statement.too_large`, `statement.too_many_rows`, `account.not_found`). **Never seen:** a real second export (overlap, whether the bank sequence number is stable), amounts of 1000 or more, the wording of an outgoing own-account transfer, a
real change of the bank's format, the export steps beyond what the user reported (whether a file can hold several accounts and the filters' effect on it are open), a run on a device or with the native file picker, the client against the real server, and any
Polish or Ukrainian string reviewed by a native speaker.

**Prudent Local's plan is closed in the docs, not finished:** units 0 to 11 and 13 of `docs/implemented-plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245) are built, with each
unit's PRs and ADRs in its status table; **unit 12 (real devices) is open and NOT VERIFIED**, and Prudent Local is not released before it. Unit 13 (ADR-128) wrote
Prudent Local's privacy statement, `docs/privacy-policy-local.md` (#280), and brought the README, `docs/product-roadmap.md`, `docs/zen-architecture.md` and
`docs/jzen/README.md` up to date; it found that iOS Data Protection, which ADR-100 T1 assumed, is not set on the store (#285). The plan's
closing section lists what is owed and the follow-ups (jlogicsoftware/prudent#274 to #278, #282, #285, #286, #261). What follows is the per-unit detail.

Prudent Local (jlogicsoftware/prudent#245, `docs/implemented-plans/PRUDENT-LOCAL-PLAN.md`) has its phase-0 decisions (ADR-100 to ADR-103) and unit 3
(ADR-107): `local/prudent_local_core` is pure Dart and reproduces the server's money, currency, account-number, date, month and text
rules method for method, held to the JVM by `test/golden/*.json` that `GoldenVectorsTest` writes and checks (`task golden:generate`,
`task verify:golden`, also in `test:server`); `task test:local-core` runs its tests. The parity suite runs each scenario in
`local/prudent_local_core/parity/scenarios/` through the live server and the local code (`tools/prudent_parity_server`, inside
`task test:e2e`) and compares every figure exactly. Unit 4 (ADR-111) is the store model: `local/prudent_local_store`, pure Dart on jZen's
`zen_store`, holds Local's own store messages (`proto/prudent_local/v1/store.proto`, generated by the second include `zenstore:`), ids minted
on the device or derived from natural keys (`DerivedIds`), `PrudentLocalStore` (the only write path: ids, immutable fields, write-once and
never-deleted records), jZen's `ZenMergePolicy.earliest` on the goal-status and reminder-read times and nothing else (no last-writer-wins),
`WireMapper` (presence-exact, derived figures as inputs) and the `IntegrityRunner`, whose `IntegrityCheck`s list what a merge broke across
records with actions and fix nothing; units 5–8 add checks. `task test:local-store` proves every §0.2 row through two encrypted stores
synced by `ZenFolderCloud`. A reset revoked on two devices stays a conflict (jZenDev/jZen#244). Since ADR-115 (jZen `4fa887a`) a top-level
field set to its default is stored as unset (jZenDev/jZen#245; no synced collection declares `explicitPresence`) and, since jZen `139fcd6`
(PR #259, jZenDev/jZen#255), so is a plain scalar at its default inside a nested message; the one nested `optional` field, `Plan.reminder.lead_days`
(0 is a value, the default 1 is absent), is declared with `StorePolicies.planExplicitNested` so a lead of 0 is not lost, and `merge_table_test` pins
that an explicit default inside a group agrees with an unset one (ADR-125); and every write carries its rules and the version it was decided against as the store's `expect`
(`WriteExpects.asRead`, jZenDev/jZen#251): a record a sync deleted or changed in between refuses the write (404, or 409 under §0.3 X.7)
rather than coming back or being written over. The issues reach no screen until the Local app wraps them in `zen_ui_store`'s `ZenIssueSource`
(unit 9). Unit 8a (ADR-112) is the Erste parse stage in `prudent_local_core/lib/src/imports/`: `parseErsteStatement(bytes, today:)` is
the server's upload bounds, `ErsteStatementImporter` and `ParsedStatements.validate`, and `RowFingerprints` the `v1` key byte for byte (a Local
account id is written in the server's form, so keys moved in by ADR-110 match). `test/golden/erste_import.json` holds it to every parse-stage case of
`ImportFailureCatalogue` (written by `ImportGoldenVectors`, which checks each against the catalogue first); `ImportRule` names the server's 45 codes,
5 of them for unit 8b; no statement text reaches a refusal, `toString` or log (`import_privacy_test.dart`). NFC is `unorm_dart` (with a workaround
at U+D7A4), root upper-casing the JDK's table (`tool/generate_root_upper_case.dart`). Sessions, duplicates and the commit are unit 8b's.
Unit 5 (ADR-113) is the ledger: `Ledger` in `local/prudent_local_store/lib/src/ledger/` holds every account,
category, record, transfer, correction and settings rule of §0.3 rows 5.1–5.53, wire requests in and wire messages out, refusals
shaped as the server's (`LedgerErrors`). Several records are written as one only through jZen's `ZenStore.writeAll`
(`PrudentLocalStore.writeAll(StoreBatch)`, jZenDev/jZen#232; `JZEN_REF` was then `4fa887a`), so an account deleted with its records is
all or nothing. A figure never reads a value two devices disagree about: a disputed posting, transfer or opening counts in no
balance and is named on every read that answers a balance (`Settled<T>`, `AccountBalances.unsettled`), and a correction is refused until it is settled. Search and name order are the
core's `SearchRules`, whose fold is a table from the JVM (`golden/fold.json`; the Dart VM's `toLowerCase` differs on 437 code
points). `CorrectionIntent.seen_corrections` feeds the `correction.made_apart` check. The parity suite's local side is
`StoreBackend` (`package:prudent_local_store/parity.dart`); thirteen scenarios agree with the live server. Open: the server's 500 on an account update that reorders currencies (jlogicsoftware/prudent#261).
Unit 8b (ADR-114) is statement import: `ImportWorkflow` in `local/prudent_local_store/lib/src/imports/` is the server's three phases,
destination checks, row decisions, defaults, duplicates and commit, check for check, answering the wire `ImportSession`; sessions are the
device-only collection `import_sessions` of the ledger's store (`collection(syncs: false)`, jZenDev/jZen#252), one record per session,
rows' text kept as bytes (Dart's UTF-8 decoder drops a leading U+FEFF, `ImportText`). The commit writes every row and the completed
session in one `writeAll` through `Ledger.importedRecord`, ids `DerivedIds.imported`, so two devices that commit one statement end with
each row once; every session write and the commit's batch carry `expect` preconditions (jZenDev/jZen#251), so a change a sync lands
between the checks and the write refuses it whole. All 291 catalogue cases and the server's commit-failure cases pass through the
workflow; parity scenarios `import_sessions` and `import_destination` agree with the live server. Differing category choices on two
devices are plain two-device conflicts for jZen's sweep (#234, wired by unit 9); a reset's revocation merges by its time
(`ZenMergePolicy.earliestBy`, #244); `import_sessions` declares explicit presence (#245), the only collection that does (ADR-118). Unit 6a (ADR-116)
adds budgets, carry-over resets, goals and envelopes to the ledger as two parts of its library (`ledger_budgets.dart`, `ledger_goals.dart`):
rows 6.1–6.28, 6.46–6.50, 6.54 in the server's order; the summary, carry-over, free money and progress derived from settled values only,
`Settled.unsettled` keyed by the figure's category, currency or goal; a reset or `ALLOCATE` refused while its figure is unsettled; every
write rechecking its rule inside the store's turn through jZen's `expect` (#251), edits against the exact version read;
`EnvelopeBelowZeroCheck` and `ArchivedGoalMoneyCheck`, whose repair entry's id derives from the entries it compensates, so
two devices applying one repair write one record, and `RepairsMadeApartCheck` undoes two made from different reads (ADR-120); `GoalArithmetic` held to `golden/goal_progress.json`; ten parity scenarios (`budget_*`, `carry_over*`, `goal*`, `free_money`) agree with the live server.
`JZEN_REF` is `270590a` (the pin moved from `4fa887a` to `139fcd6` in ADR-125 and on to `270590a` in ADR-127).
Unit 7 (ADR-118) is analytics: `Analytics` in `local/prudent_local_store/lib/src/analytics/` answers spend by category and by period with
`AnalyticsResource`'s semantics (expenses only; a transfer, a correction, income and a refund are not spend; one currency, never
inferred; whole-month windows; the UTC anchor), as `Settled`, leaving out of a figure only a record whose dispute changes *that* figure
(amount, account, currency, date, existence — and category for the category figure). `SpendWindow` (core) holds the window rules.
`analytics.json` and the generated `AnalyticsScenarios.large` (about 4 000 operations, reserved currencies THB/TRY/ILS and
CAD/NZD/SGD/HKD) agree with the live server to the cent; `tools/prudent_parity_server/test/analytics_large_test.dart` runs the generated one.
On the Dart VM on an M4 Pro an analytics question takes about 100 ms at 50 000 records; **no Android figure exists** (no device or
runnable emulator was available) — unit 12 owes it, with `tool/analytics_benchmark.dart`.
Unit 6b (ADR-119) is plans, occurrences and reminders: `PlanLedger` (`local/prudent_local_store/lib/src/ledger/plan_ledger.dart`) answers the
wire plan, occurrence and reminder messages with the server's statuses, over `RecurrenceRule`, `ReminderLeadTimes` (lead days `{0,1,2,3,7}`),
`PlanZones` and `CivilDate`'s calendar arithmetic in `prudent_local_core`. An occurrence is read from the plan's schedule each time and never
stored; what is stored is a skip or a reminder-read time (`OccurrenceState`, id derived from plan and date), and an occurrence is completed
when its confirming record exists (one record, `DerivedIds.confirmation`, whose `PlanLink` carries `occurrence_date`). Every operation takes
`asOf`; a plan's own zone decides its day. `plans.json` holds recurrence, zone ids, the day at the midnights of stable zones and lead days to the
JVM (eight zones are refused, `PlanZones.unsupported`; no per-zone offsets are committed, they float with the JDK's tzdata). A plan, or an occurrence state, that two devices disagree about has no occurrence in any list and
cannot be confirmed, and the lists answer `Settled`; `occurrence.skipped_and_paid` lists a skip and a confirmation that met. The six
parity scenarios `plans`, `occurrence_windows`, `occurrences`, `schedule_change`, `day_boundary` and `reminders` name dates as
`@today(Zone)±n` (`ParityClock`), because the server's plan routes take no `asOf`; the notification scheduler of `packages/prudent_ui`
is reused unchanged; every `PlanLedger` write carries its `expect` (ADR-122). Nothing has been seen on a device.
Unit 9 (ADR-121) is the app, `local/prudent_local_client`: its own composition root over the shared screens,
`LocalPrudentRepository` over the ledger, the budget and goal extensions, `PlanLedger` (as of the device clock), `Analytics` and `ImportWorkflow`
(the import sweep runs at launch and hourly);
`PrudentRepository.listAccounts()` answers `SettledAccounts` and `getBudgetSummary`/`getFreeMoney`/`getGoalProgress`/`spendByCategory`/
`spendByPeriod` answer `SettledFigures`, so every figure says beside it what it leaves out (`UnsettledBalanceNote`, en/uk/pl); analytics
(`Analytics`, unit 7) is wired too, so every tab loads from the device. A store change drops every repository read at once
(`invalidateRepositoryReads`).
`LocalSession` starts sync only through `ZenSync.start`, replaces the sync key to remove a device (#237), erases here or everywhere (#239),
and refuses a sync folder inside the app's data; the app is behind `ZenLockGate(secureScreen: true)` (#240); conflicts and integrity issues
(`prudentIssueSource`, a choice as one action per candidate, a name asked via the root navigator: jZenDev/jZen#256) open in
`ZenConflictsScreen`; the data copy is `DataExport` saved with `zen_save_file`, never the clipboard. Settings takes Local's pages through
`settingsEntriesProvider` and `privacyScreenProvider` and now scrolls; `zen_ui_store`/`zen_ui_lock` get Polish delegates. Its suite
(`flutter test` with the client's defines; the touch-size rule runs when compiled for `android`/`ios`) and `integration_test/app_test.dart`
(macOS) pass; an unsigned macOS build cannot reach the Keychain (`-34018`) and refuses to open, a non-release `ZEN_ENV=dev` build excepted (ADR-127; see the jZen paragraph below), so a signed build and every device are
unit 12's. The gates cover it (DART_ROOTS, `verify:analyze`, `verify:controls`, `verify:swiftpm`; boundaries F and H already did).
Unit 10b (ADR-123) moves a server account in: `MoveIn` (`local/prudent_local_store/lib/src/move_in/`) reads the privacy export file
(`MoveIn.read`, unknown fields and out-of-range 64-bit integers refused; every value held to the create-time rules, `move_in.invalid_value`) into an **empty** store as one `writeAll` whose first `expect` rechecks emptiness inside the turn;
ids are the export's (`LocalIds.fromServerId`) or derived from natural keys (openings, budgets, skips, confirmations, imported records keyed
by `record_import_keys`, so a statement imported on the server is a duplicate after the move); openings are `exported balance − Σ records`
(F-03), transfer legs are joined, and the move is refused whole (`MoveInRule`, no free text in its facts) unless every balance from
`LedgerView.planned` matches the export to the cent. **Only balances are checked at run time**; budgets, carry-over, envelopes, free money,
goal progress and occurrences are proven by `tools/prudent_parity_server/test/move_in_test.dart` (`parity/move_in/move_in.json`), which moves
the live server's export in, expects no `IntegrityRunner` issue, and compares every answer. The Local app has "Move my data in" under Privacy and data (`MoveInScreen`, en/uk/pl).
No real export and no device has been tried.
Unit 11 (ADR-124) is the Taskfile and CI: `task run:local DEVICE=<native>`, `task build:local:runners` and `build:local:runners:release` delegate to a
third include of jZen's `Taskfile.app.yml` (`zenlocal`, with a server module that must stay nonexistent at `local/no_server`), so jZen's own Local
behaviour applies and the web is refused by name; `task test:local-tasks` proves it through `task` against a stub `flutter`. CI builds Local on iOS,
macOS (a new `macos-runner`, reversing ADR-003 for this app only), Android, Windows and Linux. `task verify:local-release` fails when the Android
manifest (or, in CI, a merged one) allows a backup, when shipped Dart names `ZEN_SYNC` at all, when a sync transport or plan is built or started anywhere but
`sync_starter.dart`, when a workflow sets it or when a web runner exists; a release build with `ZEN_SYNC` is refused by jZen at run time and
`task test:local-release-refusal` proves it on a real release build. Each rule has a planted-violation test. **CI proved every step in run 44106692883 (head `5884c91`) and on the PR's final head `9dd59cc`: the merged Android manifests, the Linux probe under `xvfb`, the Windows build and probe, the macOS and iOS release builds, `verify:swiftpm` after the builds and the macOS probe.** Separately, main's push run 44124134602 at `f858dbf` was red on one test, `task test:local-store` "three devices repairing from three different reads", through a flaw in the two-device test harness ("offline" writes leaked; no money defect); #281 (ADR-126) fixed it and main is green from `8447f8f`. Windows failed in `local_auth_windows` under MSVC 14.51 (jZenDev/jZen#257); jZen fixed it by dropping that plugin from `zen_ui_lock`
(PR #260, ADR-086) and `JZEN_REF` is now `270590a` (ADR-127), with no override or silencing in Prudent. Android needed core-library desugaring (added), and
`PlStoreLocalizations` the new `issueContinue` string of jZen #258. Still open: Android release uses the debug key; iOS, macOS and Windows have no real signing (unit 12 owes a real signing configuration), no platform was
seen on a device (unit 12), and Windows has no biometric or device-owner check by jZen's design (jZen ADR-086: "Forgot PIN?" offers erasing the device's copy).
jZen's own device verification (jZenDev/jZen#231) is closed upstream (jZen `270590a`, ADR-127): it ran on simulators and an emulator and on a real Mac and iPhone, **for jZen's
demo app, not for Prudent Local**, and left #266 (Android), #267 (Windows), #268 (Linux), #269 (folder-service sync), #270 (Apple: Face ID, `--release`, CloudKit, Developer ID) and #271 (camera QR) open;
`docs/jzen/README.md` has the row. Since jZen ADR-087 (proposed upstream) a macOS build with `ZEN_ENV=dev` that is not `--release` (`zenIsDevBuild`) keeps the store key and PIN hash in the
login keychain, so it opens unsigned; every other build keeps the data-protection keychain and an unsigned one still refuses with `-34018` (the integration test and ADR-121's start failure,
run with `ZEN_ENV=local`). `task build:local:runners:release` passes `ZEN_ENV=prd` so a release build is never taken for a dev one; the two keychains do not see each other's items, so a Mac switched between
a dev and a release build refuses to open its data until it is erased and synced again.

**The deploy path: run against disposable environments, and once against a persistent proof of concept.**
`task deploy:cloudrun` and `task verify:deploy` exist (ADR-020, ADR-021, ADR-023). On 2026-10-22
(ADR-065, #45) they were run against a real GCP project and a real Supabase project made for the
purpose: `deploy:cloudrun` passed end to end, `verify:deploy` passed nine of nine, and **everything
was then deleted** (the exact end state is in ADR-065).
That run found and fixed two defects no local check reaches. `task test:native` still proves the
exact artifact a deploy ships, in Docker, against a throwaway Postgres. A persistent environment was created on 2026-10-22 (#46): a
proof of concept on `*.run.app`, Supabase Free with **no backups** (ADR-068, ADR-069,
`docs/persistent-environment.md`), signed in to from a browser and, since 2026-10-27, from a native iPhone
build (ADR-078, #155, `docs/native-iphone-build.md`): registration, the mail, the return through
`prudent://auth-callback`, a balance, an account and an expense, once, by hand — no task builds or
installs it, and no notification or re-signing has been seen. The sign-up mail it sent was almost empty and
its link named the Supabase project's host, which reads as phishing: the sender and relay (#186) and consuming jZen's
own-origin link (jZenDev/jZen#154, #188) are open (ADR-079). Prudent's own `en`/`uk`/`pl` templates (#187, ADR-084) are written in
`supabase/templates/`, gated offline by `task verify:mail-templates` and compared with, or written to, the hosted project by
`task verify:mail-templates:hosted` / `task deploy:mail-templates` — **not yet applied** to the persistent environment, no mail
client tried, the real Management API not yet called. It holds test data only; real finances
wait for #47. Its first sign-in found that no Prudent message was registered for the native image
(#158, fixed; `task verify:reflection` guards the list). Nine genuine secrets are required (the six of ADR-070 that remain, the `APP_DB_*` pair, the relay's `SMTP_USERNAME` and `SMTP_PASSWORD`, ADR-073, and
`SUPABASE_SECRET_KEY`, ADR-075, on the service only; `SUPABASE_KEY` is the public `sb_publishable_` key and, since ADR-085, a plain variable,
and both Supabase keys are checked at boot);
the six public configuration values (`SUPABASE_URL`, `SUPABASE_KEY`, `SITE_URL`, `CORS_ORIGINS`, `AUTH_REDIRECT_URI`, `AUTH_REDIRECT_URIS`) and the
three mail values (`SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`) are plain environment variables on the service and the migration job
(ADR-070, #166, ADR-073, ADR-085), and `verify:deploy` fails when one is not. The persistent environment predates the mail values and had
no relay yet: its next deploy needs one (`docs/persistent-environment.md`, section 3). Never invent or commit a project, region,
service name or URL: no environment fact is ever written into this repository (ADR-021) — the tasks
themselves are real; use them rather than treating deployment as unstarted. Run them from the main checkout: `task` does not
load from a git worktree (ADR-065).

**A deploy cleans up after itself (ADR-087, #165).** `deploy:cloudrun` pins the pushed image (`deploy:pin`, jZen's
`zen:deploy:pin`) before anything is pointed at it and ends with `deploy:cleanup` (jZen's `zen:deploy:cleanup`) once the
service is accepted: 5 revisions / 14 days, 30 registry versions / 30 days, failure mode `fail`, passed as command-line
variables because nothing else beats jZen's own declarations. `scripts/test_deploy_cleanup.py` (in `test:deploy-origin`)
proves the calls and the non-zero exit. Run on the persistent environment on 2026-11-13 (revisions 8 to 5, five images
pinned, no registry version yet due); `docs/persistent-environment.md` section 4a has the record.

**Done: the structural flattening (ADR-026).** Client code is now flat under `client/lib/` on a
capability-folder layout (`account/ analytics/ auth/ category/ generated/ l10n/ overview/ record/`
plus flat files; since ADR-108 everything but `auth/` and the composition root is in `packages/prudent_ui/lib/`) — `client/lib/src/` is gone. The server package is `prudent.*` (`prudent/server/`
gone; new `health/` and `error/` capability packages). Tests flattened to match. It was a pure
`git mv` pass with no behaviour change, driven by `docs/implemented-plans/prudent-restructure-prompt.md`. Any
`lib/src/…` or `prudent.server.…` path in an older doc or ADR is historical — the current tree is
the one described here.

**Keep this section true.** It is the first thing a session reads, and it was wrong for a week —
it still claimed no resources, no entities, no migrations and no `ZenClient` after all four had
merged, which sends every session looking for work that was already done. When a phase lands,
update it in the same commit.

**`docs/implemented-plans/prudent-migration-plan.md` is the approved plan the remaining phases execute**, and
`docs/implemented-plans/prudent-migration-prompt.md` is the brief behind it — read them before proposing structural
change, and do not invent a different target shape. Check what actually exists before building on
it: parts of the structure described below are built and parts are still the target, `docs/DECISIONS.md`
is the record of which, and a session must not speak about the unbuilt half as if it already exists.

## How Prudent depends on jZen: a sibling checkout, by path

jZen's packages are all `0.1.0` and unpublished (`publish_to: none`, Maven `-SNAPSHOT`, no npm
registry entry). Until they are published, Prudent consumes them from a **sibling checkout at
`../jZen`**:

- **Dart/Flutter** — `path:` dependencies (from `client/`: `../../jZen/client/zen_core`, `zen_transport`,
  `zen_identity`, `zen_secure_store`, `zen_ui_identity`, `zen_ui_navigation`, `zen_ui_widgets`).
- **Java** — Prudent's server module declares `zen-parent` as its parent with an **empty
  `<relativePath/>`**, resolving it and the framework libs (`zen-core`, `zen-proto`,
  `zen-transport`, `zen-identity`, `zen-email`, `zen-jobs`, `zen-ratelimit`) from the **local
  Maven repository**. A build therefore has a prerequisite: `(cd ../jZen/server && ./mvnw -B install
  -DskipTests)`. Never reach across repositories with a filesystem `<relativePath>` — that couples
  the build to a directory layout instead of to a version.
- **Admin (if built)** — `@jzen/admin-core` from `../jZen/admin/src` via a TypeScript `paths`
  alias + Vite `resolve.alias`, not a pnpm dependency edge.

**This is a temporary shape with a known cost:** the two checkouts must move together, and there
is no version boundary between them. When jZen publishes its packages, replacing every path
dependency with a version range is a deliberate, ADR-worthy step — not a cleanup — and `docs/jzen/`
is deleted as part of it, since a versioned dependency's documentation travels with the package.

**jZen is a dependency, not a donor.** Read `../jZen` freely for reference implementations
(`apps/zen_demo/*` is the reference application), but never write to it, and never copy framework
source into this repository. If Prudent needs a framework change, that change is made in jZen and
consumed — say so explicitly rather than forking a copy here.

**A limitation met in jZen is an issue in jZen, filed when it is met.** Whenever work here runs into a
framework limitation — a control, hook, export or behaviour `zen_ui_widgets`, `zen_transport`,
`zen-identity` or any other jZen library lacks or gets wrong — open an issue in `jZenDev/jZen`
(English, as `konter-dev`, with what was tried, why it matters here and an acceptance test), add a row
to the table in [`docs/jzen/README.md`](docs/jzen/README.md), and name the issue in the workaround's
comment and ADR. Do not leave it as a sentence in an ADR or a code comment alone, and do not fork the
framework to get around it. A found limitation with no issue number is unfinished work.

## Target structure

The repo root stays **language-neutral** (jZen STANDARDS): no root `pom.xml`, no root
`pubspec.yaml`, no root `package.json`.

```
proto/prudent/v1/*.proto   the contract — canonical for models
server/                    the Quarkus backend (packaging: quarkus)
client/                    the server-connected Flutter app: composition root, auth, ServerPrudentRepository, every test
packages/prudent_ui/       the shared package: screens, view models, l10n (no transport, no identity; ADR-108)
packages/prudent_proto/    the generated wire messages, pure Dart (ADR-111)
local/                     Prudent Local: prudent_local_core (rules), prudent_local_store (store model; ADR-107, ADR-111)
admin/                     react-admin panel (only if in scope)
docs/                      Prudent's docs (zen-architecture.md is the cornerstone)
Taskfile.yml               the single orchestrator; includes ../jZen/Taskfile.app.yml
```

**Platforms.** jZen supports macOS, iOS, Android, web, Linux and Windows (jZen ADR-045). Desktop
builds are **host-only** — Flutter refuses `build linux` off Linux and `build windows` off Windows
— so every desktop target Prudent claims costs a CI runner, and no single machine can verify the
full set. Claim the platforms Prudent actually ships and let CI prove them.

**The iOS and macOS runners use Swift Package Manager only (ADR-083, #183).** There is no `Podfile`,
`Podfile.lock` or `Pods/` in `client/ios` or `client/macos`, and no `[CP]` build phase in either Xcode
project; the minimum OS (iOS 15.0, macOS 12.0) is set in the projects. Flutter falls back to CocoaPods
for a plugin that has no Swift package and the build stays green, so `task verify:swiftpm` (run in CI)
fails when a Podfile or any trace of CocoaPods returns. Do not run `pod install`; a plugin without a
Swift package is a reason to choose another plugin or version.

`task` (go-task) is the only entry point, and it **triggers native tools, never replaces them** —
`mvnw` owns Java, `dart pub` owns Dart, `pnpm` owns TypeScript. A task that reimplements a package
manager is a bug.

Prudent's `Taskfile.yml` **includes** jZen's application-facing orchestration rather than copying
it (jZen ADR-046):

```yaml
includes:
  zen:
    taskfile: ../jZen/Taskfile.app.yml
    vars: {APP_NAME: prudent, CLIENT_DIR: client, SERVER_DIR: server, PROTO_DIR: proto}
```

Included tasks run in **this** repository's directory, and jZen consumes the same file for its own
reference app, so it is shared code rather than a lookalike. `task zen:info` reports which jZen
checkout is in use, at which revision, and whether it is dirty — run it first when a build behaves
oddly. The contract loop and `deps` are consumed from the include (ADR-027), and so is the whole
`run:*` family — one-line aliases to `zen:run:*` (ADR-028, ADR-029); the server build, the gates
and the deploy are still Prudent's own.

## The rules Prudent inherits and cannot bend

These come with the framework Prudent depends on. They are load-bearing, several of them **fail
silently** when broken, and unlike jZen's house style they are not Prudent's to override — a
consumer that bends them stops being a consumer:

- **Contract-first, one direction.** `.proto` is canonical for models; SmallRye-annotated Quarkus
  resources are canonical for the REST surface. Java DTOs, Dart messages, `openapi.json` and admin
  TS are **derived**. A tracked generated file is **never** hand-edited — fix the source and
  regenerate. See the `sync-contracts` skill.
- **The client talks to one server, and it is ours.** No client package calls Supabase, Firebase,
  or any third party directly. Today's Firebase Realtime Database call in `lib/main.dart` /
  `lib/record/records_provider.dart` is exactly what this rule forbids, and removing it is the
  spine of the conversion. This breaks *silently*: an app that authenticates against someone
  else's backend still passes every test.
- **No server-side `quarkus-rest-jackson`.** jZen's JSON is canonical proto3 JSON from
  `JsonFormat`. Jackson hijacks `application/json` at build time and 500s on proto messages, so it
  must be *absent*, not out-prioritized.
- **Every library module contributing CDI beans or JAX-RS providers runs `jandex-maven-plugin`.**
  Without `META-INF/jandex.idx` Quarkus never discovers them — no error, the filters just do
  nothing.
- **Compile-time config on the client.** `String.fromEnvironment` + `if (dart.library.io)` /
  `if (dart.library.html)` conditional imports; build defines are `ZEN_ENV` / `ZEN_PLATFORM`.
  Runtime config on the client is **forbidden** — it is what lets the toolchain tree-shake the
  native-only Protobuf path out of the web bundle. The server is the deliberate opposite: runtime
  MicroProfile config.
- **Client UI: the framework's controls first.** Screens are built from `zen_ui_widgets`
  (`package:zen_ui_widgets/zen_ui_widgets.dart`), not stock Material: `showAdaptivePresentation`
  (never `showDialog` / `showModalBottomSheet` for a form or detail), `ZenButton`, `ZenSelect`,
  `ZenSegmentedControl`, `ZenSwitchRow`, `ZenDateField` / `ZenDateRangeField`, `ZenAmountField` /
  `ZenAmountRangeField` (+ `normalizeAmount`), `ZenTextField`, `ZenIconButton`, `ZenProgressIndicator`,
  `ZenProgressBar`, `ZenPageScaffold`, `showZenMessage`, and `FocusRing` for a bespoke control's focus. Never
  branch on the platform to pick Cupertino or Material — the package does it at compile time, on
  `zenIsApplePlatform` / `zenIsMobile`. A control the package lacks is a framework gap: report it and
  consume it (ADR-036, ADR-041), don't hand-roll it. What an amount *means* (minor units, currency,
  `packages/prudent_ui/lib/money.dart`) stays Prudent's; `AlertDialog`, `PopupMenuButton`, `ListTile`, `Card` and
  layout have no counterpart and are used directly. **Status:** overlays are migrated (ADR-041); the
  goal screens (ADR-053) are the first built wholly on the package's controls, and `app.dart` now
  registers `zenWidgetsLocaleDelegate` (with Prudent's Polish ahead of it) because the amount and
  date fields read their own strings; the account forms (`packages/prudent_ui/lib/account/`, #101) and the record
  forms and filter (`packages/prudent_ui/lib/record/`, #102) are migrated too — the record, transfer and filter
  amount fields refuse a sign (`allowNegative: false`), so the income/expense toggle stays the only
  source of one, and the filter's two ranges are `ZenDateRangeField` / `ZenAmountRangeField` — and so
  are the category form, settings and the analytics and chart screens (#103): their buttons are
  `ZenButton`, their language and currency picks `ZenSelect` (the currency pick moved from the app
  bar into the body, where a labelled field fits). The category form's colour and icon grids stay
  Prudent's own domain controls (`CategoryColorSwatch`, `CategoryIconChoice`), reachable by keyboard
  and ringed with `FocusRing`. **The rule is a gate, not a sentence:** `task verify:controls`
  (`scripts/verify_controls.py`, run in CI) fails on `ElevatedButton`, `FilledButton`,
  `OutlinedButton`, `TextButton`, `DropdownButton`, `DropdownButtonFormField`, `SegmentedButton`,
  `SwitchListTile`, `showDatePicker`, `showDateRangePicker`, `showModalBottomSheet`, and — so that
  iOS and macOS render Cupertino (ADR-060) — on `TextField`, `TextFormField`, `IconButton`,
  `CircularProgressIndicator`, `LinearProgressIndicator`, `Scaffold`, `AppBar` and `SnackBar`, and on a
  `showDialog` that does not show an `AlertDialog` or whose `AlertDialog` holds an input. The only
  carve-outs are `AlertDialog` for acknowledgements and confirmations (its buttons are `ZenButton`s)
  and `PopupMenuButton`; there is no per-file allowlist — a control the package lacks is a framework
  gap to report, not an entry to add. `minorUnitDigits` in `money.dart` is
  what an amount field's `maxFractionDigits` takes: the wire has one fixed scale, not one per
  currency.
  **A screen that cannot load its data shows `LoadErrorView`** (`packages/prudent_ui/lib/load_error_view.dart`) — a
  localized sentence, a hint and Try again — and never the exception's text, which is logged instead
  (#160). `client/test/load_error_view_test.dart` fails when a `*LoadError` string takes `{error}` or a
  screen passes `error.toString()` on.
  **Flutter 3.50 (ADR-099):** Material and Cupertino come from `package:material_ui` and `package:cupertino_ui`, not the SDK's `flutter/material.dart`; a `MaterialApp` that composes
  `PrudentLocalizations.localizationsDelegates` also appends `...GlobalMaterialLocalizations.delegates` (the generated list registers the SDK's, which `material_ui` does not read, and `uk`/`pl` fail without it).
  `riverpod_lint` is an analyzer plugin in `analysis_options.yaml`; `custom_lint` is gone.
  `docs/jzen/README.md` has the state of the upstream issues.
  **The analyzer is a gate (ADR-104):** `task verify:analyze` (CI, `gates`) runs `flutter analyze --fatal-infos --fatal-warnings` in `client/`, `riverpod_lint` included; fix a finding, do not ignore it.
- **Typed, generated i18n.** No hardcoded user-facing strings. Each package owns `lib/l10n/*.arb`
  + `l10n.yaml` and generates accessors with `flutter gen-l10n`; the generated output is built, not
  committed. Prudent's strings are `packages/prudent_ui`'s (ADR-108); `client/` has no `l10n.yaml`. **Prudent supports `{en, uk, pl}`** — its own decision, not the framework's (jZen
  ADR-044). `ZenLocales.shipped` is jZen's inventory (`{en, uk}`) and is a floor, not a ceiling:
  Prudent declares its set as a compile-time `const` on the client and as `zen.i18n.supported` on
  the server, and framework screens degrade to English under `pl` rather than crashing. See
  `docs/implemented-plans/prudent-migration-plan.md` for how Polish is delivered.
- **Flyway is the single migration authority.** Never two migration systems on one database.
  Prudent owns a Flyway version band that cannot collide with jZen's `zen-identity` band — pin the
  band in an ADR before writing the first migration.
- **Nothing swallows a failure.** No `|| true`, no discarded exit code, no null returned where a
  decode failed. If you are about to make a failure quieter, you are about to introduce a bug.
- **All work happens inside this repository.** Nothing reaches outside the repo root to modify a
  file; anything Prudent depends on arrives as a declared dependency. `../jZen` is read-only.

## Explaining things

A comment earns its place by saying *why* a constraint exists, in language a reader with no
history here can follow. Prudent is described on its own terms — as an application built on jZen,
which is a declared dependency, not as anything "ported", "migrated from", or "derived". The
conversion's own record (`docs/DECISIONS.md`, `docs/implemented-plans/prudent-migration-prompt.md`) is where the
before-state is discussed.

## Decisions

Architectural decisions are recorded in `docs/DECISIONS.md` — **Prudent's own log, with its own
numbering starting at ADR-001**, append-only (add an entry, never edit an accepted one). It is
distinct from jZen's archive; do not renumber against it or write Prudent decisions into it. Use
the `add-adr` skill.

## Working agreement

**Never run `git commit` or `git push` without explicit approval from the user.**

**Never commit onto `main`** — branch first, even with approval in hand, and especially right
after a PR merge, when the working copy has just landed back on `main`.

Both rules, and the 50-character subject limit, are enforced by `.claude/hooks/git_guard.py`
rather than by memory. A fresh clone has no git-side guard until
`sh .claude/hooks/install-git-hooks.sh` runs, because `.git/hooks` is not tracked.
`.claude/hooks/skill_guard.py` delivers a skill's rules the first time a file it governs is
edited in a session; the path-to-skill mapping is `.claude/hooks/skill-map.json`.

Two more guards close the gap between "a rule exists" and "a rule fires":
`.claude/hooks/verify_guard.py` runs on `Stop` and refuses to end a turn that changed source
without running a suite (config: `verify-rules.json`; docs, `.claude/` and generated output are
exempt, and it never fires twice in a row). `skill_guard.py` also matches **commands**, not just
paths — so `long-job` arrives on the first slow build and `deploy` on the first `gcloud`, which
are skills no file edit could ever have summoned.

**Everything this repository publishes is written in English** — documentation, ADRs, code
comments, issues, pull requests (title, body, comments, reviews) and commit messages — whatever
language the conversation with the user is in. Translate before writing; never publish a
Russian (or any other Cyrillic) draft. The one exception is the product's own Ukrainian
localisation (Prudent ships `en`, `uk`, `pl`): Ukrainian strings in `*_uk.arb`, the `*_uk` mail
templates and `RetentionMessagesUk`, and the tests that assert them. `.claude/hooks/english_guard.py`
enforces it (paths in `english-rules.json`): it refuses Cyrillic in text written with Edit/Write
and in a `gh` command that publishes text, outside those paths — inside them it still refuses the
letters Russian has and Ukrainian lacks (yery, e, hard sign, yo) — and `git_guard.py` refuses a Cyrillic commit
message, git-side too. Adding a path to `locale_paths` is for Ukrainian locale data only, never a
way past the guard. Test it with `python3 .claude/hooks/test_english_guard.py`.

**Branch names are `<type>/<slug>`** — `feature/`, `fix/`, `docs/`.

**Every commit and every PR in this repo is authored as `konter-dev`, never any other
identity.** `konter-dev`'s identity is `Adam Konter <konter.dev@gmail.com>`; the repo's local git
config is already set to it (`git config user.name`/`user.email`), so a plain `git commit` with no
`-c user.name=…`/`-c user.email=…` override already attributes correctly — GitHub links a commit
by **email**, so never pass an override that pairs a different name with a different account's
address.

PR authorship is a **separate** identity from the commit's: it is whichever `gh` account is
active, not the git commit identity. Before every `gh pr create`/`gh pr edit`/`gh pr comment` in
this repo, run `gh auth status` and, if the active account is not `konter-dev`, switch first with
`gh auth switch --hostname github.com --user konter-dev`. After creating or editing, verify with
`gh pr view <n> --json author -q .author.login` — do not assume the switch stuck. This check is
mechanical and unconditional: skipping it is the exact failure mode that has already shipped a PR
under the wrong account more than once.

**When a command fails twice with the same error, escalate instead of retrying** — hand over the
exact command for the user to run with the `!` prefix. Interactive authentication is never a
retry problem.

**The deploy path has run three times against disposable environments that were torn down
(ADR-065 to ADR-067), and once against the persistent proof of concept, which was not (ADR-069).**
`task deploy:cloudrun` and `task verify:deploy` (ADR-020, ADR-021, ADR-023) have real runs behind
them. Do not write skills, plans or docs that invent a project/region/service name or URL, and never
run the runbook's teardown (step 4) against the persistent environment; do use the tasks themselves.

### What is in `.claude/`

| | Purpose |
|---|---|
| `skills/add-adr` | record a decision in `docs/DECISIONS.md` (append-only, Prudent's own numbering) |
| `skills/add-endpoint` | add a REST endpoint contract-first (OpenAPI merge, Jandex, no-Jackson) |
| `skills/sync-contracts` | the proto → Java/Dart/TS regeneration loop and its drift gate |
| `skills/jzen-reference` | find a pattern in the sibling `../jZen` checkout, read-only |
| `skills/long-job` | how to wait on a slow command, with this repo's measured durations |
| `agents/visual-verify` | drive a change in a real browser; returns pass/fail + screenshots |
| `agents/regression-guard` | review a diff for what it broke and what it duplicated |
| `hooks/` | the guards above, their config, and their tests |

Run the hook tests with `python3 .claude/hooks/test_git_guard.py` and
`python3 .claude/hooks/test_skill_guard.py`.

Permissions are prefix rules in the tracked `.claude/settings.json` (read-only git, inspection
tools, this repo's own build and test entry points). `settings.local.json` is for genuine
one-offs; it is gitignored and never the place for a rule everyone needs.


## The working tree is shared

The user edits files in this repository while a session runs. A session that
assumes it is alone commits their work by accident.

**Stage by explicit path, and check the index before committing.** `git add -A`
and `git add .` sweep up whatever is there. Even explicit paths are not enough
on their own: run `git diff --cached --name-only` immediately before `git
commit` and confirm every entry is a file you wrote. A file can already be
staged when you arrive.

**Never switch branches while files you did not touch are modified.** A switch
either aborts or carries someone else's work onto another branch, and a stash
taken to get around it pops straight back onto the branch you were leaving.
Use a worktree, which needs no stash and leaves this tree untouched:

    git worktree add -b <branch> <dir> origin/main
    # work, commit, push from <dir>
    git worktree remove <dir>

This applies to `git checkout -b <branch> <start-point>` too: git aborts that
whenever a modified file differs between HEAD and the start point.

**Leave what is not yours exactly as you found it.** If you have to undo your
own commit, verify afterwards that their files are still modified and still
theirs.

`.claude/hooks/worktree_guard.py` enforces all of this: it recovers the files
this session wrote from the transcript, refuses a commit whose index holds
anything else, and refuses a branch switch under foreign changes. Prefix a
command with `ALLOW_FOREIGN=1` when the foreign files genuinely belong in the
commit.
