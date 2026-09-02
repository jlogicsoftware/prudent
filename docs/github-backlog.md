# Prudent MVP GitHub backlog

Status: discussion draft.  Creating or publishing GitHub issues requires separate approval.

## GitHub model

- Project: organisation Project **Prudent** (`jlogicsoftware/projects/2`).
- Milestone: one milestone, **MVP v0.1**, shared by every epic and task below.
- Epic: issue type **Feature**.
- Task: issue type **Task**, linked to its epic with `Parent issue`.
- Workflow: `Todo` → `In Progress` → `Done`.
- Ordering: use the `[M0]`–`[M7]` prefix; do not create a milestone for each phase.
- Scheduling: dependency-based only.  No dates, estimates or assumed human velocity.

Every task is complete only when its acceptance criteria, automated tests and relevant user-facing
documentation are complete.  Schema changes must include migration coverage.  Balance-changing
work must include server-side invariant and regression tests.

## [M0] Release foundation and data safety

**Outcome:** the existing POC can be deployed, observed, backed up and trusted with personal data.

**Depends on:** issue #23 and PR #26 are complete.

**Epic acceptance:** a fresh environment passes the release gates; backup restore, export and
erasure are proven end to end; failures are visible without inspecting raw infrastructure.

Tasks:

1. **[M0] Align deployment runbook with executable tasks** — every documented command exists and
   a clean operator can follow the runbook without undocumented steps.
2. **[M0] Prove deployment in a disposable environment** — provision, run `verify:deploy`, record
   evidence and tear down every created local and cloud resource.
3. **[M0] Provision and verify the persistent environment** — repeat the proven path and document
   ownership, secrets and recovery prerequisites without storing credentials in Git.
4. **[M0] Automate database backup and restore verification** — define retention and demonstrate
   that the latest backup restores to a clean database and passes integrity checks.
5. **[M0] Implement privacy, data export and account erasure** — publish the policy and prove that
   export is readable and erasure removes all user-owned data.
6. **[M0] Add health checks and actionable error reporting** — expose minimal availability state
   and capture server failures with enough context to diagnose them without leaking financial data.

## [M1] Transfers and ledger completeness

**Outcome:** balances and analytics stay correct for ordinary real-life money movement.

**Depends on:** M0.

**Epic acceptance:** transfers, corrections and edited transaction metadata preserve ledger
invariants across currencies, analytics and account deletion.

Tasks:

1. **[M1] Add atomic same-currency transfers** — one operation creates linked source and destination
   entries, updates both balances atomically and does not count as income or expense.
2. **[M1] Add explicit cross-currency transfers** — the user enters both amounts and currencies;
   cancellation or failure leaves neither side committed and no FX rate is inferred.
3. **[M1] Add transaction payee and note fields** — both fields can be created, edited, displayed,
   exported and migrated without changing existing records.
4. **[M1] Add transaction search and filters** — date, account, category, type and amount filters
   compose predictably and can be cleared without losing data.
5. **[M1] Add explicit balance correction operations** — reconciliation records an auditable
   correction instead of silently rewriting opening balance or transaction history.
6. **[M1] Integrate transfers and corrections with lifecycle rules** — analytics, exports and
   account/category deletion preserve links or reject unsafe actions with a clear explanation.

## [M2] Planned and recurring transactions

**Outcome:** upcoming commitments are visible but never change actual balances before confirmation.

**Depends on:** M1.

**Epic acceptance:** recurring plans generate deterministic occurrences; every occurrence can be
confirmed, edited, skipped or left overdue without double-posting an actual transaction.

Tasks:

1. **[M2] Model plans and recurrence rules separately from transactions** — support one-off, daily,
   weekly, monthly, yearly and custom intervals with explicit timezone and end conditions.
2. **[M2] Generate future occurrences idempotently** — a bounded generation window produces the
   same unique occurrences when run repeatedly or concurrently.
3. **[M2] Add planned occurrence lifecycle and views** — planned, completed, skipped and overdue
   states appear in upcoming and overdue lists with valid state transitions only.
4. **[M2] Confirm a planned occurrence manually** — confirmation may edit date, amount, account and
   category, creates exactly one actual transaction and retains the plan link.
5. **[M2] Add planned cash flow to the overview** — future income and spending are clearly separated
   from actual balances and can be included or hidden by the user.

## [M3] Monthly budgets and carry-over

**Outcome:** the user can see how much remains available in each category for a selected month.

**Depends on:** M1; M2 only for displaying planned spending.

**Epic acceptance:** plan, actual, remaining and carry-over are reproducible for every month;
underspend and overspend carry forward until an explicit reset.

Tasks:

1. **[M3] Add monthly category budget rules** — store at most one amount per category, month and
   currency, with validated edits and migration coverage.
2. **[M3] Calculate plan, actual and remaining amounts** — calculations use posted expenses only,
   handle refunds consistently and never mix currencies.
3. **[M3] Carry underspend and overspend forward** — positive and negative results propagate across
   gaps deterministically and historical edits recalculate later months.
4. **[M3] Add carry-over reset with audit history** — reset from a chosen month onward without
   deleting prior budgets or hiding who/what changed the result.
5. **[M3] Define category lifecycle behaviour** — inactive or deleted categories and months without
   a budget retain readable history and cannot corrupt totals.
