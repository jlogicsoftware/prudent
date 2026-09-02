# Prudent: POC to MVP product roadmap

**Status:** discussion draft, 2026-09-02.  This document is the product backlog to agree before
creating GitHub milestones and issues.  It does not authorise implementation or publication of
the issues.

## Product boundary

Prudent is a private, manual-first personal-finance application for Poland and the EU.  Its first
user is its developer.  It adopts the useful everyday workflows of Zenmoney without attempting
feature parity.

The MVP does **not** include paid bank APIs or automatic bank synchronisation.  Erste Polska is
supported through a user-initiated statement import.  The bank currently offers transaction
history and electronic statements in CSV and other formats; the MVP targets CSV only.  Exact
field mapping remains blocked until an anonymised sample export is available.

## What exists now

Prudent already has a complete technical vertical slice:

- authenticated Flutter application and Quarkus server;
- persistent CRUD for accounts, categories and income/expense records;
- multi-currency accounts with exact minor-unit arithmetic and no implicit FX;
- overview balances and basic spend-by-category / spend-by-month analytics;
- English, Ukrainian and Polish localisations;
- contract generation, backend/client tests, CI, native-image and deployment tasks;
- an admin panel limited to user administration.

This is a strong **technical POC**, but not yet a product MVP.  There is no live environment or
release, the core ledger cannot represent transfers, and the main product workflows below are
absent.  The database `CHAR(3)` versus JPA `varchar(3)` validation defect reported as issue #23
was fixed by PR #26; its server suite passed 79/79 and it is no longer an MVP blocker.  The
repository guidance still incorrectly says that no deploy path exists, while `Taskfile.yml`
contains `deploy:cloudrun` and `verify:deploy`; the documentation must be reconciled before the
first deployment.

## MVP definition

The MVP is reached when one user can reliably:

1. maintain accounts and actual transactions, including transfers;
2. schedule one-off and recurring transactions and confirm them manually;
3. plan category budgets with positive and negative carry-over;
4. reserve money in virtual goal envelopes without changing bank balances;
5. receive in-app and local-device reminders;
6. import an Erste Polska CSV safely without creating duplicate transactions;
7. use the product in a real production environment with backups and actionable failure signals.

## Deliberately outside MVP

- bank APIs, PSD2 aggregation and background bank sync;
- automatic categorisation or an AI assistant;
- shared/family access and debts between people;
- investments, crypto, precious metals and portfolio analytics;
- server-driven email or push notifications;
- generic multi-bank import beyond the reusable seam needed by the Erste importer;
- automatic foreign-exchange rates.

## Roadmap

The roadmap is dependency-based rather than date-based.  Each milestone must produce a usable
increment and pass the existing verification gates before the next begins.

### M0 — Make the POC trustworthy

**Outcome:** the current product can be deployed and trusted before its domain grows.

- Treat #23 / PR #26 as completed groundwork; retain its server regression coverage.
- Reconcile deployment documentation with the tasks that actually exist.
- Provision the first disposable production-like environment, run `verify:deploy`, then create
  the intended persistent environment only after the runbook is proven.
- Define automated database backups, restore verification and retention.
- Add privacy policy, data export and account-erasure acceptance checks for the first release.
- Add actionable server error reporting and a minimal health/availability check.

### M1 — Complete the ledger

**Outcome:** balances remain correct for ordinary real-life money movement.

- Add transfers as one atomic domain operation linking source and destination accounts.
- Support same-currency transfers without affecting income/expense analytics.
- Support cross-currency transfers with two user-entered amounts; never infer an FX rate.
- Add an optional transaction note/payee field.
- Add transaction search and filters for date, account, category, type and amount.
- Add safe balance correction as an explicit operation rather than rewriting history silently.
- Extend analytics and account-deletion rules for transfers and corrections.

### M2 — Planned and recurring transactions

**Outcome:** the user can see upcoming commitments without corrupting actual balances.

- Model a schedule separately from actual transactions.
- Support one-off, daily, weekly, monthly, yearly and custom-interval schedules.
- Generate occurrences for a bounded future window idempotently.
- Add planned, completed, skipped and overdue states.
- Require manual confirmation before a planned occurrence becomes an actual transaction.
- Allow confirming with edited date, amount, account and category while retaining the link to the
  plan.
- Add upcoming/overdue views and include planned cash flow on the overview without mixing it into
  the actual balance.

### M3 — Category budgets with carry-over

**Outcome:** the user can answer “how much may I still spend?” for each category and month.

