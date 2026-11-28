# Plan: Prudent Local — Prudent with no server, on every native target

> **Status (closed 2026-11-17, unit 13; documents finished 2026-11-18, ADR-128): units 0 to 11 are built and merged and unit 13 is built; unit 12 (real devices) is NOT VERIFIED and was never a session.**
> Prudent Local is **not released** and must not be until a person has done unit 12. Written 2026-11-15, on top of jZen's Local mode
> (jZen ADR-073, issue jZenDev/jZen#210). jZen's **device verification (jZenDev/jZen#231) is closed upstream** (2026-11-18, jZen `270590a`, ADR-127): it was run on simulators and an emulator and on a real Mac and iPhone, for
> *jZen's demo app*, not for Prudent Local. What jZen still lists as open is Android on a phone (#266), Windows (#267), Linux (#268), sync through a folder service between devices (#269),
> Apple Face ID, `--release`, CloudKit and Developer ID (#270) and the camera QR (#271); Prudent Local inherits those gaps. Everything below
> unit 12's list is proven by tests, the parity suite against the live server and CI, on a Mac and CI runners, never on a device.
> The status of each unit, its PRs and ADRs is in "Unit status"; what is owed is in unit 12; the follow-ups that are not unit 12 are at the end.

**Source:** jZen ADR-073 — a serverless application is a *Local* application on iOS, macOS,
Android, Windows and Linux (no web); its data lives in `zen_store`, encrypted on the device, and
syncs through CloudKit on Apple or a folder the person chooses elsewhere. The reference is
`jZen/apps/zen_demo_local`, a chore list. Prudent is a ledger with money in it, so this plan is the
same mode with a much harder model.

**What Prudent Local is.** The same product — accounts, categories, records, budgets, goals,
plans, analytics, Erste statement import — with **no server, no sign-in and no account**. Every rule
the Quarkus server enforces today (13 000 lines of Java, 22 Flyway migrations, CHECKs and unique
indexes) becomes the client's, because nothing else is left to enforce it.

**Scope:** this repository, plus gaps found in jZen, which are filed there and consumed after they
land (never patched here: "all work happens inside the repository" and the framework is a declared
dependency). Prudent Server, the admin panel and the web build are **unchanged and keep working**.

Each unit is one branch and one PR (`<type>/<slug>`), landed in order unless it says otherwise. A
unit is done when its tests are green, `task verify:contracts`, `verify:controls` and the existing
gates pass, and what it could not verify is written in its PR and in `docs/DECISIONS.md`.

## Ground rules

- **A balance is never a stored number that two devices both edit.** It is derived from the
  records. Two devices that each add a record must both be kept; there is no last-writer-wins
  anywhere (jZen ADR-065/073). A conflict is something the person settles, in words.
- **Same figures as the server.** Every number the server computes (balance, budget carry-over,
  goal envelope, free money, analytics) is computed by the local code to the same cent. A
  *parity suite* runs one scenario script through both implementations and compares them
  (unit 3 builds it, every later unit adds to it).
- **No server code in the local build and no local code in the web build.** Compile-time config
  and conditional imports, as everywhere (`ZEN_PLATFORM`, `ZEN_SYNC`). Local imports neither
  `zen_transport` nor `zen_identity`. `task verify:boundaries` gains a rule for it.
- **The server stays the proof.** Server behaviour is the specification; where the local code must
  differ (ids, ordering, atomicity), the difference is an ADR, not a surprise.
- **Nothing real in the repository.** Fixtures are synthetic, as ADR-088 requires; no real
  statement, no real amounts.
- **Decisions get ADRs** in `docs/DECISIONS.md` (Prudent's numbering) as they are made.

---

## Unit status

All PRs are in `jlogicsoftware/prudent`. Each was derived from `git log origin/main` and the `**Plan:**` line of the ADR.

| Unit | What | Status | PRs | ADRs |
|---|---|---|---|---|
| 0 (0.1–0.5) | Phase-0 decisions, inventory, threat model | built | #246 (the plan), #249 | ADR-100, 101, 102, 103 |
| 0.6 | Pins: jZen `fdef7e8`, Flutter 3.50 | built | #248 | ADR-099 |
| (gate) | `flutter analyze` as a CI gate | built | #250 | ADR-104 |
| 1 | `PrudentRepository` interface | built | #251 | ADR-105 |
| 4a | Server search and name order | built | #252 | ADR-106 |
| 3 | Domain core and parity suite | built | #253 | ADR-107 |
| 2 | Shared package `packages/prudent_ui` | built | #254 | ADR-108 |
| (gate) | `verify:boundaries` keeps Local and server apart | built | #255 | ADR-109 |
| 4 | Store model and merge | built | #256; fix #258 | ADR-111 |
| 10a | Export carries import keys; save to a file | built | #257 (server, desktop, web); #263 (iOS, Android) | ADR-110, ADR-117 |
| 8a | Erste parser and fingerprints | built | #259 | ADR-112 |
| 5 | Ledger | built | #260 | ADR-113 |
| 8b | Import sessions, duplicates, commit | built | #262 | ADR-114 |
| (jZen bump) | Store precondition and presence (`expect`) | built | #264 | ADR-115 |
| 6a | Budgets, resets, goals, envelopes | built | #267; repairs #268; fix #271 | ADR-116, ADR-120 |
| 6b | Plans, occurrences, reminders | built | #266; every write's `expect` #270 | ADR-119, ADR-122 |
| 7 | Analytics | built (Android bound **not met**, unit 12) | #265 | ADR-118 |
| 9 | `prudent_local_client` | built; macOS only | #269 | ADR-121 |
| 10b | Moving data in | built; no real export | #273 | ADR-123 |
| 11 | Taskfile and CI, five platforms | built; PR checks green at final head `9dd59cc`; main's push run at `f858dbf` was red on a two-device test-harness flaw (no money defect), fixed by #281 (ADR-126), green from `8447f8f` | #272 | ADR-124, ADR-125 |
| **12** | **Real devices (release gate)** | **NOT VERIFIED, not started** | none | none |
| 13 | Documents (this close-out) | built: plan moved, status and follow-ups (#279); the Local privacy statement, README, roadmap, architecture, `docs/jzen/README.md` and `CLAUDE.md` (#287) | #279, #287 | ADR-128 |

Epic: jlogicsoftware/prudent#245. #269's title says ADR-120; the app's ADR is ADR-121 (ADR-120 is the envelope repair of #268).

---

## Phase 0 — Decisions (each ends in an ADR before code that depends on it)

### 0.1 Shape: a second app, sharing screens through a package
**Decided: ADR-101.** Four packages — `client/`, `packages/prudent_ui`, `local/prudent_local_core` (pure
Dart), `local/prudent_local_client` — a separate bundle id, the name "Prudent Local".
Today `client/` is one app whose screens call `PrudentRepository` (600 lines) over `ZenClient`.
Decide the split. **Recommendation:** extract the screens and domain types into a package both
apps use, keep `client/` as the server-connected app, add `local/prudent_local_client` as the
Local app. Alternative rejected unless the spike shows otherwise: one app with a runtime mode
(forbidden for client config) or a compile-time flag in one app (puts server code in the Local
binary's source graph and forces web builds to carry the local store's conditional imports).
Output: ADR, and the directory layout.

### 0.2 Money under merge
**Decided: ADR-102**, with the per-field table in `docs/plans/prudent-local-phase0.md` §0.2. Local's own
store messages; ids derived from natural keys; **a transfer is one immutable record** (a Prudent Local
difference from the server's two legs); account + currency + amount one grouped field; the default
account in settings; rule breaks across records listed after every sync, never fixed silently. The
plan's "note and category are not conflicts" is withdrawn: two different values of any field are a
conflict in `zen_store`.
How do balances, transfers, corrections and goal allocations behave when two devices edit offline?
Decide: balance derived from records; a transfer is two legs created together, and what happens if
only one arrives; what an edit to a record that another device deleted means; which fields merge
without a question and which are a conflict (amount and account are conflicts; note and category
are not). Output: ADR with the per-field table for every proto message in `proto/prudent/v1/`.

### 0.3 Inventory of what the server enforces
**Done:** the table is `docs/plans/prudent-local-phase0.md` §0.3 — 9 rules in unit 3, 4 obligations in
unit 4, 53 in unit 5, 54 in unit 6 (34 + 20 after the split), 4 in unit 7, 25 rows / 44 rule codes in
unit 8, 5 in unit 9, 7 with no local owner by design. Its findings are in "Findings from phase 0" below
and have changed units 4, 5, 6, 8 and 10.
Walk the 22 migrations, every `CHECK`, unique index and resource for the rule it holds
(normalisation of account numbers, import fingerprints, archive and category kind, budget
carry-over resets, goal eligibility, plan occurrence state, row-level security). Output: a table in
this plan's PR — rule, where it lives today, where it will live locally, test that proves it.
Rules with no local owner are findings, not footnotes.

### 0.4 Moving existing data
**Decided: ADR-103.** A one-time import of the export into an empty Local store, refused whole unless
every balance matches to the cent; the export gains the import fingerprints and a file save first (unit
10a).
Is there a path from a server account to a Local one? The privacy export already exists
(`privacy.proto`). Decide: import that export into a fresh Local store, or no migration and a
fresh start. Either is acceptable; silence is not.

### 0.5 Threat model for a ledger on a device
**Decided: ADR-100** (rows T1–T26, each mapped to a unit).
Lost device, a PIN that is forgotten, a shared cloud folder that holds ciphertext of someone's
finances, a Linux desktop with no secret service, a statement file left in Downloads. Output: ADR
and a list of what the app must refuse or warn about. Reviewed before unit 9 lands.

### 0.6 Pins
Prudent consumes jZen by path at a pinned ref. Local needs jZen at or after the merge of
jZenDev/jZen#229 (Flutter 3.50, Dart 3.14) and the Local packages. Decide the ref, and whether
`client/` follows the Flutter upgrade first (its CI pins 3.44.2, local machines run 3.50).

**Decided by ADR-099:** jZen is pinned at `fdef7e8` (which contains #229) and `client/` moves to
Flutter 3.50 / Dart 3.14, CI included. Prudent Local builds on that ref; the Local packages are
a later bump of it.

---

## Phase 1 — Seams

### Unit 1 — A repository interface in front of the server
Extract an abstract repository from `prudent_repository.dart`; the server version implements it.
No behaviour change; every existing suite passes untouched. **Done when:** screens depend only on
the interface, and a test fake can stand in for it.

### Unit 2 — The shared package
Move screens, view models, money formatting and l10n that do not touch the transport into the
shared package of 0.1. `client/` consumes it. **Done when:** `client/` builds, tests and passes
`verify:controls` and `verify:widget-files` exactly as before, and the web bundle size is unchanged
within a stated tolerance.

### Unit 3 — Domain core and the parity suite
**Built: ADR-107** — `local/prudent_local_core` (rules, golden vectors from `GoldenVectorsTest`, the parity engine) and
`tools/prudent_parity_server` (the server side, run in `task test:e2e`). Scenarios live in `local/prudent_local_core/parity/scenarios/`.
Port the pure rules to Dart: money and currency handling (`Currencies`), identifier rules,
account-number normalisation (NFC, white space, root-locale upper-casing, ADR-090), validation.
Build the parity harness: a scenario script runs through the server (real Quarkus in
`test:e2e`) and the local code and the figures are compared. Golden vectors are generated from the
Java implementation and committed. **Done when:** the harness runs in CI with the first scenarios
and fails on a one-cent difference.

---

## Phase 2 — The Local data layer

### Unit 4 — Store model and merge
**Built: ADR-111** — `local/prudent_local_store` (pure Dart, on `zen_store`): the store messages
(`proto/prudent_local/v1/store.proto`), `DerivedIds`, `PrudentLocalStore`'s structural write rules, `StorePolicies`
(jZen #235's `earliest` on the goal-status and reminder-read times), `WireMapper` (presence-exact), and the
`IntegrityRunner` with the store model's six checks; `task test:local-store`. The wire messages moved to the pure-Dart
`packages/prudent_proto` so the store can map to them. Consumed jZenDev/jZen#233 and #235 (`JZEN_REF` `6301f0e`); filed
jZenDev/jZen#244 (a reset's revocation is a group, so two revocations stay a conflict) and #245 (an explicit default differs
from an unset field; consumed by ADR-115 at `4fa887a`, which also made every write's rules a precondition run in the store's
write turn, jZenDev/jZen#251). Not here: import sessions (8b), the checks that need figures (envelopes 6a, skipped-and-paid 6b,
correction intent 5), the `ZenIssueSource` wiring (unit 9, Flutter), the CloudKit backend (unit 9).
Map every proto message into `zen_store`; device-minted UUIDs (the server minted ids because
"an id from an untrusted client is not identity" — locally the device is the only authority, so the
reason changes, and the ADR says so); per-field merge as decided in 0.2, through Local's own store messages and a mapper to the wire messages
(ADR-102); ids derived from natural keys; **the integrity-check runner** that re-evaluates every rule
across records after a sync and lists what fails with actions (finding F-05; each later unit adds its
checks); the same-intent timestamp rule. Both jZen issues it waited on landed first (#233, #235), so neither a Prudent list nor a
Prudent timestamp rule was ever built. **Done when:** two real
sessions, each with its own encrypted store, merge disjoint edits and surface the conflicts of 0.2,
through `ZenFolderCloud` (as `two_devices_test` does in jZen).

### Unit 4a — Server search and name order
Two server behaviours Local cannot reproduce faithfully and no other unit owned (findings F-09, F-10): the
record search was a SQL `LIKE` with unescaped `%`/`_` and a locale-dependent `lower()`, and account, category
and free-money names were ordered by an unpinned collation. The server now applies both as rules of its own, in
Java (`prudent.text.TextRules`): a per-code-point simple lower-case fold with a plain substring match, and a
name order that places Polish and Ukrainian letters in their alphabets. No migration, no contract change.
**Done when:** the server suite is green with tests that fail on the old behaviour, and the expected-behaviour
vectors (`server/src/test/resources/text-rules/search-vectors.json`, `name-order-vectors.json`) are on `main`
for units 3 and 5 to consume. ADR-106. **Must land before unit 5.** It is user-visible on the persistent app
(search no longer treats `%`/`_` as wildcards; lists may reorder once).

### Unit 5 — Ledger: accounts, records, transfers, corrections, categories, settings
**Built: ADR-113** — `Ledger` in `local/prudent_local_store` (`lib/src/ledger/`): every rule of §0.3 rows 5.1–5.53 over the store,
wire requests in and wire messages out; derived balances that never read a value two devices disagree about (a disputed record,
transfer or opening counts in no figure and is named, and a correction is refused until it is settled); multi-record writes only
through jZen's `ZenStore.writeAll` (jZenDev/jZen#232, consumed at `e6a06c6`), so an account deleted with its records is all or
nothing and no resumable delete exists; `SearchRules` (search fold, `compareNames`) in the core, held to the server's vector files
and to a JVM table of every code point's fold (the Dart VM's `toLowerCase` differs on 437); the correction-intent integrity check
(`CorrectionIntent.seen_corrections`); `StoreBackend`, which replaced unit 3's in-memory parity backend; parity scenarios
`ledger_records`, `ledger_transfers`, `ledger_corrections`, `ledger_accounts`, `ledger_categories`, `ledger_settings`,
`record_list_filters`, `record_list_order`. Filed jZenDev/jZen#251 (no write precondition; consumed by ADR-115: every write carries
the version it was decided against, so an edit cannot bring back a record a sync just deleted). Found: the server answers 500 to an
account update that reorders held currencies (row 5.5; jlogicsoftware/prudent#261, since fixed).
Categories move here from unit 6, because a record is refused by its category's kind and archived
flag (finding F-01). Balances derived; a transfer as one immutable record (ADR-102), shown as two legs; corrections; archive. Row-level security has no local
meaning (one person per store) and is recorded as such. **Done when:** parity scenarios for every
balance-changing path pass, and the account deleted with its records (ADR-081), all or nothing through
jZenDev/jZen#232's `ZenStore.writeAll` (merged and consumed; the interim "resumable delete" this line once allowed is withdrawn
and was never built, ADR-113).
**List and filter semantics** (phase-0 §0.3 rows 5.46–5.53): the record list's date, account, category,
`type`, `abs(amount)` range and search filters and its `date desc, id` order, answered over transfers
**expanded into their two legs first**, so `type=transfer` and an amount range behave per leg as on the
server; order within one date is compared as a set, because ids differ between server and Local. The
search and name order implement `TextRules` (unit 4a, ADR-106: findings F-09 and F-10) in Dart and pass its
vector files. Parity scenarios `record_list_filters` and `record_list_order`.

### Unit 6a — Budgets, carry-over resets, goals, allocations
**Built: ADR-116** — `ledger_budgets.dart` and `ledger_goals.dart`, two parts of the ledger in `local/prudent_local_store`: every rule of
rows 6.1–6.28, 6.46–6.50, 6.54, check for check in the server's order; the summary, carry-over (through months with no budget, from the
latest live reset), free money and progress derived on every read from settled values only, with what they leave out in
`Settled.unsettled` (keyed by category, currency or goal); a reset or an `ALLOCATE` refused while its figure is unsettled; every write
checking its rule again inside its turn through jZen's `expect` (#251), edits and deletes against the exact version read; a reset's
revocation merging by `earliestBy` (#244, declared by unit 8b); no `explicitPresence` (ADR-115); integrity checks `EnvelopeBelowZeroCheck` and `ArchivedGoalMoneyCheck`; `GoalArithmetic` in the core held to the JVM by
`goal_progress.json`; parity scenarios `budget_slots`, `budget_summary`, `carry_over`, `carry_over_reset`, `budget_lists`, `goals`,
`goal_allocations`, `free_money`, `goal_progress`, `goal_lists`. `JZEN_REF` `4fa887a`.
Budget slots by derived id, the summary, carry-over and its resets; goal states, envelopes, free money,
progress; allocations append-only. The most integrity checks (envelope below zero, money in an archived
goal, two live resets for one slot). 34 rules (phase-0 §0.3 rows 6.1–6.28, 6.46–6.50, 6.54), including
the goal, envelope-history, budget and reset list filters and orders (parity scenarios `goal_lists`,
`budget_lists`). **jZen:** the goal status time merges in the store by jZenDev/jZen#235's policy (declared in
unit 4); a reset's revocation is a group, merged by jZenDev/jZen#244's `earliestBy` (declared by unit 8b, ADR-114). **Done when:** parity
scenarios cover each and the figures match the server's to the cent.
**From unit 5 (ADR-113):** every "still used by" refusal and every figure reads plans, budgets and resets the way the ledger
reads records — with the sides of a conflict (`LedgerView.recordValues` is the pattern) and leaving out of a figure what two
devices disagree about, answered as `Settled` so the flag travels with the figure. Unit 5's own reads of plans in
`deleteAccount`, `updateAccount` and `deleteCategory` read only the shown value, because plans have no rules yet; 6a and 6b move
them onto the same helper. **Done for budgets and resets (ADR-116):** `deleteCategory` reads `LedgerView.budgetValues` and
`resetValues`; the plan reads are 6b's.

### Unit 6b — Plans, occurrences, reminders
**Built: ADR-119** — `PlanLedger` in `local/prudent_local_store` (`lib/src/ledger/plan_ledger.dart`) over the plan rules of
`prudent_local_core` (`RecurrenceRule`, `ReminderLeadTimes`, `PlanZones`, calendar arithmetic on `CivilDate`); occurrences are read from the
schedule and never generated, completion is the confirming record (one record, derived id, `PlanLink.occurrence_date`), `asOf` is an
argument everywhere, a plan two devices disagree about has no occurrences and is named (`Settled`), the check `occurrence.skipped_and_paid`;
the notification scheduler of `packages/prudent_ui` is reused unchanged through the wire messages. Held to the JVM by `plans.json`
(recurrence, zones and offsets, lead days) and by six parity scenarios (`plans`, `occurrence_windows`, `occurrences`, `schedule_change`,
`day_boundary`, `reminders`) whose dates are relative to today in a zone (`ParityClock`), because the server's plan routes take no `asOf`.
`JZEN_REF` `4fa887a`. Not here: the screens (unit 9); nothing seen on a device.
Plans with their recurrence and reminder, occurrences by derived id (completion derived from the
confirming record), confirmation, reminders. Reminders use local-device notifications only. The parity
suite passes `asOf` explicitly (finding F-07). 20 rules (rows 6.29–6.45, 6.51–6.53), including the
upcoming window and the order of occurrences and reminders (finding F-11). The reminder-read time
merges in the store by jZenDev/jZen#235's policy (declared in unit 4). **Done when:** parity scenarios
cover each, including a day boundary in a plan's own time zone.

### Unit 7 — Analytics
**Built: ADR-118** — `Analytics` in `local/prudent_local_store` (`lib/src/analytics/`) and `SpendWindow` in `prudent_local_core`:
spend by category (a year or a month) and by period (1–60 months or years), rows 7.1–7.3, answered as `Settled` so a record two devices
disagree about is left out of exactly the figure it changes and named. Parity: `analytics.json` (by hand) and `AnalyticsScenarios.large`
(about 4 000 generated operations over six years and 4 currencies, relative to today) agree with the live server to the cent. Measured on
the Dart VM on an M4 Pro: 100 ms for any analytics question and 113 ms for the account overview at 50 000 records (linear, ~2 µs a
record). **Not met: the Android bound** — no Android device or runnable emulator was available (the only AVD's system image is
incomplete), so there is no Android figure; `tool/analytics_benchmark.dart` is the harness and **unit 12 must run it on a real phone and
record the number**. Row 7.4 (planned cash flow) is client-side and travels with units 6b and 9.
Spend by category and by month, computed from the local store. **Done when:** parity on a large
synthetic ledger (met), and a stated bound on how long the overview takes at that size on the slowest
target (Android), measured (**not met**, see above).

### Unit 8a — Erste parser and fingerprints
**Built: ADR-112** — `local/prudent_local_core/lib/src/imports/` (`parseErsteStatement`, `ErsteStatementImporter`, `StatementBounds`,
`RowFingerprints`, `ImportRule`), held to the JVM by `test/golden/erste_import.json` (every parse-stage case of the catalogue, the fixtures and
the Java/Dart differences) and `test/golden/import_fingerprints.json`. The server emits 45 rule codes, not 44: 40 are the parse stage's, and the
5 that need a session or the ledger are named for unit 8b. NFC comes from `unorm_dart`, root upper-casing from a JDK table.
Port `ErsteStatementImporter`, the whole-file validation before any row is returned (ADR-090), the 44
rule codes and the failure catalogue of ADR-094, and the versioned fingerprint plus occurrence number
(ADR-091) — pure functions in `prudent_local_core`. Fixtures are the synthetic ones of ADR-088.
**Done when:** the catalogue passes locally, fingerprints match the Java implementation's golden vectors,
and no statement text reaches an answer or a log line.

### Unit 8b — Import sessions, duplicates, commit, two devices
**Built: ADR-114** — `ImportWorkflow` in `local/prudent_local_store/lib/src/imports/`: the server's three phases, destination checks,
row decisions, defaults, duplicates and commit, check for check; sessions in the device-only collection `import_sessions` of the ledger's
store (jZenDev/jZen#252, filed by this unit); every row and the completed session committed in one `ZenStore.writeAll`, ids from the
row keys, each write guarded by an `expect` precondition (jZenDev/jZen#251); the whole failure catalogue and the server's commit-failure
cases through the workflow; a two-device test; parity scenarios `import_sessions` and `import_destination`. Consumes jZenDev/jZen#234
(the conflict sweep, wired by unit 9), #244 (a reset's revocation merges by its time), #245 (explicit presence on the session's
`optional` fields), #251 and #252 at `JZEN_REF` `4fa887a`. The interim clauses below are withdrawn and were never built.
The three enforced phases (ADR-089) in a second, **unsynced** store (ADR-102); only normalised rows kept,
never the file; duplicates against the destination; the commit (ADR-092) writing records whose ids derive
from the fingerprint, so two devices that import one statement end with each row once. **Blocked on
jZen:** a one-transaction commit needs jZenDev/jZen#232 (until then the commit validates everything before
the first write and is idempotent and resumable); differing category choices on two devices give one
conflict per row until jZenDev/jZen#234. **Done when:** the failure catalogue passes and "nothing was
written" holds on every refusal, and a two-device test imports one statement on both and ends with each
row once.

---

## Phase 3 — The application

### Unit 9 — `prudent_local_client`
**Built: ADR-121** — `local/prudent_local_client`: `LocalPrudentRepository` over the ledger, unit 6a's budgets and goals, unit 6b's plans and
reminders, unit 7's analytics and unit 8b's import workflow; balances, budget summaries, free money and goal progress carry what they leave out (`SettledAccounts`,
`SettledFigures`) and say so beside the figure in en/uk/pl; analytics (unit 7) is wired too, so every tab loads from the device. Sync through `ZenSync.start` (CloudKit with Prudent Local's own container, the shared folder elsewhere), `zen_ui_lock`'s PIN with
`secureScreen: true`, Settings → Lock, Sync and devices (pairing, replace the sync key), Conflicts and issues (`ZenConflictsScreen`, settle
many) and Privacy and data (a `zen_save_file` copy, erase this device's copy, erase everywhere). Every ADR-100 row has a test or a written
answer (the table in ADR-121). Filed jZenDev/jZen#256. Run on macOS (widget, a11y and integration suites); no device (unit 12), and an
unsigned macOS build cannot reach the Keychain, a non-release `ZEN_ENV=dev` build excepted (ADR-121, ADR-127).
No sign-in, no profile account section. Sync through `ZenSync.start`; PIN from `zen_ui_lock`;
Settings → Sync, Add a device, Join, Erase this device's copy, all from `zen_ui_*`. English,
Ukrainian and Polish. Screens from the shared package; nothing hand-rolled
(`verify:controls`). A copy of the person's data (the local counterpart of ADR-071's export) and
erasure of this device's data. **Done when:** widget, integration and a11y suites pass, and the
threat model (ADR-100) has a test or a written refusal for every row. Rows that change when jZen lands:
rekey (jZenDev/jZen#237), erase everywhere (jZenDev/jZen#239), screen-capture protection
(jZenDev/jZen#240).
**Also done when** (ADR-113): every balance the screens show from the Local repository comes with the `Settled.unsettled` of
the `Ledger` answer behind it, and a figure that leaves something out says so on screen, beside the figure, in all three
languages, with a widget test that syncs a disputed amount and finds the words — never a bare number.

### Unit 10a — The server export carries import fingerprints and saves to a file
Server-side, contract-first, before the import: add the import fingerprint and occurrence (ADR-091) to
the privacy export (finding F-02), and give the server-connected app "Save to a file" for the export
beside the clipboard copy, with a warning that the file is not encrypted (ADR-103, ADR-100 T14). Its own
ADR. **Done when:** `PrivacyCoverageTest` sees the new fields, `verify:contracts` passes, and a saved file
round-trips.

**Status (ADR-110, ADR-117):** built on the server and on every platform of the server-connected app; the key travels as `record_import_keys` beside the record, and "Save to a file" is
`zenSaveFile` (jZenDev/jZen#246, PR #254) on iOS, Android, macOS, Windows, Linux and web. On macOS every save failed until the runner got `files.user-selected.read-write` (ADR-132, jlogicsoftware/prudent#286), tried once on a Mac in a throwaway probe with synthetic data; on the web a download shows no confirmation (jZenDev/jZen#283). **Open:** the save sheet has not been run on a real phone, Windows or Linux, in the web app in a browser, nor in the unmodified app against a server; that belongs to unit 12.

### Unit 10b — Moving data in
As decided in ADR-103: the export read from a file into an empty store, opening amounts rebuilt from the
exported balances (finding F-03), transfers joined into one record, ids remapped, refused whole unless every
balance matches to the cent. That balance check catches dropped or mis-joined records; it cannot see a
wrong mapping of budgets, envelopes, goal progress or occurrences, which the export does not carry.
**Done when:** a synthetic export made by the real server in `test:e2e` round-trips, and the parity suite
compares the Local figures after the import with the server's own answers — balances, budget summaries,
carry-over, envelopes, free money and goal progress — to the cent. At run time only the balances are
checked; the other figures are proven by that test, not by the app.

**Status (ADR-123):** built. `MoveIn` in `local/prudent_local_store` (one `writeAll`, ids from the export, the balance check over
`LedgerView.planned`), the round trip against the live server in `tools/prudent_parity_server/test/move_in_test.dart`
(`parity/move_in/move_in.json`), and "Move my data in" in the Local app (en/uk/pl). **Open:** a real export, the picker on a device (unit 12).

### Unit 11 — Taskfile and CI
`task` runs the Local app with no server, refuses web, and builds on iOS, macOS, Android, Windows
and Linux in CI (jZen's `Taskfile.app.yml` already supports this). `verify:boundaries` forbids
`zen_transport`/`zen_identity` in the Local app and Local code in `client/`. A release build with
`ZEN_SYNC` set fails (ADR-100 T18; jZenDev/jZen#238 asks the framework to refuse it too). The Android
manifest refuses Auto Backup of the store (ADR-100 T10). **Done when:** a
deliberate violation of each rule fails the gate.

**Status (ADR-124):** built and proven in CI (run 44106692883 on `5884c91`, then the PR's final head `9dd59cc`; main's push run 44124134602 at `f858dbf` was red on one test, `task test:local-store` "three devices repairing from three different reads" (1100 where 2200 was expected, ADR-120): a flaw of the test harness, where `ZenFolderCloud` with `pollEvery: null` still syncs, so "offline" writes leaked, not a money defect; fixed by #281, ADR-126, and main's push run 44165373573 at `8447f8f` is green). Proven: merged Android manifests, the Linux probe under `xvfb`, the Windows build and probe, the macOS and iOS release builds, `verify:swiftpm` after them and the macOS probe; Windows needed jZenDev/jZen#257, fixed upstream, `JZEN_REF` `139fcd6`, ADR-125). `task run:local` / `build:local:runners[:release]` delegate to a third include of jZen's `Taskfile.app.yml`
(`zenlocal`, no server module, so jZen's own Local behaviour and web refusal); CI builds Local on all five platforms (`macos-runner` is new);
`verify:local-release` gates T10 (source and merged Android manifests), the single `ZEN_SYNC` reader, no workflow setting it and no web runner;
the T18 refusal is jZen's and is proven on a real release build by `test:local-release-refusal`. Each rule has a planted-violation test.
**Still open:** Android release uses the debug key; iOS, macOS and Windows have no real signing (unit 12 owes the real signing), no platform has been seen on a device (unit 12), and Windows has no
biometric or device-owner check by jZen's design (jZen ADR-086).

---

## Phase 4 — Close

### Unit 12 — Verification on real devices (release gate)
**NOT VERIFIED. Not started, never a coding session; a person does it.** Builds on jZen's closed device verification (jZenDev/jZen#231; its open follow-ups are #266 to #271) and repeats none of it for Prudent Local. Prudent Local is **not released** before this.

Matrix: Windows ↔ Linux ↔ Android over Syncthing and Dropbox/OneDrive; macOS ↔ iOS over CloudKit once a paid Apple Developer Program exists,
`ZenFolderCloud` before. For a ledger the matrix adds: the same balance on every device after offline edits, an import on two devices, a forgotten
PIN, a lost device.

**What unit 12 owes, gathered from the ADRs and `CLAUDE.md`:**

1. **Every platform on a real device** — iOS, macOS, Android, Windows, Linux have each been built in CI (ADR-124) and none has been seen running
   as a user would; the Windows and Linux keystores, Android `FLAG_SECURE` and the owner check, QR scanning and real
   Syncthing/Dropbox/OneDrive folders have not been exercised (ADR-121). Windows has no biometric or device-owner check by jZen's design (ADR-086).
2. **CloudKit**: no paid Apple Developer Program or iCloud entitlement, so no CloudKit run has happened (jZenDev/jZen#236 is consumed, unseen).
3. **A signed macOS build.** An unsigned one cannot reach the Keychain (`-34018`) and refuses to open, a non-release `ZEN_ENV=dev` build excepted (ADR-127); the integration test (run with `ZEN_ENV=local`) asserts that refusal, so
   the suite proves the refusal and **not** the signed path (ADR-121). **The signed device run must be a non-dev build (`ZEN_ENV=prd`, or `local`)**: a dev build keeps its key in the login keychain and would not test the data-protection path.
4. **Real release signing.** Android release uses the debug key; iOS, macOS and Windows have no real signing (ADR-124; jlogicsoftware/prudent#275).
5. **The Android analytics benchmark**: run `runAnalyticsBenchmark` (`local/prudent_local_store/tool/analytics_benchmark.dart`) in a Flutter harness on a
   real mid-range Android phone at 50 000 records and write the figures into a successor ADR (ADR-118 is append-only). Unit 7's "Done when" bound is not met until then.
6. **The save-file sheet on devices** (`zenSaveFile`): never run by the real apps on a real device or platform, on any of macOS, Windows, Linux, iOS, Android (a throwaway probe of the server-connected app's screen saved once on a Mac, ADR-132, and does not stand in for this step); and on
   Linux the move to `file_picker_linux` (a dialog helper such as zenity or kdialog) was not read for runtime requirements (ADR-110, ADR-117, ADR-121).
7. **Notifications firing**: no local notification has been seen to fire or be cancelled on a device (ADR-056 to ADR-058, ADR-119).
8. **A native-speaker review of every uk and pl string**, Local's and the server-connected app's (e.g. 'Dalej' vs 'Kontynuuj', ADR-124); none has been reviewed.
9. **The native file picker and a real Erste export** for import and for moving data in: a real statement (none may be committed, ADR-088), the picker on
   macOS, Windows, Linux and Android, a real privacy export (ADR-110, ADR-123); amounts of 1000 or more and the wording of an outgoing own-account transfer were never seen.
10. **Move-in at scale and on a syncing device** (ADR-123, not verified): an export of tens of thousands of records moved in as one `writeAll`, and a move into a device that is already syncing with peers that hold nothing.
11. **The macOS integration test is not run by CI** (`.github/workflows/ci.yml` has no entry for it); it was run by hand (ADR-121) and asserts the Keychain refusal of an unsigned build (a non-release `ZEN_ENV=dev` build excepted, ADR-127), so a signed non-dev run is owed.
12. **Performance of the write path**: building a 50 000-record ledger record by record is quadratic (379 s in batches of 500 on a Mac, ADR-118); an
    import of years of history and a first sync on a phone are where that shows, and have not been measured on a device.
13. **jZen's device verification** (jZenDev/jZen#231, closed 2026-11-18) covered jZen's demo app on simulators, an emulator and a real Mac and iPhone, so it does not stand in for any step here; its open follow-ups are #266 (Android), #267 (Windows), #268 (Linux), #269 (folder-service sync), #270 (Apple: Face ID, `--release`, CloudKit, Developer ID) and #271 (camera QR), and Local cannot be more verified than the framework under it.
14. **iOS Data Protection** (ADR-137): on a real iPhone with a passcode, in a signed build, the app opens (also after this device's copy is erased),
    and the store's directory and files, those written after launch included, carry `complete` and cannot be read while the phone is locked.
15. **The file dialogs' temporary copies** (ADR-138): on a real iPhone and a real Android phone, in each app's own build, after a statement
    and (Prudent Local) a server export is picked and read, refused, unreadable or cancelled, and after a save that completes, is cancelled
    or fails, the app's temporary and cache directories hold no `*-Inbox`, `flutter_file_picker` content or pick directory, and the picked
    original is still there; a copy left by killing the app with a dialog open is gone after the next launch; both erase actions leave none,
    and no notice that a copy may remain appears (whether iOS lets the app delete the `*-Inbox` directory itself is not known).
    Include a cloud document provider (iCloud Drive, Google Drive). Seen so far on a simulator and an emulator only: picks and saves
    with a test app, and the apps themselves only removing planted copies at launch (not the server-connected app on iOS).

### Unit 13 — Documents
**Built** (#279 and #287, ADR-128). #279 moved the plan to `docs/implemented-plans/` with the status table above
and listed the follow-ups at the end. The second change wrote what #279 left:

- **`docs/privacy-policy-local.md`**, Prudent Local's privacy statement (jlogicsoftware/prudent#280): what stays on the device, what the
  folder or CloudKit holds and can see, what is never sent, the copy, both erasures and what they leave, and what is not protected or not
  verified, each claim with its source. It sits beside the server app's `docs/privacy-policy.md`, which gained only a pointer to it.
- The README (the two forms and how to run each), `docs/product-roadmap.md` (Local's milestones; unit 12 open), `docs/zen-architecture.md`
  (Local's design where it is Prudent's own), `docs/jzen/README.md` (every row checked against jZen on 2026-11-18) and `CLAUDE.md`.

Writing the statement found that iOS Data Protection, which ADR-100 T1 counted on, was not set on the store (jlogicsoftware/prudent#285;
set since ADR-137, and seeing it on an iPhone is unit 12's, item 14).
The statement is a document: what it says is not verified on a device is unit 12's.

---

## Findings from phase 0

From `docs/plans/prudent-local-phase0.md` §0.3, each with the unit that owns it:

| # | Finding | Owner |
|---|---|---|
| F-01 | Records are refused by their category's kind and archived flag, so categories cannot wait for unit 6 | unit 5 (moved) |
| F-02 | The wire `Record` (and so the privacy export) has no import fingerprint | unit 10a (export), unit 4 (a local store field) |
| F-03 | The wire `Account.balances` is the derived current balance, not the stored opening amount | unit 4 (not stored), unit 10b (openings rebuilt) |
| F-04 | "500 characters" is code points on the server and UTF-16 units in Dart | unit 3 (count runes) |
| F-05 | No unit owned the rules a merge can break across records (13 of them) | unit 4 (runner), units 5–8 (checks) |
| F-06 | Account deletion with records and the import commit are one server transaction; `zen_store` has no multi-record write | units 5 and 8b; jZenDev/jZen#232 |
| F-07 | The server's "today" is UTC or the plan's zone; the device's is local | unit 3 harness, unit 6b (`asOf` pinned) |
| F-08 | Reminder lead days: Java allows `{0,1,2,3,7}`, the schema `0–365`; the Java set is the rule | unit 6b |
| F-09 | The record search is an unescaped SQL `LIKE` (`%`, `_` are wildcards) with locale-dependent `lower()` | unit 4a (server fix, ADR-106; Dart side in unit 5) |
| F-10 | Accounts, categories and free-money accounts are ordered by the database's unpinned collation | unit 4a (server rule, ADR-106); units 5 and 6a (Dart side) |
| F-11 | Ids order three ways: Postgres bytes (= Local's hex text), Java's signed `UUID.compareTo` in two routes | unit 3, unit 6b |

## jZen issues Prudent Local waits on

| Issue | What | Units |
|---|---|---|
| jZenDev/jZen#231 (closed), #266–#271 (open) | device verification of jZen Local: closed upstream for the demo app; the follow-ups are Android, Windows, Linux, folder-service sync, Apple release and CloudKit, camera QR | 12 (release gate); ADR-100 rows marked #231 |
| jZenDev/jZen#232 | multi-record write — **merged (PR #248, jZen `e6a06c6`: `ZenStore.writeAll`), consumed by unit 5** | 5, 8b |
| jZenDev/jZen#233 | application issues beside conflicts — **merged (PR #242), consumed by unit 4** | 4, 9 |
| jZenDev/jZen#234 | settle many conflicts at once — **merged (PR #250), consumed by unit 8b (the shape; ADR-114), wired by unit 9 (ADR-121)** | 8b, 9 |
| jZenDev/jZen#235 | intent-preserving per-field merge policy — **merged (PR #241), consumed by unit 4** | 4, 6a, 6b |
| jZenDev/jZen#236 | CloudKit record names in plaintext — **merged (PR #243, jZen `cf36d77`: HMAC-hashed names), consumed by unit 9 (ADR-121)**; no CloudKit run yet | 4, 9 (ADR-100 T7) |
| jZenDev/jZen#237 | rekey / remove a device — **merged (PR #253), consumed by unit 9 (ADR-121)** | 9 (ADR-100 T3) |
| jZenDev/jZen#238 | refuse the unencrypted folder in release | 11 (ADR-100 T18) |
| jZenDev/jZen#239 | erase everywhere — **merged (PR #253), consumed by unit 9 (ADR-121)** | 9 (ADR-100 T24) |
| jZenDev/jZen#240 | screen-capture protection — **merged (PR #253), consumed by unit 9 (ADR-121): on** | 9 (ADR-100 T15) |
| jZenDev/jZen#256 | a `ZenIssueAction` cannot ask for a choice or a text — **filed by unit 9**; one action per candidate and a name asked through the app's navigator until it lands | 9 |
| jZenDev/jZen#244 | a merge policy over a group (a reset's revocation: who and when) — **merged (PR #249), consumed by unit 8b (ADR-114)**; unit 6a relies on it (ADR-116) | 4, 6a |
| jZenDev/jZen#245 | a proto3 field set to its default differs from an unset one in the merge — **merged (PR #254, jZen `4fa887a`); consumed by unit 8b for the import sessions (ADR-114) and for the unit 4/5 collections by ADR-115** | 4, 5 (every write path), 8b |
| jZenDev/jZen#246 | save-file capability on iOS and Android | 10a (mobile half) — fixed by PR #254, consumed (ADR-117) |
| jZenDev/jZen#252 | an atomic write across synced and device-only data — **merged (PR #254, jZen `4fa887a`), consumed by unit 8b: sessions are a device-only collection, the commit one `writeAll` (ADR-114)** | 8b |
| jZenDev/jZen#251 | a write precondition, so a rule checked before a write holds when it runs (an edit cannot resurrect a record a sync just deleted) — **merged (PR #254, jZen `4fa887a`); consumed by unit 8b's session and commit writes (ADR-114) and for units 4 and 5 by ADR-115** (`WriteExpects.asRead`); 6a and 6b pass it on their own write paths | 4, 5, 6a, 6b, 8b (every write path) |
| jZenDev/jZen#255 | the presence rule of #245 inside a nested message (a posting, a schedule, a reminder setting) | 4, 5, 6b (every writer of a group builds it with its defaults unset until then) |

None blocks starting a unit; each is a stated limitation of that unit until it lands and is consumed.

## Open risks

- **Merge semantics for money** are the hardest part and are decided in 0.2 before any code; if the
  per-field table cannot be made honest, the answer is a narrower Local (e.g. one writer device),
  not a silent compromise.
- **Parity drift:** a server change that is not mirrored locally. The parity suite is the guard;
  until it covers a rule, the rule is listed as uncovered in 0.3.
- **Inherited jZen gaps** (jZenDev/jZen#266 to #271; #231 is closed). Prudent Local cannot be more verified than the framework under it.
- **Size of the port.** The importer and the budget/goal rules are the bulk; units 6 and 8 are split
  (6a/6b, 8a/8b) on 0.3's count.

## Follow-ups that are not unit 12

Known work left by the plan, each with its issue:

- The Local occurrence and reminder lists do not answer `Settled` — jlogicsoftware/prudent#274 (nit of the review of #269).
- Android release uses the debug key; iOS, macOS and Windows have no real signing — jlogicsoftware/prudent#275 (the real signing configuration also serves unit 12).
- One low finding from the review of #265: a conflict about a record's account alone leaves it out of both analytics figures, though neither reads
  the account — jlogicsoftware/prudent#276, blocked on jZenDev/jZen#286 (`ZenConflict.sides` can omit a disputed value). The review's other four
  findings under that issue are done.
- `askForName` and one-action-per-candidate are workarounds until jZenDev/jZen#256 lands — jlogicsoftware/prudent#277 (ADR-121, ADR-125).
- Nits from the reviews of #269 and #272 (unreadable-store 'Retry', raw English `syncProblem`, the comment
  stripping and line-based transport gates, 'Dalej' vs 'Kontynuuj', the probe's untested branch, no old-format fixture for ADR-125) —
  jlogicsoftware/prudent#278.
- The Local data copy leaves out skipped dates and reminder-read marks — jlogicsoftware/prudent#288 (found by the review of #287).
- iOS Data Protection was not set on the Local store, which ADR-100 T1 assumed — jlogicsoftware/prudent#285 (found by unit 13, ADR-128),
  fixed by ADR-137; seeing the protection class on a real iPhone is unit 12's, item 14.
- The file dialogs left plaintext copies of a picked statement or export, and of a saved copy, in the app's storage — jlogicsoftware/prudent#309
  (found by the review of #285), fixed by ADR-138; seeing it on real devices is unit 12's, item 15.
- The server policy said "Save to a file" was not on iOS and Android, which ADR-117 made untrue — jlogicsoftware/prudent#286 (found by unit 13, ADR-128), fixed in `docs/privacy-policy.md`, together with the macOS runner's read-only entitlement, which made the save fail there (ADR-132); seeing the save sheet on a real device is still unit 12's, item 6.
- Prudent Local's macOS runner grants no `files.user-selected` entitlement, so saving a copy is expected to fail there (read from the plugin's code); that its open dialogs fail too is an inference, since `file_selector_macos` makes no entitlement check. Nothing was run — jlogicsoftware/prudent#296 (found by the review of #286).
- Main's push run at `f858dbf` was red on a two-device test-harness flaw, fixed by jlogicsoftware/prudent#281 (ADR-126), green from `8447f8f` (see unit 11); the reference helper's same flaw is jZenDev/jZen#263, open.
- The import crash test once saw the commit succeed — jlogicsoftware/prudent#282.