6. **[M3] Build monthly budget overview** — navigate months and show plan, actual, carry-over,
   remaining amount and percentage with distinct overspent and empty states.

## [M4] Virtual goal envelopes

**Outcome:** money can be reserved for goals without fictional bank transactions.

**Depends on:** M1.

**Epic acceptance:** allocations are auditable, currency-safe and excluded from bank balances and
income/expense analytics; total active allocation cannot exceed eligible money.

Tasks:

1. **[M4] Add goal model and lifecycle** — create a goal with name, currency, target amount and
   optional date; support active, completed and archived states without deleting history.
2. **[M4] Add auditable envelope allocation actions** — allocate, withdraw and move money between
   same-currency envelopes as explicit immutable history entries.
3. **[M4] Calculate eligible and free money** — define eligible accounts per currency and prevent
   allocations that exceed their available total.
4. **[M4] Calculate goal progress and contribution guidance** — show allocated, remaining and, when
   dated, the monthly contribution needed using documented rounding rules.
5. **[M4] Build goal and envelope views** — show active and archived goals, history and actions while
   keeping envelope amounts visually distinct from account balances.

## [M5] Local reminders

**Outcome:** upcoming planned transactions produce useful reminders without a paid delivery service.

**Depends on:** M2.

**Epic acceptance:** reminders work in-app and, where the installed platform supports them, as local
device notifications; edits and state changes do not leave stale or duplicate notifications.

Tasks:

1. **[M5] Add reminder settings to planned transactions** — enable/disable and choose supported lead
   time with validation and a safe default.
2. **[M5] Build the in-app reminder centre** — show due and overdue reminders with unread/read state
   and navigation to the relevant planned occurrence.
3. **[M5] Schedule local-device notifications** — request permission only when needed and schedule a
   local notification with no sensitive amount in lock-screen text by default.
4. **[M5] Reconcile notifications after state changes** — edits, confirmation, skip, login and app
   update reschedule or cancel notifications idempotently.
5. **[M5] Handle unsupported or denied notifications** — explain platform limitations and retain the
   in-app reminder path without repeated permission prompts.

Server email and push delivery, budget thresholds and goal-progress reminders are post-MVP follow-up
features, not hidden scope in these tasks.

## [M6] Erste Polska CSV import

**Outcome:** the same statement can be reviewed and imported repeatedly without duplicates or loss.

**Depends on:** M1.  The exact parser contract is blocked until an anonymised Erste export is
available; no real statement may be committed to the repository.

**Epic acceptance:** a representative statement previews validation results, commits atomically and
is idempotent; malformed or changed formats fail safely with actionable feedback.

Tasks:

1. **[M6] Capture the Erste CSV contract and synthetic fixtures** — document the export steps,
   inspect an anonymised sample locally and commit only synthetic files covering the discovered
   headers and formats.
2. **[M6] Add reusable import sessions and importer boundary** — separate parse, preview and commit
   phases so future formats can reuse the workflow without weakening Erste validation.
3. **[M6] Parse and validate Erste statements** — validate encoding, delimiter, headers, dates,
   decimals, currency and account identity; reject unsupported variants before any write.
4. **[M6] Build import preview and correction flow** — show accepted, duplicate and rejected rows;
   select the destination account and allow category/note edits before confirmation.
5. **[M6] Detect duplicate statement rows** — prefer a stable bank identifier and otherwise use a
   documented fingerprint that behaves consistently across repeated and overlapping files.
6. **[M6] Commit imports atomically and privately** — write the confirmed session once, make retries
   idempotent and discard the uploaded statement after parsing by default.
7. **[M6] Cover import failures and format drift** — tests include malformed, duplicate,
   mixed-currency and structurally changed files with no partial database writes.

## [M7] MVP hardening and first release

**Outcome:** Prudent is safe and understandable enough to replace the developer's existing personal
finance workflow for one complete budget cycle.

**Depends on:** M0–M6.

**Epic acceptance:** POC data migrates, first-run setup works, restore and erasure pass, and a full
dogfooding cycle finds no unresolved balance-integrity or data-loss defect.

Tasks:

1. **[M7] Prove migration from current POC data** — upgrade a representative pre-MVP database with
   no lost or reinterpreted balances and document rollback/recovery.
2. **[M7] Add first-run onboarding** — guide creation of accounts, budgets, plans and goals and link
   to Erste import without forcing optional setup.
3. **[M7] Complete Polish UX and accessibility review** — review copy, keyboard/screen-reader access,
   destructive confirmations and empty, loading and error states on claimed platforms.
4. **[M7] Run release and real-device verification** — pass automated gates plus a documented smoke
   matrix for every platform named in the release.
5. **[M7] Dogfood one complete budget cycle** — use real personal workflows, record defects in the
   Project and resolve every balance-integrity or data-loss issue before release.
6. **[M7] Publish MVP v0.1** — verify restore, export and erasure once more, write release notes and
   publish only after every milestone issue is closed or explicitly removed from MVP scope.

## Publication order

After this document is approved:

1. Create milestone **MVP v0.1**.
2. Create the eight **Feature** issues and add them to Project **Prudent**.
3. Create the **Task** issues, assign the milestone and connect each to its parent Feature.
4. Keep only M0 tasks in `In Progress`; all other items start in `Todo`.
5. Start a later phase only when its listed dependencies and the previous phase's release gates pass.
