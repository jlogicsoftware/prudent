# Plan: Prudent Local — Prudent with no server, on every native target

> **Status: planned, nothing built.** Written 2026-11-15, on top of jZen's Local mode
> (jZen ADR-073, issue jZenDev/jZen#210, all code units merged). jZen's **device verification is
> still open** (jZenDev/jZen#231): Android folder access, the store key off Apple, real CloudKit and
> every cross-device matrix row are *not verified*. Prudent Local inherits that gap; unit 12 is the
> release gate that closes it.

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

## Phase 0 — Decisions (each ends in an ADR before code that depends on it)

### 0.1 Shape: a second app, sharing screens through a package
Today `client/` is one app whose screens call `PrudentRepository` (600 lines) over `ZenClient`.
Decide the split. **Recommendation:** extract the screens and domain types into a package both
apps use, keep `client/` as the server-connected app, add `local/prudent_local_client` as the
Local app. Alternative rejected unless the spike shows otherwise: one app with a runtime mode
(forbidden for client config) or a compile-time flag in one app (puts server code in the Local
binary's source graph and forces web builds to carry the local store's conditional imports).
Output: ADR, and the directory layout.

### 0.2 Money under merge
How do balances, transfers, corrections and goal allocations behave when two devices edit offline?
Decide: balance derived from records; a transfer is two legs created together, and what happens if
only one arrives; what an edit to a record that another device deleted means; which fields merge
without a question and which are a conflict (amount and account are conflicts; note and category
are not). Output: ADR with the per-field table for every proto message in `proto/prudent/v1/`.

### 0.3 Inventory of what the server enforces
Walk the 22 migrations, every `CHECK`, unique index and resource for the rule it holds
(normalisation of account numbers, import fingerprints, archive and category kind, budget
carry-over resets, goal eligibility, plan occurrence state, row-level security). Output: a table in
this plan's PR — rule, where it lives today, where it will live locally, test that proves it.
Rules with no local owner are findings, not footnotes.

### 0.4 Moving existing data
Is there a path from a server account to a Local one? The privacy export already exists
(`privacy.proto`). Decide: import that export into a fresh Local store, or no migration and a
fresh start. Either is acceptable; silence is not.

### 0.5 Threat model for a ledger on a device
Lost device, a PIN that is forgotten, a shared cloud folder that holds ciphertext of someone's
finances, a Linux desktop with no secret service, a statement file left in Downloads. Output: ADR
and a list of what the app must refuse or warn about. Reviewed before unit 9 lands.

### 0.6 Pins
Prudent consumes jZen by path at a pinned ref. Local needs jZen at or after the merge of
jZenDev/jZen#229 (Flutter 3.50, Dart 3.14) and the Local packages. Decide the ref, and whether
`client/` follows the Flutter upgrade first (its CI pins 3.44.2, local machines run 3.50).

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
Port the pure rules to Dart: money and currency handling (`Currencies`), identifier rules,
account-number normalisation (NFC, white space, root-locale upper-casing, ADR-090), validation.
Build the parity harness: a scenario script runs through the server (real Quarkus in
`test:e2e`) and the local code and the figures are compared. Golden vectors are generated from the
Java implementation and committed. **Done when:** the harness runs in CI with the first scenarios
and fails on a one-cent difference.

---

## Phase 2 — The Local data layer

### Unit 4 — Store model and merge
Map every proto message into `zen_store`; device-minted UUIDs (the server minted ids because
"an id from an untrusted client is not identity" — locally the device is the only authority, so the
reason changes, and the ADR says so); per-field merge as decided in 0.2. **Done when:** two real
sessions, each with its own encrypted store, merge disjoint edits and surface the conflicts of 0.2,
through `ZenFolderCloud` (as `two_devices_test` does in jZen).

### Unit 5 — Ledger: accounts, records, transfers, corrections
Balances derived; transfers as paired legs; corrections; archive. Row-level security has no local
meaning (one person per store) and is recorded as such. **Done when:** parity scenarios for every
balance-changing path pass, including a transfer with one leg late.

### Unit 6 — Categories, budgets, goals, allocations, plans, occurrences, reminders
Budget carry-over and its resets, goal envelopes and free money, plan occurrences and their state,
reminders. Reminders use local-device notifications only. **Done when:** parity scenarios cover each
and the figures match the server's to the cent.

### Unit 7 — Analytics
Spend by category and by month, computed from the local store. **Done when:** parity on a large
synthetic ledger, and a stated bound on how long the overview takes at that size on the slowest
target (Android), measured.

### Unit 8 — Erste statement import
Port `ErsteStatementImporter`, `ImportWorkflow` and the three enforced phases (ADR-089); the
versioned fingerprint plus occurrence number (ADR-091); the whole file validated before any row is
returned (ADR-090); only normalised rows kept, never the file; committed in one local transaction
(ADR-092) with a repeat answering the same. **The new problem:** two devices that import the same
statement must merge to one set of records, so the fingerprint must be an identity the merge
understands. Fixtures are the synthetic ones of ADR-088. **Done when:** the failure catalogue of
ADR-094 passes locally and "nothing was written" holds on every refusal, and a two-device test
imports one statement on both and ends with each row once.

---

## Phase 3 — The application

### Unit 9 — `prudent_local_client`
No sign-in, no profile account section. Sync through `ZenSync.start`; PIN from `zen_ui_lock`;
Settings → Sync, Add a device, Join, Erase this device's copy, all from `zen_ui_*`. English,
Ukrainian and Polish. Screens from the shared package; nothing hand-rolled
(`verify:controls`). A copy of the person's data (the local counterpart of ADR-071's export) and
erasure of this device's data. **Done when:** widget, integration and a11y suites pass, and the
threat model of 0.5 has a test or a written refusal for every row.

### Unit 10 — Moving data in
As decided in 0.4: import of the privacy export into a fresh store, or the recorded decision not
to. **Done when:** a synthetic export round-trips and every figure matches the server's.

### Unit 11 — Taskfile and CI
`task` runs the Local app with no server, refuses web, and builds on iOS, macOS, Android, Windows
and Linux in CI (jZen's `Taskfile.app.yml` already supports this). `verify:boundaries` forbids
`zen_transport`/`zen_identity` in the Local app and Local code in `client/`. **Done when:** a
deliberate violation of each rule fails the gate.

---

## Phase 4 — Close

### Unit 12 — Verification on real devices (release gate)
Depends on jZenDev/jZen#231. Windows ↔ Linux ↔ Android over Syncthing and Dropbox/OneDrive;
macOS ↔ iOS over CloudKit once a paid Apple Developer Program exists, `ZenFolderCloud` before. For a
ledger the matrix adds: the same balance on every device after offline edits, an import on two
devices, a forgotten PIN, a lost device. **Not done by a coding session; recorded as "not
verified" in `docs/` until a person does it.** Prudent Local is **not released** before this.

### Unit 13 — Documents
README, `CLAUDE.md`/`AGENTS.md`, `docs/product-roadmap.md`, `docs/zen-architecture.md`, the privacy
policy (a Local app has no server to hold data: say so, and say what the sync service sees),
`docs/jzen/README.md`. Move this plan to `docs/implemented-plans/` with each unit's PR linked and
whatever was not verified stated at the top.

---

## Open risks

- **Merge semantics for money** are the hardest part and are decided in 0.2 before any code; if the
  per-field table cannot be made honest, the answer is a narrower Local (e.g. one writer device),
  not a silent compromise.
- **Parity drift:** a server change that is not mirrored locally. The parity suite is the guard;
  until it covers a rule, the rule is listed as uncovered in 0.3.
- **Inherited jZen gaps** (#231). Prudent Local cannot be more verified than the framework under it.
- **Size of the port.** The importer and the budget/goal rules are the bulk; units 6 and 8 may need
  splitting once 0.3 has counted the rules.