- Add one monthly budget amount per category and currency.
- Calculate plan, actual, remaining amount and percentage used.
- Carry both underspend and overspend into the next month.
- Allow the user to reset accumulated carry-over from a selected month onward.
- Preserve a readable audit trail of budget changes and resets.
- Add month navigation and plan-versus-actual overview.
- Define behaviour for category deletion, inactive categories and months with no budget.

### M4 — Virtual goal envelopes

**Outcome:** money can be reserved for goals without creating fictional bank transactions.

- Add goals with name, one currency, target amount, optional target date and lifecycle state.
- Add explicit allocate, withdraw and transfer-between-envelope actions.
- Keep envelope allocations outside account balances and income/expense analytics.
- Calculate free money as eligible account total minus active envelope allocations.
- Prevent total allocations from exceeding eligible available money in that currency.
- Show progress and the recommended monthly contribution for dated goals.
- Define archive/completion behaviour without deleting allocation history.

### M5 — Local reminders

**Outcome:** upcoming obligations are visible even when the user is not looking at the schedule.

- Add reminder settings per planned transaction.
- Support an in-app reminder centre with unread/read state.
- Add local-device notifications on supported mobile/desktop platforms.
- Reschedule notifications after plan edits, completion, skips, login and application updates.
- Handle notification permission denial and unsupported web behaviour explicitly.
- Add optional budget-threshold and goal-progress reminders after transaction reminders are stable.

Server-driven email/push reminders become a post-MVP epic.  They may reuse the existing server and
jobs capability but require delivery credentials, retry policy, user preferences and operational
monitoring; they are not silently bundled into local reminders.

### M6 — Erste Polska CSV import

**Outcome:** a statement can be imported repeatedly without loss, surprises or duplicates.

- Obtain and commit only a synthetic fixture shaped like an anonymised Erste CSV export.
- Document the export path in Erste internet banking for a non-technical user.
- Build a reusable import session model and an Erste CSV parser.
- Validate encoding, delimiter, headers, dates, decimal format, currency and account identity.
- Show a preview with accepted, duplicate and rejected rows before writing anything.
- Let the user select the destination account and edit category/note before confirmation.
- Detect duplicates using a stable bank identifier when present and a documented fingerprint
  fallback when it is absent.
- Commit the whole confirmed import atomically and make retrying the same file idempotent.
- Keep the original file only for the duration needed to parse it; do not retain bank statements
  by default.
- Add fixtures for malformed files, duplicate files, mixed currencies and changed Erste formats.

This milestone may be specified at issue level now, but implementation cannot be considered
ready until the sample file resolves the actual column contract.

### M7 — MVP hardening and release

**Outcome:** the product is usable as the developer's daily financial system.

- Run the full release gates and a real-device smoke matrix for the claimed platforms.
- Test migration from the current POC data to the MVP schema.
- Verify backup restoration and account erasure end to end.
- Add first-run onboarding for accounts, budgets, plans, goals and CSV import.
- Review accessibility, Polish copy, empty/error/loading states and destructive confirmations.
- Measure real dogfooding defects for at least one complete budget cycle.
- Publish the first version only after there are no unresolved balance-integrity or data-loss
  defects.

## Future GitHub epics

When this document is approved, create one GitHub milestone per roadmap milestone and these epics:

1. **Release foundation and data safety** — M0
2. **Transfers and ledger completeness** — M1
3. **Planned and recurring transactions** — M2
4. **Monthly budgets and carry-over** — M3
5. **Virtual goal envelopes** — M4
6. **Local reminders** — M5
7. **Erste Polska CSV import** — M6
8. **MVP hardening and first release** — M7

Issues should be created from the bullet points only after each epic has explicit acceptance
criteria, dependencies and a small enough vertical slice.  GitHub publication is a separate,
user-approved action.

## Product rules agreed during discovery

- The target market is Poland and the EU; the first user is the developer.
- Paid bank APIs and automatic synchronisation are excluded.
- Erste Polska import is manual and CSV-based.
- Planned transactions become actual only after manual confirmation.
- Budgets carry both underspend and overspend; the accumulated carry-over can be reset manually.
- Goals are virtual envelopes, not bank accounts or fictional ledger transactions.
- MVP reminders are in-app and local-device notifications.
- Server-driven notifications belong on the post-MVP roadmap.
- Delivery is performed by AI agents, so milestone sizing is based on dependencies and verified
  outcomes rather than calendar estimates or assumed team velocity.
