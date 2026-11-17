# Prudent — architectural decisions

This is **Prudent's own decision log**, numbered from **ADR-001**. It is **append-only**: add an
entry, never edit an accepted one. A decision that turns out to be wrong is superseded by a later
entry that says so, because the reasoning that led to the wrong answer is the part worth keeping.

It is **distinct from jZen's archive** (`../jZen/docs/architecture/DECISIONS.md`). Do not renumber
against it, and do not write Prudent decisions into it — `../jZen` is read-only from this
repository. jZen's ADRs constrain Prudent only where Prudent actually consumes the framework: the
contract, the transport seam, auth, migrations. Where a jZen rule and a Prudent rule conflict on
something **Prudent** owns, Prudent's wins and the divergence is recorded here as an entry of its
own — ADR-001 is the first instance.

---

## ADR-119 — Prudent Local reads a plan's occurrences from its schedule and never generates them; completion is the confirming record; time is an argument; a plan two devices disagree about has no occurrences

**Date:** 2026-11-16. **Status:** accepted. **Plan:** unit 6b of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245);
phase-0 §0.3 rows 6.29–6.45 and 6.51–6.53; findings F-07, F-08, F-11. **Builds on:** ADR-037 to ADR-040 (plans, recurrence, occurrences,
confirmation), ADR-042 (planned cash flow), ADR-054 to ADR-058 (reminders and their notifications), ADR-102, ADR-107, ADR-111, ADR-113.
**jZen:** nothing new is asked of the framework; `JZEN_REF` moves to `4fa887a` (which carries jZenDev/jZen#245 and #251 for the write
paths this unit's writes go through).

### Decision

- **Where it lives: `PlanLedger`, beside `Ledger`** (`local/prudent_local_store/lib/src/ledger/plan_ledger.dart`), taking the wire plan,
  occurrence and reminder requests and answering the wire messages, as `ZenResult`s with the server's statuses (`LedgerErrors`). Its
  pure rules are in `prudent_local_core`: `RecurrenceRule` (the date arithmetic), `ReminderLeadTimes` (finding F-08), `PlanZones` (the
  zones and the day in one), `CivilDate`'s calendar arithmetic (`plusDays`/`plusMonths`/`plusYears`, epoch days), and
  `LocalIds.compareAsJavaUuid` (finding F-11). The existing local-notification scheduler of `packages/prudent_ui` is **reused unchanged**:
  it reads `Plan` and `PlanOccurrence` wire messages through the repository seam, and `PlanLedger.listPlans` and `upcoming` answer
  exactly those. Wiring is unit 9's.
- **Nothing is generated; an occurrence is read from the rule each time.** The server materialises a plan's window on every view and
  keeps the rows. Here the dates a rule produces are a pure function of the plan (`RecurrenceRule.occurrencesBetween`, computed from the
  anchor, so 31 January clamps to 28 February and returns to 31 March), and what is stored is only what a person decided: an
  `OccurrenceState` (skipped, or a reminder read) under an id derived from the plan and the date (`DerivedIds.occurrence`), **only while it
  differs from the default**. Listing writes nothing. Both sides look back at most 366 days (`OccurrenceResource.LOOKBACK_DAYS`); Local
  makes that the rule in every case, where on the server an overdue row once generated stays for good (stated difference below).
- **Completion is derived: an occurrence is completed when its confirming record exists.** Confirming writes **one** record — the plan's
  title, payee, note, amount, account and category unless the request overrides date, amount, account or category — through
  `Ledger.recordForConfirmation`, so every record rule applies in its order, under the id `DerivedIds.confirmation(occurrenceId)`, carrying
  the plan link. Two devices that confirm one occurrence write one record; if their overrides differ it is one record in conflict, which
  no balance reads (ADR-113). Deleting the record reopens the occurrence because nothing else said it was done. It goes through
  `writeAll` as a batch of one, so it inherits the write precondition of jZenDev/jZen#251 with every other write. `PlanLink` gains
  `occurrence_date` (immutable): the id is a hash and cannot be turned back into a date, and an occurrence completed under an earlier
  schedule is still listed, as on the server.
- **Skipped and completed together is a state a merge can reach and the server cannot.** One device skips, another confirms: the occurrence
  reads as **completed** (money moved) and the new integrity check `occurrence.skipped_and_paid` lists it, with two actions: clear the
  skip, or delete the record (which reopens it, skipped). Nothing is fixed silently.
- **Deleting a plan** deletes it and its occurrence states in one `writeAll`. Its records are *detached by being read as detached*:
  `Ledger` answers a record whose plan no longer exists without `planId` and `planOccurrenceId`, which is all `detachFromPlan` does
  (row 6.34). Nothing is written to the records, so a plan deleted on one device while another confirms leaves a record that reads as
  detached on both. Replacing a plan whose schedule changed deletes, in the same write, the stored states of still-planned
  occurrences the new schedule no longer produces (`OccurrenceGenerator.dropStale`); skipped and completed ones stay. An occurrence the
  schedule no longer produces that is *restored*, or whose confirming record is deleted, keeps a state record of its own, because the
  server keeps its row planned (`Ledger.deleteRecord` writes it in its batch).
- **Time is an argument** (finding F-07). Every operation whose answer depends on the day takes `asOf`, reckons it in each plan's own
  zone (`RecurrenceRule.today`), and nothing in the package reads a clock. `reminder_read_at_ms` is written from `asOf` and kept at its
  first value when already set; two devices that read on one reminder merge by `ZenMergePolicy.earliest` without a question
  (ADR-111, jZenDev/jZen#235).
- **Zones.** A plan may name exactly the ids `ZoneId.getAvailableZoneIds()` answers on the server's JDK (604 on JDK 25: region ids and
  legacy aliases such as `US/Pacific`, never a fixed offset), a generated list (`java_zone_ids.dart`, `tool/generate_java_zone_ids.dart`),
  less eight that Local refuses (`PlanZones.unsupported`): `Africa/Casablanca` and `Africa/El_Aaiun` (the clock follows Ramadan, which
  the database does not carry) and the JDK's `SystemV/*DT` ids (the pre-2007 US rules, followed by no zone in the database). The
  calendar day comes from `package:timezone`; `plans.json` holds it to `LocalDate.ofInstant` at each midnight of 22 zones whose rules
  are stable, the second before and after. **No per-zone offsets are committed.** A first version did, and CI failed: Temurin 25.0.3 and
  25.0.5 (and GraalVM 25.0.2) carry different tzdata, so a committed table of the JDK's offsets for legislated zones (Moldova, the
  Canadian provinces, Morocco) is true of one JDK build and false of the next, and says nothing about what the server does. What the
  limit costs is stated instead: a zone legislated since `package:timezone`'s data is read at the older rules until the package moves,
  so a plan in it can turn overdue an hour early or late on the changed days. Beyond 2037 the package stops too. The server's
  recurrence rule is held in `plans.json` (about 45 rules, 4 windows each, the `+999999999` calendar edge) and so are the lead days.
- **Lists and their order.** Plans are ordered start date then id (SQL byte order, which is the text order of Local ids); upcoming,
  overdue and reminders by date then **Java's signed `UUID.compareTo`** of the id, as the server's in-memory sorts do (F-11). Ids differ
  between server and Local, so the parity suite compares ties as a set per date and states, for each side, whether ties came out in the
  signed order.
- **A figure never reads a value two devices disagree about** (ADR-113, carried forward). A plan in conflict about its amount, account,
  category, schedule or reminder, or about whether it exists, and an occurrence state in conflict about whether it was skipped or its
  confirming record about existing, has no occurrence in any list, no reminder, and cannot be skipped, restored, confirmed or read (409)
  until it is settled. `upcoming`, `overdue` and the reminder list answer `Settled<…>` naming what was left out by plan — planned cash flow
  (ADR-042) is their sum, so it leaves it out too. A conflict about a title, payee or note changes nothing. Unit 5's "still used by" reads
  of plans (`deleteAccount`, `updateAccount`, `deleteCategory`) now read `LedgerView.planValues()`, which includes every side of a
  conflicted plan, as `recordValues()` does for records.
- **Parity without a pinned server.** The server's plan routes read the wall clock and take no `asOf`; adding one would change the contract
  for the sake of a test. So a scenario never names a date: it names `@today(Europe/Warsaw)+3`, which `ParityClock` resolves once
  before either backend runs the step, and Local reads the same instant as its `asOf` while the server reads its clock a moment
  later. If a zone's midnight passed during the run the engine runs the scenario again (and fails if it happens twice). **The day
  boundary is proved without pinning the instant:** `Pacific/Kiritimati` (UTC+14) and `Pacific/Pago_Pago` (UTC−11) are 25 hours apart, so a
  date that is today in one is overdue in the other at every instant (`day_boundary`, `reminders`). The exact instants are proved
  against the JVM's own `LocalDate.ofInstant` (`plans.json`, `plan_zones_test`) and at pinned instants in `plans_test`.

### Differences from the server, on purpose

1. **Nothing is materialised.** The server's overdue view lists rows generated in earlier views, however old; Local lists the last 366 days
   from the schedule every time. A person who opened the app every day for two years sees, on the server, the same overdue list they
   would see here, bar anything older than a year.
2. **An id Local never listed** (an occurrence beyond today ± 366 days) is found by the same window and answers 404 where the server, which
   would have no such row either, also answers 404 — a difference only for a guessed id.
3. **Skipped-and-paid** (above) cannot happen on the server.
4. **Two devices** can disagree about a plan, and then its occurrences leave the lists (above); the server has one writer.

### Not verified

- Nothing here has run on a device: no notification has been seen, the plan screens are not built (unit 9), and the shared screens'
  plan forms do not exist (CLAUDE.md: no client screen sets a reminder).
- The server was run in a local stack (`task test:e2e`'s shape, from a worktree: the jar on another port with the Supabase keys of
  `supabase status`), not in CI by this change; CI runs `task test:e2e` and will compare every scenario.
- Offsets past 2037 are not the JVM's, and a zone legislated since `package:timezone`'s data is read at the older rules.
- A real daylight-saving change crossed while a plan is open on a device has not been seen.

### Consequences

New: `local/prudent_local_core/lib/src/plans/`, `test/golden/plans.json` (written by `GoldenVectorsTest.plans`), `ParityClock` and the
engine's rerun, the readers for plans, occurrences and reminders, 14 parity operations on both backends and 6 scenarios (`plans`,
`occurrence_windows`, `occurrences`, `schedule_change`, `day_boundary`, `reminders`), `PlanLedger`,
`OccurrenceSkippedAndPaidCheck`, `PlanLink.occurrence_date`, `plans_test`, `plans_two_devices_test`, and a `timezone` dependency of
`prudent_local_core`. `JZEN_REF` is `4fa887a`.
## ADR-117 — The server-connected app saves the privacy export through jZen's `zen_save_file` on every platform, so iOS and Android get "Save to a file" too

**Date:** 2026-11-16. **Status:** accepted. **Plan:** unit 10a (mobile half) of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245).
**Builds on:** ADR-083 (no CocoaPods), ADR-103, ADR-110 (which left iOS and Android open; ADR-110 is accepted and not edited).
**jZen:** consumes jZenDev/jZen#246 (fixed by PR #254, which merged without closing the issue, so it still showed open on 2026-11-16) at
`JZEN_REF` `4fa887a`.

### Decision

- **One save path, the framework's.** `saveExportFile` is now `zenSaveFile(name, bytes, mimeType: 'application/json')` from `zen_save_file`
  (`path:` dependency of `packages/prudent_ui` and `client/`). It returns true once written and false on a cancel, and throws `ZenSaveFileError`
  when the platform refuses the write. `file_selector` is no longer used for the export; it stays only for the statement picker (ADR-093), a different
  job (choosing a file to read), where its API fits.
- **No platform branch.** `exportFileSavingSupportedProvider` is deleted, so the screen offers "Save to a file", with the not-encrypted warning ahead of
  it, on iOS, Android, macOS, Windows, Linux and web. I did not keep `file_selector` on desktop and web: `zen_save_file` covers them with the same call
  (the save panel, a download), and a second path would be a second thing to keep equal for no gain.
- **Unchanged:** the warning before the button, a cancel saying nothing, the `finally` that resets the in-progress flag, the web's "handed to your
  browser's downloads" wording (`exportFileSavedByDownloadProvider`), and the localized `privacyExportSaveFailed` sentence in en, uk and pl.
  A refused write (`ZenSaveFileError`) is caught as an `Exception` and goes to the log with its stack; the screen shows only the localized sentence, never the cause. An `Error`
  that is not a `ZenSaveFileError` still propagates.
- **Boundaries.** `zen_save_file` depends on `file_picker`, `flutter` and `meta` only, so `prudent_ui` still imports no transport, identity or
  secure-store package (`task verify:boundaries`, check E).
- **Swift Package Manager (ADR-083).** `file_picker` resolves on iOS and macOS through its Swift package `file_picker_darwin`: the runners gained the
  plugin registration (`client/macos/Flutter/GeneratedPluginRegistrant.swift`) and no Podfile, Pods directory or `[CP]` phase; `verify_no_cocoapods.py`
  stays green.
- **`JZEN_REF` moves from `e6a06c6` to `4fa887a`** in `ci.yml` and `audit.yml`; the only jZen change in that range this repository consumes is
  `zen_save_file`.

### Tests

`client/test/privacy_screen_test.dart`: the screen over a fake `ExportFileSaver` (save round-trips to an equal `DataExport`, cancel is silent, a
`ZenSaveFileError` shows the sentence, an `Error` still stops the spinner, web wording) and `saveExportFile` over a fake `ZenSaveFilePort`
(name, bytes and `application/json` pass through; cancel is false; a refused write throws `ZenSaveFileError`). The test that the button is absent where
no save exists is removed with the provider.

### Not verified

The save sheet on a real iOS or Android device, and on a real macOS, Windows or Linux desktop, has not been seen: the suite stands in for the plugin.
That belongs to unit 12, together with one thing not checked at all: on Linux the save moved from `file_selector_linux` (GTK) to `file_picker_linux`, whose runtime requirements (a dialog helper such as zenity or kdialog) were not read; a desktop without it would show the failure sentence. Built here, debug, with no CocoaPods: the macOS app (`flutter build macos`), the iOS simulator runner (`--simulator --no-codesign`) and the Android debug APK; `task verify:swiftpm`'s script (`scripts/verify_no_cocoapods.py`), `verify_boundaries.py` and `verify_controls.py` pass, and `flutter analyze --fatal-infos --fatal-warnings` is clean in `client/` and `packages/prudent_ui`. None was launched. `task` does not load from a worktree (ADR-065), so the scripts were run directly. CI's `android-runner` is the Android check of record.

---

## ADR-116 — Prudent Local's budgets, carry-over resets, goals and envelopes reproduce the server's rules over the store, leave every disputed value out of a figure, and check each rule again inside its write

**Date:** 2026-11-16. **Status:** accepted. **Plan:** unit 6a of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245);
phase-0 §0.3 rows 6.1–6.28, 6.46–6.50, 6.54; finding F-07, F-10. **Builds on:** ADR-043 to ADR-053, ADR-102, ADR-107, ADR-111,
ADR-113, ADR-114. **jZen:** consumes jZenDev/jZen#251 (PR #254, `expect`) at `JZEN_REF` `4fa887a`; relies on #235 (declared by
unit 4) and #244 (the revocation's `earliestBy`, declared by unit 8b, ADR-114).

### Decision

- **Where it lives: two parts of the ledger's library**, `ledger_budgets.dart` (`extension LedgerBudgets on Ledger`) and
  `ledger_goals.dart` (`extension LedgerGoals on Ledger`), so they share the ledger's refusal plumbing, its date rules and
  `LedgerView` without widening `Ledger`'s file, which units 6b and the #245/#251 consumption also edit. Each operation is the
  server's resource method check for check and in its order (`BudgetResource`, `BudgetCalculator`,
  `BudgetCarryOverResetResource`, `GoalResource`, `GoalState`, `GoalAllocationResource`, `FreeMoney`, `GoalProgressCalculator`),
  wire requests in and wire messages out, refusals shaped as the server's (`LedgerErrors`). `Ledger` gains an injectable clock
  that labels what an audit entry records (a reset, a revocation, a goal's times, an entry) and orders the histories, as
  `created_at` does on the server; it decides no merge and no figure.
- **Every figure is derived on every read and never reads a disputed value** (ADR-113, carried forward). The budget summary and
  the carry-over leave out a record whose posting, date, category or existence two devices dispute, a budget whose amount or
  existence is disputed, and a reset in conflict, each named under its category in `Settled.unsettled`; a category whose only
  budget in the month is disputed has no item and is named all the same. Free money leaves out an account whose `active` or
  `eligible_for_goals` flag (or existence) is disputed, under every currency it holds, plus whatever its balance leaves out.
  Goal progress leaves out a goal whose target, date or status is disputed, keyed by the goal. `Settled.unsettled` is therefore
  keyed by what the figure belongs to — an account, a category, a currency or a goal — and its documentation says so. Envelopes
  need no flag: entries are immutable, so an envelope never reads a disputed value.
- **Refusals that a figure decides refuse while the figure is unsettled**, as a correction does (ADR-113): a reset (it records
  the carry-over it discards, which must be a number someone saw) and an `ALLOCATE` (its cap is the currency's free money), both
  409. A rule about a goal's state reads every side of its conflict: money goes into a goal only when every side is active, and
  out of one only when no side is archived. `deleteCategory`'s "still used by a budget / a reset" now reads every side of their
  conflicts (`LedgerView.budgetValues`, `resetValues`), as it already read records.
- **Each rule is checked again inside the write's turn** (jZenDev/jZen#251). Every budget, reset, goal and entry write passes an
  `expect` that re-reads the store as it stands when the write runs and runs the same rule again — the category not archived for
  a new slot, one live reset per slot and the same discarded carry-over, the envelope and the free money for an entry, the
  envelope for an archive — and, for an edit or a delete, the record exactly as read (same bytes), so a field another device
  changed in between is refused (404 gone, 409 changed) rather than written back. Proven deterministically by queuing a
  conflicting write between the ledger's check and its write; with the `expect` removed every such test fails.
- **A reset's revocation merges by `earliestBy` its time** (jZenDev/jZen#244, declared by unit 8b, ADR-114): two devices that revoke
  one reset keep the earlier revocation, whole, on both, so `revokeBudgetReset` needs no settling of its own. **No
  `explicitPresence` is declared** (jZenDev/jZen#245), as ADR-115 decides for every collection: the `optional` fields here —
  `Goal.target_date`, an entry's source and target goal ids — have no meaningful default (an empty date or goal id is never
  written; an absent date is cleared), so declaring them would only make `""` and a cleared field conflict.
- **Integrity checks** (ADR-102 D6): `EnvelopeBelowZeroCheck` (two withdrawals made apart) offers a compensating `ALLOCATE` of the
  deficit; `ArchivedGoalMoneyCheck` (money put into, or left in, a goal archived meanwhile) offers reactivating the goal or a
  `WITHDRAW` of what it holds. Neither edits or deletes an entry: the history only grows. Two live resets for one slot stay
  unit 4's `LiveResetSlotCheck`. One envelope sum, `goalEnvelopes`, serves the ledger and both checks.
- **The progress arithmetic is a core rule** (`GoalArithmetic` in `prudent_local_core`: the exact percent, the inclusive calendar
  months, the rounded-up contribution), held to `GoalProgressCalculator` by a new golden file, `goal_progress.json`, which
  `GoldenVectorsTest` writes through `prudent.goal.GoalRulesAccess` (test-only, no production change) — including the 64-bit
  edges (`intValueExact` throwing for an envelope far below zero, `ceilDiv` near `Long.MAX_VALUE`) that no scenario reaches.
- **Parity.** Ten scenarios run every rule through the live server and the store: `budget_slots`, `budget_summary`,
  `carry_over` (months with no budget, earlier budgets and records edited), `carry_over_reset` (the boundary, the latest live
  reset, a revocation restoring the sum), `budget_lists`, `goals`, `goal_allocations`, `free_money` (name order, inactive and
  ineligible accounts, free money going negative after a spend and a transfer), `goal_progress` (every guidance, `asOf` pinned,
  finding F-07) and `goal_lists`. The server's user is shared by a run (ADR-107), so each scenario owns its currencies and months,
  and lists keep only the scenario's own rows; a summary's items, ordered by category id on both sides, are compared as a set
  with the id order observed as a fact. Unit 3's `budget.set` and `reset.create` stand-ins are gone. Mutations of the carry-over
  boundary, the `active` flag and the contribution rounding each fail the suite.

### Not proven

- The race tests queue the conflicting write on one device; a sync's `receive` takes the same turn in the store's queue, but no
  test drives a real sync into that window.
- `listBudgets`, `listBudgetResets` and the goal and envelope lists show records as the store shows them, disputed or not, as
  the record list does (ADR-113); only figures leave disputed values out.
- Nothing has run on a device (jZenDev/jZen#231); no screen shows `Settled.unsettled` yet (unit 9).

---

## ADR-115 — Every Prudent Local write carries what it was decided against as the store's precondition, and the store keeps a top-level default as unset; no synced collection declares an explicit-presence field

**Date:** 2026-11-16. **Status:** accepted. **Plan:** units 4 and 5 of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245);
phase-0 §0.2 (the per-field table) and §0.3 X.7. **Builds on:** ADR-102, ADR-111, ADR-113, ADR-114. **jZen:** consumes jZenDev/jZen#251 (write
precondition) and #245 (proto3 presence), both PR #254, at `JZEN_REF` `4fa887a`; files jZenDev/jZen#255.

### Decision

- **The store's own rules run inside the write's turn.** `PrudentLocalStore`'s write-once, immutable-field and "a correction is never
  edited" rules used to be checked with a `get` before the `put` (`_admit`); a sync's `receive` already queued ran in between, so a
  rule held only for a version that was no longer there. They are now the `expect` jZen runs against the record as it stands when the
  write takes its turn (`_admitting`), single writes and `StoreBatch` alike. The id rule stays outside: it reads only the value. A stored
  record that no longer decodes is still never written past — jZen answers its decode failure before any `expect` runs (ADR-111, PR #258).
- **Every write takes a `WriteExpect<T>`** (`ZenError? Function(T? current)`), passed through to `ZenCollection.put`/`delete` and
  `ZenBatch`. `WriteExpects.asRead(basis)` is the one Prudent uses: the record must still be **exactly** the version the write was decided
  against (the same serialised bytes), or still absent when `basis` is null. Exact, not "the fields this write touches": a write puts a
  whole message, and the store counts every field that differs from the stored one as this device's edit, so a field another device
  changed in between would be written back to the value read — a last writer winning. Refused instead, the person looks again.
- **The ledger passes it on every write** (ADR-113's operations): an edit of a record, category, account or the settings carries the
  version its rules were checked against; a create carries "still absent"; the account delete with its records carries each record,
  transfer, currency and the account as read; archive, restore and the category delete likewise; a correction is written "absent" and
  deleted "as read". A record deleted meanwhile answers **404 under the rule that finds it** (5.1, 5.15, 5.31, 5.37, 5.38) — what the
  server answers when the delete came before the request — and stays deleted. On a put that is the `gone` of `asRead`; on a delete jZen
  answers an absent record itself, with a bare `ZenNotFoundError`, before any precondition runs, so the ledger maps that answer
  (`_write(missing:)`) to the same 404 — or, when the missing record is one of many in a batch (an account deleted with its records, an
  account update dropping a currency), to the 409 of X.7, because the state the operation was decided on is gone. A not-found that already
  carries a ledger status passes through unchanged. One changed meanwhile answers **409 under §0.3 X.7**, where
  the server holds a row lock; the other device's edit survives. "Start fresh" accepts a starter that is absent or byte-equal (another
  device's identical starters arriving is no edit) and refuses any other.
- **The repairs carry it too.** A re-creation (`recreate_account`, `recreate_category`, `add_currency`) expects "still absent", so a record
  another device restored or added is not reset to defaults; an edit built from a record (`move_to_*`, `clear_account_number`, the
  default-account choice, `category_takes_both`, which is built from the category the check saw) expects that version; the
  correction-intent replacement expects each correction it summed and "absent" for the replacement — a correction is immutable, so of
  those what can happen meanwhile is its deletion, which jZen's own existence check on a batch delete already refuses; the precondition
  states the intent and holds if corrections ever become editable. A plain delete repair acts on the record as it stands when it runs, as
  before.
- **What a precondition cannot hold is still the integrity checks'.** `expect` sees only the record being written. A rule across records
  — a record filed under a category another device deletes, a record added to an account being deleted, a balance a correction's delta is
  taken from — can be broken by a sync arriving one moment *after* the write just as well as one moment before, so checking it in the turn
  would win nothing; D6's checks list it after the merge, as ADR-111 and ADR-113 already say.
- **Presence: no synced collection declares `explicitPresence`.** jZen now stores a top-level implicit-presence field at its default as unset.
  An `optional` field must be named only where "set to the default" means something other than absent. Every top-level `optional` field of
  Local's store messages is a string — `Record.category_id`, `payee`, `note`; `Goal.target_date`; `GoalAllocation.source_goal_id`,
  `target_goal_id`; `Plan.payee`, `note`; `Settings.default_account_id` — an id, a date or a trimmed text, for which `""` is never written
  and would mean "none", exactly as absence does (`TextRules.optionalTrimmed` maps blank to absent; `""` is no id or date). Declaring them
  would keep apart two spellings of "no payee" and make them conflict. `merge_table_test` pins the list from `store.proto`, so a new
  `optional` field of another type fails until this decision is made for it. `ReminderSetting.lead_days` is `optional` but nested, so
  the rule does not reach it (below). The device-only `import_sessions` (`imports.proto`, ADR-114) is the one collection that declares
  it, and rightly: there `committed_written` = 0 — a commit that wrote nothing — is a value, not "never committed".
- **§0.2 checked against the new behaviour:** a record rebuilt with every default written out is no edit and merges beside another
  device's real change to one of those fields; a note cleared by `""` on one device and by `clearNote()` on the other is one value; clearing
  a payee against a new payee is still a question (Merge); a reminder marked unread with an explicit `0` against a read is still a question
  — before #245 the explicit `0` was a value, and `earliest` would have kept it, silently undoing the read.
- **The rule stops at the top level: jZenDev/jZen#255, filed.** A nested message (posting, schedule, reminder setting, correction intent)
  is versioned by its bytes; an implicit-presence field written at its default inside it differs from an unset one. Every writer of a
  group therefore keeps building it with its defaults unset — the ledger's clearing of a zero target and seen balance on a correction's
  intent stays, now citing #255. `merge_table_test` pins the conflict so it flips when the fix lands.
- **The ledger keeps building records with their defaults unset at the top level too, on its own merits.** It was a #245 workaround; it is
  kept because `put` answers the value it was given, not the stored record, and `WireMapper` copies presence exactly: an explicit `false`
  would answer a record that differs, by presence, from the next read of the same one. `restoreCategory` therefore still clears
  `archived`; `ledger_test` asserts the restore's answer equals the next read byte for byte (setting `false` turns it red).
- **Records already stored keep their old form until next written.** A record written before this change may hold an explicit default;
  jZen normalises on write, so it is rewritten the next time any device writes it. Nothing has shipped — no device holds a Local store —
  so no migration is needed or written.

### What this supersedes, and why

- **"Presence-exact writes (jZenDev/jZen#245) … Restoring a category clears `archived` rather than setting it false"** (ADR-113) →
  **the store now canonicalises; presence-exact construction stays for the answer's sake (top level) and for #255 (nested groups).**
  *Why:* #245 merged; the reason that remains is argued above, not inherited.
- **"`WireMapper` copies field presence exactly … The store does not canonicalise writes in the meantime"** (ADR-111) → **the store
  canonicalises top-level fields; the mapper still copies presence exactly**, because its round trip is byte-for-byte and nested groups
  are still compared as bytes.
- **"New jZen gap, filed: jZenDev/jZen#251 … A stated limitation of every write path until it lands"** (ADR-113) and **"the interleaving
  behind #251 is reasoned from the code, not reproduced"** → **consumed and reproduced**: the interleaving is driven in
  `write_precondition_test` and every write path of units 4 and 5 is held.
- **`_admit`, run before the write** (ADR-113: "refactored into one `_admit`") → **`_admitting`, run in the write's turn.** Unit 8b's
  import-session writes and the commit's batch, which passed their `expect` beside `_admit`, now go through the same `_admitting`, their
  own preconditions first.
- **"Applying them to the unit 4/5 collections and the ledger's writes is a separate change"** (ADR-114) → **this is that change.**

### Consequence

Verified on 2026-11-16 in the worktree against jZen `4fa887a`, rebased onto unit 8b (ADR-114): `prudent_local_store` 603 green (unit
8b's 579 unchanged, six presence cases in `merge_table_test` and eighteen in the new `write_precondition_test`, each on two encrypted stores:
an edit and a restore against a synced delete answer 404 and nothing comes back; an edit and a settings change against a synced edit
answer 409 X.7 and the other device's value survives; an account delete with its records, one of which a sync moved, is refused whole
with nothing written; review round (#264): a delete of a record, transfer and correction a sync deleted answers 404 under 5.15, 5.31 and
5.37; an account delete with records, one of which a sync deleted, 409 X.7 with nothing written; an account update dropping a currency
whose opening a sync changed, an archive and a category delete against a synced edit, 409 X.7; the correction-intent replacement against a
synced delete of a summed correction refuses whole; `recreate_account` after the other device restored the account is refused and that
version stays; an import session's immutable currency is held against a second write queued behind the first; "Start fresh" against the other device's identical starters writes them once; a transfer arriving before an add of
the same id is never edited by it; a repair built from what the check saw is refused once `ZenFolderCloud` brought a change to that
record). Mutations each turned the matching tests red and were restored: `asRead` passing everything (six of the eight; 8b's
change-in-between cases stay green under it because the commit's own precondition re-plans the commit), write-once skipped in the turn
(the transfer case), `explicitPresence: {7}` on accounts (the rebuilt-defaults case), `archived = false` in the restore (the
answer-equals-read case); the delete mapping switched off (the three delete 404s and the batch case); the re-creation's "absent"
removed (the `recreate_account` case). Creates are written "absent" but not tested: their ids are fresh random 128-bit ids no sync can
deliver first. `prudent_local_core` 2 791 green. **The parity suite against a live Quarkus on the local Supabase (port 8113,
built from this branch): all 15 scenarios agree**, the two import scenarios included. `dart analyze --fatal-infos --fatal-warnings` clean
in the core, the store and `tools/prudent_parity_server`; before the rebase, `flutter analyze` with the same flags was clean in
`packages/prudent_ui` and `client/` on the new jZen (the rebase touches neither); `verify_boundaries.py` and its tests and
`verify_import_fixtures.py` pass.

### Not verified

- `task` does not load from a git worktree (ADR-065): `test:local-store`, `test:local-core`, `verify:analyze`, `verify:boundaries` and the
  parity half of `test:e2e` ran only as their underlying commands here, and run as tasks in CI. The client e2e half was not run.
- `ZenFolderCloud` reads its folder asynchronously and offers no point at which to step in between a check and a write, so the
  check-then-write interleavings queue the other device's `receive` themselves, with exactly the payload its store hands its transport;
  everything else, and the repair case end to end, goes through `ZenFolderCloud`. No device, no CloudKit.
- Units 6a and 6b own their write paths (budgets, resets, goals, plans, occurrences); the store methods take a `WriteExpect` for them,
  but which version each of their writes is decided against is theirs to pass. Unit 8b's import writes pass their own (ADR-114).

---

## ADR-114 — Prudent Local imports a statement through the server's three phases in a device-only collection, and commits every row and the completed session as one `writeAll` whose record ids derive from the row keys

**Date:** 2026-11-16. **Status:** accepted. **Plan:** unit 8b of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245);
phase-0 §0.3 rows 8.1–8.5, 8.10–8.19, 8.24, 8.25; finding F-06. **Builds on:** ADR-089 to ADR-094 (the server's import), ADR-102
(sessions never synced; ids from natural keys), ADR-111, ADR-112 (the parser and fingerprints in Dart), ADR-113 (the ledger).
**jZen:** consumes jZenDev/jZen#232 (`writeAll`, as unit 5), #234 (PR #250, settle many conflicts), #244 (PR #249, a group merge
policy) and, from PR #254, #252 (device-only collections, filed by this unit), #251 (write preconditions) and #245 (explicit presence),
at `JZEN_REF` `4fa887a`.

### Decision

- **`ImportWorkflow` in `local/prudent_local_store/lib/src/imports/` is the server's `ImportWorkflow`, `ImportDuplicateStage` and
  `LedgerImportCommitter`, check for check and in their order.** It takes the wire requests of `imports.proto` and answers the wire
  `ImportSession`, `UpdateImportRowResponse` and `ListImportSessionsResponse` (`ImportMapper`), so the shared import screens read it
  unchanged. Every refusal carries the server's status and, where the server's message is a rule code with rows, that message word
  for word: the screens' `ImportFailure` reads only that. The five session-stage codes unit 8a named (`account.not_found`,
  `duplicate.already_imported`, `commit.category_unavailable`, `commit.account_unavailable`, `commit.row_refused`) are emitted here.
  On one device the workflow is serialised, as the server's row lock serialises two requests on one session.
- **Sessions are the device-only collection `import_sessions` of the ledger's own store** (`ZenStore.collection(syncs: false)`,
  jZenDev/jZen#252), declared by `PrudentLocalStore` with the others, before any transport starts. Its records are never sent and a
  record of that name arriving from a transport is refused, so statement rows reach no other device and no sync service (ADR-102);
  they are encrypted like the ledger. One session is one record of its own message (`proto/prudent_local/v1/imports.proto`,
  `LocalImportSession`), rows included. Only normalised rows and the statement's identity digest are kept, never the file; the
  24-hour expiry, the lazy expiry on a read, the sweep (`expireDue`, run by the app at launch and on a timer) and the deletion of
  rows, identity and defaults when a session ends behave as on the server. The `optional` fields are declared with explicit presence
  (jZenDev/jZen#245), so `committed_written` = 0 — a commit that wrote nothing — is a value, not "never committed".
- **The commit is one `ZenStore.writeAll`: every record and the completed session together** (jZenDev/jZen#232, #252), through
  `PrudentLocalStore.writeAll`. Each record is built by the ledger's own `RecordWriter.apply` (`Ledger.importedRecord`) with the id
  `DerivedIds.imported(account, fingerprint, occurrence)`. All refusals — the destination checked again, the confirmed count, a row
  without a category, a category gone (`commit.category_unavailable` with rows), a row the ledger refuses (`commit.row_refused`) —
  come before the batch, and a refused operation writes nothing. A crash leaves the records and the completed session, or neither.
  Two devices that commit one statement write the same ids, so each row ends once. A duplicate the person includes takes the next free
  occurrence at commit time, as on the server; included on two devices offline, both choose the same occurrence and it is one record.
- **A rule checked before a write holds when it runs** (`expect`, jZenDev/jZen#251). Every session write expects the session to be
  exactly the one the operation read (a new one: absent). In the commit's batch each record expects to be absent — a record of the
  same row that a sync brought in meanwhile, perhaps under another category, is never written over — and the session's precondition
  checks the destination, the categories and the held keys again against the store as it stands in the write's turn, by planning the
  commit again and requiring the same records and counts. Anything that changed refuses the whole batch with the same rule a fresh
  commit would name, or a 409 saying the ledger changed; nothing is written and the review stays.
- **Duplicates** are rows whose key a ledger record of the destination holds on any side of a conflict (the key is immutable). A row's
  key is computed at preview for the destination account; the session row keeps the statement's text as exact UTF-8 bytes, because
  Dart's UTF-8 decoder — which the protobuf runtime reads every `string` with — drops a leading U+FEFF, and a BLIK counterparty of
  only that mark would otherwise key differently from the server (`ImportText`; found by the catalogue case "a BLIK counterparty of
  only U+FEFF").
- **Differing category choices on two devices are settled with jZen's sweep, not Prudent's** (jZenDev/jZen#234). They are one plain
  disagreement per differing record, on one field, between exactly the two devices — the shape `ZenConflictsScreen` offers "keep this
  device's version for all N" for — and they leave every figure settled (a category is not money, ADR-113). Unit 8b settles nothing;
  the sweep is a Flutter screen of `zen_ui_store`, driven once the Local app gives it the records collection (unit 9).
- **A carry-over reset's revocation merges by its time** with `ZenMergePolicy.earliestBy(Revocation.at_ms)` (jZenDev/jZen#244):
  revoked on two devices, the earlier revocation is kept whole, its author with it (`StorePolicies.budgetResets`). The import itself
  has no time-with-author field.
- **Parity:** the operations `import.create/preview/defaults/row/commit/discard` on both backends, with shared bodies and observations
  (`ImportParity`), and two scenarios, `import_sessions` and `import_destination`: counts, row statuses and codes, committed counts,
  refusals by status and the balances after each commit. Keys are never on the wire and differ anyway (the account id is part of one).
- **Scope against units 4 and 5.** `#245`'s presence and `#251`'s preconditions are declared here only for the import's own collection
  and writes; `StoreBatch.putRecord` gained the `expect` the commit passes. Applying them to the unit 4/5 collections and the ledger's
  writes is a separate change.

### What this supersedes, and why

- **"a one-transaction commit needs jZenDev/jZen#232 (until then the commit validates everything before the first write and is
  idempotent and resumable)"** (plan, unit 8b; §0.3 row 8.16) → **withdrawn: one `writeAll`, the session included.** *Why:* #232 and
  #252 merged; no interim.
- **"ImportSession, ImportRow: … in a second, unsynced store (fact 8)"** (ADR-102, phase-0 §0.2) → **a device-only collection of the
  ledger's store.** *Why:* the same guarantee — never synced, encrypted on the device — and only one store can write the session and
  the records as one. An earlier draft of this unit used a second store with a write-ahead plan to settle a commit interrupted between
  the two stores; it was replaced before merge when #252 landed, and never released.
- **"differing category choices on two devices give one conflict per row until jZenDev/jZen#234"** (plan, unit 8b; ADR-102's stated
  cost) → **withdrawn: they are swept by jZen's screen.** *Why:* #234 merged as PR #250.
- **"a reset's revocation is a group and stays a conflict until jZenDev/jZen#244"** (ADR-111, plan unit 6a) → **merges by its time.**
  *Why:* #244 merged as PR #249.
- **`ImportRow`'s text as `string`** (the wire's shape) → **bytes in the store.** *Why:* the leading U+FEFF above.

### Found, not fixed here

- **Every `string` of every Local store message loses a leading U+FEFF on a store round trip** (Dart's `Utf8Decoder`, through the
  protobuf runtime). The import keys are safe (`ImportText`), but a record title, payee or note that begins with U+FEFF is stored
  without it, where the server keeps it. It is the Dart runtime's, not jZen's; a follow-up for the ledger (unit 5's store messages).

### Consequence

Verified on 2026-11-16 in the worktree against jZen `4fa887a`: `dart test` — `prudent_local_store` 579 green, among them
`import_failure_matrix_test` (all 291 cases of `test/golden/erste_import.json` uploaded through the session workflow: each refusal
names the server's rule and rows, leaves the store byte for byte as it was and quotes no statement text; each accepted statement
lists its rows as the server does, keys them exactly as the server for the server's account id, and commits exactly its accepted
rows; plus the four named workflow cases, the matrix's own, and no logging call in the import code), `import_commit_failure_test`
(the server's ImportCommitFailureTest: categories gone, archived or of the other direction, a renumbered, inactive, currency-less or
deleted destination, expiry, two concurrent commits, discard against commit, a ledger refusal at each row; plus a crash inside the
batch at three points, finished whole at the next opening with an included duplicate written once; and four changes landing between
the checks and the write — a category archived, the destination deleted, the same row's record arriving under another category, the
session discarded — each refusing the batch with nothing written), `import_workflow_test` (31 tests of phases, destination, list,
expiry, bounds, rows, defaults, commit, duplicates), `import_two_devices_test` (two encrypted stores through `ZenFolderCloud`: one
statement committed on both offline ends with each row once; after a sync it is all duplicates; differing defaults are four plain
two-device conflicts on `category_id`, settled for all; an included duplicate on both is one record; no session reaches the other
device, the shared folder or the unsent set) and `merge_table_test` (the revocation). `prudent_local_core` 2 791 green. **The parity
suite against a live Quarkus on the local Supabase: all 15 scenarios agree**, the two import scenarios included. Deliberate mutations
turned the suites red (duplicate detection off: the workflow and two-device tests; the session's precondition removed: three of the
four change-in-between tests, the fourth caught by the record's own), and the file was restored. `dart analyze --fatal-infos
--fatal-warnings` clean in the core, the store and `tools/prudent_parity_server`; `verify_boundaries.py` and
`verify_import_fixtures.py` pass.

### Not verified

- `task` does not load from a git worktree (ADR-065): `test:e2e`, `test:local-store`, `test:local-core`, `verify:contracts`,
  `verify:analyze` and `verify:golden` ran only as their underlying commands here (the parity half of `test:e2e` against a server
  built and started from this worktree on port 8097); the client e2e half was not run. CI runs them as tasks.
- The sweep of #234 is not driven: it is a Flutter screen and no Local app exists yet (unit 9). Only the shape it requires is proven.
- The change-in-between tests land the change before the batch is submitted (a test hook); that a sync queued behind the submission
  runs after the batch's turn is jZen's ordering, proven by jZen's own tests for #251.
- The device-only collection must be declared before a transport starts; `PrudentLocalStore` declares it with the others, and the
  Local app (unit 9) must construct it before `ZenSync.start`.
- No device, no real statement, no screen.

---

## ADR-113 — Prudent Local's ledger reproduces the server's account, category, record, transfer, correction and settings rules over the store, writes several records only through `ZenStore.writeAll`, and never computes a figure from a value two devices disagree about

**Date:** 2026-11-16. **Status:** accepted. **Plan:** unit 5 of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245);
phase-0 §0.3 rows 5.1–5.53, X.1, X.2; findings F-01, F-06, F-09, F-10. **Builds on:** ADR-081 (account deleted with its records),
ADR-101, ADR-102, ADR-105, ADR-106, ADR-107, ADR-109, ADR-111. **jZen:** consumes jZenDev/jZen#232 (PR #248, `ZenStore.writeAll`) at
`JZEN_REF` `e6a06c6`; files jZenDev/jZen#251.

### Decision

- **Where it lives: `local/prudent_local_store`, `lib/src/ledger/`, not a new package.** ADR-101's shape puts the rules in pure Dart
  that the parity suite can run on the VM, and the Local app's `LocalPrudentRepository` (unit 9, Flutter) adapts them. The ledger
  writes only through `PrudentLocalStore` (ADR-111: the only write path) and its checks join that package's integrity runner, so a
  sixth package would only add a pubspec, a task and a gate scope around one dependency edge. Pure-text rules stay in
  `prudent_local_core` (below), so the golden vectors still run with one dependency.
- **`Ledger` is the server's resource methods, check for check, in the server's order.** It takes the wire request messages the
  shared screens already build and answers wire messages through `WireMapper`, as `ZenResult`s. A rule's refusal is a `ZenError`
  shaped as the server's (`LedgerErrors`: `internalData` `code` = `invalid`/`not_found`/`conflict`, `status`, `rule`), so
  `failureCode(error)` reads it unchanged; the store's own errors (a record in conflict, a storage failure) are returned as they are
  and carry no status. A figure that leaves the 64-bit range is an error, never a wrapped value (ADR-107).
- **Several records are written as one only through `ZenStore.writeAll`.** `PrudentLocalStore.writeAll(StoreBatch)` holds each
  operation to exactly the single-record rules (id, immutable fields, write-once; refactored into one `_admit`) and passes the batch
  to jZen; one refused operation writes nothing. Used for an account with its currencies and the default setting, an account
  update that drops a currency, a record whose statement key must go, the starter categories, the correction-intent repair, and
  **an account deleted with its records** (ADR-081): every record on it, every transfer touching it (both legs, one record here),
  its currencies and the default setting naming it, in one batch — all or nothing, on this device. **No resumable or partial delete
  was built**; the plan's interim clause is withdrawn. A record of the account that two devices disagree about is put in the batch,
  so the store refuses the whole delete until it is settled. Another device receives the batch record by record (#232's stated
  limit); what a half-arrived batch, or a record added meanwhile, leaves behind is a dangling-reference issue (ADR-111).
- **A figure never reads a disputed value — excluded and named, consistently** (carried-forward finding 2 of PR #256). While a
  record is in conflict `ZenCollection.get`/`list` show each disputed field from its latest version, which is a wall-clock choice;
  summing it would let two clocks decide a balance. So `LedgerView` leaves out of every figure, on every device alike, a record
  whose conflict touches its posting or its existence (delete against edit), a transfer in conflict, and an account currency whose
  opening is disputed (counted as zero), and `AccountBalances.unsettled` names what was left out. A conflict about anything else
  (note, title, category, date, display position) leaves the money agreed, and it is counted. A correction is refused (409) while
  its balance is unsettled — a delta from a guess would be wrong money. The record list still lists a disputed record as the store
  shows it, because the person has to see what they settle. **The flag travels with the figure:** every ledger read that answers
  balances (`getAccount`, `listAccounts`, `createAccount`, `updateAccount`) answers a `Settled<T>` — the wire message and, by
  account, what its balances leave out — because the wire `Account` has no field for it and a bare wire figure would drop money
  silently. The Local repository (unit 9) must show it beside the figure; the plan's unit 9 says so. Flagging alone (counting the shown side) was rejected for the clock
  reason; excluding without naming was rejected because a figure that silently drops money reads as settled.
- **The default account is the settings record's one field** (ADR-102); creating, updating or deleting an account writes it in the
  same batch, and nothing is written when it does not change. An absent settings record reads as `PLN` and is not written by
  "Start fresh", which would be a choice nobody made; a reset writes `PLN` explicitly, as the person's action.
- **Presence-exact writes** (jZenDev/jZen#245): every store record is built fresh from the request with only non-default fields set,
  so a false flag, a zero opening or an empty description is absent, never an explicit default that conflicts with another device's
  edit. Restoring a category clears `archived` rather than setting it false.
- **Search and name order (ADR-106) are `SearchRules` in the core**, method for method with `prudent.text.TextRules`, and pass the
  server's own vector files (read from `server/src/test/resources/text-rules/`, never copied). **The fold is a table from the JVM**,
  `simple_lower_case.dart`, generated from a new golden file `fold.json` that `GoldenVectorsTest` writes from
  `TextRules.foldCodePoint` for every code point: the Dart VM's `String.toLowerCase` follows an older Unicode than the JDK and
  disagreed on **437 code points** (U+037F, Cherokee, Georgian Mtavruli, Latin and Cyrillic additions), which the exhaustive test
  found on its first run. Java's `isBlank`/`trim` are used, not Dart's (finding 1 of PR #252): a search of only control characters is
  not blank, trims to the empty term and matches every record, as on the server; U+FEFF, U+0085 and U+00A0 are neither blank nor
  trimmed. Pinned by new server vectors t18–t22 and m11, which `TextRulesTest` runs against Java too.
- **The record list** expands each transfer into its two legs first, then applies every filter per row as the server does (dates
  inclusive, account, category never a leg, `type` trimmed and upper-cased as Java does — `ıncome` is income — amount bounds on
  `abs`, search last), ordered `date desc, id`. A row of `Long.MIN_VALUE` under an amount bound is an error, as Postgres' `abs()` is.
- **The correction-intent check (D7) records what each correction saw.** `CorrectionIntent` gains `repeated string seen_corrections`
  (field 3, immutable with the rest): the other corrections of its account and currency the device held. Two corrections neither of
  which names the other were made apart, and their deltas together overshoot — `correction.made_apart`, one issue per group, with
  "delete one" and "replace the group by one correction to the balance one of them asked for" (one `writeAll`). A balance alone
  cannot tell this: a later record legitimately moves a balance away from what a correction saw. A record a correction did not see
  is **not** flagged: with deltas the merged balance is the server's for one of the two orders, and no clock may choose.
- **Row-level security has no local meaning** (§0.3 X.1, X.2): one person per store, whose encryption is the boundary. There is no
  "another user's account" to answer 404 for; every lookup is the store's.
- **Issues stay `IntegrityIssue`, shaped on `zen_ui_store`'s `ZenIssue`** (finding 5 of PR #256): the new check adds no field and no
  type. Nothing needed was missing from jZen there.
- **The parity suite's local side is now `StoreBackend`** (`package:prudent_local_store/parity.dart`): the ledger over a real
  encrypted store, one per scenario. Unit 3's in-memory `LocalRulesBackend` is deleted, as ADR-107 planned. Both backends read answers
  through one set of `ParityReaders` in the core (Local's wire messages via `toProto3Json`) and build requests with the same helpers,
  so they cannot observe differently by accident. `budget.set` and `reset.create` keep unit 3's rule set as stand-ins until unit 6a.
  List observations keep only rows of names the scenario bound (the run shares one server user), group rows by date in the order
  answered, compare one date as a set, and state `idOrder` from each side's own ids. Running each scenario through `StoreBackend`
  against its stated server outcomes is `test/parity/scenarios_local_test.dart` in the store package (the core keeps the parse check).
- **New jZen gap, filed: jZenDev/jZen#251.** `put`, `delete` and `ZenBatch` take no application precondition, so a rule checked
  before a write runs outside the store's write turn; a sync already queued can deliver a delete in between, and the edit then
  brings the record back with no conflict. A stated limitation of every write path until it lands; no Prudent-side lock or copy.

### What this supersedes, and why

- **"the account deleted with its records (ADR-081), whose all-or-nothing waits on jZenDev/jZen#232 (until then a resumable delete
  and integrity issues for what remains)"** (plan, unit 5) → **withdrawn: all or nothing through `writeAll`.** *Why:* #232 merged
  before this unit; the user's rule is to consume a fix after it merges and never build an interim copy.
- **"`CorrectionIntent`: the balance asked for and the balance it saw"** (ADR-102, §0.2 `Record` row; ADR-111's store message) →
  **refined: plus the corrections it saw.** *Why:* the two figures cannot tell two corrections made apart from a correction followed
  by ordinary records; without causal information the check would either miss the double correction or fire on every later record.
  Still immutable, still one group, under a new field number.
- **"`LocalRulesBackend` is unit 3's stand-in … the store-backed backend of units 4–5 replaces it under the same operation names"**
  (ADR-107) → **done; it lives in `prudent_local_store`, not the core.** *Why:* the store depends on the core, so the core cannot
  hold a backend over the store.
- **"A Dart implementation folds each code point … with `toLowerCase()` and special-cases U+0130"** (ADR-106) → **corrected: a
  table from the JVM.** *Why:* measured — 437 code points differ on the Dart VM.
- **§0.3 test column for rows 5.1–5.53** → filled with the tests that exist (that document is updated in the same change).

### Found, not fixed here

- **The server answers 500 to an account update that reorders held currencies** (jlogicsoftware/prudent#261) (`PUT /api/v1/accounts/{id}` with `[EUR, PLN]` →
  `[PLN, EUR, …]`): Hibernate rewrites the `@OrderColumn` element collection in place and violates
  `prudent_account_balance_unique_currency` (SQLSTATE 23505) — row 5.5's "declared order is kept" holds only for appends and drops
  at the end. Local reorders fine. The parity scenarios do not reorder; a server fix is its own change.

### Consequence

Verified on 2026-11-16 in the worktree against jZen `e6a06c6`: `dart test` — `prudent_local_core` 2 143 green (the fold over all
1 114 112 code points, every search and name-order vector), `prudent_local_store` 223 green (the existing 168, the ledger's rules, the
writeAll atomicity, ten two-device cases through `ZenFolderCloud`: records added on both kept; note and amount edits merge; two
amounts, two openings and an edit against a delete are left out of every figure and named on both devices, and the delete with
records is refused whole; a dispute about a note is counted; an account deleted with its records while the other device adds a
record and a transfer leaves two dangling-reference issues on both, settled once; two corrections made apart are one issue, settled
by replacement or by deleting one; two devices starting fresh write five starters once). **The parity suite against a live Quarkus
on the local Supabase: all 13 scenarios agree**, including `record_list_filters`, `record_list_order` and the account delete with
records. Three deliberate mutations each turned it red (amount bound exclusive: `record_list_filters`; a correction one cent off:
four scenarios; a transfer leg not always a transfer: `record_list_filters`), and the file was restored byte for byte.
`GoldenVectorsTest` and `TextRulesTest` green; `dart analyze --fatal-infos --fatal-warnings` clean in the core, the store and
`tools/prudent_parity_server`; `verify_boundaries.py` and its tests pass.

### Not verified

- `task` does not load from a git worktree (ADR-065): `task test:e2e`, `verify:contracts`, `verify:analyze`, `test:local-store`,
  `test:local-core` and `verify:golden` ran only as their underlying commands here (the parity half of `test:e2e` against a server
  built and started from this worktree, on port 8095), and run as tasks in CI. The client e2e half was not run.
- All or nothing **across a power loss** rests on jZen's own journal tests for `writeAll` (jZenDev/jZen#232); there is no
  Prudent-side test that kills the process in the middle of an account delete. The Prudent tests prove a refused operation writes
  nothing.
- Unit 5 reads plans, budgets and resets for its "still used by" refusals from the shown value only, not from conflict sides;
  units 6a and 6b, which give those collections their rules, move them onto the ledger's helper (plan, unit 6a).
- No device, no CloudKit, no screen: figures and issues reach no UI until unit 9. The interleaving behind jZenDev/jZen#251 is
  reasoned from the code, not reproduced.

---

## ADR-112 — Prudent Local reads an Erste statement and keys its rows exactly as the server does: the parser and the fingerprint ported to pure Dart, held to the JVM over the whole failure catalogue

**Date:** 2026-11-16. **Status:** accepted. **Plan:** unit 8a of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245).
**Builds on:** ADR-088 (synthetic fixtures), ADR-090 (the importer), ADR-091 (the fingerprint), ADR-094 (the failure catalogue), ADR-103
(ids moved in from the server), ADR-107 (golden vectors), ADR-110 (the export carries each record's key). **jZen:** nothing consumed or filed.

### Decision

- **The parse stage is pure Dart in `local/prudent_local_core/lib/src/imports/`**, one file per server class: `ErsteCsv` (strict UTF-8,
  line structure, the RFC 4180 reader), `ErsteStatementImporter` (summary row, whole-file validation, the three description shapes,
  `layout.amount_column`, the `transfer.own_account` hint, `checkDestination`), `StatementBounds` (`ParsedStatements.validate` and the
  upload bounds of `ImportWorkflow.create`: 5 MiB, 5 000 rows, 1 024 UTF-16 units a field, the stable-identifier rules),
  `RowFingerprints` (`v1` fingerprint, `e1` stable-id key, occurrence numbers), `ParsedRow` / `ParsedStatement`, and `ImportRule` /
  `ImportRejection`. `parseErsteStatement(bytes, today:)` is what the server does to an upload before a session exists. No store, no
  Flutter, no clock: "today" is a parameter, as the server's `Clock` is. Sessions, duplicates against the ledger and the commit are unit 8b's.
- **Held to the server by two golden files**, written by `GoldenVectorsTest` through `ImportGoldenVectors` (and `ImportRulesAccess`, which
  opens the package-private import code to it, as `RecordRulesAccess` does for records). `erste_import.json` runs **every one of the 217
  cases of `ImportFailureCatalogue` the parse stage decides**, the three synthetic fixtures and 71 cases at the places Java and Dart
  differ, and records each answer: the rule with its rows and total, or every row (dates, amount, texts, hint, rejection code) with its
  fingerprint and key. The generator first checks each catalogue answer against what the catalogue itself expects and throws on a
  disagreement, so a golden file can never carry an answer the server's own matrix would fail. Two cases are too large for a file (over
  5 MiB; 5 001 rows): they are written as a recipe with the SHA-256 and length of the bytes the server read, and the Dart side refuses to
  run a rebuild that differs. `import_fingerprints.json` holds `normalise` over the hostile text of ADR-107 and more, 142 fingerprints,
  the stable-id keys and occurrence lists, and the JDK's root upper-case and canonical-decomposition tables.
- **Java's semantics, spelled out, where Dart's differ.** Java's `\S` is "not one of six ASCII white space characters" (Dart's also
  excludes a no-break space, U+3000 and a byte-order mark); Java's `.` excludes U+0085 (Dart's does not); `isBlank` and `strip` are
  `javaIsBlank` / `javaStrip` (ADR-107); `Character.isDigit` over UTF-16 units is a range table held to the JDK over all 65 536 units;
  UTF-8 is validated against the Unicode standard's table 3-7 before decoding, so what is refused does not depend on one SDK's decoder;
  `LocalDate.plusYears(1)` on the 29th of February is the 28th. Each has a golden case, and changing any one of them fails cases.
- **The fingerprint is the server's byte for byte, and the account id is written as the server writes it.** A Local id is the server's
  id without its dashes (ADR-103), so `RowFingerprints.fingerprint` writes either form as `UUID.toString()` would. An account moved in
  from the server therefore keeps the fingerprints the server stored for it (ADR-110), and a statement imported before the move is
  recognised after it; an account made on the device gets the same treatment, so there is one rule, not two.
- **`normalise` needs NFC and Java's root upper-casing; Dart has neither.** NFC comes from `unorm_dart` (pure Dart, MIT), the core's
  second dependency after `crypto`. Root upper-casing is a table of the JDK's own answer for every code point it changes (1 552),
  committed as `java_root_upper_case.dart` and generated from the golden file by `tool/generate_root_upper_case.dart` — the same
  "a copy held to its source" as the ISO-4217 list of ADR-107. Dart's `toUpperCase` leaves `ß`, `ŉ` and every astral letter alone.
  The test compares NFD and NFC of every code point that decomposes, all 11 172 Hangul syllables, and that nothing else changes, over
  the whole code space. That sweep found **a defect in `unorm_dart` 0.3.3**: it takes U+D7A4, the unassigned code point after the last
  Hangul syllable, for a syllable (a `<` where the algorithm says `<=`). `RowFingerprints.nfc` normalises the text on each side of it
  separately, which is exact because U+D7A4 is a starter that composes with nothing; a test fails as soon as the package is fixed, so the
  workaround is removed then.
- **The rule catalogue mirrors `ImportRuleCatalogueTest`.** The server's scan of its own sources (45 codes) is in the golden file;
  `ImportRule` names all 45 — 40 that this package emits (`parseStage`) and 5 that need a session, an account's owner or the ledger
  (`sessionStage`: `account.not_found`, `duplicate.already_imported`, `commit.*`). The second set is not an exemption: those rules
  belong to stages that do not exist here, the server also proves four of them outside its parse-stage catalogue (`coveredElsewhere`), and
  the fifth is decided by the four catalogue cases that need a session (the generator lists them). The test fails when the server emits a
  code Local does not name, when Local names one the server dropped, when a parse-stage rule has no passing case, and when this package's
  sources spell a rule as a literal or emit a session-stage one.
- **No statement text leaves the parse stage.** `ImportRejection` holds a code, row numbers and a count, and refuses a code that is not
  one without quoting it; `ParsedRow.toString` names the row and its codes, never its text. `import_privacy_test.dart` puts a unique
  marker in every field (the holder, the summary fields nobody reads, each merchant, counterparty and balance, and the very value that
  breaks the rule), drives every parse-stage rule with `print` captured, and finds no marker in any refusal, error, `toString` or line.

### Consequence

Unit 8b can build sessions, duplicate detection and the commit on functions that answer as the server does for every catalogue case,
and on keys that match what the server stored. **Verified:** `dart test` in `local/prudent_local_core` (2 734 tests, the new ones
included), `GoldenVectorsTest` without writing (the drift gate of `verify:golden`), the server's `ImportRuleCatalogueTest`,
`ErsteStatementImporterTest`, `ErsteFormatDriftTest` and `RowFingerprintsTest`, `dart analyze --fatal-infos --fatal-warnings` in the three
pure-Dart packages, `dart test` in `local/prudent_local_store` (its lock gains `unorm_dart`), `scripts/verify_boundaries.py` and
`scripts/verify_import_fixtures.py`. These were run as the underlying commands from a git worktree, where `task` does not load (ADR-065);
the tasks themselves run in CI. **Not verified:** no real statement has been parsed by the Dart code (none may be, ADR-088); the parse of a
5 000-row statement has not been timed on a device; `verify:import-fixtures` does not read the golden files, whose statements are built
by the server's catalogue from its synthetic base rather than kept as fixtures; the `unorm_dart` defect is not reported upstream.

---

## ADR-111 — Prudent Local's store model: its own messages on `zen_store`, ids minted on the device or derived from natural keys, jZen's per-field merge, and an integrity-check runner; the wire messages move to a pure-Dart package

**Date:** 2026-11-16. **Status:** accepted. **Plan:** unit 4 of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245); the
per-field table of `docs/plans/prudent-local-phase0.md` §0.2 (frozen by ADR-102), §0.3 rows 4.1–4.4, findings F-02, F-03, F-05.
**Builds on:** ADR-101 (package shape), ADR-102 (money under merge), ADR-107 (ids and rules), ADR-108 (the shared package), ADR-109
(boundaries). **jZen:** consumes jZenDev/jZen#235 (PR #241) and #233 (PR #242) at `JZEN_REF` `6301f0e`; files jZenDev/jZen#244 and #245.

### Decision

- **A fifth package, `local/prudent_local_store`, pure Dart.** It holds the store messages, the store's write rules, the mapper and the
  integrity runner, on `zen_store` (path dependency into `../jZen/client/zen_store`), `prudent_local_core` and `prudent_proto`.
  `prudent_local_core` stays as ADR-107 built it — the server's rules with one dependency (`crypto`), which the parity suite runs — so the
  store does not pull `zen_store`, `cryptography` and `protobuf` under the golden vectors.
- **The wire messages move to `packages/prudent_proto`, a pure-Dart package holding only the generated Dart of `proto/prudent/v1/`.**
  `PROTO_DART_OUT` points there, `prudent_ui` and `client/` depend on it, and every `package:prudent_ui/generated/…` and relative
  `generated/…` import (90 files) became `package:prudent_proto/generated/…` — a mechanical rewrite; `protoc` writes byte-identical
  files into the new place. jZen's `Taskfile.app.yml` anticipates exactly this ("an application that keeps its wire types in a
  dedicated package overrides it").
- **The store messages are Local's own** (`local/prudent_local_store/proto/prudent_local/v1/store.proto`), generated into the package's
  `lib/generated` by a second include of jZen's `Taskfile.app.yml` (`zenstore:`), as jZen does for `zen_demo_local` (jZen ADR-080);
  `task generate` and `task verify:contracts` run it, and the drift check is tree-wide. Their shape **is** the §0.2 table: a field of
  its own merges; a nested message is a group (`Posting` = account, currency, amount on records, plans and both sides of a transfer;
  `Schedule`; `ReminderSetting`; `Revocation`; `CorrectionIntent`, `PlanLink` and `ImportKey`, which are immutable); derived figures
  are absent (no `balances`, no `is_default`, no occurrence status or copied fields); import sessions are not here (device-only, unit 8b).
  The default account is `Settings.default_account_id`; a transfer is one `Transfer` record; a record carries its `ImportKey` (F-02);
  an account's openings are `AccountCurrency` records (F-03).
- **Ids are minted by the device** (`ZenStore.newId`, 128 random bits as 32 lower-case hex, the `LocalIds` form of ADR-107), **or derived
  from natural keys** (`DerivedIds`: account currency, budget slot, occurrence, confirming record, imported record, starter category,
  transfer leg; settings is the constant `settings`). The server mints every id because "an id from an untrusted client is not identity"
  (`Ids.java`). That reason does not hold on a device that is the only authority over its own store: there is no other party, no other
  person's rows an id could reach (one person per store; row-level security has no local meaning, §0.3 X.1), and two devices must create
  records offline with no one to ask. A derived id is `SHA-256(length-prefixed "prudent-local/derived-id/v1", kind, components)` cut to
  128 bits; the encoding is frozen (one vector per kind is pinned, cross-checked against an independent implementation), and a component
  that is not canonical (upper-case hex, `pln`, `2026-1`) is refused, never derived a second way.
- **`PrudentLocalStore` is the only write path** and enforces the structural rules: an id matches its natural key; immutable fields are
  written once; a correction is never edited; a transfer, a goal allocation and a reset are written once (a reset then takes one
  revocation); allocations, resets, goals and settings are never deleted. Rules about values (currency held, sign, archived category)
  are units 5–6's. Rules across records are not refused anywhere.
- **No last-writer-wins.** The only policies are jZen's `ZenMergePolicy.earliest` on `Goal.status_changed_at_ms` and
  `OccurrenceState.reminder_read_at_ms` (`StorePolicies`, field numbers read from the descriptors and pinned by a test). A goal's status
  is a field of its own, so completing on two devices merges and completing on one and archiving on the other is still a question.
- **A reset's revocation stays a conflict.** It is a group — who and when — and jZen's policies decide a single scalar or timestamp field;
  two top-level fields would leave "who" a conflict, or pair one device's time with the other's author. Filed as jZenDev/jZen#244; until it
  lands, two devices revoking one reset is a conflict the person settles. Prudent does not settle it through `resolve`.
- **`WireMapper` copies field presence exactly.** Derived figures (balances, an occurrence's status) and Local-only fields (a correction's
  intent, an import key, the openings) are explicit inputs; a transfer's two leg `Record`s get ids derived from it; anything the other
  side cannot represent (a transfer leg as a record, legs that are not one transfer, balances that do not name the held currencies) is an
  `ArgumentError`. The Dart protobuf runtime serialises a field explicitly set to its default, and `zen_store` compares serialised fields,
  so a mapper that filled in defaults would hand the store edits nobody made (reproduced: "no description" written as `''` on one device
  and cleared on the other is a conflict). Filed as jZenDev/jZen#245. The store does not canonicalise writes in the meantime.
- **The integrity-check runner (F-05).** `IntegrityCheck` is the extension point (units 5–8 add theirs); `IntegrityRunner.evaluate()`
  reads every collection afresh and returns every issue, ordered by id, or the store's error — never "no issues" for a store it could not
  read. It keeps no cached answer: the store announces a change on a stream after the write returns, so a cache could be read stale.
  An `IntegrityIssue` is data shaped one-to-one on `zen_ui_store`'s `ZenIssue` — a stable id from the rule code and record ids (never an
  amount, a name or an account number), facts for the words, and actions (`now`, `choose` among ids, `withText`) whose `run` answers
  `ZenResult` and writes through `PrudentLocalStore`, against the record as it stands when the person acts. The unit's checks:
  dangling references (records, transfers, account currencies, plans, budgets and resets naming a deleted account or category — rows
  5.10–5.12, 5.42), a default account that was deleted, money in a currency its account no longer holds (5.6, 5.7, 5.18), a sign the
  category's kind refuses (5.19, `CategoryEntity.canFile` value for value), one account number on two accounts (5.9), two live resets in
  one slot (6.9). Actions: delete, move (not for a correction or an imported record, whose id names its account), re-create a deleted
  account or category under its old id with a name the person gives, add the currency, let the category take both directions, clear a
  number, revoke a reset.
- **Surfacing the issues is the Local app's.** `zen_ui_store` is a Flutter package and this one is pure Dart, so the
  `ZenIssueSource(issues: …)` that puts them beside the conflicts, with words chosen by code, is wired in unit 9. No Prudent-side list
  exists or will.
- **Gates.** `task test:local-store` (CI gates job); `verify:analyze` runs `dart analyze --fatal-infos --fatal-warnings` in the package;
  `packages/prudent_proto` joins `DART_ROOTS` and has no analyzer line because it holds nothing but excluded generated code;
  `verify:boundaries` checks F and H (ADR-109) cover the package with no exemption; check G (pure Dart) now names
  `local/prudent_local_store` and `packages/prudent_proto` beside the core and reads generated sources too, and check E's pubspec scan
  reads every package under `packages/`, so the wire messages cannot bring the transport one hop under Local where F, which reads
  `local/` pubspecs, would not see it. Check F also refuses any `path:` dependency of a `local/` pubspec that lands outside `local/`,
  `packages/` or a jZen client package other than the four server ones, whatever key it sits under (resolved lexically from the
  repository root). Flow-style one-line dependencies are still not read, as ADR-109 records. `scripts/test_verify_boundaries.py` plants each new violation; both were also proved red on the
  real tree and removed. `JZEN_REF` moves to `6301f0e` in both workflows.

### What this supersedes, and why

- **"local/prudent_local_core/ — pure Dart: the local store model (its own protos, see 0.2) … the integrity checks"** (ADR-101; ADR-102's
  "`local/prudent_local_core/proto/prudent_local/v1/`") → **refined: in `local/prudent_local_store`.** *Why:* the core is the parity
  suite's rule set with one dependency; the store needs `zen_store`, and keeping them apart keeps that suite's graph small.
- **"The generated proto Dart moves … to `packages/prudent_ui/lib/generated`"** (ADR-101, ADR-108) → **superseded: `packages/prudent_proto/lib/generated`.**
  *Why:* ADR-101 also required the Local core to depend on the generated messages and to stay pure Dart; a pure-Dart package cannot
  depend on a Flutter package, so both could not hold.
- **"Until jZenDev/jZen#233 lands, Prudent shows the list itself"** and **"the same rule is applied by `prudent_local_core` through
  `resolve` … until #235"** (ADR-102) → **never built.** *Why:* both issues landed before this unit; the user's rule is to consume a fix
  after it merges, never to build an interim copy.
- **The §0.2 row "`revoked_by`, `revoked_at_ms` — Group (revocation), same-intent rule"** → **the group stands; its same-intent merge waits
  for jZenDev/jZen#244.** *Why:* the merged policy cannot decide a group, and settling it in Prudent would be the interim copy the rule forbids.
- **"Ids are minted by the server; a client-sent id is not identity"** (§0.3 row 3.9, `Ids.java`) → **device-minted or derived, locally.**
  *Why:* stated above; ADR-102 decided it, this records the reason the plan asked for.

### Consequence

Verified on 2026-11-16, in the worktree against jZen `6301f0e`: `dart test` in `local/prudent_local_store` — 166 tests green: every §0.2 row
through two real encrypted stores synced by `ZenFolderCloud` (merge, group, same-intent, derived ids, write-once, edit against delete,
derived and device-only), the structural rules, the derived-id vectors, the mapper's byte-for-byte round trip of every stored message,
each check and its actions, and the two-device suite (disjoint edits merge; the §0.2 conflicts surface on both devices, refuse writes and
are resolved once; a category deleted on one device while the other files under it is listed on both and settled by one action). Five
deliberate mutations each turned it red: the goal policy removed, the mapper dropping `payee`, the dangling-reference check removed, the
derived-id domain changed, the correction no longer immutable. `dart analyze --fatal-infos --fatal-warnings` is clean in the package;
`flutter analyze` with the same flags is clean in `client/` and `packages/prudent_ui` after the move; `verify_boundaries.py`,
`verify_controls.py` and jZen's `verify-widget-files.py` pass.

### Not verified

- `task` does not load from a git worktree (ADR-065), so `task verify:contracts`, `task generate` (the `zenstore:` include),
  `task verify:analyze`, `task test:local-store` and `task zen:test:client` ran only in CI; locally their underlying commands were run.
- No device, no CloudKit backend (unit 9 wires it; jZenDev/jZen#236, hashed record names, merged in jZen `cf36d77` and is not yet
  consumed), no Flutter surface: the issues reach no screen until
  unit 9. The ledger's multi-record writes wait on jZenDev/jZen#232 (unit 5). The parity suite still runs unit 3's in-memory backend; a
  store-backed one is unit 5's.
- A write path that is not presence-exact can still raise a conflict about nothing until jZenDev/jZen#245 lands.

---

## ADR-110 — The privacy export carries each imported record's statement key beside the record, and the server-connected app saves it to a file where the platform can; the clipboard copy stays

**Date:** 2026-11-16. **Status:** accepted. **Plan:** unit 10a of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245), finding F-02 of
`docs/plans/prudent-local-phase0.md`. **Builds on:** ADR-071 (the export), ADR-083 (no CocoaPods), ADR-091 (the key), ADR-100 (T14), ADR-103 (the move
into Local), ADR-108 (the shared package). (ADR-109 is the boundaries PR.)

### Decision

- **`DataExport.record_import_keys` (field 16) is a list of `ExportImportKey { record_id, fingerprint, occurrence }`**, one entry for each record whose
  `prudent_record.import_fingerprint` is set and none for any other, so an ordinary record exports with nothing and a person who never imported a
  statement has an empty list. The exporter copies the two columns as stored: the fingerprint string, whose `v1:` prefix is its version (ADR-091), and the
  occurrence. There is no second version field, because a second spelling of the version could disagree with the first; a reader that does not know the
  prefix refuses the file. Adding a field does not change `format_version` (still 1).
- **Beside the record, not on `Record`.** ADR-091 said the key is "never on the wire"; `Record` is the shape of every record answer, so a field there would
  put a digest of statement text into each list, create and update response. This is the one place the key is handed back, to the person who owns it, in
  the export that already holds every other fact about them. ADR-091's sentence "it is not in the data export" is superseded by this one; the digest is not
  secret (ADR-091), so the file is exactly as sensitive as the rest of the export and says so.
- **The coverage is derived, not remembered.** `PrivacyCoverageTest` finds every `import_*` column of `prudent_record` from the schema and fails unless they
  are exactly the two that `ExportImportKey` carries, and unless the message's fields are `record_id`, `fingerprint`, `occurrence`; a third column cannot be
  added without deciding whether it is exported. `PrivacyImportKeysTest` proves the key survives the export exactly over both transports (including two rows
  of one fingerprint told apart only by occurrence), that an ordinary record and an empty ledger export no key, and that a neighbour's key is never in the
  export. The two hand-kept lists (`openapi.yaml`'s `ExportImportKey` schema, `PrudentProtoReflection`) are updated and `verify:reflection` checks the second.
- **"Save to a file" sits beside the copy on "Privacy and data"** (`PrivacyScreen`, `packages/prudent_ui/lib/privacy/`). It writes the same text the copy
  makes (`PrivacyActions.exportFile`: the indented JSON, UTF-8, named `prudent-export-<day of the export>.json`) through `ExportFileSaver`, an injectable
  function like the statement picker, defaulting to `file_selector`'s `getSaveLocation` + `XFile.saveTo` on macOS, Windows and Linux and to the browser's
  download on the web. The shared package already depends on `file_selector` (ADR-093), whose Apple implementations ship Swift packages (ADR-083), so no new
  dependency and no plugin in `client/` is needed; the function stays in `prudent_ui` because it names no server code (ADR-108).
- **The warning comes before the button, in words, in en, uk and pl:** the file is not encrypted, holds all the person's finances in plain text, should be
  kept somewhere private and deleted once used (ADR-100, T14). It is on the screen, not in a dialog that can be dismissed unread, and the success message
  repeats the deletion advice.
- **iOS and Android get no "Save to a file" yet.** `file_selector_ios` and `file_selector_android` implement no save location and the framework has no
  save-file capability, so the button is absent there (`exportFileSavingSupportedProvider`, `!zenIsMobile`) and only the copy is offered. Hand-rolling a
  plugin choice is what CLAUDE.md forbids; the gap is jZen's (nothing under jZen's `client/` saves or shares a file, checked before filing) and is reported as jZenDev/jZen#246 and listed in `docs/jzen/README.md`, and the mobile half of unit 10a waits for
  it (a phone user with a server account cannot move to Local by file until then).
- **The clipboard copy stays in the server-connected app.** T14 refuses the clipboard as the *Local* app's export channel; the server app's copy is a
  convenience the person already has, and removing it would take away the only export on a phone. It now carries its own sentence saying the clipboard is
  shared with other apps and, on some devices, with the person's other devices, and the Local app never reads an export from it (ADR-103).
- **Save failures are shown, never swallowed:** a refused write shows "The file could not be saved" and logs the exception; a cancelled panel says nothing,
  because nothing was asked for. The busy state is reset in a `finally`, so an `Error` the handlers do not catch (an `UnimplementedError` from a platform without a save panel) still propagates, as an unhandled error, without leaving the button spinning. On the web the browser decides where the file goes and the app cannot tell whether it was kept, so the confirmation says it was handed to the browser's downloads, not that it was saved.

### Consequence

Unit 10b can rely on the export carrying each imported record's key, so statements imported before the move are recognised after it. **Verified:** the
server suite (1279 tests, including the new ones), `verify:contracts`, `verify:reflection`, the client suite (539 tests, including that a saved file reads
back as an `DataExport` equal to the one the server sent, key included), `verify:controls`, `verify:analyze`, `verify:boundaries`, `verify:swiftpm`.
**Not verified:** the save panel on any real platform (the saver is faked in tests; macOS, Windows, Linux and the web download were not run), the web
download's file name in a browser, a real export (every figure and key in the tests is synthetic), and that a Local import accepts the file (unit 10b).

---


## ADR-109 — `task verify:boundaries` keeps the server out of `local/` and Local out of `client/` and `packages/`; the parity harness moves to `tools/`

**Date:** 2026-11-16. **Status:** accepted. **Plan:** ground rules and unit 11 of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245).
**Builds on:** ADR-101 (pure-Dart core, no server package in Local), ADR-107 (the parity harness), ADR-108 (check E, whose pattern this follows).
It moves a package ADR-107 placed at `local/prudent_parity_server`; ADR-107 is accepted and is not edited, so read its path as `tools/prudent_parity_server`.

### Decision

- **The parity harness moves to `tools/prudent_parity_server`.** It drives the *live server* through the real transport and identity packages
  and compares the answers with `prudent_local_core`, so it needs exactly what Local must not have. A gate exemption is legitimate only for
  content of a different category, and this is one: a test that exercises the server is not Local code. So it is placed where it belongs
  rather than excused where it was. `tools/` is a new top-level home for repository-owned programs that are not an app or a shipped package
  (`publish_to: none`, run by a task); the name says what it is without claiming a framework role. Only paths changed (`git mv`; the core
  dependency is `../../local/prudent_local_core`, the scenario directory `../../local/prudent_local_core/parity/scenarios`; Taskfile, CLAUDE.md,
  the plan and four comments name the new path); no code moved or changed.
- **Check F — nothing under `local/` reaches the server, with no exemption.** Every package under `local/` (a directory with a `pubspec.yaml`,
  so a package added later is covered) fails the gate if it names `zen_transport`, `zen_identity`, `zen_ui_identity` or `zen_secure_store` — the
  four ADR-108 refuses in `packages/prudent_ui`, because the last two pull the first two in. It scans `import`/`export` in `lib/`, `bin/`,
  `test/` and `integration_test/`, and the pubspec in **every** section: `dependencies`, `dev_dependencies` and `dependency_overrides` alike (a dev
  dependency is in the graph the tests run in; an override can replace a clean dependency with the transport). It also fails when anything under
  `local/` depends on `prudent_parity_server`, or the transport would be one hop away.
- **Check G — the Local core is pure Dart.** `local/prudent_local_core` fails on a `flutter:` section, any `sdk: flutter` dependency, a dependency
  on or import of `flutter`, `flutter_test`, `flutter_localizations`, or an import of `dart:ui` (ADR-101: the parity suite runs the core on the
  plain VM). Other Local packages may use Flutter.
- **Check H — nothing outside `local/` uses Local.** `client/` and every package under `packages/` fail when a pubspec names a package found under
  `local/` (by name) or has a `path:` into `local/` (whatever it is called), or when a Dart file in `lib/`, `bin/`, `test/` or `integration_test/`
  imports or exports one. This is the "no Local code in the web build" half of the ground rule and of unit 11 (ADR-101).
- All three fail as stale when `local/`, `packages/`, the core or the Dart sources are missing, as every scope in this script does.
  `scripts/test_verify_boundaries.py` plants each violation and its clean counterpart and runs first in `task verify:boundaries`, which CI runs.

### Consequences

- The ground rule "Local imports neither `zen_transport` nor `zen_identity`, and no Local code in the web build" is a gate, not a sentence.
- The checks read pubspecs by indentation, as A and E do: a dependency in flow style on one line (`{zen_transport: ...}`) would not be seen. No
  pubspec here is written that way.
- Not covered: the Local *app* (`local/prudent_local_client`, unit 4+) has to be scanned by the same checks when it exists — F and H find it
  without a change; G names only the core.

### Not verified

- The checks were proved red on deliberate violations in real files (in the PR), each then removed. No package under `local/` other than the
  core exists yet, so the "added later" path is proved by the unit tests alone.
- The moved harness was analysed (`dart analyze --fatal-infos --fatal-warnings`) at its new path against the sibling jZen checkout; its
  suite needs the live stack and was not run (`task test:e2e`).

---

## ADR-108 — The screens, the generated messages and the strings live in `packages/prudent_ui`, which cannot import the transport or sign-in

**Date:** 2026-11-16. **Status:** accepted. **Plan:** unit 2 of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245).
**Builds on:** ADR-101 (the four packages), ADR-105 (the repository interface). (Written as ADR-106 and then ADR-107 while other PRs were in
flight; numbered ADR-108 at rebase.)

### Decision

- **`packages/prudent_ui`** is a Flutter package (`prudent_ui`, `publish_to: none`, consumed by `path:`) holding every screen, view model,
  provider, the money formatting, the `PrudentRepository` interface, the notification code, the three languages' ARB files and the
  generated protobuf messages. Files moved with `git mv`, so history follows; the folders keep their names and are imported as
  `package:prudent_ui/<folder>/<file>.dart`. `client/` keeps `main.dart`, `app.dart`, `app_root.dart`, `auth/`,
  `ServerPrudentRepository`, the Polish identity wording, and every test (they exercise the screens through the server repository and
  its mock transport, as before).
- **The package may not import, or depend on, `zen_transport`, `zen_identity`, `zen_ui_identity` (which renders sign-in over
  `zen_identity`) or `zen_secure_store`.** `task verify:boundaries` gains check E and `scripts/test_verify_boundaries.py`, which plants
  each violation and requires the gate to fail; the other four checks now scan both `client/lib` and `packages/prudent_ui/lib`.
- **The unit-1 leaks, resolved:**
  - `ZenTransportError` in three screens → `failureCode(error)` (`lib/failure_code.dart`) reads `ZenError.internalData['code']`, which is
    where the transport already puts the wire code, so a Local repository reports a refusal the same way. `FailureCodes.network` /
    `.decode` name the two codes the transport invents; `client/test/failure_code_test.dart` fails if they drift from `ZenTransportErrorCode`.
  - `unwrapImportResult` stripped the transport's decoder message (which quotes statement text) by building a `ZenTransportError`; it now
    throws an `ImportDecodeFailure` (same code, fixed sentence) for any decode failure, so the guarantee holds for every repository. The
    server repository still returns the transport's raw error — the existing test that shows why this matters still passes untouched.
  - `RecordFilter.toQueryParameters` → an extension in `client/lib/record_filter_query.dart`, used only by `ServerPrudentRepository`.
  - Settings' profile page and log-out, and the sign-out that ends erasing an account, came from `identitySessionStoreProvider`. They are
    now a `SettingsSession?` (`settingsSessionProvider`, default `null`); `client/` overrides it (`identitySettingsSession`). With no
    session Settings shows neither entry: a button that signs out of nothing would be a lie in an app with no sign-in.
- **l10n is the package's.** `packages/prudent_ui/l10n.yaml` and the ARB files (en, uk, pl) generate `PrudentLocalizations`, built and
  never committed (`.gitignore` follows the move). `client/` has no `l10n.yaml` and no `generate: true`; it takes the delegates from the
  package and keeps Polish identity wording, which wraps `zen_ui_identity`. The Polish navigation and widget wording moved with the screens.
- **The contract loop writes into the package** (`PROTO_DART_OUT: packages/prudent_ui/lib/generated`), and `DART_ROOTS` on the include
  names both packages, so `pub get`, gen-l10n discovery, the one-widget-per-file gate and `test:client` cover both. `verify:controls`
  scans both trees and fails when either is empty; `verify:analyze` runs gen-l10n and `flutter analyze --fatal-infos --fatal-warnings`
  in the package and in `client/`.
- **`FakePrudentRepository.createCategory` is removed** (unit 1's review): it invented a `fake-N` id against its own rule that a fake
  never answers with a made-up value, and nothing called it.

### Consequences

- A second app can link the screens and the messages with no server code in its source graph; whether it can *build* without the server's
  packages still depends on `zen_ui_widgets`/`zen_ui_navigation` being free of them, which they are today.
- The package's own tests (`packages/prudent_ui/test/`) hold what needs no transport: `failureCode`, and Settings with and without a
  session. The 533 existing tests stay in `client/`; the only test added there is the drift check above, which needs the transport.
- `load_error_view_test.dart` reads source files by relative path, so its two paths now point at the package (and it scans both `lib`
  trees); its assertions are unchanged.

### Not verified

No second app consumes the package yet; that the package builds with no server packages is shown by the gate and by `flutter analyze`
and its own tests, not by a build of Local. `integration_test/` compiles (analyze) and was not run, as before.
## ADR-107 — Prudent Local's domain core reproduces the server's rule methods exactly, held to them by golden vectors from the JVM and by a parity suite of data scenarios run through the live server

**Date:** 2026-11-15. **Status:** accepted. **Plan:** unit 3 of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245);
rows 3.1–3.8 and findings F-04, F-07, F-11 of `docs/plans/prudent-local-phase0.md` §0.3. **Builds on:** ADR-088 (synthetic data
only), ADR-090 (account numbers), ADR-101 (the package shape), ADR-102 (ids, money under merge).

### Decision

- **Two packages under `local/`.** `local/prudent_local_core` is pure Dart (its only dependency is `crypto`, for SHA-256): the rules
  and the local side of the parity harness, as ADR-101 says. `local/prudent_parity_server` is a test-only package holding the
  harness's **server** side, because that side needs `zen_transport` and `zen_identity`, which the core must never import, and the
  server-connected app's `pubspec.yaml` must name no Local package (ADR-101), so it cannot live under `client/`.
- **One Dart function per Java method, named after it** (`javaTrim`, `javaStrip`, `javaIsBlank`, `codePointCount`, `javaUtf8`,
  `Currencies`, `AccountNumbers`, `CivilDate.parse` = `LocalDate.parse` strict, `CivilMonth.parse` = `BudgetResource.parseMonth`,
  `addExact`/`subtractExact`/`negateExact`/`signum`, `TextRules` per call site). The server is the specification; where the plan's
  one-line summary and the code disagree, **the code wins**:
  - Account numbers get **no NFC** and **ASCII-only** upper-casing (the plan said "NFC, root-locale upper-casing"):
    `AccountNumbers.java` does neither, so `e`+U+0301, `é`, `ı` and `ß` are refused, never folded into another number.
  - Currencies **are** upper-cased in the root locale, with Java's consequences reproduced: the server accepts `"ınr"` as INR,
    `"ſek"` as SEK and `"ßp"` as SSP, and so does Local. Recorded here as the server's behaviour, not endorsed; changing it is a
    server change with its own ADR, after which the golden file changes and Local follows.
  - "Text is trimmed" is three different rules on the server and stays three here: `trim()` (code units ≤ U+0020: titles, names,
    payees, record notes, import-row notes), `strip()` (Java white space, not the no-break spaces: allocation and reset notes), and
    `isBlank()` for "required". A title of only U+0001 is not blank and trims to the empty string, which the server stores; Local
    stores it too.
- **F-04 resolved: a note's 500 characters are code points** (`runes`), as Postgres `char_length` and Java `codePointCount` count;
  a lone surrogate counts one. A note of 500 emoji (1000 UTF-16 units) is accepted on both sides.
- **The identity token hashes Java's UTF-8**, which writes a lone surrogate as `?` (Dart's encoder writes U+FFFD), so the token is
  the server's for every input.
- **Money is a Dart `int`** (the VM's 64-bit integer; Prudent Local has no web build), and every sum goes through the exact
  operations, which throw `MoneyOverflow` where Java throws `ArithmeticException` — never a wrapped balance. `wireMinorUnitDigits`
  (2) is the one fixed wire scale; `client/lib/money.dart`'s `minorUnitDigits` is a second copy until unit 2 moves that file into the
  shared package, which should then read this one.
- **Local ids are 32 lower-case hex characters compared as text** (= Postgres' byte order of a `uuid`, not Java's signed
  `UUID.compareTo`; F-11). `LocalIds.fromServerId` reads only the form the server writes; `UUID.fromString`'s leniency (`1-1-1-1-1`,
  upper case, signs, non-ASCII digits) is shown in the vectors and refused, since a looser reader would make two spellings of one id
  two records. Who mints ids stays unit 4's.
- **Golden vectors come from the server's own methods.** `server/src/test/java/prudent/parity/GoldenVectorsTest.java` (plain JUnit,
  no Docker) writes `local/prudent_local_core/test/golden/*.json` with `-Dprudent.golden.write=true` (`task golden:generate`) and
  otherwise **fails when a committed file differs from what the server answers today** (`task verify:golden`; it also runs in
  `test:server`, so CI's backend job enforces it). Package-private rules are reached through test-side accessors
  (`RecordRulesAccess`, `BudgetRulesAccess`), not copies. The money and id vectors are the exception: the server keeps no
  repository class for either, so `money.json` and `ids.json` come from the JDK calls the server makes (`Math.addExact`,
  `subtractExact`, `negateExact`; `UUID.toString`, `UUID.fromString`, `UUID.compareTo`) and from Postgres' documented `uuid` byte
  order, not from a Prudent method. Files are ASCII with `\uXXXX` escapes, the only way a lone surrogate
  survives a file. Hostile inputs: combining marks, every white space Java and Unicode disagree on, U+FEFF, U+200B, controls, the
  Turkish i, ligatures, astral characters, lone surrogates, negative zero (`-0000` years, `"-0"` amounts), `Long.MIN/MAX_VALUE`.
  Where a table is involved the vectors are **exhaustive**: `Character.isWhitespace` and `(?U)\s` for all 1 114 112 code points,
  every A–Z triple for ISO-4217, every code point that root-upper-cases to ASCII capitals. The ISO-4217 table is the running JDK's,
  which is the point: a JDK update that changes it fails `GoldenVectorsTest`, and `lib/src/iso4217.dart` is edited to match (its
  test compares the two sets).
- **The parity suite is data run through two backends.** A scenario is a JSON file in
  `local/prudent_local_core/parity/scenarios/` (name, description, the §0.3 rows it covers, steps of `op` + `input`, `as` to bind an
  id, optional `outcome` the **server** must answer). `ParityEngine` runs each step on the server and locally and compares the
  observations **exactly**: same keys, same strings, figures as decimal text of minor units; a double in an observation, an unknown
  operation or a broken binding fails the scenario, never skips a step; refusals compare by status (message texts are prose).
  Units 4–8 add scenarios as files and operations as entries in each backend's `ops` table; the format, engine and comparison do not
  change. `LocalRulesBackend` is unit 3's stand-in, enforcing only unit-3 rules over an in-memory model; the store-backed backend of
  units 4–5 replaces it under the same operation names, and any server rule it lacks shows as a difference, never a pass.
- **One server user per suite run, not per scenario.** Registration hits zen-ratelimit's production auth limit (which `%dev` keeps)
  on the second run inside the window; bending the limit for the suite was rejected. Each scenario creates and binds its own
  accounts and categories, so none reads another's rows; a later list operation must filter to its scenario's bound ids, or argue
  for a user per scenario.
- **F-07 for the harness: no implicit "today".** No unit-3 operation depends on the date; a later operation that does takes `asOf`
  in its input, on both backends.
- **Where it runs.** `task test:local-core` (`dart pub get`, `dart test` in the core) in CI's gates job; both packages are analysed
  by ADR-104's `task verify:analyze` (`dart analyze --fatal-infos --fatal-warnings`), which until now covered only `client/`; the parity suite inside `task test:e2e`, after the e2e suite, against the same live
  Quarkus server, either one failing fails the gate.

### What this supersedes, and why

- **"account-number normalisation (NFC, white space, root-locale upper-casing, ADR-090)"** (plan, unit 3) → **corrected to what
  `AccountNumbers.java` does: Unicode `White_Space` removed, ASCII upper-cased, no NFC.** *Why:* the server is the specification
  (plan, ground rules); porting the summary would make Local accept numbers the server refuses.
- **"`client/` — the only Dart package in the repository"** (ADR-104, `verify:analyze`'s summary) → **refined: `verify:analyze`
  also runs `dart analyze --fatal-infos --fatal-warnings` in both `local/` packages.** *Why:* the gate's reason (a declared rule
  nothing runs is decoration) holds for every Dart package, and a second analyzer task would be two gates for one rule.
- **"Test that will prove it locally"** column of §0.3 rows 3.1–3.8 → **filled with the tests that now exist** (that document's
  table is updated in the same change). Row 3.3's `multi_currency` and the others are parity scenarios that run against the live
  server.

### Consequence

Verified on 2026-11-15: `GoldenVectorsTest` writes and then checks the six files; a one-character change to `currencies.json` makes it
fail. `dart test` in `local/prudent_local_core`: 2 088 tests green, and five deliberate mutations of the port (U+0085 dropped from
White_Space, negative-zero years allowed, the long s not folded, U+FFFD for a lone surrogate, `negateExact(MIN)` not throwing) each
turned it red. The parity suite against a live local Quarkus + Supabase: all five scenarios agree; a deliberate one-cent error in the
local balance turned three of them red (`balances.PLN — server "8767", local "8768"`), and green again once removed. CI's gates, backend and e2e
jobs ran the same checks green on the pull request (jlogicsoftware/prudent#253).

---

## ADR-106 — The record search and the order of names are rules of Prudent's own, applied in Java, so a second implementation can reproduce them exactly

**Date:** 2026-11-15. **Status:** accepted. Closes phase-0 findings F-09 and F-10 (`docs/plans/prudent-local-phase0.md`); jlogicsoftware/prudent#245. Ships as unit 4a of the Prudent Local plan, before unit 5.

### Context

Two things a person sees on screen were decided by the database, not by Prudent:

- **Record search** was `lower(title) like '%term%'` (and payee, note), the term lower-cased in Java. `%` and `_` in what the person typed were wildcards (a search for `50%` matched `500 off`), and `lower()` followed the database's locale, which no migration pins.
- **Name order** was `order by name` / `order by title` in the database's default collation (accounts, categories), and `String.compareTo` — UTF-16 code unit order — for the free-money accounts. Neither is pinned, and the two disagreed with each other.

Prudent Local (ADR-101) must show the same lists and cannot copy a database's locale. The server is the specification, so the specification has to be something a Dart program can implement exactly.

### Decision

**Neither rule asks the database any more.** The search keeps every other filter in SQL and applies the text match in Java to the rows they selected; names are sorted in Java after loading. Both rules live in `prudent.text.TextRules`, are per-code-point and context-free, and have no locale, no normalisation and no ICU. No migration: no column, index or collation changed.

**Search.** A `null` or blank search is ignored, as before (`String.isBlank`: Unicode white space, which excludes U+00A0, U+2007 and U+202F). Otherwise the term is `String.trim()`med — every leading and trailing code point at or below U+0020 — and folded. A record matches when its folded title, payee or note (a null one never matches) contains the folded term as a plain substring. `%`, `_` and `\` are ordinary characters; there is no pattern and so nothing to escape (the brief suggested an explicit `ESCAPE` clause; with the match in Java there is no `LIKE` to escape, and the fold could not be done in SQL anyway).

**The fold** is Unicode's *simple* lower-case mapping, one code point to one code point (`Character.toLowerCase(int)`). Consequences, all in the vectors: `Ł`→`ł`, U+0407 → U+0457, `Σ`→`σ` always (a final `ς` stays `ς`: no final-sigma rule), `ß` is unchanged and **does not** match `ss`, `ẞ` (U+1E9E) folds to `ß`, Turkish `İ` (U+0130) folds to plain `i` and so does `I`, while dotless `ı` is unchanged and matches neither. Polish and Ukrainian letters are distinct from their Latin or base lookalikes: `ł` does not match `l`, U+0457 does not match U+0456. A Dart implementation folds each code point of a one-code-point string with `toLowerCase()` and special-cases U+0130 → `i` (the only code point whose full mapping is longer than one code point). The rule follows the Unicode tables of the JDK that runs the server, which can change only for newly assigned letters.

**Name order** compares, in turn: (1) the sequence of *primary weights* of the folded code points, shorter first when one is a prefix of the other; (2) the code points of the names as written, so `A` sorts before `a` only to break an exact fold tie; (3) the id as lower-case text, which is also Postgres's byte order for a UUID. A code point's weight is four times its value, so code point order is the baseline (digits, then `_`, then letters; ASCII Latin before other Latin letters before Cyrillic), with these tailorings, which put letters where a Polish or Ukrainian reader looks for them:

- Polish, each right after its base letter: `ą`, `ć`, `ę`, `ł`, `ń`, `ó`, `ś`, `ź`, `ż` (`ź` then `ż` after `z`).
- Ukrainian: U+0491 after U+0433, U+0454 after U+0435, U+0456 and U+0457 after U+0438 (then U+0439, which already follows U+0438 in Unicode).

Weight is `base*4 + 1` (and `+2` for the second letter after a base), which fits between `base*4` and the next code point's weight. Every other code point keeps its own position.

### What a person sees

The previous order depended on how the database was created, so no one could rely on it. Against the test database (an en_US-style collation) the old order differed in two checked ways: names that differ only in case listed lower case first (`a`, `A`), and `Lazienka` with its stroke letter (U+0141) sorted after `Zupa`. The new rule lists `A`, `a` and puts that name between `Lato` and `Mleko`. The Ukrainian cases (the letter U+0407 after U+0418 and before U+0419, U+0491 after U+0433) agreed with that database already and are pinned by the rule rather than changed by it; a database in the C locale would have put the capital U+0407 before every other Cyrillic capital. Names in other scripts or with other diacritics (`E` with acute, `u` with umlaut, Turkish `s` with cedilla) are in code point order, **after `z`**: this rule is a reading order for the two languages Prudent ships beyond English, not a general collation. Digits sort as characters (`10 PLN` before `2 PLN`). An existing person's lists may reorder once on upgrade; no data changes.

### Not done, on purpose

- **Unicode normalisation.** `ą` typed as `a` plus a combining ogonek orders by its two parts, and a name typed both ways does not match in search. A keyboard produces the composed form; normalising would need a table Dart does not ship. Revisit if import or paste produces decomposed names.
- **A full collation (ICU `und-x-icu`, UCA).** It would order every script well, but Dart cannot reproduce it exactly without implementing the algorithm and carrying the tables, and the database would have to have ICU at the same version; a rule two codebases can state in a paragraph and test with a file is worth more here than a better order for scripts Prudent does not ship.
- **Search in the database, for scale.** The list is unpaginated by design (`records.proto`); a search now loads the rows the other filters select, as an unfiltered list already does. If a ledger grows to where that hurts, the answer is a stored folded column written by the same rule, not a locale-dependent function.
- **Other id orders (F-11)** are untouched.

### Proof

`server/src/test/resources/text-rules/search-vectors.json` and `name-order-vectors.json` hold the expected behaviour, synthetic only (ADR-088; Cyrillic letters are written as `\u` escapes because the repository publishes English text). `TextRulesTest` runs them against `TextRules` (every vector permutation sorted twenty times), and `TextRulesApiTest` drives the rules through the record search, the account and category lists and the free-money position over a real database. Run against the previous production code (the four changed files taken from `main`, the tests kept), four of its eight tests fail: a `%` search returns the record containing `500` as well, an `_` search returns `axb` for `a_b`, accounts named `b B a A` list as `a A b B`, and the free-money contributors list in UTF-16 order (`Lato`, `Zupa`, then the stroke-L name). The other four (the Polish and Ukrainian list orders and the `\u0142` fold, which that database already got right) pass on both, and pin the rule. Prudent Local's parity suite reads the same two files.

### Consequences

The server change is user-visible on the persistent app: search no longer treats `%` and `_` as wildcards, and lists of accounts, categories and free-money accounts may appear in a different order. The contract is unchanged (no proto, no route, no OpenAPI difference). Unit 3's parity suite and unit 5's Dart code consume the vectors; a rule change is a new ADR and a new vector, never an edit of either.

---

## ADR-105 — Screens depend on an abstract `PrudentRepository`; the server's HTTP version is `ServerPrudentRepository`

**Date:** 2026-11-15. **Status:** accepted. **Plan:** unit 1 of `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245).
**Builds on:** ADR-101 (the four packages; the abstract `PrudentRepository` lives in the shared package, the server version in `client/`).

### Decision

- `client/lib/prudent_repository.dart` is now an `abstract interface class PrudentRepository` — the 65 methods screens, providers and
  notification code call, with the server's method contracts (refusals included) as its documentation. It imports `zen_core`
  (`ZenResult`, `ZenError`) and the generated messages, and nothing from `zen_transport` or `zen_identity`.
- `client/lib/server_prudent_repository.dart` is `ServerPrudentRepository implements PrudentRepository` over `ZenClient`: every path,
  query string and `ZenClient` call moved there unchanged. Only `main.dart` — the composition root — names it.
- `prudentRepositoryProvider` is typed as the interface. **No behaviour change:** no request, header, path or result differs; the
  existing suites are untouched except that those which built the repository now build `ServerPrudentRepository` (the construction,
  never an assertion).
- `test/fake_prudent_repository.dart` is an in-memory implementation (a `Fake`, so a method it was not given throws), and
  `test/category/categories_screen_fake_test.dart` runs the real categories screen on it with no HTTP mock.

### Where the server still leaks through (input for units 2 and 4, not solved here)

- `RecordFilter.toQueryParameters()` is a REST concern on a type that the interface's `listRecords` takes; the Local implementation must
  ignore it and filter by the fields.
- Screens read `ZenTransportError` (HTTP status, rule code) to choose a sentence: `imports/import_result.dart`,
  `imports/import_failure.dart`, `account/account_save_error.dart`. A Local implementation must either produce the same error type or
  these three move to a transport-neutral error in `zen_core`.
- `lib/auth/` and the sign-in screens use `zen_identity` directly; they stay in `client/` (unit 4).
- Methods whose meaning is server-only — `eraseAccount`, `exportData` (the server's view of the user) and the import-session methods —
  are on the interface because screens call them; whether Local keeps the same shape is unit 4's and unit 10's decision.

### Not verified

The Local implementation does not exist; that the interface is *sufficient* for it is shown only by a fake that holds categories.

---

## ADR-104 — `task verify:analyze` runs `flutter analyze` with infos fatal in CI, so the analyzer and `riverpod_lint` are a gate

**Date:** 2026-11-15. **Status:** accepted. Follows ADR-099, which is not edited.

### Context

`client/analysis_options.yaml` includes `flutter_lints` and loads `riverpod_lint` as an analyzer plugin, and no task or CI job ran `flutter analyze` (true before ADR-099 too). Both were configuration nothing enforced, and the independent review of ADR-099 found it.

### Decision

- `task verify:analyze` runs `flutter gen-l10n` and then `flutter analyze --fatal-infos --fatal-warnings` in `client/`, the only Dart package in the repository. Infos are fatal because that is the level `riverpod_lint` and most `flutter_lints` rules report at. `ci.yml`'s `gates` job runs it after the contract gate and before the client suites.
- Three findings existed and each was handled: one in code, two in generated output. `test/load_error_view_test.dart` no longer exposes a public field on a `Notifier` (`avoid_public_notifier_properties`) — fixed. The other two are `deprecated_member_use` on `GlobalMaterialLocalizations` and `GlobalCupertinoLocalizations` in `lib/l10n/generated/prudent_localizations.dart` — handled by the exclusion below.
- `lib/l10n/generated/**` joins `lib/generated/**` in `analyzer.exclude`. What it carries: the output of `flutter gen-l10n`, gitignored and rebuilt on every checkout, whose only findings were the SDK's own two delegate deprecations written by the generator. A fix would be an edit the next build overwrites; the ARB sources and every call site stay analyzed, and ADR-099's `GlobalMaterialLocalizations.delegates` append is the actual fix and is checked in the app's code.

### Proof the plugin loads

A scratch commit added a `Notifier` with a public field; the gate went red on `avoid_public_notifier_properties`, a `riverpod_lint` rule, locally and in CI (run recorded in the pull request), and the file was then removed. No check re-proves this on every run: if the plugin stopped loading, the gate would still pass on the rules that remain.

### Consequences

A new analyzer finding fails the build. Fix it; there is no ignore list, and an exclusion must say what the excluded content carries.


---

## ADR-103 — Existing data moves into Prudent Local once, by a file, into an empty store, and only if every balance matches to the cent

**Date:** 2026-11-15. **Status:** accepted (decided by the user on the phase-0 analysis). **Plan:** decision 0.4 of
`docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245); analysis in `docs/plans/prudent-local-phase0.md` §0.4. **Builds
on:** ADR-071 (the privacy export), ADR-091 (import fingerprints), ADR-102 (the Local store model).

### Decision

- **A one-time import of the privacy export (`DataExport`, `privacy.proto`) into an empty Local store**, not a fresh start and not an
  ongoing bridge between the two products. A store that already holds data refuses it: merging two histories has no identity story.
- **Refused whole, nothing kept, unless every balance matches to the cent.** An exported account balance is the *derived current*
  balance (`AccountMapper.java:86`), so the opening amount is rebuilt as `exported balance − Σ exported records` per account and
  currency; after the import every derived Local balance must equal the exported one. Because the openings are built from those very
  balances, the check holds by construction for a correct import and catches **dropped or mis-joined records** (a lost transfer leg,
  a flipped sign, a record on the wrong account). **It does not check** budgets, carry-over, envelopes, free money, goal progress or
  occurrences: the export carries none of those figures (ADR-071). They are proven instead by unit 10b's test, which imports an export
  made by the real server and compares every figure with the server's own answers to the cent; at run time they are unchecked. An unknown `format_version`, a file that does
  not parse, or a transfer with one leg missing is refused the same way.
- **Repairs made on the way in:** server UUIDs are kept as ids so links survive, normalised to 32 lower-case hex characters so that their text order (Local's
  tie-break) is the server's byte order; the two legs of each transfer become one transfer
  record (ADR-102); a correction's intent fields are filled from the balance before it; occurrences and budgets get their
  natural-key ids and every `plan_occurrence_id` is remapped; the default account moves into settings. **Dropped on purpose:** the
  profile (Local has no account), open import sessions and rows, reminder-read times and archive times (not in the export).
- **A new unit before the import unit, on the server side:** the import fingerprint and occurrence (ADR-091) are added to the
  export, contract-first, so a statement imported before the move is still recognised after it; and the server-connected app gains
  **"Save to a file"** for the export (beside the clipboard copy), with a warning that the file is not encrypted. The Local app reads
  the export from a file the person picks, never from the clipboard (ADR-100, T14).
- **The server account is not erased by the move.** The Local app says how to erase it once the person has checked the figures.

### What this supersedes, and why

- **"Is there a path from a server account to a Local one? … Decide: import that export into a fresh Local store, or no migration and
  a fresh start."** (`PRUDENT-LOCAL-PLAN.md`, 0.4) → **decided: import, gated.** *Why:* the export already holds every row in every
  state, and its balances give a check strong enough to refuse a wrong import rather than ship one.
- **"The clipboard is the export's only destination for now"** (ADR-071, Decision) → **refined: the server-connected app also saves
  the export to a file.** *Why:* the move is a whole ledger in plaintext, and the clipboard reaches clipboard managers and other
  devices (ADR-100, T14). The clipboard copy stays for the person who wants it.
- **`Record` on the wire has no import fingerprint** (`records.proto`; finding F-02) → **to change**, in its own unit and ADR. *Why:*
  without it a re-imported statement writes every row twice after the move.

### Consequence

Nothing is built. The plan gains the server-side unit (export fingerprints and file save) before the import unit. Verified: nothing;
this records a decision.

---

## ADR-102 — Money under merge in Prudent Local: its own store messages, ids from natural keys, a transfer as one record, and rule breaks shown, never fixed

**Date:** 2026-11-15. **Status:** accepted (decided by the user on the phase-0 analysis). **Plan:** decision 0.2 of
`docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245); the full per-field table for every message in `proto/prudent/v1/` is
`docs/plans/prudent-local-phase0.md` §0.2, and is part of this decision; **that table is frozen as of jlogicsoftware/prudent#249** —
the phase-0 document is not append-only, so a change to a field's class is made by a new ADR that supersedes the row, never by editing
the table. **Depends on:** jZen ADR-065/073 (`zen_store`'s per-field
merge). **jZen issues:** jZenDev/jZen#232 (multi-record write), #233 (app issues beside conflicts), #234 (bulk resolution), #235
(per-field policies), #236 (CloudKit record names).

### Decision

- **No last-writer-wins anywhere; wall-clock time never decides.** `zen_store` merges per top-level proto field: edits to different
  fields merge, equal values merge, and two different values of one field are always a conflict for the person. Every rule below is
  built on that and asks nothing more of it.
- **Every figure is derived:** balances (opening + net of records, ADR-014), budget summary and carry-over, envelopes, free money, goal
  progress, analytics, overdue, due reminders. The opening amount per account and currency is the only stored money figure of an
  account.
- **The Local store has its own messages** (`local/prudent_local_core/proto/prudent_local/v1/`, generated as jZen ADR-080 does for its
  demo); a mapper produces the `proto/prudent/v1/` messages the shared screens use. The wire `Account.balances` is a derived value and
  is not stored; each account currency is its own record.
- **Field classes** (table in the phase-0 document): *merge* (its own field), *group* (coupled fields in one nested message that
  conflict together — on records and plans, account + currency + amount is one `posting`), *immutable*, *derived*, *device* (never
  synced). Note, payee and category are plain merge fields: they merge beside edits to other fields, and **two different values of one
  of them is still a conflict** — the plan's "note and category are not conflicts" is withdrawn, because the only way to make it true
  would be to pick a winner.
- **Ids from natural keys.** Where the server holds a unique index on a natural key, the local id is derived from it, so two devices
  that make "the same" thing write the same record and a uniqueness rule becomes a same-record conflict the store shows: settings
  (constant id), account currency (`account, currency`), budget (`category, month, currency`), occurrence (`plan, date`), the record
  confirming an occurrence, an imported record (`account, fingerprint, occurrence`), starter categories (seeded only by "Start fresh on
  this device", never by "Join"). No id is ever derived from an amount, title, payee or account number. **The default account moves
  into settings** as one field, so two devices cannot leave two defaults.
- **A transfer is one immutable record holding both legs — a deliberate Prudent Local difference from the server**, which writes two
  `Record` rows sharing a `transfer_id` (`TransferResource.java:74`). Locally a leg can never arrive alone, because there is no second
  record to wait for; the two leg `Record`s the screens and the parity suite see are produced on read with ids derived from the
  transfer's. Figures are the same as the server's; storage is not. Like the server, a transfer is never edited, only deleted.
- **Completion and detachment are derived, not written:** an occurrence is completed when a live record carries its id; a record
  whose plan is deleted reads as detached. Neither needs a second record written beside the first.
- **Rules across records are checked after every sync and listed as integrity issues with actions**, beside the store's conflicts;
  nothing is fixed silently. The list (dangling references, a currency an account no longer holds, a sign against a category's kind,
  an envelope below zero, money in an archived goal, two live resets for one slot, an occurrence skipped on one device and paid on
  another, a correction whose effect changed, two accounts with one account number) and its actions are in the phase-0 document. An
  envelope below zero is repaired by a compensating entry, never by a delete. Free money below zero is not an issue (ADR-051 allows it).
  Until jZenDev/jZen#233 lands, Prudent shows the list itself.
- **A correction keeps the server's meaning** — a stored delta from the balance at that moment (`CorrectionResource.java:95–110`) — and
  two immutable local fields, the balance asked for and the balance seen, so the integrity check notices when a merge changed its
  effect and asks: keep, adjust to the intended balance, or delete.
- **Goal allocations stay append-only** with random ids: two devices' entries never meet.
- **Same-intent timestamps keep the earliest time.** Only for `revoked_at`/`revoked_by` of a reset, a goal's `status_changed_at`
  and an occurrence's reminder-read time, and only when every side holds the same new state, Prudent settles the conflict itself by
  keeping the earliest time. That is not last-writer-wins: no side's intent is dropped, and arrival order cannot change the answer.
  It moves into the store when jZenDev/jZen#235 lands. Every other conflict goes to the person.
- **Lists answer as the server's do.** A transfer is expanded into its two leg `Record`s before the record list's filters run, so
  `type=transfer`, an account filter and an `abs(amount)` range apply per leg exactly as on the server. Ids are lower-case hex text
  compared as text — the server's Postgres byte order — so the `date desc, id` tie-break is the same on every device; it is not a
  parity property, because server and Local mint different ids (phase-0 §0.3, "List, filter and order semantics").
- **Import sessions and rows are device-only**, in a second, unsynced, encrypted store (`ZenDeviceStoreKey.load` with its own `name`).

### What this supersedes, and why

- **"A transfer is two legs created together, and what happens if only one arrives"** (`PRUDENT-LOCAL-PLAN.md`, 0.2, and the server's
  model in ADR-014 / `transfers.sql`) → **reframed for Prudent Local: one record.** *Why:* `zen_store` has no multi-record write and
  the transport delivers record by record (jZenDev/jZen#232), so two legs could be half-written on one device and half-delivered to
  another; one record removes the case instead of inventing a rule for it. The server keeps two legs, unchanged.
- **"which fields merge without a question and which are a conflict (amount and account are conflicts; note and category are
  not)"** (`PRUDENT-LOCAL-PLAN.md`, 0.2) → **corrected.** *Why:* any field set to two different values is a conflict in `zen_store`;
  what can be chosen is how fields are grouped, which are immutable, and which are not stored.
- **"Map every proto message into `zen_store`"** (`PRUDENT-LOCAL-PLAN.md`, unit 4) → **refined: through Local's own store messages.**
  *Why:* stored as they are, the wire messages would let a currency and an amount merge apart and would store a derived balance.
- **"the server minted ids because an id from an untrusted client is not identity"** (plan, unit 4; `Ids.java`) → **changed locally:
  random ids minted by the device, or ids derived from natural keys.** *Why:* the device is the only authority over its own store.

### Consequence

The plan's units 4–8 build to this; unit 4 owns the integrity-check runner (finding F-05). The one honest cost: a statement imported on
two devices with different category choices gives one conflict per differing row until jZenDev/jZen#234 lands. On CloudKit, ids derived
from slots show Apple which months and dates exist until jZenDev/jZen#236 lands (ADR-100, T7). Verified: nothing; this records a
decision.

---

## ADR-101 — Prudent Local is a second app that shares its screens with the server-connected app through a package

**Date:** 2026-11-15. **Status:** accepted (decided by the user on the phase-0 analysis). **Plan:** decision 0.1 of
`docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245); analysis in `docs/plans/prudent-local-phase0.md` §0.1. **Depends on:**
jZen ADR-073, ADR-079, ADR-080.

### Decision

- **Four Dart packages, linked by `path:`** (the root stays language-neutral; there is no root `pubspec.yaml`):

  ```
  client/                       the server-connected app: auth, ServerPrudentRepository, its runners, the web build
  packages/prudent_ui/          every screen and view model, money formatting, the abstract PrudentRepository,
                                the generated Dart of proto/prudent/v1/, the shared screens' en/uk/pl strings
  local/prudent_local_core/     pure Dart: Local store messages, the rules and calculators, the Erste importer,
                                the integrity checks, the parity harness's local side
  local/prudent_local_client/   the Local app: LocalPrudentRepository, ZenSync.start, zen_ui_lock, zen_ui_store,
                                its own runners, no web runner
  ```

- **No server package in the Local app's `pubspec.yaml`** (`zen_transport`, `zen_identity`, the auth deep links) **and no Local
  package in `client/`'s** (`zen_store`, `zen_store_sync`, `zen_ui_lock`, `zen_ui_store`). `verify:boundaries` checks both pubspec
  files, which is a fact one file states rather than an import graph to analyse.
- **The Local rules are pure Dart** so the parity suite runs the same scenario through the real server (`task test:e2e`, ADR-017) and
  through `prudent_local_core` on the Dart VM.
- **The Local app is its own product on the device:** its own bundle id, the name "Prudent Local", its own CloudKit container and
  data; both apps can be installed side by side.
- **The generated proto Dart moves** from `client/lib/generated` to `packages/prudent_ui/lib/generated`; `PROTO_DART_OUT` on the jZen
  include and `verify:contracts` follow it.

### What this supersedes, and why

- **"keep `client/` as the server-connected app, add `local/prudent_local_client` as the Local app"** (`PRUDENT-LOCAL-PLAN.md`, 0.1) →
  **refined: plus `local/prudent_local_core` and `packages/prudent_ui` as named packages.** *Why:* the parity suite needs the local
  rules without Flutter, and the plan named no home for the shared screens.
- **One app with a compile-time flag** (the plan's rejected alternative) → **rejected.** *Why:* it needs flavours in every runner
  (SwiftPM-only Xcode projects, ADR-083; Android, Windows, Linux), puts server packages in the Local app's dependency graph and Local
  packages in the web build's, and turns a pubspec-level boundary into an import-graph one.
- **`docs/zen-architecture.md` §3, "A wrapper around a single implementation is not an abstraction"** → **unchanged, and satisfied:**
  the repository interface of unit 1 has two real implementations.

### Consequence

Unit 2 is a large move of `client/lib` into `packages/prudent_ui` (a `git mv` pass like ADR-026); `verify:controls`,
`verify:widget-files` and the l10n setup follow the files. Verified: nothing; this records a decision.

---

## ADR-100 — Prudent Local's threat model: what a ledger on the person's own devices refuses, warns about, and accepts

**Date:** 2026-11-15. **Status:** accepted; reviewed again before plan unit 9 lands. **Plan:** decision 0.5 of
`docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245); the analysis of 0.1–0.4 is in
`docs/plans/prudent-local-phase0.md`. **Depends on:** jZen ADR-065, 073, 075–081. **Not verified:** everything here that rests on
jZen behaviour jZenDev/jZen#231 has not yet checked on a device (marked **#231** below). Decision 0.6 is ADR-099.

### Decision

Prudent Local keeps a person's whole financial history on their own devices with no server: no operator can read it, and no
operator can recover it. The threat model is the list below. Each row says what the app **refuses** (will not do, whatever is asked),
**warns** (says in words, before the step, and lets the person go on) or **accepts** (a residual risk, stated in the app's privacy text
and here), and which plan unit makes it true. A row is done only when unit 9's suite has a test for it or the row is a written refusal.

Assets: the ledger (records, balances, account numbers, payees, notes, plans, goals); the store key (`zen_store_key`, per device);
the sync key (shared by paired devices on Android, Windows and Linux); a statement file; a data copy (export).

| # | Threat | Answer | Unit | Rests on unverified jZen |
|---|---|---|---|---|
| T1 | A lost or stolen device, locked | **Accept**: the store is AES-256-GCM files with a key in the platform's secret storage; iOS adds Data Protection `complete` | 4, 9 | **#231** (store key off Apple, ADR-075 is a desk study) |
| T2 | A lost device that is unlocked, or has no PIN | **Warn**: on first launch, offer a PIN (off by default, as jZen ADR-065), saying that without one anyone holding the unlocked device sees everything; the lifecycle lock relocks in the background | 9 | **#231** (`inactive`/`hidden` on Windows, Linux, Android, ADR-078) |
| T3 | A lost device still paired keeps receiving new data and, on the folder transport, holds a key that can write valid records | **Warn**: Settings → Sync says how to cut it off today (remove it from the Apple ID; for a folder, stop sharing the folder with it, start a new folder and re-pair); **refuse** to call a device "removed" while no rekey exists | 9 | jZen has no rekey (jZenDev/jZen#237); CloudKit not verified (**#231**) |
| T4 | A forgotten PIN | Owner check where it exists (iOS, macOS, Android); erase this device's copy and re-sync on Linux and Windows (ADR-078/081). **Warn** before turning a PIN on where there is no owner check **and** no other paired device: "If you forget this PIN, this device's data is erased and nothing else holds a copy — save a copy first" | 9 | **#231** ("Forgot PIN?" on real Android, Windows, Linux) |
| T5 | Every device lost, or the iCloud Keychain lost | **Accept and warn**: the data cannot be recovered by anyone. Said at first run, in Settings → Sync, and in the privacy text; "Save a copy" is offered there | 9, 13 | **#231** (iCloud Keychain and CloudKit recovery behaviour, never run) |
| T6 | A shared cloud folder holds the ledger's ciphertext | **Accept**: the service sees the number of devices and records, sizes and times, never content (jZen ADR-076). **Warn** when a folder is chosen: choose one only you can open; a folder shared with others shows them when and how much you edit. **Refuse** a folder inside the app's own data directory | 9 | **#231** (real Syncthing, Dropbox, OneDrive; Android SAF) |
| T7 | Apple sees CloudKit metadata | **Accept, closing later**: record names are `<collection>:<id>` in plaintext (`ZenCloudKitBridge.swift:12`), so Apple sees collection names and counts. **Refuse** to derive any id from an amount, a title, a payee or an account number; ids derived from slots (category + month + currency, plan + date) expose which months and dates exist until jZen keys the names | 4 | jZenDev/jZen#236; real CloudKit **#231** |
| T8 | A Linux desktop with no secret service, or a locked keyring | **Refuse** to open: no key in a file, no plaintext fallback, no new key over existing data (ADR-075). Show what to install or unlock; offer nothing that erases | 9, 11 (`libsecret-1` in the Linux package) | **#231** (no-secret-service desktop) |
| T9 | Windows answers a failed key read with "nothing stored" | **Refuse** to make a key beside existing files (ADR-075's directory check); offer "erase this device's copy and re-sync", never automatically | 9 | **#231** |
| T10 | An OS backup restores the store files without their key (iCloud backup, Time Machine, Android Auto Backup, File History) | **Refuse** to open and explain; offer erase and re-sync. Android: the app's manifest sets `android:allowBackup="false"` (or excludes the store and secret storage), and a gate checks it | 9, 11 | **#231** (Keystore behaviour after restore) |
| T11 | A statement file left in Downloads | **Warn** after a commit or a discard: "Prudent did not keep the statement file; it is still where you picked it — delete it if you no longer need it." **Refuse** to copy, cache or log the file's bytes; it is read once (ADR-089). Prudent cannot and does not delete the person's own file | 8b, 9 | — |
| T12 | Import session rows (descriptions, counterparties) spread to other devices and the sync service | **Refuse** to sync them: sessions live in a second, unsynced, encrypted store and end after 24 hours, at commit or discard (phase-0 doc, 0.2) | 8b | — |
| T13 | Two devices import one statement | **Accept**: deterministic record ids make each row one record; differing category or note choices become conflicts the person settles | 4, 8b | — |
| T14 | A data copy (export) is plaintext | **Warn** before saving that the file is not encrypted and should be deleted after use. **Refuse** the clipboard as the Local app's export channel (clipboard managers, Universal Clipboard, Windows cloud clipboard history); the copy is a file the person picks | 9, 10b | — |
| T15 | Balances in the app switcher, Android's recents or a screen recording | `zen_ui_lock`'s cover on `inactive`. **Accept for now** that Android's `FLAG_SECURE` is not set (ADR-078); not patched in Prudent | 9 | jZenDev/jZen#240; recents timing **#231** |
| T16 | Reminder notifications on a lock screen | **Refuse** amounts in notification text (ADR-056); the plan's title is shown. **Warn** in the reminder setting that titles appear on the lock screen | 6b, 9 | — |
| T17 | A pairing code photographed or overlooked | **Accept** jZen ADR-077's answer: shown on request, five minutes, hidden in the background, never in a log, URL or clipboard | 9 | QR camera scanning **#231** |
| T18 | A release build syncing through `ZenFolderCloud`, which stores payloads unencrypted | **Refuse**: the Local app's release tasks and CI fail when `ZEN_SYNC` is set for a release build | 11 | jZenDev/jZen#238 (the framework does not refuse it) |
| T19 | Someone with write access to the folder but no key | **Accept**: AES-GCM with the file path bound in, so a file cannot be forged, renamed or replayed into something else; deleting files only delays sync (ADR-076) | — (accept only; no unit) | **#231** |
| T20 | An older app version re-saves a record and drops fields a newer version added | **Refuse** whole-record saves from forms: a form applies only what the person changed onto the record as stored now (jZen ADR-080's rule), so unknown fields survive | 4, 9 | **#231** (jZen ADR-080's unknown-field rule is tested on a host only) |
| T21 | Data in logs | **Refuse** amounts, titles, payees, notes, account numbers, statement text, the sync key and pairing codes in any log line; a failure is one line of classes and codes (ADR-072, ADR-094) | 9 | — |
| T22 | Account numbers | Kept only inside the encrypted store; **refuse** them in ids, logs, notifications and file names | 4, 5 | — |
| T23 | A merge breaks a rule across records (an envelope below zero, a record on a deleted account) | **Refuse** to fix it silently; listed as an integrity issue with actions (phase-0 doc, 0.2 D6) | 4–8 | jZenDev/jZen#233 (no place in `zen_ui_store` for app issues) |
| T24 | "Delete my data" has no server to delete from | **Refuse** to say "deleted everywhere": "Erase this device's copy" says what remains (other devices, the folder, iCloud) | 9 | jZenDev/jZen#239 |
| T25 | One OS account shared by two people | **Accept**: one ledger per OS user; the PIN is a door, not a key (jZen ADR-065). Said in the privacy text | 13 | — |
| T26 | A wrong device clock | **Accept**: time decides nothing in a merge; it shows dates, expires pairing codes on an honest device, and dates reminders and import expiry | — (accept only; no unit) | — |

### What this supersedes, and why

- **"Lost device, a PIN that is forgotten, a shared cloud folder…, a Linux desktop with no secret service, a statement file left in
  Downloads. Output: ADR and a list of what the app must refuse or warn about."** (`docs/plans/PRUDENT-LOCAL-PLAN.md`, 0.5) →
  **answered.** *Why:* the five named threats are rows T1–T4, T6, T8 and T11; working them through found the others — the clipboard
  as an export channel (T14), CloudKit's plaintext record names (T7), a release build on the unencrypted development transport (T18),
  backups restored without keys (T10), and a paired device that can never be removed (T3) — which are the ones a reviewer would not
  have listed and an attacker would find.
- **ADR-071's "the clipboard is the export's only destination for now"** → **unchanged for Prudent Server; refused for Prudent
  Local** (T14). *Why:* the server app's copy existed to avoid a platform package per target; a Local app's copy is the only copy of
  the data outside its devices, and the clipboard reaches other machines.

### Consequence

- Unit 9's "done when" gains a test or a written refusal per row; units 4, 5, 6b, 8b, 10a, 10b, 11 and 13 carry the rows named for them.
- Nine jZen limitations are filed (jZenDev/jZen#232–#240) and listed in `docs/plans/prudent-local-phase0.md` (J1–J9); T3, T7, T15, T18, T23 and T24 change
  when they land. None is patched around here.
- Rows T1–T10, T15, T17, T19 and T20 cannot be more verified than jZenDev/jZen#231; Prudent Local is not released before unit 12.
- Nothing was built or run for this entry.

---

## ADR-099 — Prudent moves to Flutter 3.50 and Dart 3.14 with jZen pinned at `fdef7e8`, imports Material and Cupertino from `material_ui` and `cupertino_ui`, appends their localization delegates, and drops `custom_lint`

**Date:** 2026-11-15. **Status:** accepted. jlogicsoftware/prudent#235; jZenDev/jZen#212 (jZen PR #229, its ADR-082). Follows ADR-097 and ADR-098, which are not edited.

### Decision

- **The pin moves** from `c1a4e22` to `fdef7e8` (jZen `main`, which contains #229) in `ci.yml` and `audit.yml`. The eight commits between them were read; relevant to what Prudent
  consumes: the Flutter 3.50 migration of every `zen_ui_*` package and the SDK constraints `>=3.14.0 <4.0.0` (`zen_ui_widgets` also `flutter: >=3.50.0`), a second guard commit for nested
  detail pages (Prudent's real-flow tests pass with it), `zen_secure_store` (one line in the io keystore), and the local-first line (`zen_demo_local`, a Windows `local_auth` stand-in,
  docs), none of it consumed. No change under `server/`, so the Java side is untouched.
- **Toolchain.** `.fvmrc` and the four `flutter-version` pins in `ci.yml` go from `3.44.2` to `3.50.0`; `client/pubspec.yaml` has `sdk: ">=3.14.0 <4.0.0"` and `flutter: ">=3.50.0"`. The Android runner
  follows jZen's demo: Gradle `9.1.0` to `9.5.0`, AGP `9.0.1` to `9.3.1`, Kotlin `2.3.20` to `2.4.20` (Flutter 3.50's Gradle plugin refuses Gradle below 9.3.1).
- **Material and Cupertino come from packages.** `package:flutter/material.dart` and `cupertino.dart` are deprecated in 3.50. `dart fix --apply --code=migrate_design_widgets` rewrote 105 imports in
  103 files (`client/lib`, `client/test`); `material_ui: ^1.11.0` and `cupertino_ui: ^1.1.6` are declared, the same versions as jZen. The `verify:controls` rules are unchanged: they forbid
  controls by name, and the names are the same.
- **A `MaterialApp` composition appends `...GlobalMaterialLocalizations.delegates`.** `material_ui`'s `MaterialApp` looks up its own Material and Cupertino localizations, and the list that
  `flutter gen-l10n` generates (`PrudentLocalizations.localizationsDelegates`) still registers the SDK's, so `uk` and `pl` failed with "A MaterialLocalizations delegate that supports the pl
  locale was not found". `lib/app.dart` and the 21 test files that compose the list append them; the list is no longer `const`.
- **`custom_lint` is removed, `riverpod_lint` becomes an analyzer plugin.** Under Flutter 3.50 `flutter_test` pins `test_api 0.7.14`, which needs `test >=1.31.2` and so `analyzer >=13`; `custom_lint`
  needs `analyzer ^7` or `^8`, so the project could not resolve. `riverpod_lint` 3.2 no longer uses `custom_lint`: it is installed with `plugins: riverpod_lint: 3.2.0` in
  `analysis_options.yaml`, and neither package is in `pubspec.yaml` any more. This also ends the long-standing "the repository's own `pub get` fails on this machine" in earlier ADRs. Whether
  the plugin's rules are actually running in CI was seen once (a finding appeared and disappeared between two runs of `dart analyze`) and is not established.
- **Lints that the newer analyzer added are fixed, not silenced:** `use_null_aware_elements` (11), `prefer_initializing_formals`, `unnecessary_underscores`, `curly_braces_in_flow_control_structures`
  (`dart fix --apply --code=...`), and one unused constructor parameter in a test. `dart analyze lib test` reports nothing outside the generated localizations, which are built and not tracked.
- **`client/pubspec.lock` is regenerated** by `flutter pub get` under 3.50 (the hand-merged entries of ADR-098 are superseded by a real resolution).

### Checked

`dart analyze lib test` (nothing outside the generated localizations); the whole client suite on Flutter 3.50 against jZen `fdef7e8`: 530 pass (two tests read `../server` and were run with it linked);
`verify:controls`, `verify:import-fixtures`, `verify:swiftpm`. Debug builds of the app on Flutter 3.50 succeed for macOS, an iOS simulator and Android (`flutter build apk --debug` on Gradle 9.5.0, AGP 9.3.1, Kotlin 2.4.20); they were built in a scratch copy against jZen `fdef7e8`, as the checkout's own `../jZen` is not at that commit.

### Not checked

CI on the new pins; the server suite (nothing under `server/` changed); a run of the migrated app by hand (the suite and the builds are the evidence); Windows, Linux and web builds; a real device. Formatting is not changed: the committed layout is from an older formatter,
as in jZen's migration.

---

## ADR-098 — The import is driven through the compiled app on a device by `integration_test/app_import_test.dart`, which CI does not run, and the native file panel is still only seen by hand

**Date:** 2026-11-15. **Status:** accepted. Follows ADR-093 and ADR-097, which are not edited.

### Decision

- **A device-level test exists.** `client/integration_test/app_import_test.dart` runs *inside* the built app (`flutter test integration_test/app_import_test.dart -d macos`, or an
  iOS simulator) against a live Quarkus server and Supabase. It signs up a throwaway user, creates an account with a bank number, imports a synthetic nine-row
  statement through the real screens, asserts the six records and the derived balance, imports the file again and expects six duplicates and no second write, then
  leaves through the leave prompt (Escape on a wide host, Back on a narrow one; jZen#226, ADR-097). Run on 2026-11-15 on macOS and on an iPhone 17 Pro simulator.
- **`statementPickerProvider` is overridden with the file's bytes.** A native dialog cannot be driven from inside the app. The statement is a synthetic literal in the
  test (amounts of 1000 or more included, which the one real export never had); no real statement is involved.
- **It is not a CI gate.** `task test:client` runs `test/`, and `task test:e2e` names `integration_test/e2e_test.dart`, a pure-Dart VM suite, so neither picks the new file up.
  It needs a running stack and a device, which no CI runner here has, and it leaves its test user in the local database.
- **`integration_test` (SDK) joins the dev dependencies.** `client/pubspec.lock` was extended **by hand** with the six entries it brings (`integration_test`, `flutter_driver`,
  `fuchsia_remote_debug_protocol`, `process`, `sync_http`, `webdriver`), copied from a resolution that succeeded in a copy without `custom_lint`: the checkout's own
  `pub get` cannot resolve under the local Flutter 3.50 (`custom_lint` against `test`, as before). Whoever next runs `pub get` under the pinned Flutter 3.44.2 should check
  that it leaves the lock unchanged.

### Seen by hand, not by the test

On the iOS simulator the real app's "Choose CSV file" opened the system file picker, the CSV in "On My iPhone" was selectable, was read, and checked to the same review
(6 to import, 3 not readable); Back asked "Leave this import?". **The macOS file panel (`NSOpenPanel`) has not been seen**, nor a physical device.

### Found on the way

A local Supabase database migrated on 2026-10-28 refused the server because the checksum of jZen's migration `V200` had changed since it was applied. Starting the server
once with `QUARKUS_FLYWAY_REPAIR_AT_START=true` repaired the history and applied the import migrations; nothing else was touched. In the same macOS run a second Escape, sent right after "Stay" closed the leave prompt, showed no prompt again; the first Escape had. Whether focus is not restored to the pane after the dialog, or only the test's key event is affected, was not investigated. On a phone-sized screen the review page gives most
of its height to the default-category selects, and the rows are visible three at a time.

---

## ADR-097 — jZen is pinned at `c1a4e22` to consume the nested-page guard (jZen#226), so the import's leave prompt now answers Escape and a replacing detail on the real path through Accounts

**Date:** 2026-11-15. **Status:** accepted. jZenDev/jZen#226 (Prudent's report), jZen PR #227. Follows ADR-096, which is not edited.

### Decision

- **The pin moves** from `3a820b2` to `c1a4e22` ("Guard nested detail pages on close") in `.github/workflows/ci.yml` and `.github/workflows/audit.yml`.
  The only commit between them is #227, which touches `zen_detail_pane.dart` and its test and nothing else.
- **The framework's change.** `ZenDetailPaneState.requestClose` asks every page on the pane's stack, topmost first, and stops at the first
  page that vetoes with `canPop: false`; a `NavigatorObserver` keeps the stack. Escape and a second detail replacing the pane use it. The Close button
  is still offered only by the pane's first page: a nested page shows Back, which asks that page's guard as it always did. A tab switch is still
  not guarded, by design.
- **Prudent's code did not change.** `ImportPreviewScreen`'s `PopScope` was already the guard; the framework now reaches it on the real path
  (Overview or Settings, Accounts as the pane root, the import a nested page). Only comments changed.
- **Tests flipped, as their comment required.** In `client/test/import_flow_test.dart` the group "real flow: Accounts pane, then Import" no longer
  pins Escape and a replacing detail as not asking: each now asks "Leave this import?", Stay keeps the review open and discards nothing,
  "Discard and leave" discards once. The pin that the nested page has no Close button stays, now as jZen's design rather than a defect.
  Back's two tests are unchanged.

### What this supersedes

ADR-096's statement that on the real path Escape and a second detail do not ask, and that this is jZen#226. It no longer holds. The rest of ADR-096 stands:
nothing is discarded in `dispose`, a tab switch leaves the session open and listed.

### Checked

The whole client suite against a copy of jZen at `c1a4e22`, in a scratch copy without `custom_lint` and `riverpod_lint` (530 pass); `verify:controls`,
`verify:import-fixtures`, `zen:verify:widget-files`. Not run: the server suite (nothing under `server/` changed), CI on the new pin, and any real window or device.

---

## ADR-096 — jZen is pinned at `3a820b2` to consume the detail-pane guard (jZen#222), the import's leave prompt answers Close, Escape and a replacing detail only when the import is the pane's root (not on the real path through Accounts, jZen#226), and a tab switch still discards nothing

**Date:** 2026-11-15. **Status:** accepted. jZenDev/jZen#222 (Prudent's report), jZen PR #224; the nested case it leaves open is jZenDev/jZen#226.

### Decision

- **The pin moves** from `3313b40` to `3a820b2` ("Let a detail page guard Close and Escape") in `.github/workflows/ci.yml` and, as its
  comment requires, `.github/workflows/audit.yml`. The 26 commits between them were read. Relevant to what Prudent consumes: #224
  itself (`zen_detail_host.dart`, `zen_detail_pane.dart`) and `c5f1c87`, which changed `ZenCupertinoTextFormField` under `ZenTextField`
  (Apple platforms; the whole client suite is green on macOS with it). `Taskfile.app.yml` gained `guard:web` and `build:web`, which refuse a web
  target for an application with no server pom; Prudent has one, so both are no-ops here, and the build-runner and CI-runner tasks it
  calls changed only for a pom-less application. No change under `server/`, `zen_core`, `zen_transport`, `zen_identity` or `zen_secure_store`.
  The rest is the local-first line, none of it consumed by Prudent: `zen_ui_lock`, `zen_ui_store`, `zen_store`, `zen_store_cloudkit` and the new
  `zen_store_key`, `zen_store_shared_folder` and `zen_store_sync`, pairing, and ADR renumbering and docs.
- **The framework's change.** Close, Escape and a second detail asking to replace the pane now consult the pane's first page's `PopScope`
  as Back does: a page that vetoes with `canPop: false` is told through `onPopInvokedWithResult` and decides whether to pop itself, and
  a replacing detail is dropped while the guard vetoes. A tab switch discards the pane with its navigator and cannot be vetoed; jZen's
  documented hook there is `State.dispose`.
- **Prudent's code did not need a new guard.** `ImportPreviewScreen` already wraps its page in a `PopScope` that, while the session is open,
  asks "Leave this import?" and discards on "Discard and leave" (ADR-093). For an import opened as the **root route of a pane** (`showZenDetail` from a
  list) the framework now reaches it for the other exits too: "Stay" keeps the review, "Discard and leave" discards on the server and closes the pane.
  Once the session is committed or ended the page allows the pop, so nothing is asked. The first step (no session yet) has no guard and closes at once.
  Only the comments that called the pane exits a framework gap changed.
- **This narrows ADR-093's limitation; it does not remove it.** The guard does **not** reach the real entry path. The only opener of the import is
  `AccountScreen`, itself a pane root (opened with `showZenDetail` from Overview and Settings, ADR-062), and `showZenDetail` called from inside a
  detail pushes a `ZenPageRoute` onto the pane's navigator, so the import is a **nested page** above the Accounts root. jZen's `requestClose`
  consults only the pane's first route, which is Accounts and has no `PopScope`. On the real path: **Back asks** (the nested route's own
  `PopScope`); **Escape closes the whole pane with no prompt**; **a second detail replaces the pane with no prompt**; **the Close button is not shown** on
  the nested page (it shows Back); in each unprompted case the session stays open and is listed under "Unfinished imports". This is
  jZenDev/jZen#226. ADR-093's premise that the import sits in "the root route of a side pane" is accurate only for the root case, and ADR-093 is
  not edited. A minor consequence on the guarded (root) path: after "Discard and leave" from a second-detail attempt the replacing detail is dropped,
  and the user must click it again.
- **Nothing is discarded in `dispose`.** Discarding is a network call that can fail, that the user has not agreed to, and that would race a
  commit the user just made; a `dispose` cannot ask or report. The session is left open, as it is when the app is closed, and the
  "Unfinished imports" list on the first step stays as the way back to it or out of it, and as the way out of a "too many open imports" refusal.
- **Tests** (`client/test/import_flow_test.dart`, wide host). *Import opened as the pane root:* each of Close, Escape and a second detail asks, "Stay"
  vetoes (the second detail is not shown), "Discard and leave" discards once and closes. Only these ask/Stay/Discard tests prove the guard; the four
  negative tests (no prompt on the first step, after a commit or a discard, on a tab switch) also pass on the pre-#224 pin. A tab switch (removing the
  host from the tree) leaves the session undiscarded and listed. *Real flow (Accounts pane, then Import):* Back asks, Stay keeps and "Discard and leave"
  discards and returns to Accounts; Escape and a second detail are pinned as **not** asking, with the session left open and listed, and the nested page
  is pinned as having no Close button. Those pins are jZen#226: when it is fixed and consumed they fail on purpose, as the signal to flip them (the
  comment on the group says so). The narrow (pushed page) tests are unchanged and pass.

### What this supersedes

The sentence of ADR-093 that said a pane's Close, Escape and a second detail do not ask, but only for an import opened as a pane root; on the real path through Accounts it still holds (jZen#226). Its other decisions stand and it is not edited.

### Checked

Client suite in a scratch copy without `custom_lint` and `riverpod_lint` (528 pass); `verify:controls`, `verify:swiftpm`, `zen:verify:widget-files`,
`verify:boundaries`, `verify:import-fixtures`; server `./mvnw test` through `task test:server` (1256 pass). Not seen on a device or a real window, and
CI on the new pin has not run.

### The tab switch

It remains unguarded and the framework says so on purpose, so it is a documented limit rather than a bug to file. It costs the user nothing here, because the session
stays open and findable. If an application ever needs to stop a tab switch, that is a new framework request, not a reason to discard in `dispose`.

---

## ADR-095 — The Erste export steps are recorded as reported by the user, the comma separator is required, and #42 may close

**Date:** 2026-11-15. **Status:** accepted. jlogicsoftware/prudent#42.

### Decision

- `docs/erste-csv-contract.md` now holds the export procedure, **reported by the user from the bank's
  web UI on 2026-11-15** (Polish interface, four screenshots): "Historia" then "Historia", the filter
  panel, "Pobierz listę transakcji" then "CSV", the "Separator" dropdown, "POBIERZ", and the file name
  `history_YYYYMMDD.csv`. Nothing beyond what the user saw is stated; the rest is listed there as
  unconfirmed (whether one page can hold several accounts in a file, the filters' effect on the file, size
  limits, a non-default separator's output). The user later added two facts: the account is chosen in the
  page header, and "Widoczne w tabeli" does not change the CSV.
- The importer requires the comma separator, as ADR-088 already had it; the procedure now tells the
  user to leave the dropdown on "przecinek - ,". The file name is still never parsed.
- This closes the last open bullet of #42, which ADR-088 said must not be closed until the steps
  existed. #42 may be closed with the change that records them.

### What this supersedes, and why

Only the sentences of ADR-088 that said the export steps were missing and #42 stays open. ADR-088
is not edited; its other decisions stand.

---

## ADR-094 — The import's failures are a catalogue that runs through the real API and proves "nothing was written", every rule the importer can emit must have a case, and a commit that fails now says which rule and which rows

**Date:** 2026-11-15. **Status:** accepted. jlogicsoftware/prudent#77, last task of the epic jlogicsoftware/prudent#41.

### Decision

- **The epic's safety claim is a test, not a sentence.** `ImportFailureCatalogue` (test sources, `prudent.imports`) is data: 180 statements the Erste import must
  refuse as a whole and 41 it must accept as a file and flag row by row, each with the rule code, the bounded row numbers or the exact message it must produce. Every file is built in memory from one
  synthetic base statement (`ImportTestSupport.Erste`: a summary row and five rows holding each description shape); none is a copy of a real export and none needs a fixture file or a pass
  through `verify:import-fixtures`. The classes: empty and one-newline files; encoding (UTF-8, UTF-16 and UTF-32 with and without a BOM, Windows-1250, ISO 8859-2, NUL, a lone lead byte, an
  overlong sequence); line endings and a missing or doubled final newline; a header added above, below or instead of the summary row; the summary row missing, repeated, moved or alone; columns
  added, dropped, shifted or swapped, on every row or on transaction rows alone; delimiters (semicolon, tab, pipe), quote styles; the summary's dates, account (including `ß` and a dotless `ı`), currency; mixed
  currency (a summary in another currency, card payments in euro or dollars, an amount with a currency suffix, a destination that does not hold PLN); dates in other formats, impossible days, out-of-range years;
  amounts with separators, other decimals, signs, other digit sets, 12 digits; an amount column that has moved (a positive card or BLIK row, amount and balance swapped, card rows that disagree with their own text); sequence numbers; descriptions in new wordings, a card mask or currency that changed; counterparty accounts; oversized (5001 rows, 5 MiB + 1,
  a field of 1100 characters); files cut mid-row, mid-quote and mid-letter; a PDF, PNG, zip, gzip, random bytes, JSON, XML, HTML, prose, another bank's CSV of the same shape; and every wrong destination (another number, no
  number, inactive, another user's, unknown).
- **Every case proves both halves.** `ImportFailureMatrixTest` uploads each through `POST /api/v1/import-sessions` with `erste-pl-csv` and asserts the status, that the message is exactly the contract's one shape (rule, rows,
  "and k more"), that it holds only words of the fixed vocabulary, and that no value of the file, no `0000` and none of the synthetic marker words appears in the body, and that no log line the server wrote meanwhile (a JUL handler on the root logger) holds a free-text value, a number of the file (every date, account number, amount of four or more digits, compared after stripping everything but letters and digits, so an account number without its spaces is found) or any amount in its comma or dot spelling, whatever its size, after only UUIDs, timestamps and durations are removed; the check was proved by planting a `log.warn` of an account number and the amount of an `amount.zero` row in a scratch copy of the importer, which failed three matrix cases, and a self-test holds the same plants and the allowed shapes. It then compares a **snapshot of everything a refused import could touch, for both users** — every record
  with its key, every account with its number, balances and net, every session and row — taken before and after, and finally uploads a good statement to show nothing was left poisoned. A flagged file is held to the
  same standard, then previewed and committed: exactly the accepted rows reach the ledger and the account's net moves by exactly their sum.
- **Exactly once.** The same statement imported twice, two tabs that previewed before either committed, a commit repeated after a lost answer, overlapping exports with different sequence numbers, identical rows in one file
  (and again), and a statement of only flagged rows each leave the ledger with the effect of one import.
- **The commit phase.** `ImportCommitFailureTest` changes the world between the preview and the commit and asserts the same four things — a rule and its rows, no text, an unchanged ledger, the session still open — and then that the retry after the fix writes the
  statement once: a default or a row category deleted, archived or made the wrong direction; an account renumbered, unnumbered, deactivated, stripped of PLN, or deleted together with its records (ADR-081); an expired session; two tabs;
  a discard and a commit in either order; a failure injected at the parse, at the preview and at each of the five rows of the commit; a ledger refusal that quotes its input; another user's session and ledger.
- **A commit that failed used to explain nothing.** `LedgerImportCommitter` answered a refused row with `Row N cannot be written: <the writer's own sentence>`, and the client could only say "that could not be done in the import's current state".
  Three rule codes replace it, in the contract's message shape so the client already knows how to read them: `commit.category_unavailable` (checked **before the first write**, naming up to ten rows and how many more: a category that is gone, archived or for the other
  direction), `commit.account_unavailable` (the destination is gone, inactive or no longer holds the statement's currency, at the commit only; before it the 400 keeps its plain sentence) and `commit.row_refused` (the backstop for
  any other ledger refusal, which no longer echoes the writer's sentence, since a writer can quote a value it was given and a row's values come from the statement). The client has a sentence for each in en, pl and uk, shows the rows a commit refusal names, and no longer
  says "may not have been written" over a refusal that wrote nothing. Rule codes the client knows: 45 in all (the 40 of the catalogue, the amount-column rule and the four below).
- **The amount column is checked without the balance column.** A swap of the amount and balance columns used to be accepted for an incoming own-account transfer (the balance became its amount) because only the sign of card and BLIK rows gave it away. `layout.amount_column` now refuses the **whole file** on either of two witnesses:
  any card or BLIK row with a positive amount (a real export has none, so one is enough), or the amount column disagreeing with the amount written in the card description on **half or more of at least two card rows**. A lone disagreeing card row in an otherwise consistent file is not systematic and stays the per-row flag
  `card.amount_mismatch`; so does a file with a single card row. The balance column is still never read (it does not chain, contract). Residual limit: a file with no card or BLIK row at all (own-account transfers only) cannot witness the swap, and is not refused. `amount.sign_unexpected` now remains for an outgoing own-account transfer only.
- **Upload bounds are rule codes too.** An empty upload, a file over 5 MiB, more than 5000 rows and a destination account that is not the caller's used to answer plain sentences that the client could only meet with "check that the account is active and holds the currency", which is false advice for a long export. They are now `statement.empty_upload`, `statement.too_large`, `statement.too_many_rows` and `account.not_found` (status codes unchanged), with a client sentence each in en, pl and uk that says what to do (a shorter period, another file, choose the account again). The inactive and wrong-currency destinations keep their plain sentences.
- **New rules cannot ship untested.** `ImportRuleCatalogueTest` reads every dotted lower-case string literal in `src/main/java/prudent/imports` (comments dropped, the way the client's `import_failure_test` does) and fails when a rule is emitted that no case in the catalogue names
  and no test named in `coveredElsewhere` proves (eight rules owned by another stage: the duplicate code, the own-transfer hint, the identity hook, two identifier rules and the three commit rules); it fails the other way when a case names a rule nothing emits, when a named test method does not exist or its body does not mention its rule, and when
  the matrix has shrunk below a floor. The client holds its own sentences to the same scan, and `ErsteFormatDriftTest` holds the rule codes written in the contract's validation list to the ones `ErsteStatementImporter` and `ErsteCsv` can emit, both ways.
- **Format drift fails closed.** `ErsteFormatDriftTest` pins each committed fixture to its exact parsed rows (golden values typed from the synthetic fixtures, 1 + 2 + 8 rows, field by field) and derives from each fixture, programmatically, a column dropped or added at every position,
  columns shifted either way, dates swapped, a header, no summary, a repeated summary, a changed currency, semicolons, another encoding, CRLF, a cut, a new wording of every description, a first row with each field emptied or broken. All 3 fixtures x all mutations are refused with a specific rule
  or, where the file stays well-formed and a row loses its meaning, flagged on every row; a guard test shows each mutation changes the bytes.
- **The account-number nit.** `AccountNumbers` upper-cased with `Locale.ROOT` before the shape check, so `ß` became `SS`, `ı` became `I` and `ſ` became `S`: two different typed strings were one stored number and passed. It now upper-cases `a` to `z` only; such a character stays what it is and the
  shape check refuses it, for the account form and for the Erste summary row (`summary.account_invalid`), which share the one function.

### Findings, stated rather than smoothed

- The matrix found **no partial write, no leaked text, no 500 and no accepted file that should have been refused** in the importer, the workflow or the resource. Three checks first failed because my expectation or harness was wrong, not the code (a `DD-MM-YYYY` export date reads as a transaction, so
  `layout.summary_missing`; every column shifted right puts the sequence number in the field that must be empty, so `row.trailing_field`; a follow-up upload to an account the case had emptied); no importer rule changed. The defects were the commit-phase ones above and the account number's case folding.
- **The first version of this ADR left a swapped amount and balance column accepted for an incoming own-account transfer, as a "known limit".** The audit showed that was money-unsafe, and it is closed by `layout.amount_column` (above). The remaining unwitnessed case is a file made only of own-account transfers.
- UTF-8 text that was decoded as Windows-1250 and saved again (mojibake) is valid UTF-8, so it is refused only per row: every row with a Polish letter in a description is flagged, a BLIK row in plain ASCII survives. A file with every field in quotes is accepted, as RFC 4180 and the contract's "standard CSV quoting" allow.
  A semicolon file whose amounts are still quoted is reported as `csv.malformed` and not `layout.delimiter`, because the quote is found first; the sentence still tells the user to download the statement again. A statement of only flagged rows previews and commits as "nothing imported".
- Another user's **account** named in an upload body is a 400 ("no such account for this user", the id arrived in a body); another user's **session** in a URL is a 404.

### Verified, and not

Server: the full `./mvnw test` (1256 pass: 231 matrix, which is 180 refusals, 41 flagged and 10 others, 15 commit-phase, 18 drift, 6 catalogue, the rest as before); `task verify:import-fixtures`, `task verify:reflection`, `task verify:controls`, `flutter gen-l10n`. Client, in a scratch copy without
`custom_lint`/`riverpod_lint` (the repository's own `pub get` fails first on this machine): 511 pass and 2 fail, the two `prudent_l10n_test.dart` cases that fail identically on HEAD; the new ones are widget tests and sentence checks (every failure class at upload, at commit, at a row decision, on opening; a dropped connection; 5000 rows built lazily from a builder delegate, under 60 row widgets, before and
after a long scroll). No proto or generated contract changed (only `docs/erste-csv-contract.md`), so `task generate` was not run. The plant proof of the log check ran in a scratch copy of the server.

**Not covered, and not claimed:** a real second export (so overlap and whether the bank sequence number is stable are still only what the fingerprint assumes, ADR-091); a real change of the bank's format (a bank's next format is not in any list a test can hold, only the changes thought of here); amounts of 1000 or more in a real export;
the wording of an outgoing own-account transfer; the bank's UI steps; a run on a device or with the native file picker; the client against the real server rather than a stand-in; native-speaker review of the pl and uk sentences; load (the 5000-row bound is tested, not its time on a phone); two real browsers racing one session (the race is
driven from threads in `ImportConcurrencyTest`, not through two clients). The matrix is as good as the failures someone thought to write: the catalogue forces a case for every rule that exists, not a rule for every way a bank can change.

---

## ADR-093 — The client reviews an import in one flow of three pages on the framework's controls, turns every server refusal into a localized sentence from its rule code, and picks the file with `file_selector`

**Date:** 2026-11-14. **Status:** accepted. jlogicsoftware/prudent#74, fourth task of the epic jlogicsoftware/prudent#41.

### Decision

- **Where it starts and how it moves.** The Accounts page has an "Import a statement" action in its bar (`ImportStatementScreen`), opened with
  `showZenDetail` like every other page reached from Accounts (ADR-062, ADR-063), so it stacks inside the destination's own `Navigator` and the
  sidebar stays. `ImportStatementScreen` is ONE page whose two steps are state, not routes: `ImportUploadStep` (account, file, upload) hands the session id up
  and the page swaps in `ImportPreviewScreen` (review, and after the commit the result), which hands "back to import" up to swap the upload step in again.
  It must not navigate between them: opened with `showZenDetail` on a host of 720 px or more the page is the *root route* of a `ZenDetailPane`, and a root
  route that is replaced or popped closes the pane, so a `pushReplacement` made the pane vanish after "Check statement" and left an open session behind.
  Leaving the page altogether (Back, the result's "Back to accounts", a pane's Close) pops that one route. All code is in `client/lib/imports/`, one widget per file.
- **State.** `importReviewProvider(sessionId)` (a family `AsyncNotifier`) holds the session and its held rows and sends every decision to the server;
  nothing is tallied on the client. A row decision takes the row and the three counts from `UpdateImportRowResponse`; a destination change takes the
  session the server re-classified; defaults take the session without rows; the commit sends `confirmed_accepted_rows` equal to the **server's last
  `accepted_rows`**, never a client count. A method that fails throws the server's error and leaves the state as it was. The provider has **no automatic
  retry** (`retry: null`): Riverpod's default back-off would keep a 404 or a rule refusal spinning where it should explain.
- **What confirm needs.** The button is enabled only when the session has a destination, every row that would be written has a category of its own or the
  session's default for its sign, and the writable rows held equal the server's `accepted_rows`. When the counts disagree it says so and offers a reload
  (the server would answer 409). Zero accepted rows is a valid confirmation ("Finish without importing", ADR-092).
- **Three groups, one at a time.** To import (accepted), Duplicates (every duplicate, including those the user chose to include), Not readable (rejected),
  chosen with a `ZenSegmentedControl`. A row is edited through `showAdaptivePresentation` (`ImportRowForm`: `ZenSelect` category, `ZenTextField` note up to
  500 characters); only categories that can file the row's direction are offered (`selectableCategories(expense:)`, archived ones excluded) and only fields
  that changed are sent. A duplicate carries a visible **Import anyway** `ZenSwitchRow` that says in words the row will be counted twice if it is the same
  operation (ADR-091). A rejected row shows its row number and its reason and has **no control at all** (the server takes no decision on it). A row whose
  `hint_code` is `transfer.own_account` carries a warning box that the other side must be a plain expense and never a Transfer (ADR-092).
  The rows show the bank's own description and the amount (`formatMinorUnits`, never a `double`), because without them nobody can decide a category; that is
  the only place statement text is shown, and it is the user's own data on their own screen.
- **Failures are sentences, not server text.** `ImportFailure.from` classifies a refusal by the wire `code` of the `ZenError` (`invalid`, `conflict`,
  `not_found`, `unavailable`, `network_error`) and, only when the **whole** message matches the one shape the importer produces
  (`The statement was rejected [at row(s) n, n and k more] (rule.code).`), lifts out the rule code and the row numbers. Everything else in a message is
  discarded, so nothing but a code and numbers can reach the screen or a log. `importRuleMessage` maps 37 rule codes (the contract's, the importer's, the
  duplicate code and the own-transfer hint) to one sentence each in en, uk and pl: what is wrong and what to do. An unknown code gets "rejected (code x.y)" and
  the generic advice. `import_failure_test.dart` reads every `*.java` in `server/.../prudent/imports` (comments dropped) for any string literal shaped like a rule code
  (the server builds codes as an exception's argument, a failure's, a row's, a returned name and a constant, in several files, so no list of files or call patterns is
  kept; `jakarta.`/`java.`/`prudent.` configuration keys are not codes) and fails when the server can emit a code the client has no sentence for, or the reverse.
  There are 37 codes (counted from the list, no repeats; a test holds that); a planted literal in a new file is reported. A 409 or 404 after an action reloads the session and shows a generic localized sentence: the cause may be an expired session,
  and the screen then shows the ended state (expired, discarded, gone) with a way back.
- **The account number.** `AccountNew` and `AccountEdit` have the bank account number `ZenTextField` (ADR-090). `AccountEdit` fills it with the stored number and
  sends what it holds, so leaving it alone keeps it and emptying it clears it. Both forms now `await` their save and, on a refusal, stay open with a localized
  line (409 "another account has this number" and 400 "not an account number" only when the server's fixed message says so, since a 400 can also be a missing name or an
  unknown currency; otherwise "not saved", which is also what a failure that is not a server answer says, and the spinner always ends); until now a refused save closed the form over an error nobody
  saw. The upload page offers only active accounts and, for one without a number, shows a notice with a button that opens `AccountEdit`.
- **Leaving.** Leaving an open import by the page's own Back, the system back or the browser back (`PopScope`) asks and then discards it (a session holds its rows
  for 24 hours and only a few may be open). **A side pane's Close button and Escape, switching to another tab, and a second detail replacing the pane do NOT ask**:
  `ZenDetailPane` calls its owner directly, `ZenDetailScope` is not exported and `ZenPageScaffold` gives no hook for Close, so the page cannot intercept them (a jZen gap to
  report; not worked around, because `onBack` would turn Close into a Back arrow). The session is then simply left open, which is safe: it is listed under
  "Unfinished imports" on the first page, each with Continue and Discard, as one left open by closing the app is, and it is the way out of "too many open imports".
  A test closes the pane with an open session and continues it.
- **Commit and destination.** After any failed commit other than a rule refusal (a lost answer may mean it went through) the session is read again, and the message
  says it may not have been written and was reloaded; a repeat of a commit that did go through answers with the same result (ADR-092), so sending it again is safe. The
  destination field says beforehand that choosing another account checks duplicates again and resets "Import anyway" choices (categories and notes are kept; the server
  resets only the duplicate decisions). Dates are shown in the app's locale, as a record's are.
- **No statement text in a log.** The transport's decode-failure message ends with the decoder's text, which for a JSON body quotes the part it choked on, i.e. statement
  rows, and `LoadErrorView` logs the error it is given. Every import request goes through `unwrapImportResult`, which replaces that message by a fixed sentence and keeps
  the type and code; a test shows the transport's message does quote the body and the import providers' errors do not.
- **An empty preview.** The client previews a fresh session with an empty request: `{}` in JSON, zero bytes in Protobuf. Verified on the server
  (`ImportSessionResourceTest.preview_withAnEmptyRequest_isAcceptedInBothModes`, both content types, 20 of 20 in the class pass); no change was needed.
- **File picking: `file_selector ^1.1.0`** (flutter.dev, federated). Neither the client nor jZen had a picker. It is first party, its iOS and macOS implementations
  ship Swift packages (checked in the pub cache: `file_selector_ios`, `file_selector_macos`), so the runners stay free of CocoaPods (ADR-083). The macOS runner needed
  `com.apple.security.files.user-selected.read-only` in both entitlement files (the app is sandboxed). The picker is reached through `statementPickerProvider`, so tests
  replace it. A file over 5 MiB is refused before it is read, an empty one after, with a localized sentence; a read failure logs only the exception's type, never its text.
  The `pubspec.lock` stanzas for the new packages were taken from a resolution run in a scratch copy (the repository's own `pub get` fails here on the pre-existing SDK mismatch:
  local Flutter 3.50, CI pins 3.44.2, which is not installed on this machine). The first attempt resolved under 3.50 and picked `file_selector_ios` 0.5.3+7 and `file_selector_macos`
  0.9.5+2, which need Flutter 3.47 and Dart 3.13 and so cannot resolve under CI's 3.44.2. The lock therefore pins the newest releases whose own constraints admit 3.44
  (read from their pubspecs): `file_selector_ios` 0.5.3+6 and `file_selector_macos` 0.9.5+1 (both ship `Package.swift`), with `file_selector_android` 0.5.2+11,
  `_linux` 0.9.4+1, `_windows` 0.9.3+6, `_web` 0.9.5, `_platform_interface` 2.7.0 and `cross_file` 0.3.5+5; the lock's `sdks:` line is unchanged. This is an emulation, not a
  resolution under 3.44.2: it has not been run under that SDK. The tracked generated plugin registrants for macOS, Linux and Windows were regenerated by `flutter pub get` in
  that copy and carry only the `file_selector` entries (iOS and Android track none).
- **No framework gap found.** Every control is one `zen_ui_widgets` has: `ZenPageScaffold`, `ZenSelect`, `ZenTextField`, `ZenButton`, `ZenSwitchRow`,
  `ZenSegmentedControl`, `ZenListRow`, `ZenIconButton`, `ZenProgressIndicator`, `showAdaptivePresentation`, `showZenMessage`; the confirmations are `AlertDialog`s with
  `ZenButton`s. `task verify:controls` passes.

### What this supersedes, and why

Nothing earlier. It completes what ADR-091 ("Requirements handed to #74") and ADR-092 ("no client screen sets a row's category, note or inclusion") left to the client, and
it changes `AccountEdit`'s comment that the bank number "has no field yet" (ADR-090): it has one now.

### Consequence

Verified: `import_flow_test.dart` (widget tests over a mock HTTP server that follows the server's rules, including its per-account duplicate classification and a lost network), `import_failure_test.dart`, `import_repository_test.dart`
(routes, bodies, both wire formats, decode failures), `account_forms_test.dart`; the flow is also driven through `showZenDetail` in a real `ZenDetailHost` at 1000 px
(a pane) and 500 px (a push), upload to result; the client suite in a scratch copy without `custom_lint`/`riverpod_lint` (the repository's own
`pub get` fails first on this machine): 479 pass and 2 fail, the two being `prudent_l10n_test.dart` cases that fail identically on HEAD; `task verify:controls`, `task verify:swiftpm`, `task zen:verify:widget-files`. Not verified: a build of the iOS or macOS runner
with the new plugin (so that SwiftPM resolves `file_selector` is established from the packages' own `Package.swift`, not from a build), the native file picker on any
device, an import against the real server and database end to end, and anything on Android, Windows or Linux. The Polish and Ukrainian strings were written without a native
review. Open for #77 (the failure suite): a statement that arrives while the session limit is reached, a very long statement (5000 rows) in the list, a commit refused
at the ledger (`Row N cannot be written`), and two tabs reviewing one session.

---

## ADR-092 — A statement import is committed by one locked transaction that writes ordinary records, answers a repeat with the same result, and invents no transfer leg

**Date:** 2026-11-14. **Status:** accepted. jlogicsoftware/prudent#76, sixth task of the epic jlogicsoftware/prudent#41.

### Decision

- **`LedgerImportCommitter`** replaces the 503 default (`UnavailableImportCommitter` is deleted; the committer is not format specific).
  `ImportWorkflow.commit` locks the session, then the destination account's row (`SELECT ... FOR UPDATE`, `AccountEntity.findOwnedForUpdate`)
  **before** re-checking the destination, so what is checked is what is written to. The committer then refuses a session in which a
  writable row has neither a category of its own nor the session's default for its direction (409, a count and no text), re-reads `RecordEntity.importedKeys` under the lock, counts a row whose key is held
  as `alreadyImported`, and writes every other row through `RecordWriter.apply` (the same ownership, currency, category-kind and archived
  checks as a typed record), copying `fingerprint`/`occurrence` onto `import_fingerprint`/`import_occurrence`. The lock order is always session,
  then account, so two commits cannot deadlock. Records an import writes differ from typed ones **only by those two key columns**: nothing else
  was needed, because a record's title is the row's description, its payee the counterparty, its note the user's.
- **Atomic.** Nothing in the committer opens a transaction; a refused row (409 `Row N cannot be written: ...`, no statement text) or any
  exception rolls back every record written for the session, and the session stays PREVIEWED with its rows. Tested by injecting a failure at
  row 1, 2 and 3 of three (and by archiving the third row's category after it was chosen), and by a later commit succeeding.
- **Idempotent.** The session keeps `committed_written` and `committed_already_imported` (migration V20261114120000, set exactly when
  COMMITTED, paired, non-negative; on the wire `ImportSession.committed_written` / `committed_already_imported`). A commit of a COMMITTED
  session with the same `confirmed_accepted_rows` answers with the stored result (200, nothing written); a different number is a 409; a
  DISCARDED or EXPIRED session stays refused. Two sessions of one file (two tabs) write it once: the second reports `alreadyImported`. The
  unique index stays as the backstop.
- **Per-row decisions** (`POST /api/v1/import-sessions/{id}/rows/{rowNumber}`, `UpdateImportRowRequest`, columns `category_id`, `note`,
  `include_duplicate` on `prudent_import_row`). The verb is POST on purpose, a deliberate exception: the call is a partial update, `PUT` in
  this API means full replacement, and the repository has no `PATCH`. A category is needed because an ordinary record always has one and nothing in a statement
  names one; it is validated when set (the caller's, active, right direction) and again at commit. A note is at most 500 characters like every other note
  in the schema (400 beyond, and a CHECK). The answer is the light `UpdateImportRowResponse` (the changed row and the session's three counts),
  not the whole session: the first design returned the session with every row, so deciding n rows moved O(n²) data (5000 rows took about a minute).
  Only the one row is read, and the counts are recomputed only when the inclusion decision changed. `GET /api/v1/import-sessions/{id}` stays the full view. `include_duplicate` is the server side of
  ADR-091's override: only a DUPLICATE row may carry it (400 otherwise; a rejected row takes no decision, 409), such a row is counted in
  `accepted_rows` (what the commit confirms) and not in `duplicate_rows`, it is written under the **next free occurrence** of its fingerprint
  (`max + 1` over what the account holds plus what this commit just wrote, under the account lock), and a new preview clears the decision
  because the row's status is recomputed. Two sessions that each force the same row both write it: that is the user's explicit choice twice.
  Note and category are personal data held only with the row and deleted with it; the data export carries them like the other row fields.
- **Session defaults** (`POST /api/v1/import-sessions/{id}/defaults`, `SetImportDefaultsRequest`; `ImportSession.default_expense_category_id` /
  `default_income_category_id`, columns on `prudent_import_session`). Choosing a category for every row of a long statement is not a usable
  flow, so a session carries one default per direction; a row with no category of its own is written under the default for the sign of
  its amount, and a row's own category wins. Each default is validated when set exactly like a row's category (the caller's, active, able to
  file that direction; an empty string clears it) and again when written at commit (a category archived in between refuses the commit, 409, and
  nothing is written). Defaults are plain columns with no foreign key, a CHECK keeps them null once the session is not PARSED or PREVIEWED, and
  the workflow clears them when the session ends. The answer is the session without its rows.
- **Zero accepted rows is a valid commit.** A statement imported in full has only duplicates, and refusing its commit forced a discard. A
  PREVIEWED session may be committed with `confirmed_accepted_rows = 0`: it completes as COMMITTED with `committed_written = 0` and
  `committed_already_imported = 0`, and a repeat answers the same. (A statement with no rows at all is still refused at parse; a statement of
  only rejected rows can likewise be committed, which writes nothing and ends the session.)
- **Own-account transfers: imported as a plain record of the destination only; no leg is created in the other account.** Double-counting
  analysis (corrected: an earlier version of this entry claimed the approach "never double counts", which holds only if the other side is
  recorded as a plain expense): (a) creating a Prudent transfer would write an outgoing leg into an account whose statement the user has not imported. That
  leg could not carry a key (the other statement's wording of the outgoing row is unseen, so its fingerprint cannot be computed), so the day
  the other account's outgoing rows become importable, or the user types the transfer by hand, the money leaves that account twice. It
  would also change a second account the user did not choose. (b) A plain record gives the destination the right balance and never doubles
  anything; the cost is that the source account's balance falls only when its own outflow is recorded, and that analytics counts the
  incoming amount as income unless the user files it under a category that says otherwise. Today an outgoing own transfer is rejected by the
  parser (`amount.sign_unexpected`), so nothing can be imported twice; the user records the outflow by hand. Pairing is future work that
  needs the outgoing wording (an open question of `docs/erste-csv-contract.md`).
  **The user must record the other side as a plain expense in the source account, never as a Prudent Transfer:** the Transfer feature creates both
  legs, so using it for the same money would credit the destination a second time. Analytics counts the imported incoming amount as income of the
  destination (a plain expense on the source side is counted as spending), so both show unless the user files them under categories the
  analytics leaves out. To let a client warn, the importer puts a stable code on the row, `ImportRow.hint_code = transfer.own_account`
  (`ParsedRow.HINT_OWN_ACCOUNT_TRANSFER`, column `hint_code`, a rule-shaped code, never on a rejected row), set at parse. Tested: the incoming row writes one record, the other
  account has none and its balance is unchanged; an outgoing row stays rejected.
- **Titles are the bank's raw description.** A record's title is the statement row's description (its payee the counterparty), so it is noisy:
  a card mask and the amount appear in it. That is a #74 user-experience point (shorten or let the user edit before commit), not changed here.
- **Privacy.** The statement is still read once and dropped. After a commit no import row remains, the identity token is cleared, the response
  and every error carry counts and rule codes only (asserted on the raw body), and the key columns were already covered by ADR-091's log filter.
  The policy changed (`docs/privacy-policy.md`): the staging description now lists the category and note a user gives a row and the session's
  default categories, says they are held no longer than the session's 24 hours, and lists the committed counts on the session record. An earlier
  version of this entry said the policy was unchanged, which was wrong.

### Limitations

- Not run against a deployed service; no client screen sets a row's category, note or inclusion (jlogicsoftware/prudent#74), so until
  then only the API can commit an import.
- Every written row still needs a category, but a session default covers it; there is no automatic guess from the statement.
- Rows are written one at a time (up to 5000), inside one transaction.

### Consequence

Verified: `ImportCommitTest` (tests: records written, keys, the missing-category refusal, failure at each of three rows, the HTTP 500,
repeat commit, discarded session, two sessions of one file, a race of six sessions of one file and of one session committed twice from real
threads, own transfers, duplicate overrides, privacy), `ImportCommitSchemaTest`, and the existing import suites adapted to substitute
`LedgerImportCommitter`; the duplicate-detection suite (ADR-091) now runs through the real committer and defaults, not a hand-written double.
The committer still takes the account's row lock although the workflow does too: the `ImportCommitter` contract asks every implementation to
serialise on the account, and the second `SELECT ... FOR UPDATE` in one transaction is free. A one-off local run over the real export is recorded in the task report as counts only.

---

## ADR-091 — A statement row is recognised by a versioned fingerprint plus an occurrence number, kept on the ledger record under a unique index; the bank's sequence number is not an identifier

**Date:** 2026-11-14. **Status:** accepted. jlogicsoftware/prudent#75, fifth task of the epic jlogicsoftware/prudent#41 (done before #76 and #74, because the preview shows duplicates and the commit must store what detection needs).

### Decision

- **The key of a row is `(fingerprint, occurrence)`** (`RowKey`, computed by the pure `RowFingerprints`). The fingerprint is
  `v1:` and the SHA-256 (64 lower-case hex) of: a scheme tag, the destination account's id, the format id, the statement's
  currency, the transaction date, the signed amount in minor units, and the description, counterparty and counterparty account
  after `normalise` (Unicode NFC, any white space run one space, trimmed, upper-cased in the root locale, null is empty). Each
  field is written with its length, so shifting text between fields changes the input.
- **Deliberately excluded:** the bank's sequence number and the row's position (the contract says it looks like a rank from the
  newest row of one export, so a later export that adds newer rows can renumber older ones), the booking date (not monotonic, can
  be later than the export date, whether it can still change is unknown), and the balance (does not chain; not even read). The BLIK
  `ref:` number stays inside the description and so is part of the fingerprint, which is why two BLIK payments for one amount to one
  merchant on one day differ even before the occurrence number. `normalise` finishes with a second NFC pass so it is idempotent for code points that recompose when upper-cased. Punctuation, letters and word order are **not** normalised away:
  each such fold would also merge two genuinely different operations.
- **The sequence number is a hint only, as ADR-088/090 said.** The switch is `StatementImporter.stableExternalId()`
  (default false; Erste's stays false). A format returning true is keyed by `RowFingerprints.stableIdKey` (`e1:` prefix, occurrence
  1, account-scoped) and its rows must then carry `externalId`. Flipping it needs a second export of the same account whose overlap
  shows the same operation keeping the same identifier, and an ADR that says so. Records imported earlier keep their `v1` key and
  are not re-keyed, so the first overlapping import after a flip would offer them again; the ADR that flips it must say how that is
  handled. `TestStableIdImporter` proves the switch works; nothing proves any real format deserves it.
- **Occurrence numbers keep genuine repeats.** The n-th row of one statement with a given fingerprint gets occurrence n, over all
  its non-rejected rows in statement order (rows another stage already marked keep their slot). Rows with one fingerprint are
  interchangeable, so only how many there are matters, not which is called 1. A row is a duplicate exactly when a ledger record of
  the destination account already holds its `(fingerprint, occurrence)`. Hard cases, all tested: the same file twice (everything is a
  duplicate, nothing is written); a later export with newer rows, other sequence numbers, other positions and a moved booking date
  (exactly the new rows); an overlap that cuts through identical rows (the older file ends with 2 of 3, the newer has 3: one new);
  the same file in another row order (same keys); an amount, date or description that differs (another row).
- **Digest, and what that does not buy.** A key goes into a ledger column nothing displays, so it is a digest rather than statement
  text again. It is **not secret**: the input is a date, an amount and a short string, so anyone who can read the table can test
  guesses (the account id only stops one table of precomputed digests serving every account). It is stored as personal data on rows
  that already carry `user_id` (RLS, the eraser, the account delete cover it), is never on the wire (`ImportRow` gains only
  `duplicate_code`, field 12, a code such as `duplicate.already_imported`), is kept out of the logs (see Limitations), and is not in the data export: it is derived
  from fields the export already carries, and it is not something the person can read.
- **Persistence** (V20261114110000): `prudent_import_row.fingerprint`, `occurrence`, `duplicate_code` (CHECKs: shape, paired,
  occurrence positive, no key on a rejected row, a code only on a DUPLICATE row) and `prudent_record.import_fingerprint`,
  `import_occurrence` (CHECKs: shape, paired, positive). **`prudent_record_import_key_unique` is UNIQUE** over
  `(account_id, import_fingerprint, import_occurrence)` where the fingerprint is not null, not a plain index. The preview is advice;
  two commits of overlapping sessions can both pass it (two tabs, a retry after a timeout), and only a unique index makes the second
  writer fail rather than double the ledger; it is the backstop, and #76's idempotence comes from the lock and re-read below. Deleting an imported record frees its key, so
  importing the statement again brings that row back; a record the user typed by hand carries no key and is never matched.
- **`ImportDuplicateStage`** (an `ImportPreviewStage`) clears every key, stops if the session has no destination account, keys every
  non-rejected row, then marks each still-ACCEPTED row whose key a record of `session.accountId` holds as `DUPLICATE` with code
  `duplicate.already_imported`. The workflow's existing reset (DUPLICATE to ACCEPTED before stages run) now also clears the code, so a
  repeated preview for another account starts clean, and the key is recomputed because the account is part of the digest.
  `RecordEntity.importedKeys` is one chunked query over the fingerprints the statement carries.

### What #76 must do with it

Copy `row.fingerprint` and `row.occurrence` of each accepted row onto the `RecordEntity` it writes (`importFingerprint`,
`importOccurrence`) and refuse a row whose key is null (a PREVIEWED session always has them when it has a destination, which commit
requires). **Idempotence is #76's job and a unique-index violation is not the way to say "already imported"**: the workflow runs
the committer inside one `@Transactional`, a failed `INSERT` or flush aborts the Postgres transaction, and it cannot be caught and
continued. #76 must instead **lock the destination account's row** (`SELECT ... FOR UPDATE`; chosen over a pg advisory lock because it
needs no invented lock key, is scoped to exactly the resource being written, is released with the workflow's transaction and is
covered by the same row-level security as the data), then re-run `RecordEntity.importedKeys` for the accepted rows' fingerprints and
write only those whose key is still absent. `INSERT ... ON CONFLICT DO NOTHING` on the unique index is the acceptable alternative; either
way the index stays as the backstop that makes a bug a refused write, not a doubled ledger. **The seam now says so**: `ImportCommitter.commit`
returns a `CommitResult(written, alreadyImported)`, the two must sum to the accepted rows it was given (the workflow rolls back
otherwise), and `UnavailableImportCommitter` still refuses. The test committer in `ImportDuplicateDetectionTest` does exactly the lock,
re-read and write, and the test of two sessions of one file previewed before either commits proves the second writes nothing. What
that proves is the algorithm and the seam, sequentially; it is not a concurrent race, and the real committer is #76's. The committed
rows' keys live on the records, not on the import rows, which are deleted.

### Requirements handed to #74 (the review screen)

**A row marked DUPLICATE can be a genuinely new operation, and the user must be able to say so.** Nothing in this ADR's server work
provides that; #74 must give the user a per-row way to include a DUPLICATE-marked row in the commit, and the server must then accept
it. The seam for it is not built, deliberately: it needs an `include_duplicate` decision on the row (proto, entity, migration),
the committer writing that row with the **next free occurrence** of its fingerprint in the account (`max(import_occurrence) + 1` over
the account's records with that fingerprint, computed under the same account lock, because the unique index forbids a second record with
the key the row would otherwise carry), and tests for it, none of which could be half-built here. Until #74 ships it, a wrongly marked
row cannot be imported from a statement; it can be entered by hand.

### Limitations, stated rather than implied

- **LOSS mode: a new row can be silently marked DUPLICATE.** The booking date is not part of the key and a card row carries no unique
  reference. Two exports that do not overlap by transaction date, for example adjacent exports cut by booking date, can therefore hold a
  genuinely new row with the same transaction date, signed amount and text as an already imported row that was booked on another day; it
  gets the same fingerprint and, being the only such row in its file, occurrence 1, so it is marked DUPLICATE and is not offered.
  Nothing tells the user. `ImportDuplicateDetectionTest` pins this behaviour. Whether the bank's range is by transaction date or by
  booking date is **not known**; the contract's open questions now ask for a second export to settle it. This is an accepted risk of
  fingerprinting without a bank identifier, and the remedy is the per-row override above.
- **A row pending in one export and booked in the next** is unknown: if its description or date changes it is a different
  fingerprint and is imported again; if only its booking date changes it is the same row. The contract has no example either way.
- **A description the bank rewrites between exports** has the same effect. The only remedy is deleting the extra record.
- **Overlap is judged by counts.** If an export drops one of three identical rows (a pending one disappearing) and the record is
  already in the ledger, nothing notices. Detection never deletes.
- **A record the user entered by hand for the same bank transaction is not a duplicate** of the statement row.
- **One account is checked, not the ledger.** The same statement imported into another account of the user (possible only for a format
  whose identity check allows it) is not a duplicate there, by design: the account is part of the key.
- **The digest scopes to the account's id, not its stored number.** The number can be cleared, changed or moved to another account,
  and a key that followed it would change meaning under records already written. The id is permanent, and the key only has to answer
  "is this row already in this account's records", a question that has no meaning outside that account. The consequence: clearing the
  number on account A and setting it on a new account A2 makes a re-import into A2 offer every row again, because A2 holds none.
- **Editing and moving an imported record.** Editing its date, amount, text, category or note keeps the key on purpose: the key names
  the statement row the record came from, not the record's current content, so correcting a typo does not make the next overlapping
  import offer the row again. **Moving the record to another account clears the key** (`RecordWriter`), because the key means "this
  row is in this account": left in place it would keep the old account's slot occupied for a record no longer there, and a second such
  move could collide on the unique index. Tested in `RecordImportKeyTest`. After a move, re-importing offers the row into the old account
  again, which is correct.
- **The key is kept out of the server's logs by a filter.** Postgres puts the offending values in a unique-violation message, and
  Hibernate (`org.hibernate.orm.jdbc.error`) and Narayana (`ARJUNA012125`, with the cause chain) both log it; a first test run showed
  the digest in those lines. `StatementKeyLogFilter` (a Quarkus `@LoggingFilter`, wired by `quarkus.log.console.filter`) drops exactly
  the records whose message, parameters or causes name the `import_fingerprint` column, rather than silencing a logger, so other
  database and transaction warnings stay. The failure still reaches the caller, and `UnhandledExceptionMapper` logs one line without
  the message. `ImportKeyLoggingTest` proves the violation is still refused, that the filter drops each shape the key arrives in and
  keeps unrelated records, and that the config names it; it does **not** run a log line through the live console handler, so that last
  hop is Quarkus's contract, not something proven here. A log shipped by any handler other than the console (none is configured)
  would need the same filter property.
- **The stable-identifier path refuses a file that cannot be keyed.** For a format that declares `stableExternalId()`, a non-rejected row
  with no identifier is the rule `identifier.missing` and two with one identifier are `identifier.duplicate` (400, row number, no text;
  `ParsedStatements.validate`), because both rows would otherwise take occurrence 1 and collide at commit.
- **Not run against a second real export**; the scheme was checked on one real export, counts only (below), and on synthetic overlaps.

### Limitations, stated rather than implied

- **A row pending in one export and booked in the next** is unknown: if its description or date changes it is a different
  fingerprint and is imported again; if only its booking date changes it is the same row. The contract has no example either way.
- **A description the bank rewrites between exports** has the same effect. The only remedy is deleting the extra record.
- **Overlap is judged by counts.** If an export drops one of three identical rows (a pending one disappearing) and the record is
  already in the ledger, nothing notices. Detection never deletes.
- **A record the user entered by hand for the same bank transaction is not a duplicate** of the statement row.
- **One account is checked, not the ledger.** The same statement imported into another account of the user (possible only for a format
  whose identity check allows it) is not a duplicate there, by design: the account is part of the key.
- **Not run against a second real export**; the scheme was checked on one real export, counts only (below), and on synthetic overlaps.

### What this supersedes, and why

Nothing earlier. It uses ADR-089's `ImportPreviewStage` and `RowStatus.DUPLICATE` as designed and ADR-088/090's decision to treat the
sequence number as a hint. `docs/erste-csv-contract.md` found no mistake; one open question was added to it (whether the bank's range is by transaction or booking date).

### Consequence

Verified: `RowFingerprintsTest` (scheme properties, normalisation, boundaries, occurrences, the cut-through-identical-rows overlap),
`ImportDuplicateDetectionTest` (the same statement twice, repeats not collapsed, overlap with other sequence numbers and positions, the
cut group, changed fields, a deleted record, a hand-typed record, no account, wire without keys, rejected rows, a repeated preview for
another account and back, the stable-identifier switch) with a test-only committer that copies the key, and `ImportFingerprintSchemaTest`
(the unique index and every CHECK by name). Run once, locally, counts only, over one real export: 39 rows, 39 distinct fingerprints
(so no identical-looking rows in it, and the repeated-row path is proven on synthetic rows only), a second import yields 0 new rows, and
for every cut of the file into an older part and a whole one exactly the rows outside the older part are new. Not verified: any
deployed run, a second real export, and concurrent commits hitting the unique index (#76).

---

## ADR-090 — The Erste importer validates the whole file against the contract before returning a row, identifies the account by a stored number and refuses an account without one

**Date:** 2026-11-14. **Status:** accepted. jlogicsoftware/prudent#73, third task of the epic jlogicsoftware/prudent#41.

### Decision

- **`ErsteStatementImporter`** (`prudent.imports`, an `@ApplicationScoped` bean returning `ImportFormatIds.ERSTE_PL_CSV`) reads one
  export per `docs/erste-csv-contract.md`, with `ErsteCsv` for the byte and delimiter layer. Bytes are decoded strictly as UTF-8;
  a BOM (`encoding.bom`, UTF-8 or UTF-16), a NUL byte (`encoding.nul_byte`), invalid UTF-8 (`encoding.not_utf8`), any CR
  (`layout.line_ending`, so CRLF) and a missing final LF (`layout.no_final_newline`) are refused, not repaired. Comma is the only
  delimiter (`layout.delimiter` when row 1 is one field containing `;` or a tab), quoting is RFC 4180 on one line
  (`csv.malformed`), a header row is `layout.header_row` and a first row that is a transaction is `layout.summary_missing`. Every
  row has nine fields with an empty ninth (`row.field_count`, `row.trailing_field`).
- **The summary row** needs an ISO export date (`summary.export_date_invalid`), a `DD-MM-YYYY` period start
  (`summary.period_start_invalid`), an account that starts with `'` and has a number's shape (`summary.account_invalid`) and the currency `PLN` (`currency.unsupported`: one currency per statement, taken only from here).
  The holder, fields 6 to 8, the balance column and the period start are never read or shape-checked: the contract says they do
  not chain or are not understood, personal data has no use here, and no row is checked against the period.
- **Whole-file rules, found before any row is returned**: `date.invalid` (a real `DD-MM-YYYY` day),
  `date.booking_before_transaction`, `date.out_of_range` (before 2000-01-01 or after today plus one year, today read from an injectable `Clock`, in UTC; rows only),
  `amount.invalid` (`-?`, 1 to 11 digits with no separator and no leading zero except a single `0`, a comma, exactly two decimals;
  Long arithmetic, no floating point), `amount.zero`, `sequence.invalid`, `sequence.duplicate`, `card.foreign_currency` (a card payment whose embedded currency is not the file's) and `statement.empty`. A
  failure in the layout or summary is thrown at once; row failures are collected over the whole file and thrown as the rule of the
  first failing row, naming up to 10 rows that broke it and how many did in all. **Row numbers count transaction rows**, the
  summary row is not row 1, as `ParsedRow.rowNumber` does. `ImportRejectedException` gained a second constructor, `rowNumbers()` and
  `totalRows()` for this; the single-row message is unchanged and nothing else in ADR-089 moved.
- **A row with no known meaning is returned rejected, not dropped and not a whole-file failure** (the contract's per-row clause):
  `description.unknown_shape` (including a card payment with a counterparty), `card.amount_mismatch` (embedded amount versus the
  column), `amount.sign_unexpected` (a card or BLIK entry that is positive, an own-account transfer that is negative: the wording of an
  outgoing one is unknown), `counterparty_account.invalid` (two digits then six groups of four) and `transfer.same_account`. A
  rejected row carries no text. The three shapes are card payment, BLIK purchase and own-account transfer; every other operation type
  lands in `description.unknown_shape`.
- **An own-account transfer is a row, not a pair, and carries no `kind` column.** It is recognised by its description,
  `ErsteStatementImporter.OWN_TRANSFER_DESCRIPTION`, kept verbatim and tested with `isOwnAccountTransfer`; its `counterpartyAccount` is
  the user's other account in `AccountNumbers`' normal form and its `counterparty` is empty, because that field held the holder's own
  name and address, which nothing here needs. #76 can find the other leg with `AccountEntity.findOwnedByNumber` and decide whether
  to book a transfer; #75 sees an ordinary positive row. Adding a column and a wire field for a kind that is one string today
  was not needed to finish #73, and is open to #75/#76 if they want it.
- **The bank's sequence number is `externalId`, as a hint only.** The contract does not know whether it survives a second export that
  adds newer rows. #75 must not use it as a duplicate key unless an overlapping export proves it stable. The BLIK reference
  (`ref:` and 11 digits) stays inside the description for #75 to consider.
- **Account identity: `Account.account_number`** (proto field 12 and the create and update requests, `prudent_account.account_number`,
  V20261114100000). It is optional and `AccountNumbers.normalize` fixes one form: whitespace removed, upper-cased, a leading `PL`
  dropped from a 26-digit number, then 10 to 34 letters and digits (a shape, not an IBAN checksum, because the fixtures use check
  digits `00`). Blank stores none; a malformed number is 400 and one another of the user's accounts already holds is 409 (and a unique
  index per user backs it up); a PUT is a full replacement, so a form that does not edit it must resend it, which `AccountEdit` now
  does. It is personal data on a row that already carries `user_id`, so the export (it rides on `Account`) and the eraser (it goes
  with the account) cover it and `PrivacyExportTest` checks it. Neither the number nor the digest is ever in an error or a log.
- **`checkDestination`** compares `ParsedStatement.identityOf(stored number)` with the statement's token, and fails closed: an account
  with no number is `account.number_missing` (add the number first), a different one is `account.identity_mismatch`, a statement
  without a token is `account.identity_unverifiable`. The workflow's calls (parse, preview, repeated preview, commit) are unchanged.

- **Amendments to `docs/erste-csv-contract.md` made with this review** (the facts it describes are unchanged): (1) amounts of 1000
  or more are accepted when digit-only; `amount.unsupported_magnitude` and `balance.invalid` are gone, a separator is
  `amount.invalid`, and an open question asks for a private export with such an amount; (2) `order.not_newest_first` is gone, and
  the row-order line says a file is not rejected for its order; (3) the validation list now names every rule the code applies, and
  the foreign-currency card payment is stated as a whole-file rejection (the contract had said both "flag" and "reject"); (4)
  `date.out_of_range` and the leading-zero rule are added. Each kept uncontracted rule, in one line: `layout.no_final_newline`
  kept (a truncated file would silently lose its tail), `layout.summary_missing` kept (without it a transaction row would be read as
  the summary), `row.field_count` on the summary row kept (the contract's "any row"), `csv.malformed` kept (a line that cannot be
  split cannot be read), `card.foreign_currency` kept as whole-file (the amount column's currency is not observed), `amount.sign_unexpected`
  and `transfer.same_account` kept per row (an unobserved sign, or a transfer from an account to itself, is not safe to book).
  Dropped as speculative: `summary.holder_missing`, `summary.field_shape`, `balance.invalid`, `amount.unsupported_magnitude`,
  `order.not_newest_first`.
- **One normal form, one place.** `AccountNumbers` is the only definition: white space is Unicode white space (`(?U)\s`, so a
  no-break U+00A0 or narrow U+202F space pasted from a bank page is removed), upper-casing uses `Locale.ROOT`, and
  `ParsedStatement.identityOf` delegates to `AccountNumbers.identityOf` instead of normalising a second way (the `imports` package
  already depends on `account`, so the direction is unchanged). A blank number is one that is only white space of any kind.
- **Unique-number clashes are a 409 even under a race.** The resource flushes the number inside the request and maps a SQLSTATE
  23505 to the same 409 as the pre-check; only the mapping is tested (`isUniqueViolation`), the race itself is not reproduced. An
  archived account keeps its number, and the number stays unavailable to the user's other accounts until it is cleared or changed.
- **Known hazard: PUT is a full replacement.** An older client build, or a client holding a stale cached account list, that PUTs an
  account without `account_number` deletes the stored number, and the next import then fails closed with `account.number_missing`.
  `AccountEdit` resends it (tested in `account_forms_test.dart`); nothing on the server can tell "absent" from "cleared".
- **Privacy:** `docs/privacy-policy.md` lists the number (plaintext, same user scope, in the export, deleted with the account and
  by erasure).

### What this supersedes, and why

ADR-089's statement that `Account` has no number field and that only a test importer implements the hook. Nothing else is
replaced. The decisions that follow the contract's `Open questions` are unchanged.

### Consequence

Verified: `ErsteStatementImporterTest` (every rule above at least once, the three fixtures, destination checks, reporting),
`ErsteImportSessionTest` (parse through `POST /api/v1/import-sessions` with `erste-pl-csv`, a wrong or number-less destination at
parse and at preview, a number removed after parse, a rejected statement writing no session and no row), `AccountNumberTest`
(normalisation, resource and schema), `PrivacyExportTest`, the Dart wire round trip, and the importer run once, locally and
reading counts only, over one real export (it parsed with no row flagged). Not verified: any deployed run; the broad malformed,
drift and mixed-currency suite (#77); amounts written with separators, CRLF and every operation type the contract lists
as unseen, which are refused, not handled.
Open: **how a real amount of 1000 or more is written** (digit-only is read, a separator is `amount.invalid`; a private export with
such an amount must be checked); **nothing in the client sets an account number**, so no import can run until the
account form has a field (the one-line carry-through in `AccountEdit` only stops an edit from deleting a stored number); #75 decides
duplicates from the fields above.

---

## ADR-089 — Statement imports are sessions with three enforced phases behind an importer boundary; only normalised rows are kept, never the uploaded file

**Date:** 2026-11-14. **Status:** accepted. jlogicsoftware/prudent#72, second task of the epic jlogicsoftware/prudent#41.

### Decision

- **The importer boundary.** `prudent.imports.StatementImporter` is one bank format: `formatId()` and a pure
  `parse(bytes, ImportContext)` returning a `ParsedStatement` (one currency, normalised `ParsedRow`s). Importers are
  `@ApplicationScoped` beans and `ImportFormats` indexes them by id; two importers claiming one id, or an id that is
  not a plain identifier, fail the boot. An unknown id is a 400 `ZenError` that lists the supported ids and does
  not echo the request's. **The Erste importer does not exist yet** (jlogicsoftware/prudent#73): `ImportFormatIds.ERSTE_PL_CSV` is its registration seam,
  and until a bean returns that id the format is refused like any unknown one. An importer rejects a whole statement
  with `ImportRejectedException`, whose message is built from a rule code (`date.invalid`) and a row number and nothing
  else, so no statement text reaches an error body or a log. A variant outside a format's contract is rejected, not
  adapted (ADR-088); the workflow's own checks (`ParsedStatements`) only add to an importer's, never relax them, so
  a format cannot weaken another's validation by sharing the workflow.
- **Three phases, three requests, enforced by the server** (`ImportWorkflow`, over `ImportState`):
  `PARSED -> PREVIEWED -> COMMITTED`, with `DISCARDED` and `EXPIRED` reachable from either open state, all three
  ends terminal, and one edge onto itself, `PREVIEWED -> PREVIEWED` (below). A session exists only after a parse that succeeded (importer first, writes after, one transaction), so a
  rejected statement, an unknown format or an importer failure writes no session, no row and no ledger record.
  `POST /api/v1/import-sessions` parses; `.../{id}/preview` needs PARSED or PREVIEWED, validates the destination account, runs every
  `ImportPreviewStage` bean and fixes the account; `.../{id}/commit` needs PREVIEWED, a destination account, and a body repeating how many
  rows were accepted, refused (409) when that differs, so a commit confirms what was reviewed. Every phase change locks
  the session row, and another user's session is a 404. A read takes the same lock, so it never sees a PREVIEWED
  session without its rows while a commit is in flight, and expires an overdue session itself.
- **A preview can be repeated.** Bytes are never kept, so a user who sees the preview and then chooses a different
  destination account would otherwise have to upload again. `PREVIEWED -> PREVIEWED` re-validates the destination and
  re-runs the stages; the workflow first sets every `DUPLICATE` row back to `ACCEPTED`, so a stage's result never
  carries over from a preview for another account.
- **The destination account is validated wherever it is set or replaced, and again at commit.** It must be the caller's,
  active (stricter than `RecordWriter`, which does not look at `is_active`: staging money into an account kept only for
  its history is refused), and hold the session's currency (`AccountEntity.holds`, the rule `RecordWriter`,
  `TransferResource` and `CorrectionResource` share); a failure is a 400 when the account came in a request and a 409
  at commit. **The statement's own account is checked by a hook, not at parse.** `ParsedStatement` still carries no
  account number, but it carries an opaque identity token (`ParsedStatement.identityOf`: whitespace removed, upper-cased,
  SHA-256, 64 hex characters; `null` for a format with no identity). The session keeps it (`statement_identity`), and
  `StatementImporter.checkDestination(token, account)` runs on every assignment (parse, preview, repeated preview) and at
  commit, rejecting with a rule code (`account.identity_mismatch`) that never echoes statement text. Without the hook, a
  statement parsed into account A could be previewed into B and committed unchecked, because the importer only sees the
  statement at parse. **What the hook can and cannot do today:** `Account` has no account-number field, so the default
  implementation has nothing to compare with; it accepts a statement with no identity and rejects one that has an
  identity with `account.identity_unverifiable` (fail closed) rather than pass it. jlogicsoftware/prudent#73 adds the
  field and the Erste implementation; until then only a test importer implements it, and the suite uses the account's name
  as its stand-in for a number. The token is a digest, not encryption (an unsalted digest of a short structured number can
  be guessed), so it is personal data: kept only while the session is open, cleared when it ends, never sent over the wire,
  never logged, and not part of the data export.
- **Bounds.** A statement is at most 5 MiB, `prudent.import.max-rows` transaction rows (default 5000) and, per text
  field, 1024 characters; exceeding either is a 400 naming the limit or a rule code and row number, never content. A user
  has at most `prudent.import.max-open-sessions` (default 10) open sessions that have not yet run out of time; one more is
  a 409 (the check precedes the parse, so requests racing each other can overshoot by the number in flight). The list
  route returns the newest `limit` sessions (default 50, at most 100; the data export is the unbounded view).
- **Storage and privacy: the statement is read once and dropped.** Two tables, `prudent_import_session` and
  `prudent_import_row` (V20261114090000, RLS enabled and `zen_runtime` policies added in the same change), have no
  binary column and nothing a workflow method is handed the bytes for. A row holds the importer's normalised fields (dates,
  a signed minor-unit amount, description, counterparty, counterparty account, the bank's entry id, a status
  `ACCEPTED`/`DUPLICATE`/`REJECTED` and, for rejected rows only, a rule code). **Personal data lives only in rows, and rows live only while the
  session is PARSED or PREVIEWED:** committing, discarding and expiring a session delete its rows in the same transaction
  and keep the session row with its three counts (and, for the rows, the identity token is cleared). Holder name and the statement's own account number are compared by
  the importer and never part of `ParsedStatement`. `account_id` is a plain column with no foreign key, so an account delete
  (ADR-081) is not blocked by staging data; commit re-checks it.
- **Retention.** A session expires `prudent.import.session-ttl` after creation (default 24 hours). A read of an overdue session
  expires it, preview and commit refuse it (409), and `ImportSessionExpiryJob` (a `ZenJob`, interval one hour, run when the
  external scheduler triggers `/api/v1/jobs/trigger`) calls `ImportWorkflow.expireDue()`. So the bound on how long rows
  survive is the time-to-live plus however late the sweep runs (an hour with the scheduler as configured), and a read ends an
  overdue session at once; the privacy policy says this and not "24 hours at the latest". The short session record (state,
  counts, format, account id, timestamps) stays until the person's data is erased. Both tables carry `user_id`, so `PrudentDataEraser` deletes them (rows first, no cascade, ADR-010), the
  data export carries `import_sessions` and `import_rows` (`DataExport` fields 14 and 15, the rows naming their session), and
  `PrivacyCoverageTest` covers both tables.
- **The extension points the next tasks fill, without reshaping this one.** #73: an `StatementImporter` bean for
  `erste-pl-csv`. #75: an `ImportPreviewStage` that marks rows `DUPLICATE` (the status, its wire value and its CHECK
  value already exist; a stage may move a row between ACCEPTED and DUPLICATE and nothing else, which the workflow
  checks). #76: an `ImportCommitter` bean; `UnavailableImportCommitter` is the `@DefaultBean` until then and answers 503
  `unavailable` with the session left PREVIEWED, so no import can claim to have worked. The committer runs inside the
  transaction that marks the session COMMITTED, so its failure leaves the session PREVIEWED and its rows in place.
  #76 also decides whether a repeated commit becomes an idempotent success (today it is a 409 from the state graph).
  #74: the screens, plus a per-row edit route and `category_id` / `note` columns when it needs them.

### What this supersedes, and why

Nothing earlier. It builds on ADR-088 (the contract the Erste importer validates against) and on the backlog line
"discard the uploaded statement after parsing by default": discarding is not a default that can be switched off here, it is the shape, because
there is nowhere to put the bytes.

### Consequence

Verified: the new suites in `server/src/test/java/prudent/imports/` (state graph, registry, the resource end to end in JSON and
protobuf, the sweep, ownership between two users, destination checks on every assignment path and at commit, bounds, two
commits / commit against discard / sweep against read driven concurrently, and the expiry job's discovery and boot registration), `ImportSessionSchemaTest` (constraints by name), `PrivacyCoverageTest`,
`PrivacyExportTest`, `PrivacyErasureTest`, `PrudentRowLevelSecurityTest` and `HibernateSchemaValidationTest`, and the whole backend
suite (`task test:server`, 850 tests, 0 failures, PMD included); `task verify:reflection` and `task verify:import-fixtures`. `task generate` was run and
produced the Dart messages and the admin schema; `verify:contracts` discovers protos with `git ls-files`, so it passes only once `imports.proto` and
the generated `imports.*.dart` files are tracked. Not verified: any real importer (none exists), the committer (none exists), the Dart client (generated messages only, no
screen), and the expiry job's schedule inside a running `zen-jobs` scheduler (its registration and the sweep it calls are tested; a tick is not).
Open: whether the destination account is chosen at parse or at preview (both are accepted); that `Account` has no account-number field, so the
identity check the Erste contract asks for is only a hook with a fail-closed default until #73 adds the field and implements it; and that the
open-session cap is checked, not locked, so concurrent uploads can overshoot it slightly.

---

## ADR-088 — The Erste CSV contract is what one real export showed, written down with synthetic fixtures and a gate; no real statement enters the repository

**Date:** 2026-11-14. **Status:** accepted. jlogicsoftware/prudent#42, first task of the epic jlogicsoftware/prudent#41.

### Decision

- `docs/erste-csv-contract.md` is the contract the Erste importer (#73) validates against. It was derived
  from **one** real export that stays outside the repository; the document says what that file showed
  (UTF-8 without a BOM, LF, comma delimiter, no header row, nine fields with a trailing empty one, a
  summary row first, transactions newest first with the bank sequence number growing down the file, comma decimals always quoted, a balance column that does not chain, `DD-MM-YYYY` dates with an ISO export date in the
  summary row, three description shapes) and lists what one file cannot show as open questions, not as
  facts.
- The parser's stance follows: **a variant not in the contract is rejected, not adapted.** The bank's
  own export steps are not written down because they were not captured; the document marks them as to be
  confirmed in the bank's UI.
- Fixtures are synthetic only, under `server/src/test/resources/import/erste/`. Every free-text field carries
  a whole-word marker (TEST, TESTOWY, TESTOWA, TESTOWE, TESTOWO, EXAMPLE, PRÓB, PRÓBNA or PRÓBNY), accounts
  have IBAN check digits `00` (which no real IBAN has) and card masks are `000000******0000`.
- `task verify:import-fixtures` (`scripts/verify_import_fixtures.py`, run in CI) has this scope: every file
  under `server/src/test/resources/import/` must be a lowercase `statement-*.csv` inside `import/erste/`, and
  any `*.csv` (any case) anywhere under `server/src/test/resources/` fails unless it is one of those
  (other file types outside `import/` are not read). `.DS_Store` is skipped by name. It refuses: a long number
  (13 or more digits or mask characters, with space, hyphen, dot or no-break-space separators, asterisk and
  bullet masks included) that is not the fictional IBAN (22 zeros then 4 digits) or the fictional card mask;
  another card mask; a `ref` number that does not start `000`; a run of 9 to 12 digits in a CSV field; a row
  that does not have exactly 9 fields, a non-empty 9th field, a line break inside a field, or a field that
  does not match its pattern (dates, quoted two-place comma decimals, sequence digits, a grouped fictional
  IBAN, a three-letter currency, the summary row's apostrophe-prefixed account); and a description or
  counterparty (the holder, on the summary row) without a whole-word marker (the fixed own-transfer phrase
  is exempt). The contract document is scanned for the same numbers.
  It is **weak by design** and still passes: a real name next to a marker word in one field; digit runs
  shorter than 9; amounts, dates and balances (their shape is checked, never their content); `ref:000`
  followed by arbitrary digits; any sequence number; runs broken by three or more separator characters or
  by letters; a `.DS_Store`. It narrows the room for a leak; a reviewer still reads every fixture change.
  Every `*.csv` is gitignored (the bank names its export `history*.csv`, and people rename it), with only
  the `statement-*.csv` fixtures under `server/src/test/resources/import/erste/` let back in, so a real
  export cannot be staged by accident.
- Fixtures are newest first and their balances deliberately do not chain, as in the real export, so a parser
  that asserts a running balance fails on them.
- The bank sequence number is **not** assumed to be a stable duplicate key. It grows as the date falls, so it
  looks like a rank from the newest row and may shift between exports. #75 must not use it unless a second,
  overlapping export shows it stable, and otherwise uses a documented fingerprint.
- #42 is only partly done: the bank's export steps are user-supplied and still missing, so the issue stays open.

### What this supersedes, and why

Nothing earlier. It settles the blocker recorded in `docs/github-backlog.md` (M6): "The exact parser
contract is blocked until an anonymised Erste export is available". The export was available and was
inspected locally; the anonymised copy that the backlog expected is replaced by synthetic fixtures,
because a hand-anonymised real statement keeps the shape of a real person's life and is easy to get wrong.

### Consequence

Verified: `task verify:import-fixtures` passes, and its tests plant each violation in a throwaway
tree and require it to fail. Not verified: any parser (none exists yet), the balance column's meaning, the
sequence number's stability across exports, and every variant listed as unsupported in the contract.

---

## ADR-087 — A deploy pins its image and ends by running jZen's cleanup, with Prudent's numbers and a failure mode that fails

**Date:** 2026-11-13. **Status:** accepted. jlogicsoftware/prudent#165, which stays open until the persistent environment's first run. **Follows:** ADR-021, ADR-065, ADR-069, jZen ADR-074.

### Decision

- `deploy:cloudrun` **pins the pushed image** (`deploy:pin`, which calls jZen's `zen:deploy:pin`) right
  after `docker push` and before the migration job or the service is pointed at it. If the pin fails the
  deploy stops, while nothing yet depends on the image.
- `deploy:cloudrun` **ends with `deploy:cleanup`**, which calls jZen's `zen:deploy:cleanup`, after
  `deploy:accept-origin` — that is, once the service is accepted. Nothing follows it.
- Prudent's numbers:

  | Setting | Value | Why |
  |---|---|---|
  | `CLEANUP_KEEP_VERSIONS` | 30 | A deploy leaves three registry versions (a tagged index, the untagged image Cloud Run runs, an attestation), so 30 is the last ten deploys per package. Prudent deploys rarely and in bursts; a count, not an age, is what keeps a rollback target after a quiet month. |
  | `CLEANUP_IMAGE_DAYS` | 30 | Versions younger than this are never deleted. Must exceed `CLEANUP_REVISION_DAYS` (an image is older than its revision). |
  | `CLEANUP_KEEP_REVISIONS` | 5 | A rollback target and a few before it. Revisions cost nothing at idle; the point is that the list stays readable. |
  | `CLEANUP_REVISION_DAYS` | 14 | A revision younger than two weeks is never deleted, whatever the count. |

  Anything a revision or job still needs is pinned and kept however old; a serving revision is never
  selected. The other `CLEANUP_*` switches keep jZen's defaults (local Docker cleaned, build cache
  older than 168 hours).
- **The failure mode is `fail`, and it is Prudent's, not the shell's.** The numbers and
  `CLEANUP_ON_FAILURE=fail` are passed to jZen's task as command-line variables. Measured on
  go-task 3.53.1: a variable the included Taskfile declares beats a `vars:` entry on the include and
  on a `- task:` call (an include var of 5 still printed jZen's default of 3), and an exported variable
  beats those but not a command-line one. Command-line variables are the only way in that cannot be
  overridden by an exported `CLEANUP_ON_FAILURE=warn`. Changing a number is therefore an edit and an
  ADR, not an environment variable. `CLEANUP=off` and `CLEANUP_DRY_RUN=1` are left to reach jZen's
  task: one skips the cleanup deliberately and visibly, the other changes nothing.
- A cleanup that cannot finish exits non-zero, and jZen's report says the deploy itself succeeded. It is
  never reported as success (CLAUDE.md, "Nothing swallows a failure"). Re-run `task deploy:cleanup`
  alone after fixing the cause.
- The runbook's teardown (step 4) is unchanged: it is for throwaway environments and still deletes the
  whole project. No environment fact is written into the repository (ADR-021): the wrappers read the
  project, region, service and repository from the shell like the rest of `deploy:cloudrun`.

### What is covered and what is not

`scripts/test_deploy_cleanup.py` (run by `task test:deploy-origin`, in CI) runs `task deploy:pin` and
`task deploy:cleanup` against a stub `gcloud` and `docker` that record their calls: the pin tags the
digest of this commit, an image missing from the registry fails, the cleanup runs with 5, 14, 30 and 30,
a failed registry listing exits non-zero and says the deploy succeeded even with an exported
`CLEANUP_ON_FAILURE=warn`, and a dry run deletes nothing. The order inside `deploy:cloudrun` (pin after
the push and before the first `gcloud run`, cleanup last) is read from the Taskfile text, because the
task itself builds a native image and cannot run in a test.

**Not done by this entry:** the cleanup has not been run against the persistent environment. jZen
validated its mechanism on its own production environment on 2026-11-13 (37 to 20 versions, a rerun
deleted none). Prudent's own run — a `CLEANUP_DRY_RUN=1` read, the real run, and the registry listed
before and after — is the operator's, and the result belongs in this record when it exists.

---

## ADR-086 — Skwasm stays single-threaded while the page remains non-isolated

**Date:** 2026-11-06. **Status:** accepted. **Closes:** jlogicsoftware/prudent#230. **Follows:** jZen ADR-016, ADR-035.

### Decision

- Prudent keeps the browser page non-isolated and accepts Flutter's single-threaded Skwasm fallback.
  Multi-threading is a performance option; the app does not require it to function.
- `client/web/flutter_bootstrap.js` sets Flutter's `suppressMultithreadingWarning` configuration.
  This only silences the warning; it does not enable workers or change the renderer.
- Prudent does not add `Cross-Origin-Embedder-Policy` itself. Those response headers belong to
  jZen's shared HTTP security-header layer. jZen ADR-035 deliberately omits COEP until the page's
  cross-origin resources have passed a browser compatibility check.
- The release app and API remain same-origin, preserving the session-cookie flow. Prudent's browser
  auth calls its own API; it does not call Supabase directly.

### Why this resolves the issue

Issue #230 asks whether to enable isolation or keep the fallback quiet. The release Wasm build
reproduced the warning in Chrome while rendering the login screen. The warning reports a
single-threaded fallback, not a failure. Adding COEP would be a page-wide framework response-header
change, and the framework's existing security decision leaves it out pending browser verification.
Prudent records and follows that boundary instead of opting the app into isolation on its own.

### Consequence

Flutter's web build consumes this bootstrap template. The page remains non-isolated and
single-threaded, with the diagnostic suppressed. Verified in Chrome after rebuilding the Wasm
bundle: the login screen renders and the Skwasm warning is absent. The sign-in flow itself was not
exercised because this local browser run had no backend.

---

## ADR-085 — `SUPABASE_KEY`, the publishable key, is a plain environment variable and no longer a secret

**Date:** 2026-11-01. **Status:** accepted. **Refines:** ADR-070, ADR-075.

### Decision

- **`SUPABASE_KEY` leaves Secret Manager.** It is Supabase's *publishable* key (`sb_publishable_…`), the one Supabase gives to
  any browser; it is visible in the network panel and what it can do is bounded by row-level security, not by its secrecy. It
  is exported in the operator's shell like `SUPABASE_URL` and passed to the migration job **and** the service as a
  `--set-env-vars` literal. **Nine genuine secrets remain:** `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `ZEN_JOBS_TRIGGER_TOKEN`,
  `SMTP_USERNAME`, `SMTP_PASSWORD`, and, for the service only, `APP_DB_USERNAME`, `APP_DB_PASSWORD` and `SUPABASE_SECRET_KEY`.
  `SUPABASE_SECRET_KEY` is **not** touched: it administers every identity in the project and stays a secret bound as a reference.
- **The kind is checked where it is cheap.** `scripts/public_config.sh` refuses anything but `sb_publishable_…` made of letters,
  digits, `-` and `_`, before the native build, instead of at the service's boot. `verify:deploy` fails when the running service's
  `SUPABASE_KEY` is absent, is still a Secret Manager reference, or is not a publishable key. The boot check of ADR-075 stays.
- **It is configuration at runtime, not baked into the image.** The server reads it as MicroProfile config; the image is the same
  for every environment. The client never uses it (it talks only to Prudent's server).
- **A service made before this change is rebound once**, the way ADR-070 describes: remove the `SUPABASE_KEY` secret reference from
  the job, then from the service, then run `deploy:cloudrun`. The secret is deleted afterwards.

### What this supersedes, and why

- **"`SUPABASE_KEY` ... a secret"** (ADR-075; `deploy:cloudrun --summary` step 2; `docs/persistent-environment.md` section 3) →
  **changed.** *Why:* a value that every browser can read gains nothing from Secret Manager except a per-version bill and a false
  signal of confidentiality that hides the one key that needs it. The reason ADR-075 gave for the *secret* key is untouched.
- **"Ten genuine secrets"** (ADR-070's count as amended by ADR-073 and ADR-075) → **nine.**

### Consequence

- The pre-change service is the persistent environment: its `SUPABASE_KEY` secret held a key of the wrong kind, which is why
  revision 00006 did not start on 2026-11-01 (`SUPABASE_KEY must be the project's publishable key`). The last good revision kept serving.
- Verified: `scripts/test_public_config.py` and `scripts/test_deploy_origin_tasks.py` pass, including the refusal of a legacy JWT and a
  secret key in either place. Not verified until the deploy it enables has run: the rebind, and the sign-in on a device.

---

## ADR-084 — Sign-up and recovery mail is worded by Prudent's own templates, kept in the repository, gated offline and compared with the hosted project on demand

**Date:** 2026-10-30. **Status:** accepted. **Refines:** ADR-079. jlogicsoftware/prudent#187.

### Decision

- `supabase/templates/confirmation.html` and `recovery.html` are Prudent's own mail: the product name, one
  sentence saying why the person received it, a button **and** the plain link, a line saying what to do if
  they did not ask, and nothing from the ledger. They carry **two placeholders only**, `{{ .ConfirmationURL }}`
  and `{{ .Email }}`. There is no remote image, script or tracking, and the one `<style>` block is the
  dark-mode rule a mail client needs.
- **One body per mail type holds all three languages, in the order English, Ukrainian, Polish**, each in its
  own `lang`-tagged block with a language label, a rule between blocks, a button in each block and one
  plain-link line under all three. The subject names the three languages separated by ` · `. The reason is
  ADR-079's: GoTrue sends one template per type and the signup and recover calls carry no language. *Why
  this order:* English is the product's default and what a forwarded or machine-read copy shows; Ukrainian
  and Polish follow as the other two languages Prudent ships (CLAUDE.md, "Typed, generated i18n"). The order
  is the owner's to change, and changing it edits two files.
- The templates are wired for the local stack by `[auth.email.template.confirmation|recovery]` in
  `supabase/config.toml`; **the hosted project reads nothing from the repository.**
- **`task verify:mail-templates`** (`scripts/verify_mail_templates.py`, run in CI) fails on a placeholder
  other than those two (GoTrue renders an unknown one as nothing, so the link would be empty), an `href`
  that is not the link placeholder, any literal `http://`, `https://` or `//` address, a remote image,
  `url(`, `src`, a script, a body without its `en`, `uk` and `pl` blocks, its plain link or the name
  Prudent, a subject that is empty, takes a placeholder or names fewer than three languages, a template
  that is wired by nothing and a wiring whose file is missing. `scripts/test_verify_mail_templates.py`
  plants each defect. **Until #188 the link is GoTrue's own `{{ .ConfirmationURL }}` and the gate pins that;
  #188 changes the set when it points the link at Prudent's own origin.**
- **`task verify:mail-templates:hosted`** reads the hosted project's mail back and **`task
  deploy:mail-templates`** writes it and reads it back, both through the Management API's `config/auth`
  (`GET` and `PATCH`, `scripts/hosted_mail_templates.py`). The fields are
  `mailer_subjects_confirmation`, `mailer_templates_confirmation_content`, `mailer_subjects_recovery` and
  `mailer_templates_recovery_content`, **read from the API's published OpenAPI document on 2026-10-30**,
  not recalled. Both need `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` and exit 2 without them. Neither
  runs in CI: a token for a real project does not belong there. CI runs only their tests, against a stub.
- **The other mails Supabase can send**, decided by what Prudent can trigger. `zen-identity` calls GoTrue's
  `signup`, `recover`, `verify`, `token`, `logout` and `PUT /user` (a new password, nothing else), and the client
  never reaches GoTrue itself (CLAUDE.md, "The client talks to one server"):
  - *Signup confirmation and recovery*: sent today; templated here.
  - *E-mail change, magic link, reauthentication*: **not templated; they keep Supabase's default.** No route
    or screen can ask for any of them, so a template would be text nobody receives. A screen that can send one
    adds its template in the same change, in the same three languages.
  - *Security notifications (password changed, e-mail address changed), decided as a group: **not enabled
    now**.* The password-changed one is reachable (a recovery ends in `PUT /user`) and the e-mail-changed one
    is not, but the pair is one decision: each wants the same trilingual body, each would go out through the
    built-in sender, which delivers only to members of the Supabase organisation at two messages an hour
    (ADR-068), and whether the Free plan offers them was not checked. So they wait for the sender of #186.
    bugeater-quarkus#546 enabled both because, after a reset, the legitimate owner otherwise gets no signal that
    someone else did it; that reasoning is why this is deferred and not rejected.
- **A local sign-up does not send the confirmation mail.** `enable_confirmations` stays `false` in
  `supabase/config.toml`, and ADR-076 relies on it (the e2e and native gates start no mail container). So
  `task run:supabase` shows the *recovery* template in its inbox and never the *confirmation* one. Turning it
  on would make every local sign-up, `task run:dev` and `task test:e2e` need an inbox click; that is a larger
  decision than this one and is not taken here.

### What this refines, and why

- **"Prudent's own template in `en`, `uk` and `pl` is #187"** (`docs/persistent-environment.md`, section 3) →
  **built, not yet applied.** *Why:* the files, their gate and the apply and read-back exist; the hosted
  project still sends Supabase's default template until the owner runs `task deploy:mail-templates`.
- **"the repo and the dashboard can drift and nothing checks it"** (the sibling product's runbook, cited by
  ADR-079) → **checked on demand.** *Why:* the Management API carries the subject and body, so drift is a
  command that exits non-zero, not a reading of a dashboard.

### Not verified, and said so

- **No mail client was tried.** Not Gmail, Outlook or Apple Mail, and no real message was received. The
  templates were rendered with sample values in Chromium, light and dark, at 375 and 700 px; that shows the
  layout and the dark-mode block and says nothing about Outlook's Word engine or how any client treats the
  `<style>` block.
- **The local stack was not restarted with the templates**, so `content_path` as written in `config.toml`
  (`./supabase/templates/…`, the form the file's own commented example used) has not been read by a running GoTrue.
- **The Management API was not called**; the stub the tests use accepts what the script sends. Whether the API
  stores a body byte for byte is unknown until the first real read-back (the comparison ignores surrounding
  whitespace for that reason).
- The hosted project is unchanged: it still sends Supabase's default template.

### Consequence

`docs/persistent-environment.md` section 3 gives the steps. A template edit is not finished until the hosted
project has it, and the check exists so that a difference is a red command rather than a surprise in a
stranger's inbox. Verified on 2026-10-30: `task verify:mail-templates` green (both unit suites and the gate on
the real files).

---

## ADR-083 — The iOS and macOS runners resolve everything through Swift Package Manager; CocoaPods is gone, and a gate keeps it gone

**Date:** 2026-10-30. **Status:** accepted. jlogicsoftware/prudent#183.

### Decision

- `pod deintegrate` was run in `client/ios` and `client/macos`: the `[CP] Check Pods Manifest.lock`
  phases, the `Pods_Runner` / `Pods_RunnerTests` frameworks and every `Pods-Runner` reference left
  both `Runner.xcodeproj/project.pbxproj` files. `Podfile`, `Podfile.lock` and `Pods/` are deleted,
  the four `#include? "Pods/…"` lines left the Flutter `.xcconfig` files, and the `Pods/Pods.xcodeproj`
  entry left both workspaces.
- The minimum OS is unchanged and now lives only in the Xcode projects: iOS 15.0
  (`IPHONEOS_DEPLOYMENT_TARGET`) and macOS 12.0 (`MACOSX_DEPLOYMENT_TARGET`) were already set on
  every build configuration there; the Podfile's `platform :osx, '12.0'` was the only other copy.
- `task verify:swiftpm` (`scripts/verify_no_cocoapods.py`, run in CI) fails when either runner has a
  `Podfile`, a `Podfile.lock`, a `Pods/` directory, or a CocoaPods trace in the Xcode project, a Flutter
  `.xcconfig` or the workspace. `scripts/test_verify_no_cocoapods.py` plants each trace and requires
  the gate to go red.

### What this refines, and why

- **"Removing CocoaPods is a separate change"** (`docs/native-iphone-build.md`, troubleshooting) →
  **done**; that row now describes the failure the gate catches. *Why:* CocoaPods here was a leftover.
  `Podfile.lock` resolved only the `Flutter` pod, every native plugin (`app_links`,
  `flutter_local_notifications`, `flutter_secure_storage_darwin`, `flutter_timezone`,
  `shared_preferences_foundation`) already arrived through Swift Package Manager, and the build still
  ran `pod install` and a manifest check each time. The CocoaPods registry also turns read-only on
  2026-12-02, and `zen_store_icloud` (jZenDev/jZen ADR-065) ships as a Swift package with no podspec,
  so Prudent could not consume it while it built through CocoaPods.
- Android is untouched: Gradle remains its only dependency manager.

### Consequence

Flutter falls back to CocoaPods for any plugin without a Swift package, writes a `Podfile`, and the
build stays green, so a plugin added later could bring a second build system back unannounced. The
gate makes that a red CI run. It reads files; it does not build a runner, which needs Xcode and a
macOS host (ADR-003), so `task zen:build:runners` remains the build check and is run by hand.

Verified on 2026-10-30 (Flutter 3.47.7, Xcode 27.1), after `flutter clean`: `flutter build ios
--simulator` and `flutter build macos` both succeed and neither writes a Podfile back. A throwaway
probe (not committed) running the app's own `SecureTokenStore` and local-notification gateway on the
iOS 26.5 simulator: the keychain write, read and delete round-trip; the plugin initialises; the system
permission prompt appears and, once allowed, a notification is scheduled, listed as pending and
cancelled. **Not verified, and stated rather than implied:** on macOS the probe launched and the
notification plugin initialised, but `SecureTokenStore` failed with keychain error -34018 (missing
entitlement) — the known boundary recorded in the earlier decision on macOS session persistence, not
something this change introduced, since the entitlements are untouched — and the macOS notification
permission prompt was not answered, so scheduling there was not exercised. No device build was run.

---

## ADR-082 — Bound page content in the navigation shell

**Date:** 2026-10-30. **Status:** accepted. jlogicsoftware/prudent#195; jZenDev/jZen#197 and #201.

### Decision

The authenticated shell supplies `ZenPageWidthScope`: ordinary page bodies are centred at a
maximum of 640 logical pixels, and analytics opts into 960 for charts. Both use the framework's
16-pixel gutter on each side. Page headers, navigation and `ZenDetailHost` retain the available
width, so the 720-pixel detail breakpoint still measures the host. The scope reaches pages pushed
inside destination navigators and framework-owned pages. The previous local settings and analytics
width constraints are removed. CI and audit pin jZen at `089ebfe`, which includes the scope.

### What this refines, and why

- **"the detail of this screen ... beside it on a wide host"** (ADR-062, Decision) → **refined.**
  *Why:* page bodies need a readable width without narrowing the host used to choose detail layout.
- **"The widest the analytics content grows, in logical pixels"** (`AnalyticsColumn.maxWidth`,
  set to 720, issue #194) → **changed.**
  *Why:* the shell owns the common width rule and charts have a deliberate wider allowance.

### Consequence

New `ZenPageScaffold` pages below the shell inherit the width without screen-specific layout code;
charts may opt into the named wider limit. The 392-test client suite passed on macOS; shell and
analytics tests measured 400- and 1600-pixel windows, and a browser preview showed settings and
the accounts detail at narrow and wide widths.

---

## ADR-081 — An account can be deleted together with all of its transactions, but only on a second, typed confirmation

**Date:** 2026-10-30. **Status:** accepted. **Refines:** ADR-008. jlogicsoftware/prudent#201.

### Decision

`DELETE /api/v1/accounts/{id}` takes `?deleteRecords=true`. Without it nothing changes: the account
is refused (409) while any record remains. With it, the account and every record that touches it go
in one transaction, and a failure anywhere leaves all of it where it was.

- **What goes.** Ordinary records, balance corrections, and transfer legs — **both legs**, the one in
  this account and the one in the other. A lone leg would be a withdrawal with no destination, a
  balance change nobody made; this is what `DELETE /api/v1/transfers/{id}` already does. The cost is
  stated to the person: the other account's balance moves, and the confirmation says so.
- **How.** `RecordEntity.deleteAllForAccount`: one bulk `update` and one bulk `delete`, scoped by
  `user_id`, however many rows there are. Per-row deletes would load thousands of entities into the
  persistence context. The record delete's other duty is kept: an occurrence that a deleted record
  had confirmed is set back to `PLANNED` (ADR-040), or it would claim a transaction that is gone
  and could never be confirmed again. That can happen to an account with no plan, because
  confirmation may override the account.
- **Plans still refuse**, flag or not, checked before any record is touched. A plan is a promise to
  act, not a transaction; the flag authorises deleting transactions only.
- **On the client** the delete action is two steps: a warning that the transactions go too, then a
  form that shows a phrase (`DELETE`, `ВИДАЛИТИ`, `USUŃ`) and enables the delete button only when it
  is typed (trimmed, without case). The phrase guards against a stray tap and is checked in the
  client; the server does not know it. Cancelling either step, or a wrong phrase, sends nothing; a
  refusal or failure is shown in the form in the server's words and nothing is removed. Both steps
  are shown for every account, including an empty one: the client holds a filtered list of records,
  so it cannot say reliably that an account has none. After success the accounts, records, budget,
  analytics, planned occurrences and reminders are refetched and the reminder notifications are
  reconciled.

### What this refines, and why

- **"Refused rather than cascaded"** (`AccountResource.delete`, from ADR-008's reasoning about money
  that left an account no longer admitting it exists) → **refined.** *Why:* the refusal is still the
  default and still what a caller gets without asking. But an account with thousands of records could
  only be deleted by removing each one, which is impractical, and a person who has been told exactly
  what goes and has typed a phrase has not had money disappear unannounced.

### Consequence

Verified: `AccountResourceTest` (18 tests, green) covers every kind of record going with the account,
the counterpart transfer leg, 5,000 records in one request, the reopened occurrence, a plan refusing
with nothing deleted, and another user's account answering 404 with nothing deleted. The new client
tests (`delete_account_form_test.dart`) cover cancelling, the disabled button, the request carrying
`deleteRecords=true`, and a refusal staying on screen.

Not done, and stated rather than implied: nothing audits the deletion; there is no undo and no backup
in the persistent environment (ADR-069); the form has not been looked at in a browser or on a device.

---

## ADR-080 — Pin jZen's adaptive list and switch rows in CI

**Date:** 2026-10-30. **Status:** accepted. **Refines:** ADR-018. jlogicsoftware/prudent#211; jZenDev/jZen#190, #192.

### Decision

Move `JZEN_REF` in both `.github/workflows/ci.yml` and `audit.yml` from
`b2c6cbc834eba0eb991a3d4c5be728208b897861` to `c3fafa13220d9359f84095658b2c44a470b4b784`,
the merge of jZen #192. This includes the adaptive switch rows from #190 and the rich list rows
from #192 that Prudent uses.

### What this supersedes, and why

- **"JZEN_REF: b2c6cbc834eba0eb991a3d4c5be728208b897861"** (the CI and audit workflows) →
  **changed.** The old revision predates the exported `ZenListRow`, so CI cannot compile the
  client even though the local sibling checkout has the widget. The same reviewed revision is
  used in both workflows, preserving ADR-018's pinned dependency boundary.

### Consequence

CI and the audit will consume the merged jZen implementation. The earlier PR run failed to compile
against the old pin; the replacement still needs verification against this exact revision in CI.

---

## ADR-079 — Sign-up and recovery mail is Prudent's to send and word; where its link points is the framework's to fix; both are reported, and nothing is built yet

**Date:** 2026-10-27. **Status:** accepted. **Refines:** ADR-068, ADR-073, ADR-078.
jlogicsoftware/prudent#186, #187, #188; jZenDev/jZen#154.

### Decision

- The owner's first native sign-in (ADR-078) produced a confirmation mail that was **almost empty and whose address looked like
  phishing**. Two separate things cause that, and they sit in different repositories:
  - **Prudent's:** who sends the mail (the built-in Supabase sender, no tie to a domain the recipient knows), what it says (Supabase's
    default template: no product name, no reason, one link) and in which languages. Tracked as #186 (an authenticated sending
    domain and a relay) and #187 (templates in `en`, `uk`, `pl`, kept in the repository and applied to the hosted project with a
    drift check).
  - **jZen's:** where the link points. `zen-identity` hands GoTrue only a `redirect_to`, so the link in the mail is
    `https://<project-ref>.supabase.co/auth/v1/verify?…`, a host that is neither the sender nor the product. A template cannot fix
    that, because the framework has no route a one-time token could land on. Reported as jZenDev/jZen#154: a landing page that
    spends nothing, a verification `POST`, a decided native hand-off, reference templates and an operator checklist. Prudent's
    consumption of it is #188, blocked until that lands.
- **Both levels, in that order of independence.** #186 and #187 can ship now with GoTrue's own `{{ .ConfirmationURL }}`; they make
  the mail legible and deliverable, not self-evidently ours. #188 is the step that removes the foreign host.
- **Prudent builds no verification route of its own.** jZen is a dependency, not a donor (CLAUDE.md): a route that holds a
  one-time credential, its CSRF reasoning and its rate limit is framework behaviour, and a copy in Prudent is the drift this
  repository exists to avoid.
- **The relay is chosen against one criterion before any other: it must not rewrite transactional links or add an open pixel.**
  One relay serves both Supabase Auth's mail and the dormancy warning (ADR-073). The reason is the evidence below.
- **All three languages go in one body per mail type**, because GoTrue sends one template per type and the signup and recovery calls
  carry no language; a template that picked one would show the wrong language to exactly the people who need another.

### Evidence

The sibling product `bugeater-quarkus` (Quarkus + Supabase, the same owner) met the same symptom and left a record:

- jlogicsoftware/bugeater-quarkus#362 (its ADR-079, `docs/EMAIL_DELIVERABILITY.md`): mail in Spam with Gmail's "might be dangerous" banner;
  fixed with an authenticated subdomain, a relay, Supabase's SMTP settings and bilingual repository-owned templates.
- #409 → #496 (its ADR-082): even then the link named `<project>.supabase.co`, "neither the sender nor the product, which reads as
  phishing"; fixed by linking to its own origin with `token_hash` and verifying the token itself. Review added a landing page that
  spends nothing (mail scanners fetch every URL), `Referrer-Policy: no-referrer`, CSRF kept on the verification `POST` (login CSRF with an
  attacker's own token), a per-IP rate limit, an upstream 429 never reported as an expired link, and no retry on a call that spends
  a token.
- Its relay (Brevo) then rewrote every link to a tracking redirect and added an open pixel, so the visible URL and the real `href`
  differed again, with no self-service switch (#380). That is why the relay criterion above comes first.

### What this supersedes, and why

- **"Sign-in mail | Supabase's default sender | Section 3"** (`docs/persistent-environment.md`, section 1; ADR-068) → **refined.** *Why:*
  the default sender was accepted for a proof of concept with one owner who is a member of the Supabase organisation. It still is
  the sender in use, and it still delivers to nobody else; what changed is that it is no longer *fine* for the owner either, because
  the mail it sends is unfit to be trusted on a phone. The environment is unchanged by this entry.
- **"No relay, host or sender is named in this repository."** (ADR-073) → **kept, with a criterion added.** *Why:* the choice stays the
  owner's, and the repository still names none (ADR-021); but the choice now has a test it must pass.

### Consequence

- **Documentation and tickets only.** No code, template, DNS record or dashboard setting changed, and no suite was run.
- **Not verified, and said so in the tickets:** that Supabase's Management API covers the template and subject fields (the names are
  recalled, not read); that any particular relay leaves links alone (bugeater-quarkus names Postmark, Resend and Amazon SES; that is its
  claim); the content and headers of the mail the owner received (this entry rests on the owner's description, not on the message);
  that jZen will take #154 as proposed.
- Until #188, the mail's link still names the Supabase project's host. `docs/persistent-environment.md` section 3 says so where an
  operator will read it.

---

## ADR-078 — A native iPhone build is a written procedure, run by hand against the persistent environment; it has signed a user in once

**Date:** 2026-10-27. **Status:** accepted. **Refines:** ADR-068, ADR-069. jlogicsoftware/prudent#155.

### Decision

- The native iPhone build is **documented as a procedure** (`docs/native-iphone-build.md`), not made a `task`
  target. It calls `flutter build ios --release` with `ZEN_ENV=prd`, `ZEN_PLATFORM=ios`, `ZEN_API_URL` (the
  service URL read from `gcloud` at build time) and `ZEN_AUTH_REDIRECT_URI=prudent://auth-callback`, then
  `flutter install --release` and `xcrun devicectl device process launch`. The build contains the origin, so it is
  rebuilt, never reconfigured, when the origin changes.
- Nothing environment-specific enters the repository (ADR-021): the document carries placeholders only, and
  the origin is read from the cloud each time.
- The build is a **development install on the owner's own device**. No distribution (TestFlight, the App Store)
  is set up or implied.

### What this supersedes, and why

- **"The native return address `prudent://auth-callback` is in the list but has not been followed, because no native
  build exists (#155)"** (`docs/persistent-environment.md`, section 3, and "Native iPhone build: A separate issue,
  #155 / The phone uses the web app first", section 1) → **refined.** *Why:* on 2026-10-27 the owner followed it. A new
  user registered, the mail arrived, the link opened in the browser, which offered to open Prudent, and the app
  opened and signed the user in at once. Both passages now say so; ADR-068 and ADR-069 are not edited.
- A task was **not** added, although the rule that `task` is the only entry point argues for one. *Why:* a task that
  cannot be run in CI (it needs a paired phone, a certificate in a keychain and an interactive Apple ID) and has
  run once is a script nothing exercises. It would pass its own checks on a machine that proves nothing about the
  phone. When the build is repeated enough to need one, it earns the task then, with the origin check the web
  bundle already has (`build:web`).

### Consequence

- **Observed once, by hand, on one iPhone (iOS 26.6) against the persistent environment:** sign-in with an existing
  user; registration, the mail and the return into the app; the overview with a balance; Settings opening; the
  language changed with all three offered; an account created and one expense recorded and reflected in the balance.
- **Found on the way:** signing failed with "could not code sign" until the Apple ID was signed in again in Xcode —
  an interactive step no script can take. The first launch is refused until the developer profile is trusted on the
  phone. Building with Xcode 27.1 rewrote `client/ios/Runner.xcodeproj/project.pbxproj` and `Runner.xcscheme`; that is
  not part of this decision and was not committed.
- **Not proven:** a notification firing (a reminder cannot be switched on in the UI); an automated read of a Prudent
  message in both transports (#159); the privacy routes on the deployed service, which predates them; when the build
  stops launching, and what kind of Apple Developer account signs it; any second device or iOS version.
- Documentation only: no code or test changed, so no suite was run for this entry.

---

## ADR-077 — `JZEN_REF` moves to `15cafd7`: the e-mail is trimmed before it is validated on sign-in, registration and restore

**Date:** 2026-10-24. **Status:** accepted. **Follows:** ADR-063 (prior `JZEN_REF` bump). jZenDev/jZen#143 (→ #144);
jlogicsoftware/prudent#161.

### Decision

- `JZEN_REF` moves from `b67a54924de2c744a05b077f5c18ac546ffcdcd3` to `15cafd786c3ef8ecf39471c77fccefe9eaf2f399` (`ci.yml`,
  `audit.yml`). It brings three jZen commits: #144 (the fix: one shared e-mail validator in `zen_ui_identity` that judges the
  trimmed value; whitespace inside an address stays invalid), #135 (`audit:server` installs the framework libs first) and #139
  (`deploy-cleanup`, new tasks in `Taskfile.app.yml`). The last two touch jZen's Taskfiles and scripts only; Prudent calls neither.
- Prudent changes no application code for it. `client/test/auth_flow_test.dart` drives sign-in, registration and password restore
  through `AuthFlow` with the delegates `PrudentApp` registers, and asserts a padded address is accepted and sent trimmed.

### Why this was a bump and not only a test

CI checks jZen out at the pinned SHA, not at the sibling checkout a developer has. The new test passed locally (the checkout was
already at `15cafd7`) and failed in CI at `b67a549`: exactly the three padded-address cases, while the case with a space inside
an address passed. That is also the evidence that the test fails without the fix, which a local run could not give.

### Consequence

- Verified locally at `15cafd7`: `task zen:test:client` (368 tests, the four new ones among them) and `task verify:controls`.
- Not verified: that the other jobs, `audit.yml` included, are green on the new pin; their first run on it is the check.

---

## ADR-076 — The e2e and native gates start three Supabase containers, not thirteen, so a registry's rate limit has less to bite

**Date:** 2026-10-24. **Status:** accepted. **Refines:** ADR-010. **Addresses:** jlogicsoftware/prudent#167.

### What failed

CI's `e2e` job runs `supabase start`, which pulls about a dozen images from `ghcr.io/supabase/*` anonymously. On 2026-10-22 ghcr.io
answered with `toomanyrequests` and five of the day's runs failed before any Prudent code ran (32-53 such lines in each log). The job
passed on other runs the same day. The failure is a property of the runner's shared address and the registry's window, not of the
code, and it still taught people to re-run red.

### Decision

- **`task test:e2e` and `task test:native` start the stack with `supabase start -x "$SUPABASE_EXCLUDE"`.** The list is one Taskfile
  variable, `SUPABASE_EXCLUDE`: realtime, storage-api, imgproxy, mailpit, postgrest, postgres-meta, studio, edge-runtime, logflare,
  vector, supavisor. What runs is Postgres, GoTrue and Kong.
- **Why those three are enough.** Prudent's server reaches Supabase for GoTrue only: sign-up and sign-in (zen-identity),
  the admin delete (ADR-075), and the JWKS at `/auth/v1/.well-known/jwks.json`, all through Kong; and the database. Nothing in
  `server/src/main`, `client/lib` or `client/integration_test` calls `/rest/v1`, storage, realtime or functions, and
  `enable_confirmations` is false, so no mail is read.
- **A service Prudent starts to use leaves the list in the same change.** The comment on the variable says so; the e2e suite fails the
  first time a call goes to a container that is not there.
- **No retry, no `continue-on-error`.** A failed pull still fails the job. There are simply roughly a quarter of the pulls to fail.

### Measured

On 2026-10-24, on the CLI installed locally (2.118.0; CI pins 2.113.0): `supabase start -x …` ran three containers and took 25 s on a warm
image cache. Against that stack, with the server on its own port, the sign-up, password sign-in, JWKS read, and the admin delete with the
secret key in `apikey` alone (200, then 404 on a repeat) all answered as they do on the full stack, and `client/integration_test/e2e_test.dart`
passed 7 of 7, including the erasure case. The scratch stack was removed afterwards.

### Not done, and why

- **Authenticating the pulls** (`docker login ghcr.io` with `GITHUB_TOKEN`, `packages: read`) is not in this change. It is unverified
  whether the CLI's pulls would count against a per-user limit instead of the shared address, and a permission added for an untested
  effect is a worse trade than waiting for the evidence. If `toomanyrequests` still appears with fewer pulls, it is the next step.
- **Caching images** costs a share of the repository's 10 GB cache for images that change with every CLI bump.
- **Not verified:** that CI no longer fails on the limit. The pull count fell; the window is the registry's. The acceptance for #167 is a
  number of consecutive green `e2e` runs, recorded there, and no number exists yet. jZen's reference app runs the same `supabase start`
  (`../jZen/Taskfile.app.yml`, `../jZen/Taskfile.yml`) and is told, not edited.

---

## ADR-075 — Erasure deletes the person's Supabase sign-in record, with a secret key the serving container alone holds

**Date:** 2026-10-24. **Status:** accepted. **Refines:** ADR-071, ADR-074. **Diverges from:** jZen ADR-007, ADR-008 (finding F4 of jZen's
security review). **Closes:** jlogicsoftware/prudent#173.

### Decision

- **Both request routes delete the sign-in record.** `POST /api/v1/privacy/erase` and the operator's
  `POST /api/v1/admin/privacy/users/{userId}/erase` call `SignInRecordEraser.delete` after the eraser and the anonymiser. That method calls
  GoTrue's `DELETE /auth/v1/admin/users/{id}` (`SupabaseAdminClient`, a REST client of its own under config key `supabase-admin`).
  The call is a hard delete: no body is sent, so `should_soft_delete` keeps its default of false.
- **Last, inside the transaction, after a flush.** If the record is deleted and the commit then fails, the person cannot sign in but keeps
  their data, and the operator route repairs that. The other order is worse: commit first, and a failed deletion leaves a person whose
  data is gone and whose self-service retry is refused, because the address it asks them to confirm is already anonymised. The flush makes a
  constraint failure in the anonymised profile refuse *before* the irreversible call.
- **A failure is the caller's answer.** GoTrue's 404 (`user_not_found`) means the work is done (deleted in the dashboard, or by an earlier
  erasure) and is success. Anything else — 401/403 for a wrong or publishable key, 5xx, no connection, no key configured — is **503 `unavailable`**
  ("The sign-in record could not be deleted, so nothing was erased. Try again later."), and the throw rolls everything back. The log line
  names the person's id and the status or failure class; never the key, never GoTrue's answer.
- **The key is a secret of its own, and it is Supabase's secret key, never the legacy service_role JWT.** It is `SUPABASE_SECRET_KEY`
  (`sb_secret_…`) in Secret Manager, bound by `deploy:cloudrun` to the **service only** (`ADMIN_KEY` in the task), not to the migration
  job, which deletes nothing. That makes ten secrets. It is sent in **`apikey` only**: it is not a JWT, so nothing goes in
  `Authorization`, and Supabase's gateway presents the call to GoTrue as the service role. Measured against the local stack, an
  `sb_secret_` key in `apikey` alone deletes a user (200, then 404 on a repeat); the publishable key gets 403 `not_admin`.
  `verify:deploy` fails when the running service lacks it as a Secret Manager reference, so a plain value fails too.
- **`SUPABASE_KEY` is the publishable key** (`sb_publishable_…`), not the legacy anon JWT. zen-identity sends it as `apikey` on
  every call it makes for a person. The runbook in `deploy:cloudrun` said otherwise (below).
- **Both kinds are checked at boot** (`SupabaseKeys`, `prudent.supabase.keys-required` in `%prod`, skipped under `zen.migrate-only`).
  A serving process refuses to start when `SUPABASE_KEY` is not `sb_publishable_…`, which catches a legacy JWT and a secret key put
  there by mistake, and when `SUPABASE_SECRET_KEY` is not `sb_secret_…`. The message names the variable and the kind, never the value.
  Supabase recommends these keys over the legacy pair: each can be revoked on its own, and a secret key is refused when it comes from a
  browser. The legacy keys are two JWTs that look alike, which is how the runbook came to ask for the wrong one, and a prefix tells the
  new kinds apart without decoding anything. `SignInRecordEraser` never sends anything but an `sb_secret_` key, so in `%dev` too a
  legacy JWT is a 503, not a call.

### Why accept the wider blast radius

jZen's review (F4) priced this as introducing "the single most powerful Supabase credential" into the container. Two facts change the price
for Prudent:

- **The container already holds the database owner.** `deploy:cloudrun` binds `DB_USERNAME`/`DB_PASSWORD` (the `postgres.REF` DDL role)
  to the service as well as `APP_DB_*`. A compromised container can already read every ledger row. What the secret key adds is
  **identity administration**: deleting users, setting passwords, minting sign-in links, so taking over any account. That is real and
  is the cost accepted here.
- **The manual step did not work for the common case.** A person who erased themselves in the app was told to ask the operator, and nobody
  was told anything. Their address and password hash stayed indefinitely, and signing in again opened an empty account. That is a
  completeness gap in the right to erasure on the route people actually use.

What limits the key: it is used by one class for one call, it never travels on a person's call, the migration job does not have it, and it
is a Secret Manager reference that `verify:deploy` checks. Prudent does this in its own code rather than in jZen, because jZen leaves
`auth.users` to the application on purpose; whether the framework should offer it is recorded in `docs/jzen/README.md` as a candidate, not
filed.

### What this supersedes, and why

- **ADR-071: "Giving the server that key would be a security-posture decision — a new secret, a wider blast radius — and is not taken
  here."** and **ADR-074: "The Supabase user stays. The server holds no service-role key … so the operator deletes it in the
  dashboard."** → **reversed for the two request routes.** *Why:* the decision is now taken, on the reasoning above.
- **`deploy:cloudrun` runbook step 2: `mk SUPABASE_KEY <the service_role key — server-side only, NEVER a client>`** → **corrected to the
  publishable key**, with `SUPABASE_SECRET_KEY` (a secret key) added beside it. *Why:* the line contradicted ADR-071/074, jZen's own Taskfile
  ("<publishable/anon key>") and how zen-identity uses the value. **Which key the persistent environment's `SUPABASE_KEY` actually holds is
  not known from this repository** (ADR-021 keeps environment facts out of it); `docs/persistent-environment.md` section 3 says how to check
  and correct it before the next deploy.
- **`docs/privacy-policy.md` "What deletion does not remove": "Your sign-in with the identity provider … signing in again with it starts an
  empty account"** → **replaced.** Deletion now lists the sign-in among what goes, and says that a failure deletes nothing. The section keeps
  the one case left open: dormancy. The in-app strings `privacyPolicyLimits` and `privacyEraseBody` (en/uk/pl) change with it.
- **`docs/persistent-environment.md`: "Delete the user in the Supabase dashboard … the half the server cannot do"** → **removed** for both
  request routes.

### What this does not do

- **Dormancy erasure still leaves the Supabase user.** The framework anonymises a batch of accounts in one transaction and fires
  `UserAnonymised` inside it. A GoTrue call in Prudent's observer would roll back the whole batch when one person's call fails, and the
  oldest-first order would put that person in every later batch, so nobody would ever be erased again. Doing it properly needs a
  per-account hook or a separate sweep. The policy and the operator doc say the operator deletes those users by hand.
- **No session is revoked.** The caller's access token stays valid until it expires; the client signs out on success, as before.
- **Not tried against a hosted Supabase project.** Both key styles were measured against the local stack only.

### Consequence

- `SignInRecordErasureTest` (13 cases), against `FakeGoTrueAdmin` (a test-only resource the test instance serves), covers:
  - what both routes send;
  - 404 as success;
  - 401/403/500/503 as 503, with every row and the profile untouched;
  - a retry that succeeds;
  - a refused confirmation, an unknown id and the operator's own id never reaching Supabase;
  - the key never reaching the log.
- `SignInRecordUnreachableTest` covers a Supabase with nothing listening.
- `SupabaseKeysTest` covers the boot check:
  - a serving `%prod` boot refuses a missing key, a legacy JWT, or a secret key in `SUPABASE_KEY`, and the message never repeats a key;
  - the migration job and the other profiles do not check;
  - an erasure without an `sb_secret_` key is refused before anything is sent.
- **Verified by breaking it:** with the call removed from `PrivacyResource`, 8 of the 13 fail. The existing privacy classes (operator 11,
  erasure 10, coverage 4) are green with the change.
- `client/integration_test/e2e_test.dart` gains the real-Supabase proof, run by `task test:e2e`, which now runs the server on the stack's
  publishable key and exports its secret key as `SUPABASE_SECRET_KEY`: it registers a person, shows the credentials work, erases them through the API and
  requires that signing in again fails. `test:native` gives the serving container the local key, and only the serving container.
- `scripts/test_public_config.py` checks:
  - ten secrets;
  - the key on the service;
  - the key absent from the migration job;
  - the key not part of `SECRETS`.

  `scripts/test_deploy_origin_tasks.py` checks that the `verify:deploy` check passes, and fails when the key is unbound or a plain value.
- **Run green on 2026-10-24:** `task test:server` 780/780 (on `-Dquarkus.http.test-port=18181`, because another project held 8081);
  `task zen:test:client` 364/364 (`privacy_screen_test.dart` also under every `ZEN_PLATFORM`); `task test:e2e` 7/7 against the local
  Supabase on its publishable and secret keys, including the erasure case; both script suites;
  `verify:controls`, `verify:boundaries`, `verify:reflection`. `task generate` changed only the two erasure routes' descriptions and
  their new 503 in `admin/src/api/schema.generated.ts`. `task test:native` was not run.
- **Not verified:** a deployed service. The persistent environment has neither the new secret nor a known-correct `SUPABASE_KEY`, and its
  next `deploy:cloudrun` fails until `SUPABASE_SECRET_KEY` exists. `task zen:run:server` (jZen's) does not export the key, so a local
  erasure under it answers 503 unless `SUPABASE_SECRET_KEY` is exported first.

---

## ADR-074 — An operator erases a person's data through an admin-only route, with the same deletion the person's own request runs

**Date:** 2026-10-24. **Status:** accepted. **Refines:** ADR-071. **Closes:** jlogicsoftware/prudent#172.

### Decision

- **`POST /api/v1/admin/privacy/users/{userId}/erase`** (`OperatorErasureResource`) erases one person's Prudent data without their session. It is
  `@RolesAllowed(admin)` — the gate the framework's `AdminUserResource` uses, resolved by `RoleAugmentor` from `users.role` on every request and
  never from the token. No session is 401, any other role 403, both before the method runs and with nothing deleted.
- **It is the same deletion.** `PrudentDataEraser` then `PrudentIdentityAnonymiser`, in one transaction, so a failure half-way leaves the person as
  they were and the operator route and the self-service route cannot disagree about what a person's data is. `PrivacyCoverageTest`'s guarantee
  therefore covers both. The typed-address confirmation of `POST /api/v1/privacy/erase` is not carried over: its purpose is to make the *person* type
  something only they would know. The operator's counterpart is that the full user id must be spelled out in the path.
- **Answers.** 204 on success and on repeating it for an already erased person (nothing left to delete is not an error, as for the eraser itself);
  404 for an id that is not a UUID or under which Prudent holds neither a profile nor any row (a typo and a stranger look the same); 400 for the
  caller's own id. Data with no profile row left behind it is still erased, since "cannot sign in" is when a profile may be missing.
- **An operator does not erase themselves here.** The self-service route exists for that, with its confirmation; a mistyped id must not be able to
  remove the profile that grants the access needed to repair it.
- **Logging.** The eraser's line (opaque id, row counts) and one line from the route (the person's id and the operator's id). Never an address, name or
  title; `OperatorErasureTest` asserts that on a person with a row in every table.
- **No new credential.** A shared token like the job trigger's would be a standing secret that erases any person on possession; an admin session is
  attributable (the operator's id is logged), revocable (set `role` back to `user`; effective at the next request) and already how Prudent's
  operators reach the admin panel. The cost is that calling it needs a browser session and a CSRF header, which `docs/persistent-environment.md` spells out.

### What this does not do

- **The Supabase user stays.** The server holds no service-role key (ADR-071, jZen ADR-007/008), so the operator deletes it in the dashboard. Still open from
  ADR-071: removing that record from the server.
- **No admin-panel button.** The route is in the OpenAPI contract and so in the panel's generated schema, but nothing in `admin/` calls it.

### What this supersedes, and why

- **`docs/privacy-policy.md` "If you cannot sign in": "An operator-initiated erasure of a person's Prudent data is **not built**"** → **replaced.**
  *Why:* it is built; the section now says the operator erases on request and that the Supabase record is deleted as well.

### Consequence

`OperatorErasureTest` (11 cases, both transports for the main one): every `user_id` table (discovered from the schema) empty for the person, the
operator's rows unchanged, the profile anonymised in the way the framework's `isAnonymised` accepts, 401/403/404/400 with nothing deleted, repeating
it, an orphaned row erased, and the log. **Not verified:** the route against a deployed service (the console recipe in
`docs/persistent-environment.md` has not been run there), and that `RoleAugmentor` grants `admin` from the `users` table for this route (the suite mints
the role with `@TestSecurity`, as jZen's admin suites do; the augmentor path is proven upstream by `RoleAugmentorTest`).

---

## ADR-073 — A dormant account is now warned by mail, and only a warning the relay accepted moves it toward erasure

**Date:** 2026-10-23. **Status:** accepted. **Refines:** ADR-019, ADR-021, ADR-022, ADR-071. **Follows:** jlogicsoftware/prudent#48.

### Decision

- **`DormancyWarningMailer` observes `AccountDeletionWarning`** and sends the first and the final warning through `zen-email`'s
  `EmailService`. It calls `receipt().confirm()` **only when `send` returned `true`** — the relay accepted the message — and on nothing
  else, so an undelivered warning leaves the account where it is and it is found again at the next cycle (the framework's own
  ordering, ADR-008 upstream). That one condition is the whole of "confirms the receipt only on real delivery"; it is the reason the
  cascade of ADR-019 and ADR-022 had never been reachable, and it is what a reviewer should read first.
- **The wording is Prudent's** (`RetentionMessages` and its `uk` and `pl` variants for the subjects, six Qute templates under
  `templates/mail/` for the bodies). It carries the recipient's own address, the days left, how to keep the data (sign in) and how to take a
  copy first (Settings → Privacy and data). **It carries nothing from the ledger**: the event holds none, and a test seeds every table and
  asserts no account, category, goal or currency name appears. The Ukrainian and Polish text says "days left: N" rather than "in N days",
  because both decline the noun by the number and the number is configuration. Template commentary is a Qute comment `{! !}`, not an HTML
  one — jZen's reference templates use HTML comments, which are delivered to the recipient with the class names in them.
- **The recipient is named in logs by user id only.** `LocalizedEmail.recipientRef` is the user id, which is all `EmailService` logs, and the
  observer's own lines use it too. A test with a relay that always fails asserts that the id is in the log and neither the address nor its
  local part is.
- **Subject and body are chosen in the same language.** `EmailService` resolves the body's template against `zen.i18n.supported`; the
  observer resolves the subject against the same property, because the framework's one-argument `ZenLocales.resolve` knows only `en` and `uk`
  and would send a Polish body under an English subject. That repeats a resolution the framework does not expose (recorded in
  `docs/jzen/README.md`), and a test covers `en`, `uk`, `pl`, `pl-PL`, an unsupported tag and none.
- **Configuration, and what is secret.** `%prod` has no default for any mail setting, so a service without a sender does not start. `SMTP_HOST`,
  `SMTP_PORT` (587, STARTTLS required) and `SMTP_FROM` are public and are plain environment variables, checked by `scripts/public_config.sh`
  (a bare host name, one address, a port number) and derived nowhere; `SMTP_USERNAME` and `SMTP_PASSWORD` are secrets, which makes **nine**
  (ADR-070 had seven). `%dev` and `%test` use the mock mailer and a `prudent.invalid` sender, the reserved TLD of ADR-021. No relay, host or
  sender is named in this repository.
- **The deploy.** `deploy:cloudrun` requires `SMTP_HOST` and `SMTP_FROM`, passes the three public values as `--set-env-vars` and the two
  secrets in `--set-secrets` on the migration job **and** the service. The job holds credentials it never uses: the packaged image fails
  configuration validation without them, and defaulting them away would let the service boot without a sender, which is the failure this
  decision exists to end. `verify:deploy` fails when the running service lacks any of the three values as a plain value or either secret as a
  Secret Manager reference. Its service read now takes a third column (`valueFrom.secretKeyRef.name`) to tell a bound secret from a literal.
- **`PrivacyRetentionStatementTest` is replaced.** It pinned the absence of the behaviour and was written to go red the day this landed.
  `PrivacyDormancyErasureTest` drives the cycle the way it runs: a dormant user with a row in every table, warned, warned again, anonymised,
  with the stamps aged between cycles; the windows are read from the framework's configuration, not repeated. It then requires every table
  with a `user_id` (discovered from the schema, as in `PrivacyCoverageTest`) to be empty for that user and another user's rows untouched. It
  also drives the **real sign-in path** (`UserStore.upsertOnLogin`) to show a returning user's countdown is cleared and that they are neither
  warned again nor erased, and it reads `docs/privacy-policy.md` to require that the windows the policy states are the ones configured.
  `PrivacyDormancyUnreachableMailerTest` runs the real observer over a relay that always throws: nothing is stamped, nothing advances over four
  cycles, nothing is erased. Verified by breaking it: with `if (sent)` replaced by `if (true)` two of its three tests fail.
- **`docs/privacy-policy.md` "How long it is kept" is rewritten** to the schedule (330 days, +23, +7), the two warnings, the cancel-by-signing-in
  rule, and the limit of "warned": the relay accepted it, which is not the same as read. The mail relay is added to the processors.

### What the build found

- **Signing in already resets the countdown.** `UserStore.upsertOnLogin` clears both warning stamps, so a person who returns after the first
  warning is not erased; this was not assumed but exercised through that method.
- **Delivery is the relay's acceptance, not an inbox.** A bounce, a spam filter or an unread message is invisible to the framework and so to
  Prudent. A person whose address no longer receives mail is *safe* in one direction and not in the other: if the relay accepts and the
  mailbox is dead, the schedule still advances. That is the framework's design (a delivered warning is the most it can ask) and the policy
  says it in those words rather than "you will be told".
- **A refusing address never erases.** An account whose address the relay rejects stays at its first step indefinitely; its data is kept. The
  policy says so. It is the safe direction, and it means the operator may hold data for people who cannot be reached.
- **`EmailService` logs `e.toString()` on failure**, and an SMTP rejection's message commonly names the recipient, so an address can reach a
  log however carefully `recipientRef` is set. Prudent cannot filter it; it is recorded for jZen.
- **The existing persistent environment has no relay.** Its next `deploy:cloudrun` fails on the missing `SMTP_HOST`, which is the intent.
  `docs/persistent-environment.md` section 3 says what to create first.

### What this supersedes, and why

- **ADR-071's "the dormancy route … has never been able to run" and its statement that nothing expires** → **superseded for the code and the
  policy**, and still true of any deployment without a relay. *Why:* the observer exists, and the policy now describes the schedule.
  ADR-071's finding is kept as written; it was true on the day.
- **ADR-021's "fewer than jZen's fourteen because Prudent assembles no `zen-email`"** → **no longer true.** Prudent assembles it for this one
  message, and sends no other mail (Supabase sends the sign-in mail).
- **`PrivacyRetentionStatementTest`** → deleted, replaced as above.

### Consequence

`task test:server` **748/748** after merging #49 (the dormancy classes: erasure 5, unreachable relay 3; 717 before the merge). The packaged
server in `%prod` boots (migrate-only) with the mail settings and refuses to start without them, run against a throwaway Postgres.
`scripts/test_public_config.py` and `scripts/test_deploy_origin_tasks.py` cover the new inputs, the secret and literal lists on both `gcloud` calls
and the two new `verify:deploy` checks.

**Not done, and named rather than glossed over:** no message has been sent through a real relay, so authentication, the sender domain (SPF and
DKIM) and delivery to a real inbox are unproven — the first real warning is the first proof, and `docs/persistent-environment.md` says how to
produce one safely. The native image has not been built with the mailer and the Qute bundles (`task test:native` does not send a mail). The
Cloud Scheduler entry and the mail relay are two separate things that must both exist; `verify:deploy` checks both and proves neither works.
Still open from ADR-071: an operator-initiated erasure, removing the Supabase record from the server, and the framework's missing
anonymise-one-account entry point.

---
## ADR-072 — Readiness is a separate probe that asks the database; an unhandled failure is logged as a request id, a handler and a code, never as an exception

**Date:** 2026-10-23. **Status:** accepted. **Refines:** ADR-021, ADR-023. **Closes:** jlogicsoftware/prudent#49.

### Decision

- **`GET /api/v1/health/ready`** answers 200 with the same `HealthStatus` as `/api/v1/health` when a connection can be taken and
  `SELECT 1` runs inside two seconds, and **503 with a `ZenError` (`code: unavailable`, a fixed message)** when it cannot.
  `/api/v1/health` stays a liveness answer that touches nothing. It is anonymous like the first, and reads no table: it proves the
  service reaches its database, not anything about the data. `verify:deploy` now checks it.
- **Every response carries `X-Request-ID`.** A caller's value is kept only if it is 1-64 characters of `[A-Za-z0-9._-]`; anything else
  is replaced by a UUID, because the id is written into a log line and a newline would forge one. The header was already in the CORS
  allow and expose lists; nothing produced it.
- **An exception no other mapper claims is logged as one line**: `request=<id> method=<verb> handler=<Class.method> status=<n>
  failure=<exception classes, outermost to root> sqlstate=<code> at=<first prudent.* frame of the root cause>`. No exception message, no
  path, no query string, no stack trace, no user id. The caller still receives the fixed `internal_error` `ZenError`. The same line
  (without request fields) is written when the readiness probe fails. A `WebApplicationException` keeps its own response and is logged
  only when its status is 5xx.
- `UnhandledExceptionMapper` is Prudent's own `ExceptionMapper<Throwable>` and takes precedence over `zen-transport`'s, which is
  registered at the lowest priority so that an application's wins.

### What this supersedes, and why

- **jZen's `ZenExceptionMapper`, which logs the throwable** (`LOG.error("...", exception)`) → **replaced inside Prudent, not changed
  upstream.** *Why:* a stack trace prints every exception's message, and Postgres puts the failing row, amounts included, in the message of
  a NOT NULL or CHECK violation. Writing that to a log is leaking financial data to wherever logs go. The framework's answer to the caller
  is right and is kept; only what is written down differs. If the framework adopts the same line, this class is deleted.
- **A readiness check folded into `/health`** (considered) → **not done.** *Why:* a platform restarts a process whose liveness fails; a
  database that is briefly away is not a reason to restart anything, and every earlier consumer (`test:e2e`, the deploy's readiness wait,
  `check_origin_serves.sh`) polls `/health` to learn the process is up.

### Consequence

- **Diagnosing a report:** take `X-Request-ID` from the failing response (browser network panel or `curl -i`) and search the service's
  logs for `request=<id>`; the line names the handler, the exception classes, the SQLSTATE and the line in Prudent's code.
- **Not done, deliberately:** no error-tracking service, no metrics, and no request id in the client's UI. Sending failures to a third
  party would need a decision about what may leave the server; the log line is written to be safe to forward, which keeps that door open.
  The id is not shown to the user, so a report from a person still needs a developer to find the request.
- **Verified:** unit tests for the line (a Postgres-style message carrying `12345.67` and a category name appears in neither the line nor
  the response), the id's sanitising, the probe's three outcomes; `@QuarkusTest` for readiness in both transport modes with and without
  the database, for the request id on success and failure, and for the logged line from a real request including that the query string
  does not reach it. **Not verified:** the line in Cloud Logging; `verify:deploy` against a live service with the new check (the service
  must be redeployed first); the native image (nothing here uses reflection, but `test:native` was not run for this change).

## ADR-071 — A person can take a copy of their data and erase it themselves; erasure is one shared deletion, and the dormancy route that was meant to back it up has never been able to run

**Date:** 2026-10-23. **Status:** accepted. **Refines:** ADR-019, ADR-022. **Closes:** jlogicsoftware/prudent#48. **Addresses:** jlogicsoftware/prudent#29.

### Decision

- **`GET /api/v1/privacy/export`** answers one `DataExport` (`proto/prudent/v1/privacy.proto`): the profile, the settings and **every**
  account, category, record, plan, occurrence, budget, carry-over reset, goal and envelope entry the caller owns, **in any lifecycle
  state**. It reuses the resources' mappers, so a record in an export is the record the API serves; it does not reuse their list queries,
  several of which narrow by state or period and would have made "my data" mean "my data minus what the screens show". Calculated
  figures (balances, budget summaries, goal progress, analytics) are not exported — they are computed from the rest on every read
  (ADR-044, ADR-050, ADR-052). It is canonical proto3 JSON by default, so it is readable, and `Cache-Control: no-store`.
- **`POST /api/v1/privacy/erase`** deletes everything the caller owns and anonymises their `users` row, **in one transaction**. It is
  refused (400, nothing deleted) unless the body repeats the account's sign-in address — a route that deletes a person's financial
  history must not be one stray request away. The deletion is **`PrudentDataEraser`**, extracted from `PrudentRetentionCleanup`, which
  now delegates to it: two routes end in the same code, so they cannot disagree about which tables hold a person's data.
- **The proof is derived from the schema, not from a list.** `PrivacyCoverageTest` reads `information_schema` for every table with a
  `user_id` column and requires each to be seeded, present in the export and empty after an erasure, and another user's rows in it
  untouched. A table added tomorrow fails the suite until the exporter and the eraser know it. Verified by breaking both: with
  `SettingsEntity.delete` removed from the eraser and `setSettings` removed from the exporter, two tests fail and name
  `prudent_settings`. What it cannot see is per-user data in a table with no `user_id` (today only `prudent_account_balance`, which is
  checked for orphans explicitly).
- **The profile row is anonymised by Prudent, copying the framework's shape** (`anon_<id>@deleted.invalid`, "Deleted User", names
  cleared), because `UserRetentionService` offers only a batch anonymiser of accounts that ran out their warnings and keeps its
  constants package-private. A copied convention is the coupling ADR-022 retired, so it is **asserted against the framework** rather
  than against our own literal: `PrivacyErasureTest` requires `UserRetentionService.isAnonymised` to accept the row.
- **The client** gets a "Privacy and data" detail of Settings: the three-paragraph summary, **Copy my data** (readable JSON to the
  clipboard) and **Delete my data** (an adaptive presentation asking for the address). After an accepted erasure the device forgets
  too: the provider caches are dropped, every pending reminder notification is cancelled by reconciling to "nothing wanted" (ADR-057),
  and the session is ended. The clipboard is the export's only destination for now: a file save needs a platform package per target
  that the app does not otherwise carry, and the clipboard behaves the same on all six.
- **`docs/privacy-policy.md` is the policy**, written to be true of this code, and each of its claims has a test named at its foot.

### Two findings the policy could not be written around

- **Dormancy erasure has never been able to run in Prudent.** The framework anonymises an account only after a warning was *confirmed
  delivered*, by an observer of `AccountDeletionWarning`; Prudent has none (it assembles no `zen-email`, ADR-021), so no warning is ever
  confirmed and no account ever advances. ADR-019 and ADR-022 describe the cascade that follows anonymisation, and
  `PrudentRetentionCleanupTest` proves it — by seeding a delivered final warning ten years old, which is why it could not notice. The
  policy therefore says **nothing expires on its own**, and `PrivacyRetentionStatementTest` pins that, so the day warnings are wired it
  goes red and names the paragraph that has become wrong. Wiring them is open work, not done here: it needs a mail sender and its
  secrets, a deliberate deployment change.
- **Erasure does not reach Supabase's `auth.users`.** That table holds the sign-in address and password hash, is Supabase's, and
  needs a service-role key this server deliberately does not hold (jZen ADR-007, ADR-008, finding F4 of its security review). Signing in
  again after an erasure starts an empty account. The policy says so in the section headed "What deletion does not remove", and tells
  the operator to delete the Supabase user on a request. Giving the server that key would be a security-posture decision — a new
  secret, a wider blast radius — and is **not** taken here.

### What this supersedes, and why

- **ADR-022's reading that the erasure path is "implemented properly"** → **narrowed.** *Why:* the cascade is right and tested; what
  triggers it for a dormant account is not wired. That sentence was true of the code and false of the behaviour.
- **`PrudentRetentionCleanup` owning the list of tables** → **moved to `PrudentDataEraser`.** *Why:* a second erasure route would
  otherwise need a second copy.

### Consequence

`task test:server` **710/710** (the privacy classes: export 7, erasure 10, coverage 4, retention statement 1, retention cascade 3);
`task zen:test:client` **364/364**; `verify:controls`, `verify:reflection` (the three new messages are registered for native),
`verify:boundaries`, `zen:verify:widget-files` and the admin typecheck green; regenerating the contract a second time changes nothing.
`verify:contracts` itself compares with what is committed, so it can only pass once the generated files are. Not run: the native image
and a deployed environment. `GET /api/v1/privacy/export` serialises most of the API's messages in one response and #159 is still open,
so **a deployed JSON read of the export is the check this decision does not have.**

**Still open, named rather than glossed over:** an operator-initiated erasure for a person who cannot sign in; warning mail so the
dormancy cycle can run; removing the Supabase record from the server instead of by hand; a file save for the export; and the framework
gap that `UserRetentionService` cannot anonymise one account on request (recorded in `docs/jzen/README.md`, not yet filed).

---

## ADR-070 — The five public configuration values are plain environment variables, not secrets; a service made before the change is rebound once

**Date:** 2026-10-23. **Status:** accepted. **Refines:** ADR-021, ADR-067. **Closes:** jlogicsoftware/prudent#166. **Addresses:** jlogicsoftware/prudent#46.

### Decision

- **`SUPABASE_URL`, `SITE_URL`, `CORS_ORIGINS`, `AUTH_REDIRECT_URI` and `AUTH_REDIRECT_URIS` leave Secret Manager.** They are public by
  construction (the origin is in the bundle, the redirect addresses are in the app and in the identity provider's allowlist), so a
  secret implied a confidentiality they do not have and was billed per version per month. `deploy:cloudrun` passes them to **both** the
  migration job and the service as `--set-env-vars` literals. **Seven genuine secrets remain:** `SUPABASE_KEY`, `DB_URL`,
  `DB_USERNAME`, `DB_PASSWORD`, `ZEN_JOBS_TRIGGER_TOKEN`, and, for the service only, `APP_DB_USERNAME` and `APP_DB_PASSWORD`.
- **Three of the five are derived, two are supplied.** `SITE_URL` and `CORS_ORIGINS` are `WEB_API_URL`, and `AUTH_REDIRECT_URI` is
  `WEB_API_URL/auth/callback`; `SUPABASE_URL` and `AUTH_REDIRECT_URIS` are exported in the operator's shell like `WEB_API_URL` and are
  refused when missing, naming which. `scripts/public_config.sh` does this and checks the shapes (an https `SUPABASE_URL`, no comma,
  `@` or whitespace where it would split a value, a scheme on every redirect entry, no empty list entry). It runs in the preflight,
  before ten minutes of build, and again where the values are used. A derived value exported as something else is refused rather than
  silently overridden. `AUTH_REDIRECT_URIS` has its own flag with the `^@^` delimiter: a comma list whose entries contain `:`.
- **The origin checks no longer read a secret.** `deploy:check-origin-config` keeps only the deterministic-host check; there is nothing
  left to compare because `SITE_URL` cannot disagree with `WEB_API_URL`. `verify:deploy`, with no URL given, reads `SITE_URL` from the
  **running service's configuration** (it now needs `GCP_REGION` and `SERVICE_NAME` with `GCP_PROJECT`), and when it can read the
  service it **fails** if any of the five is absent or still a Secret Manager reference, or if the service's `SITE_URL` is not the
  bundle's origin. Without a service name that part is announced as SKIP.
- **The rebind of an environment made before this change is a documented procedure, not a task:** remove the five secret references
  from the job, then from the service, then run `deploy:cloudrun`; the secrets are deleted afterwards. It is in
  `docs/persistent-environment.md` section 3. Nothing else needs it, because a new environment never holds the secrets.

### What this supersedes, and why

- **"The twelve secrets"** / **"Eleven secrets ... `SUPABASE_URL`, ..., `SITE_URL`, `AUTH_REDIRECT_URI`, `AUTH_REDIRECT_URIS`,
  `CORS_ORIGINS`"** (ADR-021, ADR-065; the runbook in `deploy:cloudrun --summary` step 2; `docs/persistent-environment.md` section 3)
  → **changed.** *Why:* seven are secrets; the rest are configuration. The runbook, the document and the deployer-roles paragraph
  (Secret Accessor on four secrets now, and a role that reads a Cloud Run service) were rewritten in this change.
- **"`WEB_API_URL` ... must equal the `SITE_URL` secret" and "`verify:deploy` ... reads the `SITE_URL` secret"** (ADR-067) →
  **replaced.** *Why:* the first became true by construction; the second is now the running service's variable, which is a
  stronger fact (it is what the process was started with) and needs no secret read.
- **jZen's "the packaged image fails config validation without them, on the job as much as on the service, so the intermediate revision
  never serves"** (jZen `Taskfile.yml` comment; jZen #90's later comment) → **not borne out here.** *Why:* see the rehearsal below.
- **BugEater's "one call with `--remove-secrets` plus `--update-env-vars` works"** (the perf audit, section 5.32) → **wrong for this
  gcloud and Cloud Run**, as jZen #90 had already corrected.

### Consequence

**Rehearsed before touching the live service**, on a scratch Cloud Run service in the same project, with the existing secrets and a
sample image (deleted afterwards; `gcloud run services list` shows only `prudent`): `gcloud run deploy --set-env-vars ... --set-secrets`
without the names fails with `Cannot update environment variable [SITE_URL] to string literal because it has already been set with a
different type`; so does `services update --remove-secrets=... --update-env-vars=...` in one call; `--remove-secrets` in one call and
`--update-env-vars` in the next succeeds. This confirms jZen #90 and refutes BugEater's note.

**Done on the persistent environment, 2026-10-23:** the five references removed from the job and the service, then
`deploy:cloudrun` (exit 0; repeated `--set-env-vars` flags in one call accumulate, as jZen's deploy assumes), then `verify:deploy`
(16 of 16, including the five plain values and `SITE_URL` equal to the bundle's origin). `gcloud run services describe` and
`jobs describe` show the five as plain values and the remaining secrets as references. The owner signed in from a phone and the screens
loaded. Only then were the five secrets deleted: **`gcloud secrets list` showed 12 before and 7 after**, exactly the five names gone,
and `verify:deploy` stayed green.

**A finding that contradicts the plan.** The revision created by removing the secret references **started and took all the traffic**
(`/health` answered 200) although it lacked the five values; the service ran in that state until the deploy replaced it, about eleven
minutes. So the intermediate step is not protected by a failing startup, and a sign-in during that window was not tried, so what it
would have done is unknown. For this environment's test data that was acceptable and was accepted. For a service with users,
`--no-traffic` on the removal would keep the old revision serving; **that was not tried.** `docs/persistent-environment.md` says so.

**Verified:** `scripts/test_public_config.py` (20 tests: what the script accepts, refuses and derives, and the shape of
`deploy:cloudrun`'s two `gcloud run` calls — seven secrets, five literals on the job and the service) and the rewritten
`scripts/test_deploy_origin_tasks.py` (29 tests, including `verify:deploy` failing on a public value that is a secret reference, absent,
or for another origin; the stub `gcloud` has no `secrets` case, so a call to one fails a test), both through `task test:deploy-origin`
and on Python 3.9. Six mutations were planted — `SITE_URL` back in the secret list, a literal dropped from the job, the https check
removed, the derived-value comparison removed, a public-value failure not counted, the `SITE_URL`-equals-origin check removed — and
each turns a test red.

**Not claimed:** a saving. Secret Manager bills per version, the account's older projects had already used the free versions, and the
estimate of about $0.30 a month for the five came from BugEater's reading of the price catalogue, not from this account's invoice.
It stays an estimate until an invoice shows it. **Not proven:** the `--no-traffic` variant; a sign-in during the window above; the
native iPhone build and `prudent://auth-callback` (#155); any backup or restore (#47). The service is still handed the DDL
credentials (#156).

## ADR-069 — The persistent environment exists on `*.run.app`; its first sign-in found that no Prudent message was registered for the native image

**Date:** 2026-10-22. **Status:** accepted. **Refines:** ADR-068. **Addresses:** jlogicsoftware/prudent#46 (the environment exists as a proof of concept; #47, #155 and #156 stay open); **closes** jlogicsoftware/prudent#158.

### Decision

- **The environment was created**, by the runbook (`task deploy:cloudrun`) on the owner's go, with no domain: the owner chose
  the proven deterministic `*.run.app` host, "we are only testing". The custom-subdomain attempt in ADR-068 is therefore **not
  tried**; a later move to a domain is a new origin, a rebuild and a new ADR. As ADR-021 requires, no project id, number, host,
  reference or credential is recorded here or anywhere in the repository; they live in the owner's password manager and the cloud.
- **Every Prudent proto message is registered for native-image reflection**, in `PrudentProtoReflection` (55 messages from
  `proto/prudent/v1`), with `task verify:reflection` as a gate in CI that fails on a message that is declared but not registered, or
  registered but no longer declared (`scripts/verify_proto_reflection.py`, tests that plant each failure and an empty scope).
- **Four follow-ups were filed rather than fixed in this change:** #159 (prove an authenticated JSON read in the native build and
  after a deploy), #160 (a screen that cannot load prints the raw exception, English only, no retry), #161 (the e-mail field of
  jZen's `zen_ui_identity` validates the untrimmed text although the submit trims it, so a leading space reads as invalid; the code
  is jZen's) and, from before, #155 and #156.

### What happened, in order

1. Provisioning followed `docs/persistent-environment.md` section 8: a GCP project with billing and the four APIs, an Artifact
   Registry repository, the runtime service account, the Supabase Free project in a European region, twelve secrets with the database
   password stored first, `deploy:cloudrun` (exit 0, origin answers as `prudent-server`), the Scheduler job, and `verify:deploy` (10
   of 10). The Supabase project was created through the Management API with the password read from Secret Manager, not through the
   CLI, so it never appeared on a command line; the Site URL and Redirect URLs were set through its `config/auth` endpoint.
2. The owner registered from a phone, the confirmation mail arrived (Supabase's default sender, to the organisation member), and the
   link was confirmed from a desktop. **That is the first real sign-in link ever followed**, and it worked.
3. Every screen after sign-in returned HTTP 500. The service log: `NoSuchMethodException: prudent.proto.v1.Settings.getMainCurrency()`
   and the same for `ListRemindersResponse.getRemindersList`. Canonical proto3 JSON reads accessors by reflection and a native image
   strips them. jZen registers its own messages (`zen.transport.ZenProtoReflection`); nothing registered Prudent's.
4. After the fix and a redeploy (`deploy:cloudrun` exit 0, `verify:deploy` 10 of 10, no new errors in the service log), the owner
   signed in from a phone browser and a desktop browser and the screens loaded.

### What this supersedes, and why

- **"A subdomain of a domain the owner already holds ... is tried through a Cloud Run domain mapping; if it does not work ... the
  deterministic `*.run.app` host ... is the fallback"** (ADR-068, Address) → **refined.** *Why:* the owner decided not to use a domain
  for now; the fallback is the route taken and the subdomain is untried, not failed.
- **"No persistent environment has ever been created ... nothing is running now"** (CLAUDE.md, current state and working agreement)
  → **changed.** *Why:* one is running. The two paragraphs were rewritten in this change, and still record that it is a proof of
  concept with no backups.
- **`task verify:endpoints` and `verify:deploy` as the proof a native build serves the product** (the Taskfile summaries) → **reframed.**
  *Why:* they read `/health` and the 401 paths, which are jZen's own messages, so they stayed green on a build that served no signed-in
  screen. They prove the process, the routes' guards and the bundle; they do not prove Prudent's messages serialise (#159).

### Consequence

**Verified:** `task verify:reflection` and its five tests pass; the server compiles; the redeploy and `verify:deploy` above; the
owner's sign-in and screen loading, **in a browser only**.

**Learned while provisioning, and recorded in the document rather than re-discovered:** a GCP project display name must not contain
parentheses; the registry answers `PERMISSION_DENIED` for about a minute on a new project (two tries) and the new runtime service
account was not yet visible to IAM on the first binding (one retry); the Management API reports only the transaction pooler (6543) for
the project, and the session pooler on 5432 of the same host is what the migration and the runtime login used, as the runbook says.

**Not proven:** the native iPhone build and `prudent://auth-callback` (#155); that a record created in the browser is read back on
another device (the owner reported the screens load, not that data round-trips); whether the hourly Scheduler call keeps the Free
Supabase project from pausing; a custom domain; any backup or restore (#47); that a native binary serialises a message, other than by
this one use (#159). The service is still handed the DDL credentials (#156). **Do not enter real finances.**

---

## ADR-068 — The persistent environment is a proof of concept: Free Supabase with no backups, one Owner, the web app first, and a custom subdomain tried before falling back to `*.run.app`

**Date:** 2026-10-22. **Status:** accepted. **Refines:** ADR-020, ADR-021, ADR-065. **Addresses:** jlogicsoftware/prudent#46 — the decisions and the preparation; the environment itself is not created.

### Decision

The owner decided what #46 builds. As ADR-021 requires, no region, domain, project id or reference is
recorded here; they live in the owner's password manager and the cloud.

- **Purpose and condition.** A proof of concept the owner uses from a phone's browser. It holds test
  data. **Real finances are not entered** until a backup mechanism exists and a restore has been done
  once; `docs/persistent-environment.md` states this at the top.
- **Supabase: Free, no backups, the risk accepted.** Free has none, a pause is possible, and deleting
  the project deletes everything. The persistent project takes the account's second active Free slot,
  so the older paused project must stay paused. This does **not** satisfy #47 and does not close it.
- **One Owner.** No second Owner and no project lien are required. A lost or locked account is a lost
  environment; accepted.
- **Region.** One European region near the owner, the same continent for GCP and Supabase, chosen once
  at creation (the service host contains it, so changing it later changes the origin).
- **Address.** A subdomain of a domain the owner already holds, with DNS at Cloudflare, is **tried**
  through a Cloud Run domain mapping with the record set to DNS only; if it does not work within a
  reasonable wait the deterministic `*.run.app` host, which is proven, is the fallback. The first deploy
  on the custom origin is expected to end "DEPLOY NOT ACCEPTED" because the name does not resolve yet;
  the cheap re-probe `SERVICE_URL=<origin> task verify:deploy` then shows whether it works, with no
  rebuild.
- **Project id.** The bare name is almost certainly taken; the id carries an owner-specific suffix.
- **Sign-in mail.** Supabase's default sender (the owner, a member of the Supabase organisation, is the
  one user); the Site URL and Redirect URLs are set before the first registration.
- **Management token.** Minted per provisioning session, revoked afterwards.
- **Recovery copies.** None; consistent with no backups.
- **Native iPhone build.** A separate issue (jlogicsoftware/prudent#155); the phone uses the web app first.

### What this supersedes, and why

- **The recommendations of `docs/persistent-environment.md` section 9** (written in the preparation
  of #46): Supabase Pro, a second Owner with a lien and a budget alert, custom SMTP, recovery dumps in a
  separate project, "stay on `*.run.app`" → **changed**, each to the owner's choice above. *Why:* the
  recommendations were for an environment that holds the owner's real finances; the owner decided this
  one does not, and a POC does not justify their cost. The document was rewritten to match.
- **"No persistent environment ... that is #46, and nothing is running now"** (CLAUDE.md) → **kept**,
  with a pointer to this entry: nothing is created.

### Consequence

Verified in this change, without the cloud: the preparation was code-reviewed, its eight findings were
fixed in the document (the deployer role list now names the five secrets the tasks read and
`resourcemanager.projects.get`; the Free-slot claim is corrected; the document no longer restates the
runbook's commands or secret table; the alpha component and the budget API are named), and the
provider facts below were read on 2026-10-22: Cloud Run domain mappings are **Preview**, "not
recommended for production services", and list a European region matching the decision; the base domain
must be verified for the Google account through Search Console; the certificate takes about 15 minutes
and up to 24 hours; Google warns that a CDN may intercept validation requests; Cloudflare documents
that a DNS-only record is not routed through its network.

**Not proven:** the domain mapping itself, that Cloudflare DNS-only is what makes it work, and the
single-native-build order (a first deploy that ends not accepted, then a mapping, then a re-probe); the
Supabase redirect list and the default sender, so **no real sign-in link has ever been followed**; the
pause behaviour of a Free project under the hourly scheduler call; and everything in the document's
"never done" list. Two things are deliberately left open: the running service is handed the DDL
credentials because `%prod.quarkus.flyway.username/password` have no default (to be settled before real
data), and a native iPhone build has no task (jlogicsoftware/prudent#156 and #155).

---

## ADR-067 — The deploy checks the origin the web bundle was built for before the build and after the service, and verifies it instead of Cloud Run's `status.url`

**Date:** 2026-10-22. **Status:** accepted. **Refines:** ADR-065, ADR-020. **Closes:** jlogicsoftware/prudent#151.

### Decision

The web bundle is compiled against `WEB_API_URL` and calls it for every API request. Cloud Run also
answers the service on `status.url`, a different host. The deploy now treats the bundle's origin as
a fact to check, at three points:

- **Before the build, in seconds** — `deploy:check-origin-config`, run by `deploy:cloudrun` right
  after its preflight. `WEB_API_URL` must be Cloud Run's deterministic host for the service,
  `https://SERVICE-PROJECT_NUMBER.REGION.run.app` (project number from `gcloud projects describe`),
  and must equal the `SITE_URL` secret. A typo or a wrong project number stops here and not after ten
  minutes of native build and a live revision. A deliberate other origin (a custom domain) needs
  `WEB_API_URL_ALLOW_OTHER=1`; the `SITE_URL` equality has no override.
- **After the service** — `deploy:accept-origin`, run last by `deploy:cloudrun`. It runs
  `scripts/check_origin_serves.sh` on `WEB_API_URL`: `/api/v1/health` must answer HTTP 200 **and** a
  body naming `prudent-server` (a bare 200 also comes from a reused host or a placeholder page), with
  retries for a cold start, no redirects followed. If it fails the task **exits non-zero** and the
  message gives two ways forward in order: re-run the same probe in seconds with
  `SERVICE_URL=$WEB_API_URL task verify:deploy` (the host may only be slow or not yet resolving), and
  rebuild with a different `WEB_API_URL` only if that keeps failing. On success it names `WEB_API_URL`
  as the origin to open and prints `status.url` as the alias it is; failing to read `status.url` is
  said and does not fail a deploy whose real check passed.
- **When verifying** — `verify:deploy` takes `SERVICE_URL`, else `WEB_API_URL`, else (with
  `GCP_PROJECT`) the `SITE_URL` secret, else stops; it never resolves `status.url`. The bundle's
  origin is always checked when known: when it is the URL under test the checks include that the
  health body names `prudent-server`; when `SERVICE_URL` names another host it is probed on its own;
  when it is not known it prints `SKIP`, never silence.

`task test:deploy-origin` runs two suites and CI runs it: `test_check_origin_serves.py` (the probe
script alone, 12 cases) and `test_deploy_origin_tasks.py` (22 cases), which run the real
`verify:deploy`, `deploy:accept-origin` and `deploy:check-origin-config` through `task` against
local servers playing a Prudent and a stub `gcloud`, and require the failing cases to fail.

### What this supersedes, and why

- **"BUT the 'Deployed:' line at the end of this task prints `status.url` … DIFFERENT form … Open
  that one, and pass it as SERVICE_URL to verify:deploy."** (the `deploy:cloudrun` summary, written
  in ADR-065) → **reversed.** *Why:* it told the operator to open the origin the task did not
  print, and the task printed the one the bundle does not call. A runbook that documents a defect
  in its own output is a defect.
- **"Pass SERVICE_URL, or GCP_PROJECT + GCP_REGION + SERVICE_NAME to resolve it."** (the
  `verify:deploy` summary) → **changed** to `SERVICE_URL`, `WEB_API_URL`, or `GCP_PROJECT` (read from
  the `SITE_URL` secret). *Why:* the resolved value was `status.url`, and every status-code assertion
  passes on either host, so the check was green for the wrong origin. The bundle's own
  `WEB_API_URL` is a compile-time fact that survives nowhere in the cloud; `SITE_URL` is the one
  place the same origin is recorded there.
- **ADR-066's "#151 … is still open" and ADR-065's "documented rather than fixed"** → **superseded in
  the code**, not edited: the log is append-only.

### Consequence

Verified, without the cloud:

- **The probe script alone**, 12 cases against local servers: serving host (exit 0), trailing slash,
  200 from something else (1), 404 (1), 500 (1), nothing listening (1), cold for two tries then
  serving (0), cold throughout (1, exactly the configured number of requests), redirect (1),
  malformed origin (1), no argument (1), and that the JSON transport header is sent.
- **The Taskfile glue through `task`**, 22 cases, including: `verify:deploy` with each of
  `WEB_API_URL` alone, nothing, `SERVICE_URL` alone (`SKIP`), a good alias with a bundle origin that
  never serves (fails), with one that answers 200 as something else (fails), the same origin given
  twice (checked once, not probed twice), and the origin read from the `SITE_URL` secret;
  `deploy:accept-origin` serving, with an unreadable `status.url`, never serving, and something
  else; `deploy:check-origin-config` for the deterministic host, a wrong host (naming the right one),
  the override, a `SITE_URL` that disagrees (with and without the override), an unreadable secret
  and project number, and a missing variable.
- **That these tests can fail.** Four deliberate breakages of the Taskfile were made and each made the
  suite go red: `deploy:accept-origin` swallowing the probe's exit code; `verify:deploy` dropping
  `fail=1` on the bundle probe; the `SITE_URL` comparison never failing; the wrong-host check no
  longer exiting. The fourth first survived — its test was rescued by the `SITE_URL` check — and the
  test was fixed so the first check stands alone.

- **A real, fresh environment** (a new GCP and Supabase project, torn down afterwards), by the
  tasks themselves:
  - `deploy:check-origin-config` against real `gcloud` and real secrets: a `WEB_API_URL` with a wrong
    project number fails in 0-2 s naming the host Cloud Run really serves; a custom origin without
    the override fails; with the override but a `SITE_URL` that differs it still fails (each exit
    201, go-task's wrapping of 1); the true deterministic host with a matching `SITE_URL` passes.
  - `task deploy:cloudrun`, **once**: exit 0 in 11 min 13 s, one revision serving 100%. The
    pre-build check passed, `>> runtime login` ran (ADR-066), and `>> origin check` saw
    `prudent-server` in the body from real Cloud Run — the one thing the script's tests could not
    show. Cloud Run's `status.url` was, as ADR-065 recorded, a different, hashed host, and the task
    named `WEB_API_URL` as the one to open and the alias as the alias.
  - `verify:deploy` three ways, all passing: from `WEB_API_URL` with the scheduler check; with
    `SERVICE_URL` set to the `status.url` alias (it printed the `NOTE`, probed the bundle's origin
    on its own, and passed); and with only `GCP_PROJECT`/`GCP_REGION`, the origin read from the
    `SITE_URL` secret.
  - `deploy:accept-origin` pointed at a `*.run.app` host that is not this service: Cloud Run
    answered 404, the probe failed, the task exited non-zero with "DEPLOY NOT ACCEPTED" and both
    ways forward, in 3 s with two attempts. Pointed at the alias it passed, which is the limit
    stated below.
  - Torn down and verified as in ADR-065, which also ran the corrected image-removal line for real.

**Not proven:** whether the probe needed a retry on the real cold start was not recorded, so the
30 s window is not measured against a slow one. That a cross-origin bundle loses its session cookie
is ADR-020's reasoning and has not been observed in a browser. The probe shows that the host serves
Prudent, not that it is the host the operator **meant**: the alias passes it, as does any other
live Prudent. The pre-build check narrows that to the one deterministic host, `WEB_API_URL_ALLOW_OTHER`
widens it again, and the deterministic form itself has now held on three projects of one account,
not on every kind of project. `SITE_URL` is compared; `AUTH_REDIRECT_URI` and `CORS_ORIGINS`, which
also carry the service host, are not.

---

## ADR-066 — The deploy gives `zen_runtime` its login, and `test:native` serves as that role

**Date:** 2026-10-22. **Status:** accepted. **Refines:** ADR-065. **Closes:** jlogicsoftware/prudent#150.

### Decision

- `scripts/ensure_runtime_login.sh` runs `ALTER ROLE zen_runtime WITH LOGIN PASSWORD …` as the DDL
  role, taking every input from the environment so no password reaches a process list. It uses a
  throwaway `psql` container (`postgres:17-alpine`, needs psql 15+) because a deploy already needs
  Docker and a laptop does not reliably have `psql`.
- `task deploy:cloudrun` runs it **between the migration Job and the service, on every deploy**,
  reading `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` and `APP_DB_PASSWORD` from Secret Manager. Because it
  runs every time, rotating `APP_DB_PASSWORD` is a new secret version plus a deploy, and the role and
  the secret cannot quietly disagree.
- `task test:native` runs the same script and now starts the serving container with
  `APP_DB_USERNAME=zen_runtime`. Until now it served as the DDL role, because `%prod` falls back to
  `DB_USERNAME` when `APP_DB_USERNAME` is absent — so no local gate could see a runtime role that
  cannot log in.

### What this supersedes, and why

- **"the first deploy of a new environment fails at its service step until `zen_runtime` is given a
  login"** (ADR-065, "Two defects only a real run could find", and the runbook's old step 2b) →
  **reversed.** *Why:* it was documented as a limitation in ADR-065 and is now fixed; the runbook's
  step 2b describes what the task does instead of a step the operator performs.
- **jZen treats the login as operator work outside the repository** (jZen ADR-031, whose reason is
  that a credential in a migration is plaintext in git) → **kept in its reason, changed in who does
  it.** *Why:* the reason still holds — the password is never in git, it is in Secret Manager — but
  the step is part of Prudent's own deploy task, which Prudent owns, and leaving it manual cost every
  fresh environment a failed revision and a second ten-minute native build.

### Consequence

Verified, in layers:

- **The script alone**, against a throwaway Postgres, six cases: role missing (fails, with a message
  that names both causes), role `NOLOGIN` (succeeds), a password containing `'` and `"`, a second run
  with a new password (the old one stops working, the new one works), a wrong DDL password (fails),
  a missing input (fails).
- **`task test:native`** green in 9 min 19 s with the new `runtime-login` assertion and the service
  serving as `zen_runtime`; registration with `pl` and every endpoint check still pass under the
  least-privilege role.
- **The gate bites.** The same image, same environment, but without the login step: the serving
  container exits 1 with `password authentication failed for user "zen_runtime"`. A gate that
  passes whether or not the step exists would have been decoration.
- **A real, fresh environment, on the first run.** A new GCP project and Supabase project, then
  `task deploy:cloudrun` **once**, with no manual role step: exit 0 in 10 min 32 s, one revision
  (the first), serving 100%; the log shows `>> runtime login` between the migration and the service.
  `verify:deploy` passed nine of nine; the database itself reports a live connection by
  `zen_runtime`; a Cloud Scheduler run reached `/api/v1/jobs/trigger` and got HTTP 200; the service
  log holds no authentication error. Torn down completely and verified, as in ADR-065.
- That run exercised the runbook's teardown step for the first time and found it wrong: its image
  removal built `repo:tag` from `docker images` columns that this Docker prints differently, and
  then a `*` that does not cross a `/`. It is now `docker images --filter
  "reference=REGION-docker.pkg.dev/PROJECT/*/*" -q`, verified to remove the image.

**Not proven:** the password-rotation path was exercised only against a throwaway Postgres (case 4
above), not against a live service on Cloud Run. The script pulls `postgres:17-alpine` from Docker Hub
on a machine that lacks it, so a deploy now depends on that registry being reachable. A transaction-mode
pooler was not tried. #151 (the task prints `status.url`, not the origin the bundle was built for)
is still open.

---

## ADR-065 — The deploy path has run once against a real, disposable environment and was torn down; a persistent one still does not exist

**Date:** 2026-10-22. **Status:** accepted. **Refines:** ADR-020, ADR-021. **Closes:** jlogicsoftware/prudent#45.

### Decision

`task deploy:cloudrun` and `task verify:deploy` were run against a real GCP project and a real
Supabase project created for the purpose, and **everything created was then deleted**. This is the
"throwaway" proof ADR-020 deferred, not a deployment: nothing is left running, and the persistent
environment (#46) is not created. As ADR-021 requires, no project, reference, region, service name
or URL is recorded here.

What ran, in order:

- A new GCP project billed to the account's open billing account, the four APIs, an Artifact
  Registry repository, a dedicated runtime service account holding only
  `roles/secretmanager.secretAccessor`, and twelve secrets.
- A new Supabase project on the Free plan. An older test project of the account had just been paused
  and was still `PAUSING` when this one was created, and creation succeeded; whether the pause is
  what made room was not established.
- `task deploy:cloudrun`: **the first run failed** at its service step (below); after the two fixes,
  **the second run passed end to end, exit 0, in 9 min 47 s** — web and admin bundles, the native
  `linux/amd64` build, push, the migration Job (exit 0), the service.
- `task verify:deploy` against both forms of the service's URL: **nine of nine checks passed**,
  including the redirect allowlist and the scheduled-work check.
- A Cloud Scheduler run reached `/api/v1/jobs/trigger` with the real trigger token and got
  **HTTP 200** from the service — the control was exercised, not just configured.

### Two defects only a real run could find

- **`--set-env-vars="ZEN_I18N_SUPPORTED=en,uk,pl"` was refused by gcloud** (`Bad syntax for dict arg`):
  gcloud splits that flag on commas and the locale set is a comma list. The value now uses gcloud's
  alternate delimiter (`^@^`). Every earlier check passed, because none of them reaches gcloud.
- **`zen_runtime` could not log in.** The identity migration creates it `NOLOGIN` with no password,
  deliberately, and nothing in the runbook gave it one. The service died at startup with
  `FATAL: (EAUTHQUERY) user not found in the database`, which reads like a wrong username. The
  runbook now has the `ALTER ROLE zen_runtime WITH LOGIN PASSWORD …` step and says that a new
  environment's first deploy fails at its service step until it is done.

The first is fixed in `deploy:cloudrun`'s command, the second in its runbook text; both are in
`Taskfile.yml`.

### Runbook gaps closed in the same change

Twelve secrets, not eleven; how to create the Supabase project (its password must be stored in
Secret Manager *before* the create call, because the CLI never returns it — one project had to be
deleted and recreated for exactly this); the session pooler on 5432; the user suffix
(`postgres.<ref>`, `zen_runtime.<ref>`); the deterministic Cloud Run host
(`SERVICE-PROJECT_NUMBER.REGION.run.app`), which makes the first deploy one build rather than two,
versus the different form `status.url` returns and the task prints; a brand-new project answering
`PERMISSION_DENIED` to its owner for a few minutes; the global `~/.docker/config.json`; and a
teardown step that ends by proving itself.

### What this supersedes, and why

- **"No GCP project, Cloud Run service, or persistent Supabase project has ever been created."**
  (`CLAUDE.md`, "Built, but never run for real" and "Working agreement") → **refined.** *Why:* a
  disposable GCP project, Cloud Run service and Supabase project were created and deleted on
  2026-10-22. The claim about a *persistent* environment stays true.
- **"proven only locally and against throwaway checks"** (same places) → **reframed.** *Why:* the
  deploy tasks now have one real run behind them; they are still not a record of any standing
  deployment.

`CLAUDE.md`'s two paragraphs were rewritten to match in the same change.

### Consequence

Teardown was verified rather than assumed: the GCP project is in `DELETE_REQUESTED` (Google keeps it
restorable for 30 days; that is a holding state, not a live resource) and no longer appears under the
billing account's projects; the Supabase project is absent from the account's list and the account's
other projects are untouched; both locally tagged images of the run were removed, no dangling image
or container from it remains, and `~/.docker/config.json` is byte-identical to its state before the
run. The public base images the native build uses (Mandrel builder, UBI) are shared and were left.

**Not proven, and stated rather than implied:**

- Anything past the endpoints. No account was registered, no sign-in made, no mail link followed, and
  the Supabase project's own Redirect URLs list was not set to match `AUTH_REDIRECT_URIS` — the runbook
  says it must be. The native `pl` locale check stays in `task test:native` and was not repeated.
- The pooler's transaction mode (6543) was not tried; 5432 is the one measured.
- That a service survives a day: backups, a persistent database and its recovery are #46 and #47.
- Two things documented here rather than fixed, each with its own issue: the first deploy of any new
  environment fails at its service step until `zen_runtime` is given a login (jlogicsoftware/prudent#150),
  and the task prints `status.url`, not the origin the bundle was built for (jlogicsoftware/prudent#151).
- The Scheduler header still carries the trigger token on the `gcloud` command line, visible in the
  process list while the command runs. Unchanged and undocumented as a trade-off.
- **`task` does not run from a git worktree under `.claude/worktrees/`:** `Taskfile.yml` includes
  `../jZen/Taskfile.app.yml` relative to itself, which does not exist from there. Found when a
  delegated run was started in a worktree; deploys must run from the main checkout. Not fixed here.

---

## ADR-064 — On native macOS a pushed page fades in place: seen in slow motion at `b67a549`; the Chrome-on-a-Mac half of #145 is not yet looked at

**Date:** 2026-10-09. **Status:** accepted. **Refines:** ADR-061, ADR-063. jlogicsoftware/prudent#145;
jZenDev/jZen#131 (→ #132, jZen ADR-062).

### Decision

- No code change. ADR-063 moved `JZEN_REF` to a jZen revision that includes #132, which is step 1 of
  #145; this records step 2, what was seen, and what was not.
- Native macOS is accepted as meeting #142's first line, "on macOS no pushed screen slides in from
  the right", on the evidence below.
- The Chrome-on-a-Mac line ("the default push transition, no fade") is **not** accepted here. It rests
  on jZen's own test (a web build reporting `TargetPlatform.macOS` keeps the travelling title) and has
  not been seen in Prudent. #145 stays open for it.

### What was seen

Native macOS debug build (`task run:dev DEVICE=macos CLIENT_PLATFORM=macos`) with `timeDilation = 6`
set locally in `main()` and not committed, against a local backend. A series of frames was taken
after each tap, looking at the title and the back button, not only the body:

- *Window 820 pt (the page fallback):* Reminders from the bell, and back; Accounts from Settings. The
  outgoing and incoming titles ("Prudent" and "Reminders"; "Settings" and "Accounts") cross-fade in
  the same place, the back button does not move, and the body fades. Nothing moves horizontally, in
  either direction, and the sidebar stays on screen throughout.
- *Window 1100 pt (the pane):* Categories opens beside Settings; a category's records stack in that
  pane as a cross-fade in place; Back inside the pane and Close both work and fade the same way. This
  is the case jZen#132 listed as not looked at.

### Not looked at

- **Chrome on a Mac** (the web build). The embedded browser reports `MacIntel`, so it is the right
  case, but the browser pane was hidden and the page ran at about 2 frames a second, so no frames of
  a transition could be taken; only the end state was seen (the reminder centre as a page under the
  shell's own header, Back working). The slow-motion check of #145 step 2 still has to be done there.
- **Real speed.** Every screen was operated at real speed in the sessions behind ADR-062 and ADR-063
  without anything visibly wrong, but a transition lasting a third of a second was not measured.
- Windows, Linux, iOS and a real Android device.

### Consequence

- `timeDilation` is a local debugging aid only. Nothing in `client/lib` carries it; after this entry
  `main.dart` is unchanged.
- #145 is not closed by this entry. What is left for it is the web check above, in a visible browser.
- `task zen:test:client` passed under the macOS idiom with the temporary edit in place (351 tests).

---

## ADR-063 — `JZEN_REF` moves to `b67a549`: a page pushed from a destination now stays inside the navigation shell

**Date:** 2026-10-09. **Status:** accepted. **Refines:** ADR-062. jZenDev/jZen#133 (→ #134, jZen
ADR-063) and #131 (→ #132).

### Decision

- `JZEN_REF` moves from `0fdcd05` to `b67a54924de2c744a05b077f5c18ac546ffcdcd3` (`ci.yml`,
  `audit.yml`). It brings two jZen commits: #134 (each `ZenNavigation` destination sits in a
  `Navigator` of its own, so a push, `showZenDetail`'s narrow fallback included, lands beside the
  sidebar, rail or web menu) and #132 (the macOS page transition and bar hero, #131). Both touch only
  client packages; no server, contract or migration change.
- Prudent changes no code for it. Its screens do not push pages themselves: every `Navigator.pop`
  sits inside a form or dialog that `showAdaptivePresentation` or `showDialog` opened, and those
  still go through the root navigator.

### What this supersedes, and why

- **"The sidebar stays only while the pane fits … a macOS window narrower than about 935 pt gets the
  full-screen push, and that push covers the sidebar"** (ADR-062, Decision) → **no longer holds.**
  *Why:* below 720 px of the host's width `showZenDetail` still pushes, but into the destination's own
  `Navigator`, so the shell stays. ADR-062's text is left as the record of what was true at `0fdcd05`.

### Consequence

- **What a pushed page now means.** `Navigator.of(context)` inside a destination is that destination's
  navigator; a page that has to cover the shell asks for `rootNavigator: true`. Prudent has none.
  Switching destination discards the stack of the one left (jZen only builds the selected one, as
  before), so a page opened from Settings is gone when the user comes back from another tab.
  Narrowing the window under a pane still turns it into a push, and widening it leaves a pushed page
  where it is (jZen ADR-061).
- **Verified:** `task zen:test:client` (macOS idiom) and the suite under `ZEN_PLATFORM=web`, 351
  tests each, `task verify:controls`, and `dart analyze` (the two warnings it reported before).
  Run against a local backend on the macOS debug build: at 820 pt Accounts (from Settings) and the
  reminder centre (from the bell) open as a page inside the content area with the sidebar visible and
  Back returning; at 1100 pt the bell, Accounts and Categories (with a category's records stacked in
  the same pane) open beside the screen as in ADR-062; the add-account form is still a dialog over
  the whole window.
- **Not looked at:** the web build and Windows and Linux in a running app, and a window dragged
  through the threshold with a page open.

---

## ADR-062 — Reminders, Accounts, Categories and Profile are details of the screen they are opened from, and Chart is a view of Analytics; the six tabs stay six

**Date:** 2026-10-09. **Status:** accepted. **Refines:** ADR-061. jlogicsoftware/prudent#144 (split
from #142, step 4).

### Context

Five screens were pushed over the whole window with `ZenPageRoute`, so each one covered the macOS
sidebar. `ZenNavigation` cannot prevent that: it has no nested `Navigator`, a destination is only a
`builder`, and a `Navigator.push` always goes to the root navigator. Three things keep the sidebar:
a destination of its own, a view inside an existing destination, or `showZenDetail` (ADR-061),
whose pane lives inside the destination's content area. On mobile `ZenNavigation` shows three tabs
and puts the rest under "More", whose page draws no badge; Prudent already has six.

### Decision

| Screen | Where it lives now | Why |
|---|---|---|
| **Chart** | A second view of Analytics, a `ZenSegmentedControl` beside "Spend by month" (`SpendByCategoryView`). The pie-chart button on Overview and `ChartScreen` are gone. | Same question (where did the money go), same currency pick. It is one task, so it is one screen. The currency is kept when the view changes. |
| **Accounts** | The detail of Settings and of Overview (`showZenDetail`). | Accounts are set up and corrected rarely; Overview already shows their balances. A seventh tab would only land under "More" on a phone. |
| **Categories** | The detail of Settings. | Set-up, as above. |
| **Profile** | The detail of Settings. | It is the framework's `ProfileScreen`; only the way into it changes. |
| **Reminders** | The detail of Overview, opened from the bell. | An inbox entered when the badge says so. The bell keeps its count in view on every width; a tab under "More" would lose it. |

`SettingsScreen` and `OverviewScreen` are `ZenDetailHost`s. The detail opens beside the screen from
720 px of the host's width and as a full-screen push below it, so no pushed screen is left except
that narrow fallback, which is the framework's. Prudent has no platform or width branch for any of it.

**The sidebar stays only while the pane fits.** The width that counts is the host's, measured after
the sidebar has taken its share, so on macOS a window narrower than about 935 pt (720 pt plus the
sidebar) gets the full-screen push, and that push covers the sidebar as every push does. On a phone
there is no sidebar to lose. This is a limit of `showZenDetail`, not of Prudent's screens, and it is
left as it is rather than worked around here. It was raised upstream as jZenDev/jZen#133 and fixed by
jZenDev/jZen#134 (jZen ADR-063); Prudent takes the fix when `JZEN_REF` moves past it, which is a
separate, deliberate step. Until then CI pins `0fdcd05` and the limit above stands.

A page opened from inside a pane stacks in that pane (`ZenDetailScope`), so `CategoriesScreen` and
`RemindersScreen`, which are hosts themselves, can be details without a second pane appearing.

### What this supersedes, and why

- **"Every other pushed screen (Accounts, Categories, Profile, Chart, Reminders) stays a push"**
  (ADR-061, Decision) → **changed.** *Why:* that was kept only because the placement was a product
  decision not yet made; it is made here, and a push is what hid the sidebar.
- **"Whether Reminders, Chart, Accounts, Categories and Profile should be `ZenNavigation` items or
  in-place sections instead of pushes … was not made here"** (ADR-061, What this leaves open) →
  **closed.** *Why:* each has an answer in the table above.

### Considered and rejected

- **Accounts as a destination.** Right if accounts were visited daily; nothing says they are, and
  the cost is a seventh tab on every width. Revisit if reconciliation turns out to be a habit.
- **Reminders as a destination with `badgeCount`.** The badge is drawn on a wide sidebar and a
  bottom bar, not inside "More", where this tab would be on a phone.
- **A nested `Navigator` per destination in `ZenNavigation`.** Would let any push keep the sidebar,
  including the narrow macOS window above. It is a framework change, so it is a request to make in
  jZen, not something to build here; nothing else in this decision depends on it. Made as
  jZenDev/jZen#133 and taken up there (#134) as this option.

### Consequence

- `chartTitle` is removed from the three `.arb` files and `analyticsSpendByCategory` added.
- Tests: the by-category view is covered inside `AnalyticsScreen`; Settings and the bell have a
  wide-window test (the screen stays, no Back) and a narrow one (full-screen, Back); an occurrence
  opened from the bell stacks in the reminders pane.
- **Verified:** the client suite under the macOS idiom, the touched files under `ZEN_PLATFORM=web`,
  `task verify:controls` and `dart analyze` (the two warnings it reported before).
- **Looked at in a running app, 2026-10-09**, against a local backend:
  - *Web, 1024 px wide:* the bell, Accounts, Categories (with a category's records stacked in the same
    pane) and the Analytics segment open as designed, with the top navigation staying put; at 375 px
    Accounts is a full-screen push with Back. Accounts' add form opens as a dialog over the pane.
  - *macOS, 1100 pt wide:* the same screens, plus Profile, open as an in-layout pane beside the real
    sidebar, which stays; Analytics shows the Cupertino segmented control. Resized to 820 pt, Accounts
    is a full-screen push that covers the sidebar (see above).
- **Not looked at:** a native phone or tablet, Windows and Linux, and a window dragged through the
  720 px point while a detail is open (the narrow and the wide cases were each opened fresh).

---

## ADR-061 — Details open beside their list through `showZenDetail`, and every other pushed screen is a `ZenPageRoute`

**Date:** 2026-10-08. **Status:** accepted. **Refines:** ADR-041, ADR-060. jlogicsoftware/prudent#142;
jZenDev/jZen#129 (→ #130, jZen ADR-061).

### Decision

- `JZEN_REF` moves from `351797a` to `0fdcd05` (`ci.yml`, `audit.yml`).
- `ThemeData.pageTransitionsTheme` is `ZenPageTransitions.theme` (`app.dart`): iOS keeps the slide,
  macOS fades, the rest keep Flutter's default.
- A goal's detail (`GoalsScreen`), an occurrence's detail (the reminder centre) and a category's
  records (`CategoriesScreen`) open with `showZenDetail`, and those three list screens are wrapped in
  a `ZenDetailHost`. From 720 px of the *host's* width the detail sits beside the list (an in-layout
  pane on iOS/macOS, a side sheet elsewhere); narrower, it is a full-screen push with Back. Prudent
  has no platform or width branch of its own for this.
- Every other pushed screen (Accounts, Categories, Profile, Chart, Reminders) stays a push and uses
  `ZenPageRoute` in place of `MaterialPageRoute`, so a Mac does not slide it in.

### What this leaves open

- Whether Reminders, Chart, Accounts, Categories and Profile should be `ZenNavigation` items or
  in-place sections instead of pushes (step 4 of #142) is a product decision and was **not** made
  here; they are pushes as before, only with the framework's transition.

### Behaviour that changed, stated rather than discovered

- On a wide window the list stays on screen while a detail is open, so a test that asserted a
  full-screen replacement now pins its window to 600 px (`goal_views_test`, `reminder_views_test`),
  and each file has a wide-window test showing the pane, Close, and the list beside it.

### Verified, and what is not

- `task zen:test:client` (macOS idiom) and the suite under `ZEN_PLATFORM=web` pass, `flutter analyze`
  reports only the two warnings it reported before, and `task verify:controls` passes.
- **Not looked at in a running app**: no window has been resized through the 900 px range, so the
  pane/push switch beside the macOS sidebar is covered by widget tests only.

---

## ADR-060 — Prudent's screens are built on jZen's Apple-aware text field, icon button, spinner, bar, page and message; the gate bans their Material twins outright

**Date:** 2026-10-07. **Status:** accepted. **Refines:** ADR-059, ADR-041. jlogicsoftware/prudent#116;
jZenDev/jZen#119 (→ #120 text field, spinner, identity; #121 macOS sidebar; #122 icon button; #123
page and message) and #127 (→ #128: the page's `ListTile` ink, multiline and counted text, a message
action, an icon-button badge, a progress bar).

### Decision

- `JZEN_REF` moves from `6b017bb` to `351797a`. On iOS and macOS `ZenTextField`,
  `ZenProgressIndicator`, `ZenProgressBar`, `ZenIconButton`, `ZenPageScaffold` and `showZenMessage`
  render Cupertino, as does the identity flow and the `ZenNavigation` desktop shell (a sidebar);
  elsewhere they render what the stock widgets did.
- Every screen in `client/lib` uses them in place of `TextField` / `TextFormField`, `IconButton`,
  `CircularProgressIndicator`, `LinearProgressIndicator`, `Scaffold` + `AppBar` and `SnackBar`.
  `Popup` takes an `IconData` and a `label` instead of a widget, because `ZenIconButton` requires
  the accessible name an icon cannot give itself; nine buttons that had no tooltip now have one
  (new keys `addRecordTooltip`, `addAccountTooltip`, `addCategoryTooltip`, `editCategoryTooltip`;
  existing ones reused).
- `task verify:controls` bans those twins **with no carve-out**. A first version of this change
  carved out the one capability each framework control then lacked (multiline text, a badge, a
  message action, the `Scaffold` a snack bar needs); jZen#127 added all of them, so every carve-out
  was deleted rather than kept. What has no counterpart and is used directly: `RefreshIndicator`,
  `ListTile`, `Card`, `AlertDialog`, `PopupMenuButton`.

### Behaviour that changed, stated rather than discovered

- The records screen's undo message no longer times out after three seconds: `showZenMessage`
  keeps a message that carries an action until it is acted on, dismissed or replaced (WCAG 2.2.1).
- A goal's or budget's progress bar is named (`ZenProgressBar` requires a label) and reads its
  percentage aloud; the loading state of the free-money card is a spinner, not an indeterminate bar.
- `AccountNew` reads its name and currency from controllers at submit; `ZenTextField` has no
  `initialValue` / `onSaved`, which jZen left to the application.
- Prudent's own Polish for `zen_ui_navigation` gains the sidebar's `position` ("2 z 5"); the
  `backButtonTooltip` override in the identity delegate is gone because jZen removed the string.
- The client suite's finders no longer look for `TextField`, `IconButton`, a tooltip or
  `pageBack()`: those are one idiom's types, and the host picks the idiom (`test/zen_fields.dart`).
  `task zen:test:client` on a Mac exercises the Cupertino branch; CI's runners exercise Material.

### Verified, and what is not

- A debug macOS build with `ZEN_PLATFORM=macos` opens on a Cupertino login screen where it was
  Material. The client suite passes in both idioms (`macos` and `linux`).
- **No signed-in screen has been looked at on macOS**: that needs the local stack (`task run:dev`)
  and was not run, so #116 stays open for that check.

## ADR-059 — Raw Material controls are gated out of `client/lib` by `task verify:controls`; `AlertDialog` and `PopupMenuButton` are the only carve-outs

**Date:** 2026-10-07. **Status:** accepted. **Refines:** ADR-041. jlogicsoftware/prudent#105.

### Decision

- `task verify:controls` (`scripts/verify_controls.py`) scans `client/lib`, excluding `generated/` and
  `l10n/`, and fails on `ElevatedButton`, `FilledButton`, `OutlinedButton`, `TextButton`,
  `DropdownButton`, `DropdownButtonFormField`, `SegmentedButton`, `SwitchListTile`, `showDatePicker`,
  `showDateRangePicker` and `showModalBottomSheet`. Each has a `zen_ui_widgets` counterpart
  (`ZenButton`, `ZenSelect`, `ZenSegmentedControl`, `ZenSwitchRow`, `ZenDateField` /
  `ZenDateRangeField`, `showAdaptivePresentation`).
- `showDialog` is allowed only to show an `AlertDialog`, and that `AlertDialog` may not hold a
  `TextField`, `TextFormField` or `Form`. "Used for a form or detail" is what the rule forbids, and
  a regular expression cannot see intent, so the gate checks the structure that intent leaves behind:
  a message-and-verdict dialog has an `AlertDialog` and no input; a form has an input or something else
  entirely. A `showDialog` whose builder hands off to another widget fails — it cannot be shown to be
  a confirmation, and the way to make it pass is to open it through `showAdaptivePresentation`.
- Comments and string literals are masked before matching, so a doc comment explaining why `ZenButton`
  replaces `TextButton` is not a violation; line numbers are unchanged.
- It runs in CI beside `verify:boundaries`, ahead of the framework build, and its unit tests
  (`scripts/test_verify_controls.py`) run first. They plant every banned control in a throwaway tree and
  require the gate to fail, and require every carve-out and a stale scope to behave as written here.

### The carve-outs, and what each carries

The working agreement asks for an exemption to be argued by what the excluded content carries, not
by what it saves.

- **`AlertDialog` (acknowledgement or confirmation).** It carries a title, a sentence and the verdict
  buttons — no input and no state. `zen_ui_widgets` has no counterpart, and forcing it through
  `showAdaptivePresentation` would turn "delete this account?" into a bottom sheet on a phone, a worse
  interaction for a question that wants a modal answer. The carve-out covers the dialog, **not a raw
  button inside it**: its actions are `ZenButton(variant: text)`, so `TextButton` stays banned
  everywhere and there is no second, narrower exemption to police.
- **`PopupMenuButton`.** It carries a menu of verbs (the goal screen's lifecycle actions) and is not
  banned; the package has no menu. If it grows one, this entry is superseded, not extended.

There is **no per-file allowlist**. A control the package lacks is a framework gap to report upstream
(CLAUDE.md, ADR-036, ADR-041), not an entry here.

### What this supersedes, and why

- **"Other screens may still carry stock Material controls, so the rule binds new and touched
  screens"** (`CLAUDE.md`, Client UI) → **removed.** *Why:* after #101, #102 and #103 the only
  remaining raw controls were a `TextButton` in the budget month bar and ten in `AlertDialog`
  actions; all are `ZenButton` now, so the rule binds the whole tree and a gate keeps it that way.
- **jZen #107 "Landed upstream; not yet consumed here"** (`docs/jzen/README.md`) → **Fixed and
  consumed**, as that row said to do when the last raw control was gone.

### Consequence

Run against the tree before this change, the gate reports eleven `TextButton`s and nothing else; run
after, it is green, and its 27 tests pass. `flutter analyze` reports nothing new. **Not covered, and
stated rather than implied:** controls outside the list (`IconButton`, `TextField`, `ListTile`, `Card`
have no counterpart and are used directly), and `showGeneralDialog` / `showCupertinoDialog`, which the
rule does not name. A control gets in the list when the package gains its counterpart.

## ADR-058 — A refusal or an unsupported platform is explained where reminders are read, and a refusal is remembered across launches

**Date:** 2026-10-06. **Status:** accepted. **Follows:** ADR-057 (the pass returns an outcome "for the next task"),
ADR-056 (permission is asked for only when a reminder is waiting), ADR-055 (the in-app reminder centre), ADR-054 (the setting).

### Decision

The last M5 task (jlogicsoftware/prudent#71 — "explain platform limitations and retain the in-app reminder path without
repeated permission prompts") makes the two outcomes ADR-057 only returned visible, and closes the way a prompt could repeat.

- **The reminder centre says why.** `NotificationNotice` sits above the list in `RemindersScreen` and reads the outcome of
  `reminderNotificationSyncProvider`: for `unsupported` ("this device can't show reminders as notifications; they appear
  here") and for `denied` ("notifications are turned off for Prudent, so reminders appear only here; allow them in your
  device's settings to get them too"). It is silent for every other outcome, while the pass is running, and when the pass
  failed — a failed read of the plans is that provider's own error state and is not a reason to talk about permissions. It is
  shown with an empty list too, because on the web and Linux the centre is all the user has. It has no button: it explains,
  it does not ask. The strings are in `en`, `uk` and `pl`.
- **The in-app path never depended on the device.** `remindersProvider` reads the server (ADR-055) and the notice only adds a
  line above it; nothing in this change gates a reminder on a permission or a platform.
- **A refusal is remembered across launches.** ADR-056 remembered "already asked" in the scheduler, so once per session. A
  `NotificationPermissionMemory` port now holds it, implemented over `shared_preferences` (one boolean, not secret, so not
  the keystore). The scheduler asks only when permission is absent **and** the user has not been asked, and records the ask
  **before** showing the prompt, so a launch that ends with the prompt on screen has still asked. A grant made later in the
  system's settings is seen by `hasPermission()` on the next pass and scheduled without a prompt — the memory only ever
  suppresses the prompt, never the schedule.
- **A new dependency, `shared_preferences`**, for that one fact. The scheduler defaults to an in-memory memory when none is
  given, which is the old per-session behaviour and what tests that do not care use.

### What this does not decide

- **No "open settings" action.** Reaching the system's notification settings needs a platform call the gateway does not have;
  the notice says where to go and leaves it there.
- **A user asked before this change.** The memory starts empty, so someone who refused under ADR-056 can be asked once more
  after updating. iOS and macOS answer a repeat request without a prompt; Android 13+ may show it once.
- **The notice follows the pass, not the clock.** It changes when the pass runs again (a launch or a change of state), not the
  moment the user flips the system setting.

### Consequence

Verified by `notification_notice_test.dart`: a refusal not prompted again by a later scheduler sharing the memory; the ask
recorded even when the prompt throws; a later grant scheduled with no second prompt; an unsupported platform and an empty
reminder set recording nothing; the preferences memory starting empty and keeping its value; and the notice's text for
`unsupported` and `denied`, none for the other outcomes, a pending pass or a failed one, Polish wording, no control, and its
position above the reminders (still listed) and above an empty list in the real `RemindersScreen`.

**Not verified:** no prompt, refusal or settings change was seen on a device or simulator, and `shared_preferences` was
exercised only through its test mock.

---

## ADR-057 — Notifications are reconciled to what the server says now, not patched by what changed

**Date:** 2026-10-06. **Status:** accepted. **Follows:** ADR-056 (what is scheduled, its id, and the known gap this closes),
ADR-055 (what a reminder is), ADR-054 (the setting), ADR-040 (deleting a confirming record reopens the occurrence), ADR-045
(what can be calculated is never stored).

### Decision

The fourth M5 task (jlogicsoftware/prudent#70 — "edits, confirmation, skip, login and app update reschedule or cancel
notifications idempotently") closes the gap ADR-056 stated: a notification scheduled for an occurrence that has since
been skipped, confirmed or whose plan was edited could still fire.

- **A pass reconciles; it does not react.** Each pass computes the *whole* wanted set from the plans and the upcoming
  window as they are now (ADR-056's rules), reads the ids the device has pending, **cancels every pending id that is not
  wanted** and schedules every wanted one. It never asks what changed, so one rule covers a skip, a confirmation, a plan
  edit or delete, a switched-off reminder, a changed lead time and a notification an older app version left behind — and a
  change the client did not make (another device, the admin panel) is repaired by the next pass rather than missed. The
  alternative, a cancel per kind of change, needs a case for each way the server can change and drifts the day one is added.
- **Idempotent by construction.** Scheduling replaces what the device holds under an id (ADR-056); cancelling leaves nothing
  to cancel the second time. Repeating a pass for the same state changes nothing on the device.
- **Cancelling needs no permission and comes first.** Stale notifications are cancelled before permission is considered, so
  a reminder switched off, or a plan deleted, stops firing when nothing is left to schedule, and when the user has since
  refused notifications. The permission rules of ADR-056 are unchanged: asked for only when something is to be scheduled.
- **When a pass runs.** On every build of the signed-in shell — a sign-in, a launch with a saved session, and so the first
  launch after an app update, which is how an update replaces what the old version scheduled (the new version's text and
  times win by id) — and again whenever `reminderScheduleRevisionProvider` changes. That counter is bumped by skipping,
  restoring and confirming an occurrence (`OccurrenceActions`), by creating, editing and deleting a plan (the new
  `PlanActions`, which a plan screen will use and the repository methods are not to be called around), and by deleting a
  record that has a `plan_occurrence_id`, since that reopens the occurrence. It lives beside what changes in `providers.dart`
  so that code does not import the notification code that reacts to it. A record with no occurrence, an account or a
  category changes nothing a notification reads and does not trigger a pass.
- **Passes are queued and a stale one stands down.** The scheduler runs passes one after another (a pass spans several awaits;
  two interleaved could leave the older one's notifications behind), and a pass whose provider was invalidated while it was
  still reading returns `superseded` without touching the device.
- **The gateway gained `pendingIds()` and `cancel(id)`.** Every notification the app schedules is a reminder's, so "pending"
  is exactly the set to compare. The result of a pass now also says how many it cancelled.

### What this does not decide

- **The window moving with time.** A pass runs on launch and on a change, not on a clock: an app left open for days does not
  reschedule as its 30-day window or the 60-notification cap moves, and a notification that fired stays delivered. The next
  launch repairs it.
- **Windows without a package identity.** ADR-056 recorded that the plugin's `cancel` does nothing for an unpackaged Windows
  app; on such a build a stale notification can still fire. Not worked around here.
- **Explaining a refusal or an unsupported platform** — the next task; the pass returns the outcome for it.

### Consequence

Verified by `reminder_notification_test.dart` against a fake device and a mock server whose plans and occurrences change
under the test: the scheduler cancelling what is pending and not wanted and keeping what is, cancelling everything with no
prompt when nothing is wanted or permission has since been refused, not cancelling twice, doing nothing on an unsupported
platform, running overlapping passes in order, and surviving a failed pass; and, through the real repository and actions,
sign-in cancelling an older version's leftovers and replacing an outdated one by id, skip cancelling and restore
rescheduling, confirmation cancelling, deleting a confirming record rescheduling (and deleting any other record not
running a pass), a plan edit moving the notifications and switching the reminder off cancelling them, a plan deleted and a
plan created, a repeated pass changing nothing, and a superseded pass leaving the device to its replacement. Removing the
trigger makes five of these fail.

**Not verified, as in ADR-056:** nothing was cancelled or delivered on a device or simulator; "cancelled" means the plugin
was asked without an error. `pendingNotificationRequests` on each platform is the plugin's own and was not exercised.

---

## ADR-056 — A local notification is a reminder date turned into a device time; it carries no amount, and permission is asked for only when one is waiting

**Date:** 2026-10-06. **Status:** accepted. **Follows:** ADR-055 (what a due reminder is, and that nothing about one is
stored), ADR-054 (the setting; off by default so the platform prompt follows something the user chose), ADR-045 (what can
be calculated is never stored), ADR-038 (the occurrence window), ADR-009 (per currency, never blended).

### Decision

The third M5 task (jlogicsoftware/prudent#69 — "request permission only when needed and schedule a local notification
with no sensitive amount in lock-screen text by default") schedules notifications on the device. It does not reconcile
them after a change (the next task) and does not explain a refusal (the one after).

- **What is scheduled: the reminders that are still ahead.** One notification for each still-`PLANNED` occurrence in the
  next 30 days (`reminderNotificationHorizonDays`) whose plan's reminder is on and whose reminder date — the occurrence's
  date less the plan's lead time, in calendar days — has not yet passed. The client reads `GET /plans` and
  `GET /occurrences/upcoming` and joins them by `plan_id`. A reminder that has *already* fallen due is not scheduled: it is
  in the centre (ADR-055), and a notification for a moment that has passed would only appear at once. **The client therefore
  does one subtraction the server also does** (`date − lead_days`); it does not decide what is due, overdue or read, which
  stay the server's. An endpoint that lists *future* reminders would remove even that, and is the better answer if the
  reconciliation task needs the server's word for a date.
- **The time of day is a device matter, fixed at 09:00 local** (`reminderNotificationHour`). A plan's reminder is in whole
  days (ADR-054) and every date on a plan is in the plan's own zone (ADR-037), but a notification fires on the device in
  the device's zone: the reminder's civil date at 09:00 wherever the phone is then. The date is built from calendar
  fields, never by subtracting a `Duration`, so a daylight-saving change between the two dates cannot move it a day.
- **A notification's id is a hash of its occurrence's id** (`reminderNotificationId`, FNV-1a, a non-negative 31-bit
  integer — platforms identify one by a 32-bit int). The same occurrence always lands on the same id, so scheduling it
  again *replaces* its notification: a repeated pass is idempotent without reading what the device already holds, which
  is also the property reconciliation will need to cancel exactly the right one. Two occurrences colliding is possible
  in principle (31 bits) and would make the later replace the earlier; at most 60 are scheduled at once, so the
  probability is negligible and the cost is one missed notification, not a wrong one.
- **No amount in the text by default.** A notification is shown on the lock screen, where anyone holding the phone can
  read it. The title is generic ("Planned transaction due") and the body names the plan and its date ("Rent on Oct 20,
  2026"); the amount is added only when `showAmounts` is passed (`planReminderNotifications`), which nothing sets yet —
  there is no preference screen, and a switch that nothing reads would be a second source of truth about the setting.
  **The plan's title is on the lock screen.** The task names amounts; a title can be as revealing ("Clinic"), so
  hiding it too is a decision for when the preference exists, not one made here by silently dropping the one thing that
  says which obligation is coming.
- **Permission is requested only when a reminder is waiting.** `ReminderNotificationScheduler` asks the platform for
  permission when it has at least one notification to deliver and the user has not already allowed them — never at
  launch, never when no plan has a reminder on, and never on a platform that cannot deliver one. Initialising the
  platform plugin does not prompt (the Darwin `request*Permission` flags are all off); only `requestPermission` does.
  Once asked in a session, a refusal is accepted for that session and not asked again. **Across sessions it relies on the
  platform**: iOS and macOS show the prompt once and answer "no" thereafter; Android 13+ shows it at most twice and then
  answers "no". Persisting "the user declined" in the app (Android cannot tell "never asked" from "refused" with
  `areNotificationsEnabled`) belongs to the denied/unsupported task, which is about exactly that.
- **Where it works.** Android, iOS, macOS and Windows, through `flutter_local_notifications`. **Not the web** (browsers do not
  show a notification for a page that is closed) **and not Linux** (the plugin has no scheduler API there): both answer
  `unsupported` and the in-app centre is the path. The web build never reaches the plugin — the gateway is behind a
  `dart.library.io` conditional import, as `app_links` is — and Linux is told by `Platform.isLinux` inside the native-only file.
  Windows toasts need no grant (there is none to read), so `hasPermission` is true there; `cancel` does nothing for an
  unpackaged Windows app (the plugin's limitation), which the reconciliation task has to know.
- **Inexact alarms, no special permission.** Android schedules with `inexactAllowWhileIdle`, so the app neither declares
  `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM` nor sends the user to the "alarms & reminders" setting that Android 14 turns
  off by default; a reminder for a day does not need the minute. `RECEIVE_BOOT_COMPLETED` and the plugin's two receivers
  are declared so notifications survive a reboot and an app update, and core-library desugaring is on, as the plugin
  requires. iOS sets the `UNUserNotificationCenter` delegate, which the plugin documents, so one can be presented while
  the app is open. **The iOS deployment target is now 15.0** (was 13.0): Flutter raised it when the plugins were added, because one of them
  requires it, so an iPhone on iOS 13 or 14 can no longer install the app.
- **When it runs.** `reminderNotificationSyncProvider` is listened to by `HomeShell`, so one pass runs on each sign-in and
  is dropped on sign-out. It is **not** re-run after an edit, a confirmation, a skip, a language change or an app update:
  those are the reconciliation task, and until it lands a notification already scheduled for an occurrence that has since
  been skipped, confirmed or whose plan was edited **can still fire**. This is the known gap, stated rather than hidden.
  Failure to read the plans or to schedule is the provider's error state (Riverpod retries it with backoff), not swallowed.
- **At most 60 are scheduled at once** (`maxScheduledReminderNotifications`): iOS keeps 64 pending and drops the rest
  silently. The nearest are kept; the later ones are scheduled by a later pass.

### What this does not decide

- **Reconciling after a change, and cancelling.** The next task. Nothing here cancels a notification.
- **Explaining a refusal or a platform that cannot deliver, and not asking again across sessions.** The task after it; the
  outcome (`unsupported`, `denied`, `scheduled`, `nothingToSchedule`) is returned by the pass so that screen can say so.
- **Tapping a notification.** It opens the app; it does not open the occurrence. The payload carries the occurrence id for it.
- **A preference for amounts or for the hour.** One setting each would be a client-local store the app does not have yet.

### Consequence

Verified by `reminder_notification_test.dart` against a fake device (no plugin is reached): the notification for a planned
occurrence at 09:00 on its date less the lead time, a lead of 0 and one reaching back across a month end, an absent lead time
being the contract's default of 1, the date holding across a daylight-saving change, a disabled or unknown plan and every
non-planned status producing none, a reminder date that has passed (today included, to the minute) being left to the
centre, nearest-first with a cap, a malformed date refused; the text carrying no amount or currency by default and the
amount only when asked, and following the app language; the id being stable, 31-bit and distinct over 200 occurrences;
the scheduler touching and prompting nothing on an unsupported platform or with nothing to remind of, not prompting a
user who has allowed notifications, prompting once with a reminder waiting, scheduling nothing and not asking again after
a refusal, and a repeated pass leaving one notification each; and the whole pass through the real `PrudentRepository`
over a mock server (the plans and the upcoming window read, a skipped occurrence ignored, the horizon sent, no plans read
on an unsupported platform, a failed read an error with nothing scheduled).

**Not verified, and stated rather than implied:** no notification was delivered on a device or simulator. The plugin's
scheduling, the permission prompt, the Android receivers and desugaring, the iOS delegate and the Windows toast were
compiled where the toolchain allows (see the commit) but never seen to fire. A scheduled notification is a wall-clock
event days away, and the dev loop cannot wait for it. Until someone runs it on a phone, "scheduled" means "handed to
the plugin without an error", not "appeared".

---

## ADR-055 — A reminder is an occurrence the server finds due; only "the user has read it" is stored

**Date:** 2026-10-06. **Status:** accepted. **Follows:** ADR-054 (the plan's reminder setting, and "what a due reminder
is" left to this task), ADR-045 (what can be calculated is never stored), ADR-039 (overdue is derived, and a view
generates what it reads), ADR-037 (every date on a plan is in the plan's own zone), ADR-040 (only confirming moves
money), ADR-053 (a tab's conventions: refusal shown in the server's words, nothing re-derived on the client).

### Decision

The second M5 task (jlogicsoftware/prudent#68 — "show due and overdue reminders with unread/read state and
navigation to the relevant planned occurrence") adds the in-app reminder centre.

- **A planned occurrence has a reminder when its plan's reminder is on and its date is no further ahead than the
  plan's lead time — and it keeps one, as an overdue one, until it is confirmed or skipped.** "Due" is
  `today >= date − lead_days` and "overdue" is `date < today`, both on the plan's own calendar day
  (`Recurrence.time_zone`), so a Warsaw plan is not made due or overdue by the server's UTC midnight. A completed or
  skipped occurrence is resolved and has no reminder; a plan whose reminder is off has none at all, however overdue.
  `ReminderResource.hasReminder` is the one place that says so, and the list's query bound and the single-row routes
  both use it. **None of this is stored** (ADR-045): there is no reminder row, no job to miss at midnight and no stale
  reminder to find after a plan is edited — a plan edit that drops an occurrence, a skip, a confirmation or a switched
  reminder simply stops producing one, because the next read does not find it.
- **The one stored fact is that the user has read it: `prudent_plan_occurrence.reminder_read_at`, nullable.** `NULL`
  is unread, and is what every existing and every newly generated occurrence has (the generator's insert names no
  value, as it names no state). It is a column and not a table because a reminder is not an entity: a table would be a
  one-to-one join on the occurrence, and would have a row to remove wherever an occurrence is removed (a plan's
  delete, a rule change dropping still-planned occurrences) where a column goes with its row — so there is no
  retention, RLS or cascade change either. A timestamp, not a boolean: it is what the user did and when, and reading
  twice keeps the first time. Written only through `markReminderRead` / `markReminderUnread`.
- **`/api/v1/reminders`, addressed by the occurrence's id.** `GET` lists every current reminder oldest date first, so
  the most overdue lead; `POST /{occurrenceId}/read` and `/unread` set one; `POST /read-all` sets every current one and
  answers with the list. Each `DueReminder` carries the `PlanOccurrence` (with its plan's fields, and its status —
  `PLANNED` while it is within the lead time, `OVERDUE` once its date has passed, which is how a screen tells "due"
  from "overdue" without working it out again), `remind_on` (the date it fell due), `lead_days` and `read`. A read or
  unread of an occurrence that has no reminder right now — its plan's reminder is off, it is resolved, it is not yet
  within the lead time — is a **409**, not a silent success: a client that is behind is told so and refetches, and the
  alternative would let a stale tap write a flag on something that is not a reminder. An unknown, malformed or
  someone else's id is a 404, as everywhere. The occurrence is locked for the transaction, so a read racing a
  confirmation sees the confirmation or is refused.
- **Listing generates what it reads, as the occurrence views do (ADR-039).** No job materialises occurrences, so a
  reminder whose occurrence has never been generated would never appear. `OccurrenceGenerator.ensureWindow` is the
  window — `LOOKBACK_DAYS` back, the plan's lead time ahead, never before the plan's first date — and the occurrence
  views now call it too, so there is one definition of the window rather than two copies. A plan whose reminder is off
  is not generated for by the centre.
- **Read state belongs to the occurrence, and is not reset by anything.** It survives the plan's reminder being
  switched off and on again, and a skipped occurrence being restored. Becoming overdue does **not** make a read
  reminder unread again: a flag that flips by itself would be a state the user did not set.
- **The client: a bell with the unread count on the overview, opening the centre.** The overview is where the app
  opens, and a seventh navigation tab would sit in "More" on mobile (`zenMaxItemsMobile = 4`), hiding exactly the badge
  that makes it useful. The count is in the tooltip and the semantics label as well as the badge. The centre groups
  reminders by the server's status — "Overdue", then "Due soon" — and says unread with a filled bell, a bold title and
  a semantics label, never weight or colour alone; it never compares a date with the device's clock. Opening a
  reminder marks it read (it has been seen) and then opens the occurrence; the button on a tile flips either way; "mark
  all as read" is in the bar. A refusal is shown in the server's words and the list is fetched again, so a reminder
  resolved on another device does not linger.
- **Navigation to the occurrence is a screen that can act on it.** There was no client screen for an occurrence at all
  (CLAUDE.md, M2), so a reminder had nowhere to lead. `OccurrenceDetailScreen` shows the occurrence with its account and
  category and offers what its status allows — confirm as planned, skip, or restore — through `OccurrenceActions`, which
  refetches the centre and the overview's planned cash flow, and after a confirmation the records, accounts, budgets and
  free money that a record added by hand also refetches. The status drawn is the server's last answer.

### What this does not decide

- **Local-device notifications, their permission prompt and their reconciliation.** The next three M5 tasks; they read
  this resource's definition of "due" rather than a second one.
- **Confirming with a different date, amount, account or category.** The server takes it (`ConfirmOccurrenceRequest`,
  ADR-040); the occurrence screen confirms exactly as planned, and a form for the overrides is its own piece of work.
- **A plan screen, and so a client way to switch a plan's reminder on.** ADR-054's gap stands: until one exists the
  centre is empty for anyone who has not set a reminder through the API, and its empty state says how it fills.
- **Unread counts on the server, filtering, paging.** The list is bounded by the lookback window and the lead time, and
  the client counts what it holds; an `unread_count` field would be a second copy of a number the list already gives.
- **A reminder resurfacing as unread when it turns overdue.** Deliberately not done (above); if it is wanted it is a
  decision about what "read" means, not a bug here.

### Consequence

Verified by `ReminderResourceTest` (a due reminder with its plan's fields, `remind_on`, lead time and unread state in
both transports; a plan whose reminder is off producing none and generating nothing; switching off and on again keeping
read state; overdue ones oldest first with `OVERDUE` status; the lead-time boundary at 7 and 0 days, both sides; resolved
occurrences excluded; Kiritimati and Pago Pago on one civil date; listing idempotent and generating nothing the second
time; read and unread in both transports; reading twice keeping the first time; read-all in both transports keeping
earlier times and not marking what is not a reminder; 409 for an occurrence with no reminder; 404 for unknown and
malformed ids and for another user's; 401 unauthenticated; skip ending a reminder and restore returning it still read;
confirm ending it with no record created by listing or reading), `OccurrenceReminderReadSchemaTest` (the column exists,
is nullable and timestamptz, round-trips, and goes with its row), and the existing `OccurrenceResourceTest` unchanged
over the shared window. On the client, `reminder_views_test.dart` (grouping, dates and amounts, unread said in words,
empty and failed states, a tile flipping one reminder, mark-all, a refusal shown and the list refetched, opening marking
read once and not twice, a refused mark keeping the occurrence closed, confirm posting an empty body and ending the
reminder, skip and restore, the bell's badge and tooltip), `reminder_figures_test.dart`, the repository calls in
`prudent_repository_test.dart` and the wire in `wire_round_trip_test.dart` (both formats; `false` and `0` surviving).
The full backend suite passes (688 tests, 25 of them new) and the full client suite passes (230 tests); `task generate` was
run after the last contract change and `reminders.pb.dart`, `reminders.pbenum.dart`, `reminders.pbjson.dart` and the
admin `schema.generated.ts` are its output. `task verify:contracts` compares against the commit, so it is the merge's to
confirm.

**Not verified, and stated rather than implied:** nothing here has been driven in a real browser or on a device — the
widget tests render the screens against a mock server, which is not the same as seeing them on a phone, and there is
still no screen that switches a plan's reminder on, so the centre cannot be filled from the UI.

---

## ADR-054 — A plan's reminder is a setting: off by default, a lead time from a closed set, and nothing stored or sent

**Date:** 2026-10-06. **Status:** accepted. **Follows:** ADR-037 (a plan is a validated rule stored flat on its row,
and "today" is reckoned in the plan's own zone), ADR-039 (a rule lives in one place), ADR-045 (what can be calculated
is never stored), ADR-051 (a switch defaults off, with no backfill).

### Decision

The first M5 task (jlogicsoftware/prudent#40 — "enable/disable and choose supported lead time with validation and a
safe default") gives every plan a reminder **setting**. It does not create reminders: the in-app centre, the local
notifications and their reconciliation are the next four tasks, and they read this.

- **Two columns on `prudent_plan`, not a table.** `reminder_enabled BOOLEAN NOT NULL DEFAULT FALSE` and
  `reminder_lead_days INTEGER NOT NULL DEFAULT 1`. A plan has exactly one setting, so a second table would be a
  one-to-one join (ADR-037's reason for keeping the recurrence flat). `PlanEntity.reminder()` / `setReminder` are the
  only way in or out, as `rule()` / `setRule` are for the recurrence, so the columns cannot be written in a
  combination `ReminderSetting` has not validated.
- **Off by default, and "safe" means that.** A plan that has no reminder chosen produces none, and that includes
  every plan that existed before this migration (no backfill). The reason is the next task's, not this one's: the
  first local notification is also when a platform asks for notification permission, and that prompt should follow
  something the user asked for, not the saving of a plan. The one-day lead time is what the setting holds until the
  user picks another, so switching the reminder on needs no second decision.
- **The lead time is one of 0, 1, 2, 3 or 7 days before the occurrence's date, and anything else is refused (400),
  never rounded.** A client that asks for four days and is quietly given three would show the user a setting that is
  not the one in force. "Days" are the plan's own calendar days (`Recurrence.time_zone`), as every date on a plan is
  (ADR-037). The set lives in `ReminderSetting.SUPPORTED`; the refusal names it. **The database does not list it** —
  the CHECK is structural only (`reminder_lead_days BETWEEN 0 AND 365`) — for the reason `prudent_account.kind` has no
  CHECK: the supported set is the application's to decide, and widening a CHECK is a DDL migration in every
  environment, so adding "14 days" later is a one-line Java change.
- **`lead_days` is `optional`, because 0 is a real lead time.** proto3 decodes an omitted number to 0, which here
  means "on the day"; presence is what tells it from unset. An absent `lead_days` is the default (1); a present 0 is
  the day itself. A whole absent `reminder` is the default setting rather than an error — a plan is useful without
  one. `Plan.reminder` is always present in a response and always states `lead_days`: a response says what is in
  force, never "default".
- **The lead time is kept while the reminder is off**, and is validated even then, so switching off and on again does
  not forget the user's choice and the kept value is always one the server supports.
- **`PUT` is a full replacement, so an absent `reminder` resets to the default** — the rule every other optional
  field on a plan follows (an absent payee or note clears it). The alternative, "absent means unchanged", would give
  one field a different rule from the rest and make the API's semantics depend on which field you are looking at. A
  client that edits a plan sends back the reminder it read, as it does the recurrence.
- **A reminder change is not a recurrence change.** `PlanResource.replace` drops stale still-planned occurrences only
  when the rule differs (ADR-038); the setting is not part of `RecurrenceRule`, so toggling a reminder leaves every
  occurrence where it was. A test pins it, because the cost of getting it wrong is silently deleting the user's
  planned occurrences.

### What this does not decide

- **A client screen.** There is none for plans at all (CLAUDE.md, M2), so none sets this. The repository methods carry
  the field. **The set of supported lead times is not served to the client** — a screen that offers them would
  otherwise hold a second copy of `ReminderSetting.SUPPORTED`. When a plan screen exists, serving the set is the
  better answer than copying it, and that is that task's to settle.
- **Per-occurrence or per-currency reminders, a time of day, repeated nudges.** One setting per plan, in whole days.
  The time of day a notification fires is a device concern for the scheduling task.
- **What a "due" reminder is.** An occurrence's reminder falls due `lead_days` before its date; deriving and
  presenting that is the in-app centre's (the next task), and it should be calculated on read, not stored
  (ADR-045), for the reason overdue is (ADR-039).

### Consequence

Verified by `ReminderSettingTest` (the default, every supported value, 0 versus omitted, a kept lead time, refusal of
unsupported values including ones past the signed range, the message naming the supported set),
`PlanReminderSchemaTest` (the columns default to off and one day on a row nobody set, are never null, and the lead
time is structurally bounded — refused by constraint name), and `PlanResourceTest` over both transports (the default
on create, a stored setting read back by get and list, 0 days, enabled with no lead time, a disabled setting keeping
its lead time, unsupported values refused with nothing saved, a pre-existing plan reading as off, replace changing
it, an absent reminder resetting it, a refused replace leaving the setting unchanged, and a reminder-only change
keeping the occurrences). On the client, `wire_round_trip_test.dart` pins that 0 days and an absent lead time survive
both formats, and `prudent_repository_test.dart` that the setting reaches the wire and a refusal surfaces as an
error. The full backend suite passes (663 tests), and regenerating the contracts a second time changes nothing further
(`task verify:contracts` itself compares against the commit, so it is the merge's to confirm).

**Not verified, and stated rather than implied:** nothing here has been driven in a real browser or on a device —
there is no screen to drive.

---

## ADR-053 — Goals are a tab of their own, and an envelope amount is never drawn the way a balance is

**Date:** 2026-10-02. **Status:** accepted. **Follows:** ADR-052 (progress and guidance are calculated per goal),
ADR-051 (free money per currency), ADR-050 (an envelope is the sum of an append-only history), ADR-049 (a goal is
retired, never deleted), ADR-048 (the budget overview's tab, view state and error/empty conventions), ADR-041
(`zen_ui_widgets` is the rule for new screens), ADR-009 (per currency, never blended). **Completes:** M4
(jlogicsoftware/prudent#37).

### Decision

The fifth M4 task (jlogicsoftware/prudent#67 — "show active and archived goals, history and actions while keeping
envelope amounts visually distinct from account balances") adds the client screens over the reads and writes
ADR-049–052 put on the server. No server or contract change: every figure is already calculated there.

- **A sixth navigation tab, "Goals"**, after Budgets. With `zenMaxItemsMobile = 4` it sits in the mobile bar and
  pushes Analytics and Settings into "More", as Budgets already pushed Settings. Goals are looked at as routinely as
  budgets; a button inside Overview would hide them.
- **The tab shows free money first, then one goal state at a time.** A "Money for goals" card gives, per currency,
  what the eligible accounts hold, what the envelopes hold and what is free (ADR-051), never summed across
  currencies; a negative free amount is said in words and an icon ("Envelopes hold X more than your eligible
  accounts"), not colour alone. Below it a `ZenSegmentedControl` picks Active, Completed or Archived — archived and
  completed goals are a tap away, not hidden, because their history is still the user's (ADR-049). Each segment has
  its own empty state; a failed load says so and draws nothing.
- **A goal card** shows the name, the state when it is not active, the target date, a progress bar and the server's
  whole percent, what is set aside, the target, what is still to save and one line of guidance worded from
  `GoalGuidance` — the client never re-derives which case applies (ADR-052). A card with no progress yet (loading or
  failed) shows only the goal's own name and target, rather than a zero envelope that would read as "nothing set
  aside".
- **A goal opens to a page** with its card, the actions its state allows, and its history newest first. Active:
  add money, withdraw, move, plus edit, mark as reached and archive in the menu. Completed: withdraw and move (money
  can still come out, goal_allocations.proto), edit, archive, reactivate. Archived: a read-only note and reactivate
  only. Offering only what the state allows is a convenience; the server still decides, and a refusal — archiving a
  goal that holds money, an allocation above free money — is shown in the server's words. The add/withdraw/move and
  create/edit forms open through `showAdaptivePresentation`, show what the entry draws on (free money, or what the
  envelope holds) and **do not enforce it**: that rule lives on the server (ADR-050, ADR-051), and a client copy
  would be a second source of truth. They check only that the amount is a positive number, and stay open with the
  server's message when it refuses. A move offers only active goals in the same currency.
- **A history entry is read from the goal's side**: `+` for money in, `−` for money out, so a MOVE is an outflow on
  its source ("Moved to Trip") and an inflow on its target ("Moved from Car"), with its date and note.
- **Envelope amounts are never drawn as plain text.** Every amount that is money *set aside* — on a goal card, in
  the free-money card, in the history — goes through one widget, `EnvelopeAmount`: an envelope icon on the
  `tertiaryContainer` colour, and a semantics label "Set aside for goals: X" so screen readers hear the difference
  too. Account money (eligible and free money, a target, what is still to save) stays plain text, as balances are
  everywhere else. A single widget means the distinction cannot be forgotten on one screen. The card also says in
  words that set-aside money stays in the accounts and never changes a balance or spending.
- **"Today" for guidance is the client's date.** `goalProgressAsOfProvider` sends `asOf` as the device's local
  `YYYY-MM-DD`, because a goal carries no time zone and the server's UTC date can be a day off for the user
  (goals.proto `ListGoalProgressResponse`).
- **What refetches what.** Progress, free money and history are calculated on read, so `GoalsNotifier` invalidates
  all three after any goal change or allocation, and free money is also invalidated by every record, transfer,
  correction and account change — it is a function of eligible balances.
- **The screens are built on `zen_ui_widgets`** (ADR-041): `ZenSegmentedControl`, `ZenButton`, `ZenSelect`,
  `ZenAmountField`, `ZenDateField`. They are the first Prudent screens to use the amount and date fields, which read
  `ZenWidgetsLocalizations` — and the app had never registered that delegate, so the first field to render would
  have thrown. `app.dart` now composes `zenWidgetsLocaleDelegate`, with Prudent's own Polish
  (`PlWidgetsDelegate`) ahead of it for the reason ADR-044's ordering test pins for identity and navigation.

### What this does not decide

- **A delete for a goal or an entry.** There is none on the server (ADR-049, ADR-050), so there is none here.
- **A total across goals or currencies.** There is none on purpose (ADR-009, ADR-052).
- **Reminders on goal progress.** Post-MVP (`docs/github-backlog.md`, M5's closing note).

### Consequence

Verified by `goal_figures_test.dart` (an entry's direction from either side of a move, the move targets, the
status filter, every guidance case including "due this month", an unparseable date), `goal_views_test.dart`
(through the real repository over a mock server: active goals with envelope, percent, target, remainder and
guidance; envelope amounts inside `EnvelopeAmount` and account money outside it, with the semantics label; the
over-allocated warning; completed and archived segments; empty states; a failed load; the history's signs, names
and order; add money sending exactly one ALLOCATE with the right ids, amount and note and refetching progress; a
refusal shown in the open form; a zero amount refused before sending; a move offering only same-currency active
goals; completed and archived goals' actions; reactivate; a refused archive in the server's words),
`goal_providers_test.dart` (free money refetched after a record and an account change; progress and free money after
an allocation; `asOf` is the client's date) and `prudent_l10n_test.dart` (the widgets' own strings in Polish, and the
delegate loads synchronously). The full client suite passes (199 tests) under `ZEN_PLATFORM=macos`, and
`goal_views_test.dart` also under `android` and `web`. `flutter analyze` is clean apart from the pre-existing
analyzer-plugin deprecation warning. `task zen:test:client` passes end to end, including
`zen:verify:widget-files`, once merged with `main` after jlogicsoftware/prudent#122 split out the helper widgets it
had been failing on.

**Not verified, and stated rather than implied:** the screens have not been driven in a real browser or on a device
against a running server.

---

## ADR-052 — Goal progress and contribution guidance are calculated per goal on every read; the percentage rounds down, the contribution rounds up

**Date:** 2026-10-01. **Status:** accepted. **Follows:** ADR-050 (an envelope is calculated from its history, so
progress is calculated from the envelope), ADR-049 (a goal has a target and an optional date, and "whether a date is
still reachable" was left to this task), ADR-009 (per currency, never blended), ADR-045 (a figure that can be
calculated is calculated, never stored), ADR-039 (a rule lives in one place).

### Decision

The fourth M4 task (jlogicsoftware/prudent#66 — "show allocated, remaining and, when dated, the monthly
contribution needed using documented rounding rules") adds one read, `GET /api/v1/goals/progress`, answering a
`GoalProgress` for each of the caller's goals in creation order, completed and archived goals included. Nothing is
stored: no column, no migration, no entry in any history. The calculation is one pure class
(`GoalProgressCalculator`) fed the goals, the envelope balances and a day, so the figure on screen and the figure the
tests pin are the same code (ADR-039).

- **Allocated** is the goal's envelope (`GoalAllocationEntity.balances`, ADR-050), unchanged. **Remaining** is
  `target − allocated`, **never negative**: once an envelope holds the target or more, remaining is zero. Nothing caps
  an envelope at its goal's target (ADR-050 did not and this does not change that), so `allocated` can exceed
  `target` and is reported as it is.
- **Percentage is rounded down**, `floor(allocated × 100 / target)`, at most 100, in `BigInteger` because an envelope
  near the top of the amount range overflows a `long` when multiplied by 100. Down, so **100 means reached** and a
  goal at 99.9% is shown as 99, never as done.
- **The monthly contribution is rounded up**, `ceil(remaining / months_remaining)`, in integer minor units. Up, so
  paying it every month for `months_remaining` months **always reaches the target**; the cost is that the total paid
  can exceed `remaining` by at most `months_remaining − 1` minor units, and the last payment may be smaller. Rounding
  to nearest or down would leave a goal that follows its guidance short. `ceil` is written as `q + (r == 0 ? 0 : 1)`
  rather than `(remaining + months − 1) / months` so a remainder near the top of the range cannot overflow.
- **Months remaining counts calendar months, both ends inclusive**: from the as-of date's month through the target
  date's month. A goal due on 15 December seen on 1 October has three (October, November, December), and one due
  later this month has one, so the whole remainder is the contribution. The target month counts as a month to
  contribute in because the goal is not due until its date, so counting it only partly would make the contribution
  needlessly steep for a goal due on the 31st and needlessly gentle for one due on the 1st; counting a whole month
  for each is the one rule that does not depend on the day of the month. Months, not 30-day periods, so a figure does
  not move because February is short. The target month being counted in full when "today" is already late in the
  as-of month is the same rule seen from the other end, and is accepted.
- **Which case a goal is in is stated, in a fixed order**, as `GoalGuidance`, so a client never has to re-derive why a
  contribution is absent: `NOT_ACTIVE` (completed or archived — figures only), then `REACHED` (an active goal whose
  remaining is zero), `NO_TARGET_DATE` (open-ended), `OVERDUE` (target date before the as-of day), and
  `CONTRIBUTION` — the only case that sets `monthly_contribution_minor` and `months_remaining`. They are `optional`
  so absent is distinguishable from zero. `NOT_ACTIVE` comes first so a goal completed by hand with money still
  missing is not told it is behind; `REACHED` precedes the date cases so a goal that is full is never "overdue".
- **An overdue goal gets no contribution.** A contribution "to catch up by yesterday" has no meaning, and inventing
  one (say, the whole remainder this month) would be advice the user did not ask for. The goal is reported overdue
  with its remaining amount, and moving the date is the user's edit (`PUT /api/v1/goals/{id}`), after which the next
  read gives a figure. A date equal to the as-of day is **not** overdue: it is due today, one month, the whole
  remainder.
- **"Today" is the client's to state.** A goal carries no time zone (the date is a civil date, ADR-049) and the server
  cannot know the user's, so the endpoint takes an optional `asOf` (`YYYY-MM-DD`) and defaults to the server's UTC
  date, as `AnalyticsResource` does for its anchor. The day used is echoed as `as_of`. A malformed `asOf` is a 400,
  not a fallback to today. The alternative — a clock bean as plans have — was not used because plans have a stored
  zone to apply it to and goals do not; a test can name the day directly.
- **No total across goals.** Goals are in different currencies and nothing is converted (ADR-009), and a sum of
  "monthly contributions" across goals in one currency would be a budget the user never made. A client adds them up if
  it wants to, per currency.
- **Eligibility and free money are not consulted.** Whether the user *can* afford the contribution is the free-money
  figure (ADR-051), which is already available; guidance says what the goal needs, not whether it is affordable.
- **Client.** `PrudentRepository.getGoalProgress({asOf})` and nothing else: no screen shows progress yet (#67).

### What this does not decide

- **A screen for goals, envelopes, progress or guidance** (#67), including how a percentage or a contribution is
  formatted for display; the server does not format money.
- **Pacing against what has already been saved this month.** The contribution is the same on the first and the last
  day of a month, and does not credit money allocated since the month began; that would need a monthly history the
  design deliberately does not keep (ADR-050).
- **Reminders** to contribute. They are post-MVP (the backlog's M5 note).

### Consequence

Verified by `GoalProgressCalculatorTest` (the framework-free rules: remaining and percentage, rounding down at 99.9%
and at thirds, an envelope above the target, the overflow boundary at `Long.MAX_VALUE`, the month count across month
and year boundaries and a short month, the ceiling on and off a whole division with the "smallest amount that gets
there" check, due today versus yesterday and earlier in the same month, every guidance case and their precedence, a
goal with no envelope at zero, the order of the list), `GoalProgressTest` (the figures over HTTP in JSON and
Protobuf; the contribution rounded up on the wire; figures following a real allocate, withdraw and move; goals in
two currencies with no total; every guidance case reachable through the API; one goal changing case with the day
asked about; an archived goal still listed; an edit to the date or target changing the guidance, which is what
"stored nowhere" means in practice; the default day; a malformed `asOf` refused in five forms; another user's goals and
envelopes invisible; `/progress` not swallowed by `/{id}`; no identity 401), and the Dart repository and wire tests. `task test:server` passes **612/612**; the client suite passes except
`popup_test.dart`, which fails identically on an untouched `main` and is unrelated (ADR-049 to ADR-051 record the same).

**Not verified, and stated rather than implied:** no screen shows any of this, so nothing was driven in a browser or
simulator; and the month count's treatment of the target month is a product choice made here, argued above, not one
a user has been asked about.

---

## ADR-051 — Goals draw on accounts the user marks eligible; an allocation may not exceed the free money in its currency

**Date:** 2026-10-01. **Status:** accepted. **Follows:** ADR-050 (an envelope is the sum of an append-only
history — and left "what may be allocated" to this task), ADR-014 (an account's balance is derived on every
read), ADR-009 (per currency, never blended), ADR-045 (a figure that can be calculated is calculated, never
stored), ADR-039 (a rule lives in one place).

### Decision

The third M4 task (jlogicsoftware/prudent#65 — "define eligible accounts per currency and prevent allocations
that exceed their available total") decides which money a goal may draw on, and refuses an allocation beyond it.

- **Eligibility is the user's choice, one flag on the account.** `Account.eligible_for_goals`
  (`prudent_account.eligible_for_goals BOOLEAN NOT NULL DEFAULT FALSE`) says money in this account may be set
  aside. An account counts only while it is **also active** (`AccountEntity.fundsGoals()`): an inactive account is
  kept for its history, so what it holds is not money the user is planning with. The flag is **not derived** from
  `include_in_total`, the account's type or anything else — "what counts as my money" and "what may be earmarked"
  are different questions, and a guess would earmark money nobody offered. It is a separate flag from
  `include_in_total` for the reason `include_in_overview` is.
- **Default false, no backfill.** An existing account is not drawn on until its owner marks it; the cost of the
  opposite mistake is one switch. Create and update carry the flag (`CreateAccountRequest` 10,
  `UpdateAccountRequest` 9, `Account` 11). `PUT` is a full replacement (accounts.proto), so a client that does not
  send the flag turns it off — the client's two account forms send it, and a test pins the replacement rule.
- **"Per currency" is the shape of the sum, not a second flag.** An account holds several currencies (ADR-008);
  for each currency, **eligible money** is the sum, over the accounts that fund goals, of the account's *current*
  balance in that currency — opening amount plus its records, the figure an `Account` already reports. Nothing is
  converted: an EUR surplus covers nothing in PLN (ADR-009). A per-(account, currency) flag was considered and
  left out: it would change `CurrencyBalance`, which every create and update already round-trips, to express a
  distinction nobody has asked for.
- **Allocated money is every envelope in the currency, whatever the goal's state.** Money in a completed goal is
  still set aside until it is withdrawn, so it is not free; an archived goal is empty by ADR-050, so it adds
  nothing. This reads the epic's "total active allocation" as *allocation in force*, not as *in an ACTIVE goal*.
- **Free money = eligible − allocated, calculated on every read and stored nowhere.**
  `GET /api/v1/goal-allocations/free-money` returns one `CurrencyFreeMoney` per currency that an eligible account
  holds or a goal is set in (code order), with the accounts that make up the eligible figure in name order. The
  calculation is one pure function (`FreeMoney.calculate`), used by both the endpoint and the cap, so the figure a
  user is shown and the figure an allocation is checked against cannot differ (ADR-039).
- **Only `ALLOCATE` is capped (409).** A `WITHDRAW` lowers the total allocated and a `MOVE` leaves it unchanged,
  so neither can exceed anything. The check follows the overflow check, so an amount no envelope could hold is
  still a 400 however much is free. The message states free and requested in minor units: the server does not
  format money.
- **Free money may be negative, and is reported as such.** Spending a record, or un-marking or deactivating an
  account, lowers eligible money *after* an allocation was made, and an allocation is history that is not
  rewritten (ADR-050). `free_minor < 0` means the envelopes hold more than the eligible accounts do; it refuses
  every further `ALLOCATE` until the user withdraws (or the balances recover) and blocks nothing else. Neither a
  record nor an account edit is refused because of an allocation: the server cannot stop a person spending their
  own money, and a ledger that refused to record what happened would be the worse failure.
- **Concurrent allocations are serialized per user and currency.** The cap reads every envelope in the currency,
  so locking only the goal named would let two allocations to different goals each see the same free money. An
  `ALLOCATE` first locks **all** the caller's goals in that currency, `SELECT ... FOR UPDATE` in id order (the
  order `GoalAllocationResource` already takes any pair in, so no deadlock), then proceeds as before. The currency
  is read as a scalar before the lock so no goal state is read stale. Account balances are *not* locked: a record
  landing between the check and the commit is the over-allocation case above, reported rather than prevented.
  `concurrentAllocationsToDifferentGoalsCannotExceedTheFreeMoney` fires eight allocations over two goals at once
  against 300 free and asserts exactly three succeed; with the lock removed it fails (four succeed) on every run,
  which is how it is known to test the lock.
- **Client.** The new-account and edit-account forms gain the switch ("Available for goals", with a hint that only
  active accounts count) in `en`, `uk` and `pl`, and — being touched — use `ZenSwitchRow` for all their switches
  (ADR-041's rule for touched screens). `PrudentRepository.getFreeMoney()` is the only other change: no screen
  shows free money yet (#67).

### What this does not decide

- **Progress and contribution guidance** (#66) and **any screen for goals or envelopes** (#67). Free money is an
  input to both.
- **A per-account limit** ("at most 500 of this account"), or a share of an account. An eligible account
  contributes its whole balance.
- **Warning when an edit or a spend makes free money negative.** The figure is available; telling the user is a
  screen's job.
- **Idempotency of a retried `POST`**, as in ADR-050.

### Consequence

Verified by `FreeMoneyTest` (the rule with no framework: eligible and active, balances combined with records,
currencies kept apart, an envelope taken off its own currency only, a negative result, an overdrawn eligible
account offsetting the others, account ids in name order), `GoalFreeMoneyTest` (the flag set, read back and
replaced in JSON and Protobuf, and cleared by a `PUT` that omits it; the figure per currency in both modes; an
inactive or un-marked account dropping out; a completed goal still counting; another user's accounts and
envelopes invisible; the boundary — everything free accepted, one unit more refused, and a refusal writing
nothing; the cap across goals and per currency; a withdrawal and a move never capped and a withdrawal freeing
money; spending below what is allocated showing negative free money and refusing allocations until released; no
balance moved; the concurrency test above; an unknown goal still 404 and no identity still 401),
`AccountGoalEligibilitySchemaTest` (the column exists, is never null and is off by default), `GoalAllocationTest`
(every existing case now runs behind an eligible account holding more than it can use), and the Dart wire and
repository tests. `task test:server` passes **560/560**; the client suite passes except `popup_test.dart`, which
fails identically on an untouched `main` and is unrelated (ADR-049 and ADR-050 record the same).

**Not verified, and stated rather than implied:** the migration has run only against the throwaway Postgres the
suite provisions, not against a Supabase database; the two account forms were checked with the analyzer and not
driven in a browser or simulator; and no screen shows free money.

---

## ADR-050 — An envelope is the sum of an append-only allocation history, never a stored amount

**Date:** 2026-10-01. **Status:** accepted. **Follows:** ADR-049 (a goal is its own table, retired and never
deleted — and left open what archiving a goal with money set aside means), ADR-046 (an audit entry is never
deleted by the application; erasure of a person outranks that), ADR-043 (a separate table cannot reach a
balance), ADR-009 (per currency, never blended), ADR-039 (a rule lives in one place).

### Decision

The second M4 task (jlogicsoftware/prudent#64 — "allocate, withdraw and move money between same-currency
envelopes as explicit immutable history entries") adds the actions and the history they leave. What may be
allocated at all (eligible and free money, #65), progress and guidance (#66) and the screens (#67) are the
epic's later tasks.

- **An envelope is the money set aside for one goal, and it is virtual.** Nothing moves between bank
  accounts and no record is written. The history is its own table, `prudent_goal_allocation`, which no
  balance, analytics total or planned cash flow reads, so reserving money cannot change what the user has or
  spent (the epic's "excluded from bank balances and income/expense analytics").
- **The history is the only store.** An envelope has **no stored amount**: it is the entries that put money
  in less the entries that took it out, calculated on every read (`GET /api/v1/goal-allocations/envelopes`
  returns one per goal, zero included). A stored balance would be a second place to keep right and to drift;
  this follows how budget carry-over is calculated (ADR-045). The sum runs in the database, so a running
  total that would overflow a `long` is no problem while the net, which is capped, always fits.
- **Three kinds, one entry each:** `ALLOCATE` (a target goal only), `WITHDRAW` (a source goal only) and
  `MOVE` (both). A move is **one** entry, not a withdrawal plus an allocation, so the two halves cannot be
  recorded separately, left half-applied or fail to match. The amount is **positive** and the direction is the
  kind, never the sign; zero is refused for the reason ADR-043 gives (it is what an omitted proto3 field
  decodes to). Which goal ids each kind needs is stated once, in `AllocationKind`; a body that carries an id
  its kind does not use is refused at 400 rather than having the extra field ignored.
- **Entries are immutable.** The API has no update and no delete route, and the **database refuses an
  `UPDATE`** (a trigger), so the guarantee does not rest on the resource. A mistake is corrected by another
  entry — a withdrawal or a move — which is exactly the audit trail a correction should leave. `DELETE` is
  deliberately **not** blocked: the retention cascade for an anonymised user removes the history, because
  erasure of a person outranks the history's own promise (the reasoning of ADR-046 for the reset history).
- **Currency safety is structural.** An entry stores the currency and references each goal **together with
  it** (a composite foreign key onto `prudent_goal (id, currency)`, which a goal's immutable currency makes
  safe), so the database itself refuses an entry whose currency is not its goal's — including the second goal
  of a move. The resource states the same rule first, refusing a move between currencies at 400; there is no
  conversion (ADR-009).
- **Goal state decides what may be done.** Money goes **into** an `ACTIVE` goal only (`GoalState.acceptsMoney`)
  and comes **out of** an `ACTIVE` or `COMPLETED` one (`releasesMoney`): a goal that has been reached can still
  release what is left in it, and an archived goal is read-only (ADR-049), so nothing enters or leaves it. A
  refusal is **409**.
- **Archiving a goal that still holds money is refused (409).** This settles the question ADR-049 left to this
  task. An archived goal cannot release money until it is reactivated, so allowing it would strand money in a
  goal the user said they were finished with, and would make the sum of "active" envelopes (#65) depend on which
  archived goals still hold something. The user withdraws or moves the money first. Completing a goal with money
  in it stays allowed.
- **An entry cannot take an envelope below zero** (409), and cannot raise it past what an amount can hold (400).
  The check reads the balance, so the goals involved are **locked for the transaction** — `SELECT ... FOR
  UPDATE`, in id order so two moves over the same pair cannot deadlock. The same lock guards the archive
  check, so an entry written between "it is empty" and the commit cannot leave money in an archived goal.
  `concurrentWithdrawalsCannotOverdrawAnEnvelope` fires eight withdrawals of the whole balance at once and
  asserts exactly one succeeds; with the lock removed it fails (two succeed), which is how it is known to
  test the lock.
- **There is no cap yet.** Nothing stops the total allocated from exceeding the money the user actually has.
  The epic's "total active allocation cannot exceed eligible money" is #65, which defines eligible accounts per
  currency; until then an allocation is checked only against the goal and its own envelope.
- **Each entry records who wrote it** (`created_by`, the user id today) and when, plus an optional note of up
  to 500 characters (trimmed; a blank note is stored empty), as the carry-over reset history does.
- **The history is listed newest first, then by id, optionally narrowed by `?goalId=`** to entries that put
  money into or took it out of that goal. It is unpaginated, as records are in v1.
- **Row-level security and retention** follow every other table: `prudent_goal_allocation` is in the
  repeatable RLS script's list and in `PrudentRetentionCleanup`, ahead of goals (the entries reference them
  with no cascade).

### What this does not decide

- **What may be allocated** — which accounts count as eligible and what is already spoken for (#65).
- **Progress and contribution guidance** — allocated, remaining and the monthly amount (#66). The envelope
  amount is the input.
- **Any screen.** The client gains repository methods and generated messages only (#67).
- **Idempotency of a retried POST.** Two identical requests are two entries. A client that retries after a
  timeout should read the history first.
- **A user-supplied time for an entry.** `created_at` is the server's clock; backdating is not offered.

### Consequence

Verified by `GoalAllocationTest` (each kind recorded and read back in JSON and Protobuf; the envelope changing
by exactly the amount; a move shifting money between two envelopes as one entry; a withdrawal emptying but not
overdrawing, and a refused entry changing nothing; the overflow edges, including a net that fits when the
running totals would not; no move between currencies; refusal of a non-positive amount, a missing or unknown
kind, a missing or surplus goal id, a move to the same goal, a malformed id (400) and an unknown one (404) and
an over-long note; money into an active goal only, out of an active or completed one, and an archived goal
read-only until reactivated; archiving refused while an envelope holds money; history newest first, narrowed
by goal, with no edit or delete route; a mistake corrected by a new entry; another user's goals and entries
invisible and unusable on every path; one envelope per goal including empty and archived ones; account
balances, analytics and records untouched; concurrent withdrawals unable to overdraw), `AllocationKindTest`
and `GoalStateTest` (the rules with no framework around them), `GoalAllocationSchemaTest` (each constraint
refused by name against the owner connection, including the composite currency keys, the immutability trigger
and the fact that deletion still works), `PrudentRowLevelSecurityTest` and `PrudentRetentionCleanupTest` (both
extended), and the Dart repository tests. `task test:server` passes **528/528**; the client suite passes except `popup_test.dart`, which
fails identically on an untouched `main` and is unrelated (ADR-049 records the same).

**Not verified, and stated rather than implied:** the migration has run only against the throwaway Postgres
the suite provisions, not against a Supabase database, and no screen exists to drive the endpoints from a
client.

---

## ADR-049 — A goal is its own table with a lifecycle state, retired and never deleted

**Date:** 2026-10-01. **Status:** accepted. **Follows:** ADR-043 (a budget is its own table, so it
cannot reach a balance), ADR-047 (retire a used thing, never delete it; refuse a change that is not
one), ADR-039 (a state machine lives in one place), ADR-009 (per currency, never blended).

### Decision

The first M4 task (jlogicsoftware/prudent#38 — "create a goal with name, currency, target amount and
optional date; support active, completed and archived states without deleting history") adds the goal
and nothing that hangs off it. Allocations, eligible and free money, progress and the views are the
epic's later tasks (jlogicsoftware/prudent#64–#67).

- **A goal is its own table, `prudent_goal`,** and `GoalResource` at `/api/v1/goals`. It is something the
  user wants to save for, not money that moved, so — as with plans and budgets — nothing that computes a
  balance or an analytics total reads it, and creating, editing or completing one changes no figure.
- **Fields:** a server-minted `id`, a non-blank `name` (trimmed, not unique), an ISO-4217 `currency`, a
  **positive** `target_amount_minor`, an optional `target_date`, a `status` and two timestamps. Zero is
  refused for the target for the reason ADR-043 gives for a budget amount: it is what an omitted proto3
  field decodes to. The schema holds the same invariants as the resource (positive target, non-blank
  name, upper-case currency, a known status), so a writer that skips the resource is refused too.
- **The currency is chosen at creation and never changes.** Money set aside for a goal (the next task) is
  held in that currency, so a goal that changed currency would change what that history means. It is
  therefore absent from the update request rather than present and ignored.
- **The target date is a civil date and is not required to be in the future.** Whether a date is still
  reachable is progress guidance (#66), and the server has no business refusing a date for being past: a
  goal created or imported late is still a goal. An absent date on update **clears** it — the update is a
  full replacement, as everywhere else in the API.
- **Three states, `ACTIVE`, `COMPLETED` and `ARCHIVED`, persisted by name,** with the transitions in one
  place (`GoalState`) and routes for each: `POST /{id}/complete` (active → completed), `/archive` (active
  or completed → archived) and `/reactivate` (completed or archived → active). **Nothing is terminal,**
  because nothing is deleted: a goal marked reached by mistake, or archived and wanted again, comes back
  rather than being recreated, which would orphan whatever history hangs off the original. A request for a
  change that is not one — completing a goal that is not active, archiving an archived one — is refused at
  409 rather than accepted quietly, as ADR-047 does for categories.
- **There is no `DELETE`.** "Without deleting history" is taken literally and early: the allocation
  history of the next task will point at a goal, and a goal that could vanish would take the meaning of
  that history with it. This is the one place the design differs from budgets, which are hard-deleted
  because a budget is a setting rather than something money is later recorded against. The only thing
  that removes goal rows is the retention cascade for an anonymised user, which outranks the promise for
  the reason ADR-046 gives for the reset history.
- **An archived goal is read-only.** `PUT` is refused at 409 until it is reactivated, so a stray edit
  cannot change what the user retired. A completed goal can still be edited (to correct its target after
  the fact). Editing never moves `status_changed_at`; only a transition does, and a refused transition
  leaves it alone.
- **`status_changed_at` rather than one timestamp per state.** It answers "when did this last change
  state" and is equal to `created_at` until the first change. A full per-transition history (who, when,
  from what) is not stored; it was not asked for, and the allocation history is the audit trail the epic
  cares about.
- **The list is the caller's goals, oldest first, optionally narrowed by `?status=`** with the exact
  constant name; anything else is a 400, not a guess. Archived and completed goals are listed like any
  other, so history stays readable.
- **Row-level security and retention** follow every other table: `prudent_goal` is in the repeatable RLS
  script's list and in `PrudentRetentionCleanup`.

### What this does not decide

- **How an allocation refers to a goal, and what happens to one when its goal is archived** (#64). The
  table carries no reference to anything and nothing references it yet. Whether archiving a goal with
  money still set aside is allowed is that task's question: it is the one that knows what "set aside"
  means.
- **Whether a goal may be completed before its target is allocated** (#66). Completing is the user's
  statement that it is done, and the server does not check it against a figure that does not exist yet.
- **Any screen.** The client gains repository methods and generated messages only, like budgets before
  their screen (#67).
- **Goal names being unique.** They are not; two goals called "Holiday" are the user's business.

### Consequence

Verified by `GoalResourceTest` (create and read back in JSON and Protobuf; an optional and a past date; a
lower-case currency and a padded name normalised; refusal of a blank name, a non-positive target, a
non-ISO-4217 currency and a malformed or impossible date, each leaving no goal behind; an edit that
changes name, target and date but not currency, status or timestamps, and an absent date clearing; an edit
refused identically to a create and changing nothing; an archived goal read-only until reactivated; every
permitted transition, every refused one, and a refused one leaving the goal untouched; no delete; the
status filter and creation order; another user's goal answering 404 on every verb; a malformed id
answering 404; and a goal leaving accounts, records and analytics untouched), `GoalStateTest` (the
transition table), `GoalSchemaTest` (each constraint refused by name against the owner connection),
`PrudentRowLevelSecurityTest` and `PrudentRetentionCleanupTest` (both extended), and the Dart repository
tests. `task test:server` passes **476/476**; the client suite passes except `popup_test.dart`, which
fails identically on an untouched `main` and is unrelated.

**Not verified, and stated rather than implied:** the migration has run only against the throwaway
Postgres the suite provisions, not against a Supabase database, and no screen exists to drive the
endpoints from a client.

---

## ADR-048 — The budget overview is a tab of its own, one month in one currency, and its percentage is measured against what was available

**Date:** 2026-10-01. **Status:** accepted. **Follows:** ADR-047 (a month without a budget is an empty
answer; archived categories keep their history), ADR-046 (a reset is named by the summary), ADR-045
(carry-over), ADR-044 (plan, actual and remaining are calculated on read; percent, empty and overspent
states are "task 6"), ADR-009 (per currency, never blended). **Completes:** ADR-044's "What this does not
decide — Percent, empty and overspent states (task 6)".

### Decision

The sixth M3 task (jlogicsoftware/prudent#63 — "navigate months and show plan, actual, carry-over,
remaining amount and percentage with distinct overspent and empty states") adds the screen that
renders `GET /api/v1/budgets/summary`. No server or contract change: the summary already carries every
figure, and nothing here is stored.

- **A fifth navigation tab, "Budgets"**, beside Overview, Records, Analytics and Settings. A budget is
  looked at monthly and routinely; a button inside another screen would hide it.
- **One month in one currency at a time.** Previous/next buttons move by calendar month with no limit
  (a budget can be set ahead), and "This month" appears only away from the current month. The currency
  is picked from the currencies the user holds accounts in, main currency first, with `ZenSelect`
  shown only when there is more than one — the same set the analytics screen offers. Month and
  currency are view state, not settings: they live in the screen's own state and start at the current month and
  the main currency. With no account there is no currency to budget in and the screen says so.
- **A card per budgeted category, and one for the month's totals,** each showing plan, carried over,
  spent (`actual`, net of refunds), remaining and the percentage used with a progress bar. The
  carry-over row is always drawn, even at zero, so cards line up. A reset is shown as "Carry-over
  reset from <month>" from `carry_over_reset_month`, so a zero is visibly a reset and not missing
  history. Cards are ordered by category title on the client (the server's id order is stable but not
  readable). An archived category is labelled "Archived" and keeps its card (ADR-047).
- **The percentage is `actual ÷ (plan + carry-over)`, rounded down.** `remaining` already includes the
  carry-over (ADR-045), so measuring against the plan alone would show 100% for a category that still
  has money left from last month, or under 100% for one that is overspent. Rounding down means a
  month that has not used its money never reads 100%. It is over 100 once overspent and 0 when refunds
  outweigh spending. When the carry-over has consumed the whole plan (`plan + carry-over ≤ 0`) there is
  nothing to measure against and the percentage is **absent** — no bar and no number — rather than a
  figure that could be read as meaningful. It is integer arithmetic on `Int64`, and no amount goes
  through a `double`.
- **Overspent is `remaining < 0`, using the server's `remaining`,** so the screen cannot disagree
  with the summary, and it includes an overspend carried in with nothing spent this month. It is said
  in words ("Overspent by X"), an icon, and the error colour on the bar — never colour alone. The totals
  card has the same state, judged on the totals.
- **Empty is its own state.** A summary with no items (ADR-047: no category is budgeted in that month
  and currency) shows "No budgets for <month> in <currency>." and no card, because a card of zeros would
  read as "budgeted and untouched". A failed load is reported and draws nothing, rather than zeros.
- **A change to a record refetches the summary.** `RecordsNotifier` invalidates `budgetSummaryProvider`
  on add, edit and delete, because `actual` is a sum over records and a stale figure would be wrong with
  no error to show for it. Transfers and balance corrections are excluded from `actual` (ADR-044), so
  they do not.

### What this does not decide

- **Setting, editing or deleting a budget from the client.** The repository methods exist; no screen
  calls them, so a budget can still only be created through the API. The empty state therefore does not
  tell the user to add one. A budget editor, and a reset/audit-history screen, are new scope.
- **Spending in a category with no budget.** It is in no figure (ADR-044) and the overview shows
  nothing for it. Showing "unbudgeted spending" needs a new field or endpoint.
- **A carry-over into a month where the category has no budget** (ADR-047's open point). The summary
  lists a month's budgets, so such a category has no card and its carry-over is not shown. The overview
  does not need a new field to be correct, only to be complete; this is left until a user wants it.
- **Auditing budget edits** (the epic's remaining work, jlogicsoftware/prudent#35).

### Consequence

Verified by `budget_figures_test.dart` (month arithmetic across a year boundary; percentage rounding,
the carry-over denominator, zero and absent percentages, large amounts; overspent at, past and below
zero, and from carry-over alone; ordering), `budget_overview_test.dart` (every figure and the totals on
screen, an overspent card, an overspend carried in, the empty month, month navigation both ways and back
to the current month, one currency per request, an archived category, a reset note, an unknown category,
a failed load, no accounts) and `budget_summary_provider_test.dart` (a record add, edit and delete each
refetch; an unrelated read does not). `flutter analyze` is clean apart from the pre-existing
analyzer-plugin deprecation warning. The full client suite passes except `popup_test.dart`, which fails
identically on an untouched `main` and is unrelated to this change.

**Not verified, and stated rather than implied:** the screen has not been driven in a real browser or
on a device against a running server; the widget tests render it with a fake summary.

---

## ADR-047 — A category that has been used is archived, never removed; an archived category keeps its history and takes nothing new

**Date:** 2026-10-01. **Status:** accepted. **Follows:** ADR-046 (a carry-over reset is a kept audit
entry), ADR-045 (carry-over is a sum over earlier budgeted months), ADR-044 (plan, actual and
remaining are calculated on read), ADR-043 (a budget is the slot it fills), ADR-008 (refuse rather
than orphan). **Completes:** ADR-046's "What this does not decide — Category lifecycle (task 5)".

### Decision

The fifth M3 task (jlogicsoftware/prudent#62 — "inactive or deleted categories and months without a
budget retain readable history and cannot corrupt totals") gives a category two ways out of use and
says exactly what each leaves behind.

- **Inactive means archived.** `prudent_category.archived_at` (nullable `TIMESTAMPTZ`; `NULL` is
  active, which is what every existing row is) and `Category.archived` on the wire.
  `POST /api/v1/categories/{id}/archive` and `/restore` are the only things that change it — create
  and replace never do, so renaming an archived category does not quietly bring it back. Archiving
  an archived category, or restoring an active one, is 409, as skip and restore are for occurrences
  (ADR-039).
- **An archived category stays where it was.** `GET /api/v1/categories` still returns it, flagged,
  because a record, plan or budget reads its category's name through that list; hiding it would turn
  history into ids. Nothing that sums reads the flag: the budget summary, carry-over, resets, spend
  analytics and balances are calculated from the same rows as before, so archiving changes **no
  figure**, and the category's budgets remain in the summary and in the totals, which stay the sum of
  the listed items.
- **An archived category takes nothing new.** A write that would *add* a reference to it is refused
  with 409: a new record, a new plan, moving a record or plan into it, filling an empty budget slot,
  and confirming an occurrence into it (the confirmation defaults to the plan's category, and the
  request can name another for that transaction alone, so the user is never stuck). A write that
  leaves an existing reference as it is is not new and is allowed: editing the amount or note of a
  record or plan already filed under it, correcting or deleting a budget that already exists, and
  making or revoking a carry-over reset on its history. The rule is one method,
  `CategoryEntity.requireActive`, called where each writer already looks the category up.
- **A category is deleted only while nothing points at it.** Delete stays refused (409) while any
  record, plan, budget or carry-over reset references the category, now saying "or archive it", and
  the database's foreign keys (no `ON DELETE CASCADE`) are the backstop behind it. That is the
  answer to what a deleted category should leave readable: **a used category is never deleted, so
  there is no deleted category with history to read.** A category that never had any can be deleted,
  archived or not, and there is nothing to lose. This is the same stance ADR-008 and ADR-043 took for
  records and budgets, extended to the one reference ADR-046 could not ask the user to delete first.
- **A month without a budget is an empty answer, and is not a zero.** The summary of a month in
  which no category is budgeted has no items and every total zero, however much was spent
  (ADR-044: spending in an unbudgeted category is in no figure) and whichever earlier months are
  budgeted. A category budgeted before and after that month carries across it unchanged (ADR-045),
  archived or not.

### What this does not decide

- **Soft delete.** The alternative — mark a deleted category rather than refuse, and let a deleted
  category's name live on its history — was rejected because it needs a second state beside archived
  that means almost the same thing, and every query would have to decide which of the two to
  exclude. Archive is the retire verb; delete is for mistakes.
- **A carry-over that has no budget this month.** A category budgeted in August and not in
  October has a carry-over that no October row shows, archived or not: the summary lists a month's
  budgets and ADR-045 sums over earlier ones. If a screen must show carry-over for an unbudgeted
  month it is a new field or endpoint, and task 6 will say whether it needs one.
- **Archiving's effect on a screen.** The client gains the repository methods and stops offering an
  archived category in the record form (keeping the one a record being edited already has). A
  categories screen with an archive action, and labelling archived ones in lists, are not built.
- **Account erasure.** Unchanged: the retention cascade deletes a user's categories with the rest of
  their data, archived or not (ADR-046).

### Consequence

Verified by `CategoryLifecycleTest` (archive and restore in both transports; both 409s; ownership;
an edit not restoring; each refusal and each exemption for records, plans, confirmation and budgets;
that archiving leaves the summary, the analytics and the record list identical and the totals equal
to the sum of their items; resets on an archived category; an empty month; carry-over across a gap;
delete allowed for an unreferenced category and refused for a record, plan, budget and reset, with
the refusal naming archiving), `CategoryArchiveSchemaTest` (the column, its null default, set and
clear), a client repository test and `selectableCategories`'s test, and the regenerated Dart
messages and admin schema.

---

## ADR-046 — A carry-over reset is a boundary the calculation stops at, and every reset is a kept audit entry

**Date:** 2026-10-01. **Status:** accepted. **Follows:** ADR-045 (carry-over is a sum over earlier
budgeted months, calculated on read), ADR-043 (a budget is the slot it fills), ADR-009 (per
currency, never blended). **Completes:** ADR-045's "What this does not decide — Reset (task 4)".

### Decision

The fourth M3 task (jlogicsoftware/prudent#61 — "reset from a chosen month onward without deleting
prior budgets or hiding who/what changed the result") adds a reset that starts a category's
carry-over again from a month the user chooses.

- **A reset is a boundary, not an edit.** `prudent_budget_carry_reset` holds one row per reset:
  category, month, currency. For a category, month `M` and currency, carry-over into `M` is now the
  sum of `plan − actual` over its budgeted months in `[R, M)`, where `R` is the latest live reset at
  or before `M` (and unbounded below when there is none). Carry-over into `R` itself is zero. No
  budget and no record is touched, so prior budgets survive and **no earlier month's own plan,
  actual, carry-over or remaining changes** — a reset at `R` says nothing about a month before `R`,
  and the query that reads resets stops at the requested month. Still calculated on read, stored
  nowhere.
- **Scope is one category in one currency**, the same granularity as carry-over itself, so one
  category's reset never touches another's and one currency's never touches another's (ADR-009). The
  month need not have a budget.
- **Every reset is its own audit entry, and entries are never deleted.** A row records who made it
  (`created_by`, the authenticated user), when, an optional note (≤ 500 characters), and
  `discarded_minor` — the carry-over into the reset month as the summary showed it just before, so
  the entry says what the user chose to throw away. `discarded_minor` is a snapshot: editing an
  earlier budget afterwards does not rewrite it. It is computed by the same `carryOverInto` the
  summary uses, so the two cannot disagree.
- **Undoing is revoking, not deleting.** `POST /api/v1/budget-carry-over-resets/{id}/revoke` sets
  `revoked_at`/`revoked_by` on the same row; the carry-over is counted in full again and the history
  still shows the reset and who took it back. There is no `DELETE` route. At most one **live** reset
  exists per slot, held by a partial unique index and filled with `INSERT … ON CONFLICT DO NOTHING`,
  so two racing requests leave one row and the other is told 409; a revoked slot can be reset again
  and both entries stay.
- **The result names its cause.** `CategoryBudgetSummary.carry_over_reset_month` is the month of the
  reset that bounds the figure (empty when none), so a carry-over that is smaller than the history
  alone would give is visibly the result of a reset. The entry behind it is in
  `GET /api/v1/budget-carry-over-resets` (the whole history, revoked entries included, newest first,
  filterable by `categoryId` and `currency`).
- **Why `created_by` when it always equals `user_id`.** Only the owner can write here today. History
  already written cannot be backfilled truthfully, so the column exists from the first row for the
  day a second kind of writer does.
- **Wire:** `BudgetCarryOverReset`, `ResetBudgetCarryOverRequest`,
  `ListBudgetCarryOverResetsResponse` and the new summary field are in `budgets.proto`. The OpenAPI
  schema for `CategoryBudgetSummary` also gains the `carryOver*` fields ADR-045 added to the proto but
  left out of `openapi.yaml`.

### What this does not decide

- **Category lifecycle (task 5, jlogicsoftware/prudent#62).** A category with reset history cannot be
  deleted (409), because deleting it would erase or orphan the entry the audit trail promises to
  keep, and unlike budgets there is nothing the user can delete first. That is the conservative
  answer, not a settled one: whether a deleted category should leave a readable name behind on its
  history is exactly that task's question. Account erasure is a different thing — the retention
  cascade deletes a user's reset history with the rest of their data, because erasing a person
  outranks the history's never-deleted rule, which is a promise to that person.
- **Audit of budget edits.** The M3 roadmap line "a readable audit trail of budget changes and
  resets" has two halves. This task delivers resets; a budget amount is still overwritten in place
  with no history of who changed it.
- **Reset-all.** One reset names one category and currency; a client resetting every category sends
  one request each. A bulk call would be a new endpoint and is not needed until a screen asks.
- **Percent / overspent / empty states and any screen (task 6).** The client gains only repository
  methods.

### Consequence

Verified by `BudgetCarryOverResetTest` (both transports; the audit fields; a reset restarting the
figure and naming itself; earlier months and budgets unchanged; mid-history, later-than-requested,
per-category, per-currency and per-user boundaries; a second reset discarding only what the first
left counted; the snapshot; revoke restoring the figure and keeping the entry; revoke twice and
reset twice refused; validation; ownership; no delete route; category delete refused),
`BudgetCarryResetSchemaTest` (the live-slot index, revoked rows not counting, each check
constraint, the foreign key), `BudgetCalculatorTest`, the row-level-security and retention suites
extended to the new table, and a client repository test. `task test:server` green, 403 tests.

---

## ADR-045 — A budget's unspent or overspent amount carries forward as a sum over its earlier budgeted months, calculated on read

**Date:** 2026-10-01. **Status:** accepted. **Follows:** ADR-044 (plan, actual and remaining are
calculated on read and stored nowhere), ADR-043 (a budget is the slot it fills), ADR-009 (per
currency, never blended). **Amends:** ADR-044's "Carry-over is not part of it" — `remaining_minor`
now includes carry-over, as ADR-044 said task 3 would decide.

### Decision

The third M3 task (jlogicsoftware/prudent#60 — "positive and negative results propagate across gaps
deterministically and historical edits recalculate later months") carries each budgeted category's
underspend and overspend into later months.

- **Carry-over is a sum, not a chain.** For a category, month `M` and currency, the carry-over into
  `M` is the sum of `plan − actual` over **every earlier month in which that category has a budget
  in that currency**. Underspend is positive, overspend negative, so an overspend is paid back by
  later underspend and an underspend is spent down by later overspend. `actual` is exactly
  ADR-044's (net of refunds, posted ledger records only), so the two never disagree about what a
  month spent.
- **A gap is a month that has no budget, and it contributes nothing.** The figure passes across it
  unchanged, however many months long, and spending in the gap is not measured against anything
  (consistent with ADR-044: spending in an unbudgeted category is in no figure). The alternative —
  treating a gap as a zero plan — would turn every month of unbudgeted spending into a negative
  carry, penalising a user for a month they chose not to budget. Because the figure is a plain sum
  over budgeted months, it is deterministic and independent of any iteration order.
- **The first budgeted month carries zero.** Nothing before a category's first budget is
  measured.
- **Per category and per currency.** One category's surplus never offsets another's, and a
  currency's carry is built only from that currency's budgets and records (ADR-009), in the query
  rather than filtered afterwards.
- **Calculated on every request, stored nowhere** — which is what makes historical edits
  recalculate: raising an earlier month's budget, deleting a budget, or adding, editing or
  deleting an earlier record changes every later month's carry on the next read. No column holds
  a result that could go stale, and no recalculation job exists to forget to run.
- **Wire:** `CategoryBudgetSummary.carry_over_minor` and `BudgetSummaryResponse.total_carry_over_minor`
  are new fields. `remaining_minor` and `total_remaining_minor` are now
  `carry_over + plan − actual`, i.e. what may still be spent *this month*. Nothing renders them
  yet, so the redefinition breaks no screen; `plan_minor` and `actual_minor` are unchanged and
  remain the month on its own. For a category's first budgeted month `carry_over_minor` is 0 and
  every figure is as ADR-044 gave it.
- **Server:** `BudgetCalculator.carryOver` (pure), `BudgetEntity.listEarlier` and
  `RecordEntity.netByCategoryAndMonthBefore`, which applies the same record filter as
  `netByCategory` grouped by month. The request reads earlier data only for the categories listed
  in the requested month.

### What this does not decide

- **Reset (task 4).** There is no "start again from this month" yet, so carry-over currently runs
  from a category's first budget with no upper bound on how far back it reaches. A reset is a new
  boundary the sum stops at; the audit trail is that task's.
- **Category lifecycle (task 5)** and **percent / overspent / empty states (task 6).**
- **Cost.** One extra grouped ledger query and one budget query per summary request, bounded to
  the listed categories. If long histories make that slow the answer is an index or a stored
  rollup *derived from* the rows, decided with measurements, not assumed now.

### Consequence

Verified by `BudgetCalculatorTest` (underspend and overspend, accumulation across months, a gap
passing the figure unchanged, a first month carrying zero, remaining and totals including carry)
and `BudgetSummaryTest` against the real queries in both transports (the same, plus a year boundary,
per-category and per-currency separation, refunds, transfers and corrections, another user's data,
and an earlier budget raised and an earlier record deleted both changing the later month), a client
repository test, and the regenerated Dart messages and admin schema.

---

## ADR-044 — A budget's actual is net spending from posted ledger records, calculated on read

**Date:** 2026-09-29. **Status:** accepted. **Follows:** ADR-043 (budgets are a stored limit,
nothing calculated), ADR-009 (per currency, never blended), ADR-014 (a record's date is a civil
date), ADR-040 (a planned occurrence becomes a record only when confirmed).

### Decision

The second M3 task (jlogicsoftware/prudent#59 — "calculations use posted expenses only, handle
refunds consistently and never mix currencies") calculates **plan, actual and remaining** for the
categories budgeted in one month and currency.

- **One read endpoint:** `GET /api/v1/budgets/summary?month=YYYY-MM&currency=XXX`. Both parameters
  are **required** — a summary is for one month in one currency, and a missing currency is a 400,
  never a guess or a sum over several. It answers `BudgetSummaryResponse`: one
  `CategoryBudgetSummary` per budgeted category (ordered by category id) and the totals of the
  listed categories. `month` uses ADR-043's strict `YYYY-MM`; the currency is normalised to upper
  case.
- **Calculated on every request, stored nowhere.** Plan is the ADR-043 budget row; actual is a query
  over `prudent_record`; remaining is their difference. No column holds a result, so a result cannot
  disagree with the rows it came from, and an edited or deleted record is reflected by the next
  read. The arithmetic is `BudgetCalculator`, pure and unit-tested without a database.
- **Plan** is `plan_minor`, the budget's positive amount. **Actual** is `actual_minor`, positive when
  money was spent. **Remaining** is `plan_minor − actual_minor`: negative once overspent, and not
  floored at zero, so the overspend is visible and the totals are exact sums. Carry-over is not
  part of it (task 3).
- **"Posted expenses only" means ledger records.** Actual counts only `prudent_record` rows with a
  category in the budgeted category, in the requested currency, dated within the month, that are
  **neither a transfer leg nor a balance correction** — the same exclusions as
  `RecordEntity.expenseRows`, for the same reasons. A planned occurrence is not a record until it
  is confirmed (ADR-040), so planned, skipped and overdue occurrences are never counted; the
  record a confirmation creates is counted like any other, on the date it carries.
- **Refunds are the positive side of the same sum.** A refund is an ordinary record with a
  positive amount in the category it was spent in — there is no refund type and no link to the
  original purchase, and this task does not invent one. Actual is therefore *money out minus money
  back*, so a refund lowers actual and raises remaining, in the month **the refund is dated**, not
  the month of the purchase it returns. The rule is one line of arithmetic (a signed `sum`) applied
  to every record alike, which is what makes it consistent. Actual is **not floored at zero**: when
  refunds outweigh spending in a month it is negative, so identical records always give identical
  figures.
- **Currencies never meet.** The budgets and the ledger are both read for the one currency asked
  for, in the query itself rather than filtered afterwards. A category budgeted in PLN and spent in
  EUR is not in the EUR summary and its EUR spending is not netted against its PLN plan.
- **Month boundaries are civil dates.** A record belongs to the month its `record_date` falls in,
  inclusive of the first and last day; there is no timezone to disagree about (ADR-014).
- **Only budgeted categories are listed.** Spending in a category with no budget for the slot
  appears in no item and no total. Whether and how to show it is the overview's decision (task 6).
- **Client:** `PrudentRepository.getBudgetSummary`, and nothing that renders it.

### What this deliberately differs from

`GET /api/v1/analytics/spend-by-category` reports *gross* expense — it sums only negative records,
so a refund does not reduce it (analytics.proto: "spend means expense only"). A budget's actual is
*net*. The two answer different questions — "what did I spend" versus "how much of my limit is
used" — and a refunded purchase should free the limit, so they are not unified here; a user who
compares the two screens will see the refund in one and not the other. Changing analytics to be
net is a separate decision.

Categories have no income/expense kind, so an **income record filed under a budgeted category also
lowers its actual**, exactly as a refund does; the ledger cannot tell them apart. If categories
later gain a kind, "refund" narrows to a positive record in an expense category and this rule is
revisited.

### What this does not decide

- **Carry-over (task 3).** `remaining_minor` here is the month on its own.
- **Reset and audit history (task 4), category lifecycle (task 5).** A budgeted category cannot be
  deleted (ADR-043), so the summary never meets a missing one.
- **Percent, empty and overspent states (task 6).** The response carries the amounts a screen needs
  to derive them.

### Consequence

Verified by `BudgetCalculatorTest` (the arithmetic: overspend, net-positive ledger, totals,
overflow refused rather than wrapped) and `BudgetSummaryTest` (in both transports; transfers,
corrections and planned occurrences excluded; refunds, including across a month edge and in another
category; month first and last day; currencies never mixed; ownership; every refusal), a client
repository test, and the regenerated Dart messages and admin schema. The full server suite is green
at 349, the client repository tests pass, and a second `task generate` leaves every generated file
byte-identical. (`task verify:contracts` compares against `HEAD`, so it reports the regenerated
files only until they are committed.)

---

## ADR-043 — A budget is its own table, addressed by the slot it fills

**Date:** 2026-09-29. **Status:** accepted. **Follows:** ADR-037 (a plan is not a transaction — the
same reasoning for a separate table), ADR-009 (per currency, never blended), ADR-002 (every new
table ships RLS in the same change).

### Decision

The first M3 task (jlogicsoftware/prudent#36 — "store at most one amount per category, month and
currency, with validated edits and migration coverage") stores **budgets**: the amount the user may
spend in one category, in one calendar month, in one currency.

- **A new table, `prudent_budget`** (`V20261002090000__prudent_budgets.sql`). A budget is not money
  that moved, so it is kept where no balance, analytics total or planned cash flow can read it.
- **The slot is the identity.** `(user_id, category_id, budget_month, currency)` carries a unique
  constraint, `prudent_budget_unique_slot`, and the API addresses a budget by exactly that:
  `PUT|GET|DELETE /api/v1/budgets/{categoryId}/{month}/{currency}`, plus `GET /api/v1/budgets` with
  optional `month` (`YYYY-MM`) and `categoryId` filters. There is no id on the wire and nothing to
  invent, so "at most one amount per slot" is a property of the address, and there is no
  create-versus-edit choice for a client to get wrong. The row does have a UUID primary key, unused
  by the API, so the audit trail of task 4 can name a row that survives an edit of its amount.
- **`PUT` sets, and is race-free.** It writes with one `INSERT ... ON CONFLICT ON CONSTRAINT
  prudent_budget_unique_slot DO UPDATE`, so two requests filling an empty slot leave one row
  holding the later amount instead of one of them failing on the constraint (asserted by a test
  with eight concurrent writers). It answers 201 when the slot was empty and 200 when it replaced an
  amount. It is the only write path, which is where task 4 will record who and what changed a
  budget.
- **The amount is positive.** Zero and negative are refused (400). A budget is what may be spent,
  not a signed transaction amount, and zero is what proto3 decodes an omitted field to, so
  accepting it would let a body that forgot the amount become a real budget. "No budget" is a
  deleted slot. The same rule is a `CHECK` in the schema.
- **The month is `YYYY-MM`, strictly.** Stored as the first day of the month, with a `CHECK` that
  refuses any other day, so two spellings of a month cannot be two slots. `2026-13`, `2026-1`,
  `202610`, `2026-10-01` and a signed year are refused (400) rather than corrected: a corrected
  month is a budget filed in a month the user did not choose.
- **Currency is ISO-4217, normalised to upper case** (a `CHECK` holds that too, for a writer that
  skips the resource), and a budget is never converted. It does not have to be a currency one of
  the user's accounts holds — a budget is a limit, not a balance, and tying it to today's accounts
  would make an account edit able to strand it.
- **Ownership** is resolved from the token as everywhere else; another user's category is a 404,
  the same answer as a category that does not exist.
- **What a budget protects.** Deleting a category that still has budgets is refused (409), like
  records and plans, and the foreign key carries no `ON DELETE CASCADE` as a backstop. The amounts
  a user set are never deleted as a side effect. The retention cascade deletes budgets after plans
  and before categories.
- **Client:** `PrudentRepository` gains `listBudgets` / `setBudget` / `deleteBudget` and nothing
  that renders them (the overview is task 6).

### What this does not decide

- **Category lifecycle (task 5).** Refusing the delete is the conservative choice available today,
  when a category is either present or gone; it is not a ruling on inactive categories or on
  history for a deleted one, and task 5 may supersede it.
- **Audit history (task 4).** Nothing records a previous amount yet. An edit overwrites, and a
  delete is final until that task lands.
- **Calculation and carry-over (tasks 2 and 3).** Nothing here reads records; plan, actual and
  remaining are computed from these rows later, never stored on them.

### Consequence

Verified by a schema suite (`BudgetSchemaTest`: the unique slot, each `CHECK` by constraint name, the
foreign key), a resource suite in both transport modes (`BudgetResourceTest`: replace-not-duplicate,
each part of the slot distinguishing one, case-insensitive currency, every refusal leaving the stored
amount untouched, ownership, the 409 on a category delete, the race), and the existing row-level
security and retention suites extended to the new table. The full server suite is green at 313.

---

## ADR-042 — Planned cash flow is its own overview section, fed by the existing occurrence views

**Date:** 2026-09-29. **Status:** accepted. **Follows:** ADR-037 (a plan is not a transaction),
ADR-039 (the `upcoming` and `overdue` views), ADR-040 (confirming an occurrence writes the record),
ADR-009 (per currency, never blended).

### Decision

The fifth M2 task (jlogicsoftware/prudent#58 — "future income and spending are clearly separated
from actual balances and can be included or hidden by the user") is a **client-only change**: no
proto, endpoint or migration moves, because the two views ADR-039 built already return everything
an overview needs.

- **A separate section, never a sum.** The overview draws "Planned cash flow" beneath the balances
  and the account list. No figure above it changes when it is shown or hidden — an occurrence is
  not money that moved, so adding it to a balance would make the balance a forecast.
- **What counts.** `plannedCashFlowByCurrency` sums occurrences that are `PLANNED` or `OVERDUE`,
  fetched as the overdue view plus the next 30 days of the upcoming view (`plannedCashFlowDays`,
  the server's own default window). `COMPLETED` is excluded because it is already a record and
  therefore already in the balance — counting it would count it twice; `SKIPPED` will not happen.
- **Income and spending stay apart.** Per currency: expected income (positive), expected spending
  (negative), and their net. The wire's sign convention (ADR-014) makes the net a plain sum.
- **Same account rule as the totals.** Only occurrences on an account that is active and
  `includeInTotal` count, so hiding an account from the total hides its planned money too. An
  occurrence on an account no longer in the list is dropped, not guessed at.
- **Include or hide is a view choice, on by default.** A switch on the overview
  (`plannedCashFlowVisibleProvider`, `ZenSwitchRow` per ADR-041). It is per-session client state,
  not a `settings.proto` field: it changes what one screen draws, not what any figure means, and a
  persisted preference is a later, separate decision if users ask for one. While hidden the
  provider is not watched, so nothing is fetched.
- **A failed load is local.** The section reports its own error; the balances stay readable.

### Consequence

Verified by unit tests of the calculation (states, sign split, currencies, account flags) and a
widget test that shows the section, hides it with the switch, and asserts the balance text is
identical either way. **Not built:** a per-occurrence list on the overview, and confirming or
skipping from it — the overview shows totals, and the actions remain repository methods until a
plans screen exists.

---

## ADR-041 — `zen_ui_widgets` is consumed: overlays now, the rule for everything after

**Date:** 2026-09-29. **Status:** accepted. **Follows:** ADR-036 (interactive widgets are sourced
from jZen's `zen_ui_widgets`; "accepted, blocked on upstream work"). ADR-036 is not edited — this
entry records what happened to its blocker and which part of it is now done.

### Decision

The blocker is gone. `jZenDev/jZen#106` (the package and `showAdaptivePresentation`) landed as jZen
#110 and `#107` (buttons, selects, segmented control, switch row, date and amount fields, range
pairs, `FocusRing`, all built to WCAG 2.2 AA) as #111. Prudent depends on the package by path like
every other jZen package, `JZEN_REF` moves to `6b017bb` in both workflows (ADR-018; the earlier pin
predates the package, so CI would not have found it), and **jlogicsoftware/prudent#93 is done**:

- **Every dialog-versus-sheet block is `showAdaptivePresentation`.** `Popup`
  (`client/lib/popup.dart`), `_openEdit` and `_openReconcile` in `account/account_list.dart`,
  `_presentOverlay` in `record/records_screen.dart` — and a **fifth** copy the ticket did not list,
  the edit-record swipe in `record/records_list.dart`, which had no desktop branch at all and always
  opened a sheet. The `if (zenIsDesktop) … else …` blocks are deleted, not wrapped. `Popup` stays as
  Prudent's icon-button-that-opens-something; only how it presents is the framework's.
- **The bug this fixes.** All copies gated on `zenIsDesktop`, which is `false` on every web build,
  so a wide browser window got the phone-sized bottom sheet. The framework's signal is `zenIsMobile`
  and `zenIsApplePlatform`: web and desktop native get a dialog at every window size, Android gets a
  Material sheet, iOS a Cupertino sheet, macOS a Cupertino dialog. It is a compile-time constant, so
  each build keeps one branch; there is no `MediaQuery` listener.
- **The four drifted sizes are gone with the blocks.** `Popup` was 400×300 and the rest 400×460, each
  with a fixed height. The framework's dialog is content-height with a 560 maximum width, and
  nothing here restores a fixed size. That exposed two bodies that had only ever been laid out in a
  fixed box: `NewCategory` and `NewTransfer` were a bare `Column`, which takes all the height it is
  offered, so `NewCategory` measured 952px tall in a 1000px window. Both now scroll like the other
  form bodies (`SingleChildScrollView`), and the same measure gives 684px.
- **The Prudent-side test is wiring only** (`client/test/popup_test.dart`): a `Popup` shows its
  body and the body's own `Navigator.pop` closes it. Which chrome each platform gets is
  `zen_ui_widgets`' suite; a compile-time constant means a Prudent suite only ever sees the host's
  branch, so asserting it here would be the re-test of framework behaviour ADR-036 rules out.

### The rule from here on

jZen's `STANDARDS.md` ("Client UI: the framework's controls first", jZen ADR-055) now says the same
thing ADR-036 said ahead of time, and Prudent adopts it as its own rule for client code: **use the
framework control when one exists** — `showAdaptivePresentation` (not `showDialog` /
`showModalBottomSheet` for a form or detail), `ZenButton`, `ZenSelect`, `ZenSegmentedControl`,
`ZenSwitchRow`, `ZenDateField` / `ZenDateRangeField`, `ZenAmountField` / `ZenAmountRangeField` with
`normalizeAmount`, `FocusRing` for a bespoke control's focus. Never branch on the platform to pick
Cupertino or Material. A control that is missing is a framework gap, reported in jZen and consumed —
not hand-rolled here. What stays Prudent's: what an amount *means* (minor units, currency, rounding,
`client/lib/money.dart`), `AlertDialog` for a plain acknowledgement, `PopupMenuButton`, `ListTile`,
`Card` and layout, which have no framework counterpart. The rule is in `CLAUDE.md` so a session
reads it before writing a screen.

### What this does not do

- **The other controls are not migrated by this change.** Buttons, the nine dropdowns, the segmented
  type control, switch rows and the date and amount fields and their range pairs are still stock
  Material in Prudent. ADR-036 lists them and the framework now has each, so they are backlog work
  in their own right — one PR per capability folder is the natural cut — not folded into an overlay
  fix. Until they move, the rule above binds **new and touched** screens and does not pretend the
  existing ones already comply.
- **`categories_screen.dart`'s `zenIsDesktop` grid density stays.** It chooses columns and row height
  from available space, not a presentation — a `MediaQuery`/`zenNarrowWidth` decision, a separate
  follow-up (it has the same wrong-on-web defect as the modals did).
- **`ZenWidgetsLocalizations` is not registered yet.** An app using only `showAdaptivePresentation`
  needs no delegate; the first control that speaks (a validation error, "Select a date") adds
  `zenWidgetsLocaleDelegate` beside the other packages' delegates, and `pl` follows the ADR-044
  pattern the identity and navigation delegates already use.

### Consequence

- `zen_ui_widgets` ships an untracked, generated `l10n/`, so a fresh clone needs
  `task zen:generate:l10n` (or `zen:framework:prepare:l10n` in CI) before it compiles, as for the
  other localized framework packages.
- Any new overlay-shaped screen (the plan and occurrence editors ADR-037 and ADR-040 left without a
  client) starts from `showAdaptivePresentation` and the controls, not from a fifth copy of a block.

## ADR-040 — Confirming an occurrence writes one record, and the record carries the plan link

**Date:** 2026-10-01. **Status:** accepted. **Follows:** ADR-039 (`PLANNED → COMPLETED` was put in
the transition table for this task to use; its Consequence names this task and the plan-delete
clause "must be revisited when #57 links an occurrence to a record"), ADR-014 (a balance is the sum
of records), ADR-037 (a plan is not a transaction).

### Decision

The fourth M2 task (jlogicsoftware/prudent#57 — "confirmation may edit date, amount, account and
category, creates exactly one actual transaction and retains the plan link") turns an occurrence
into a record.

- **`POST /api/v1/occurrences/{id}/confirm`** with an optional `ConfirmOccurrenceRequest`
  (`date`, `amountMinor`, `accountId`, `categoryId`, each `optional`) answers **201** with a
  `ConfirmOccurrenceResponse` — the occurrence, now `COMPLETED`, and the one `Record` it became. An
  absent field takes the occurrence's date or the plan's amount, account and category, so "as
  planned" is the empty message `{}`. (A request with no body at all is refused 400 `invalid_body`
  by the transport, as on every other POST that declares one.) Presence is
  explicit for the reason `categories.proto` gives: a `0` amount is a mistake to refuse, not a
  request for the default. The currency, title, payee and note are the plan's and are not editable
  in the request — the record can be edited afterwards like any other.
- **Allowed states.** Any `PLANNED` occurrence: overdue, due today, or ahead (paid in advance). A
  `SKIPPED` one is refused 409 and must be restored first; a `COMPLETED` one is refused 409. The
  state check runs before the body is validated, so an unconfirmable occurrence is a 409 whatever
  the body says.
- **Exactly one record, three ways.** (1) The occurrence row is locked for the transaction
  (`findOwnedForUpdate`, ADR-039), so racing confirmations serialise: the loser waits, sees
  `COMPLETED`, and is refused. (2) The state change and the record are one transaction, and every
  rule the record endpoints enforce runs inside it — a rejected edit rolls the transition back, so
  an occurrence is never `COMPLETED` without its record. (3) A **partial unique index** on
  `prudent_record.plan_occurrence_id` is the backstop for any writer that bypasses the resource.
- **The link is on the record**, not the occurrence
  (`V20261001090000__prudent_record_plan_link.sql`): `plan_id` and `plan_occurrence_id` on
  `prudent_record`, nullable, paired by a CHECK, foreign-keyed **without cascade**. `plan_id` is
  derivable from the occurrence and is stored anyway so a record list can say where each record came
  from without a join per row; the CHECK is what keeps the copy from being half-written. Both are
  on the wire as `Record.plan_id` / `Record.plan_occurrence_id` (`optional`, read-only). `PUT
  /api/v1/records/{id}` never touches them, so editing a confirmed transaction keeps its origin.
- **One implementation of the record rules.** `RecordResource`'s private `apply` moved unchanged
  into `RecordWriter`, a bean both it and confirmation call, so a rule cannot hold for a typed-in
  record and lapse for a confirmed one (title, nonzero amount, the caller's own account and
  category, an account that holds the currency).
- **Records are the ledger, so the plan is the thing that gives way.** Deleting a plan used to
  delete its occurrences outright; it now first **detaches** the records it produced
  (`plan_id`/`plan_occurrence_id` set to `NULL`) and then deletes the occurrences and the plan. The
  transactions, and therefore every balance and total, are untouched — only where they say they
  came from is lost. This resolves the clause ADR-039 left open.
- **Deleting a confirmed record reopens its occurrence.** The occurrence would otherwise claim a
  transaction that no longer exists and, `COMPLETED` being final, could never be confirmed again.
  `PlanOccurrenceEntity.reopen()` does it, called by the record delete and by nothing else. It is
  deliberately **not** in `OccurrenceState.successors()`: the table still says no route can move an
  occurrence out of `COMPLETED`, and `restore` on a completed one is still a 409 — the only way out
  is the transaction itself going away. The reopen takes the same row lock, so it cannot interleave
  with a confirmation.

### What was considered and not done

- **A link column on the occurrence instead.** Rejected: the record is what a client lists and
  edits, and it would need a join to say it was planned; and the uniqueness that matters —
  one transaction per occurrence — is naturally an index on the record side.
- **Refusing to delete a plan that has confirmed records.** Rejected: it would make a plan
  undeletable forever after its first confirmation, for the sake of a back-reference.
- **Refusing to delete a confirmed record.** Rejected: the user's remedy for a mistaken
  confirmation is to delete the transaction, and a permanently `COMPLETED` occurrence with nothing
  behind it is worse than a reopened one.
- **Editing the currency, title, payee or note at confirmation.** Not asked for by the acceptance
  criterion; each is one `PUT /api/v1/records/{id}` away.
- **Per-occurrence edits before confirmation** and the overview's planned cash flow are the
  backlog's next M2 tasks (#58 and after), not this one.

### Consequence

- A `COMPLETED` occurrence still lists the **plan's current** fields (`PlanOccurrence.title`,
  `amount_minor`, …), not what was posted; what was posted is the record, reachable through the
  `ConfirmOccurrenceResponse` and `Record.plan_occurrence_id`. A view that must show a completed
  row's actual amount reads the record. `PlanOccurrence` does not carry the record id.
- Nothing about the client changed but its repository (`confirmOccurrence`); there is still no
  plan or occurrence screen, for the reason ADR-037 and ADR-039 give.
- Retention (`PrudentRetentionCleanup`) needs no change: it already deletes records before
  occurrences and plans.

---

## ADR-039 — An occurrence stores planned/completed/skipped; overdue is derived, and the views generate

**Date:** 2026-09-30. **Status:** accepted. **Follows:** ADR-038 (occurrences are generated
idempotently; its Consequence names this task), ADR-037 (a plan's time zone decides what "today"
is, so when an occurrence is overdue).

### Decision

The third M2 task (jlogicsoftware/prudent#56 — "planned, completed, skipped and overdue states
appear in upcoming and overdue lists with valid state transitions only") gives an occurrence a
lifecycle and two views.

- **A `state` column** (`V20260930090000__prudent_plan_occurrence_state.sql`): `PLANNED` (the
  default, so every earlier row and the generator's state-less insert are planned), `COMPLETED`,
  `SKIPPED`. `TEXT NOT NULL`, no Postgres enum and no `CHECK`, for the reason the init migration
  gives for `prudent_account.kind`. The vocabulary is `prudent.plan.OccurrenceState`.
- **Overdue is not stored.** It is a `PLANNED` occurrence dated before *today in its plan's time
  zone*, computed when read (`OccurrenceMapper.status`). Storing it would need a job that flips
  rows at midnight in every user's zone; a missed run leaves a wrong row, and a derived value
  cannot be wrong. On the wire `OccurrenceStatus` has `OVERDUE`; the stored enum does not.
- **The transitions are exactly:** `PLANNED → SKIPPED`, `SKIPPED → PLANNED`, `PLANNED →
  COMPLETED`. `COMPLETED` is terminal — it will be an actual transaction (#57), and reopening it
  would have to undo that, which is confirmation's decision and not a state flip's. A repeat (skip
  a skipped occurrence) is **not** a transition and is refused, so a client that believes it is
  skipping something open learns it is not. A refused move is a **409** `conflict`; the table lives
  in `OccurrenceState.successors()` and nowhere else, and a test asserts it whole.
- **Concurrent changes are serialised** by locking the row for the transaction
  (`findOwnedForUpdate`, `PESSIMISTIC_WRITE`): a skip racing a restore — and later a confirmation
  racing either — sees the other's result instead of acting on a state it has already left.
- **`/api/v1/occurrences`:** `GET /upcoming?days=` (default 30, 1..366), `GET /overdue`,
  `POST /{id}/skip`, `POST /{id}/restore`. There is **no route that marks an occurrence completed**:
  that is confirmation (#57), which must create the transaction in the same act. `PLANNED →
  COMPLETED` is in the table so #57 uses it rather than inventing a second path.
- **Upcoming** is every occurrence from today (per plan) to `days` ahead **in any state**, so what
  was skipped, or confirmed early, stays visible where the user is looking. **Overdue** is the
  planned ones whose date has passed. Resolved past occurrences are in neither list: they are
  history, not something to act on, and a history view is not part of this task. "Today" is
  reckoned per plan, so a plan in Kiritimati and one in Pago Pago can disagree about the same
  civil date — a test pins that.
- **The views generate what they read.** ADR-038 left the trigger to the views. No scheduled job
  exists, so each view first ensures every plan has occurrences from `LOOKBACK_DAYS` (366) before
  today to the view's horizon, through `OccurrenceGenerator`. That makes a `GET` that writes, but
  an idempotent one: the second call finds everything present. The generator now reads the dates
  already present in the window first and inserts only the missing ones — an optimisation, since
  `ON CONFLICT DO NOTHING` is still what makes a race safe. Plans opened after a long absence
  therefore show at most a year of never-generated history as overdue; occurrences generated
  earlier stay overdue for as long as they are unresolved, whatever their age.
- **Replacing a plan's rule** now drops only the **still-planned** occurrences the new rule no
  longer produces (`OccurrenceGenerator.dropStale`), as ADR-038 required. Completed and skipped
  ones are kept — a completed one is a transaction and a skipped one is the user's decision —
  and dates the new rule still produces are kept. This replaces ADR-038's delete-everything on a
  rule change. Deleting a plan still deletes all its occurrences; that must be revisited when #57
  links an occurrence to a record.
- **Time is behind `PlanClock`**, a bean tests replace, so a test can say which day it is. Nothing
  else reads the clock through it.

### What this supersedes, and why

Only the rule-change clause of ADR-038 (above). The client gains repository methods
(`listUpcomingOccurrences`, `listOverdueOccurrences`, `skipOccurrence`, `restoreOccurrence`) and
no screen, for the reason ADR-037 gives: the plan and occurrence screens need the widgets ADR-036
routes through `zen_ui_widgets`. Per-occurrence edits, confirmation and the overview's planned cash
flow are #57 and #58.

### Consequence

- #57 completes an occurrence with `transitionTo(COMPLETED)` inside the transaction that creates
  its record, under `findOwnedForUpdate`, so two confirmations cannot both post.
- A bulk "skip everything overdue" and a history view are not built; a daily plan neglected for a
  year lists a year of overdue rows, each to be skipped or confirmed individually.

## ADR-038 — Occurrences are generated into their own table, and the unique key is the idempotency

**Date:** 2026-09-29. **Status:** accepted. **Follows:** ADR-037 (a recurrence is a rule computed
from its anchor; occurrences are pure functions of it). Numbered 038 because ADR-036 is drafted in
parallel.

### Decision

The second M2 task (jlogicsoftware/prudent#55 — "a bounded generation window produces the same
unique occurrences when run repeatedly or concurrently") materialises a plan's occurrences.

- **A new table, `prudent_plan_occurrence`** (`V20260929090000__prudent_plan_occurrences.sql`):
  `id`, `user_id`, `plan_id`, `occurrence_date`. Like `prudent_plan` it is not the ledger, so no
  balance or analytics query can read it. It holds only what identifies an occurrence; state
  (#56) and per-occurrence overrides (#57) are later columns, not guesses made now.
- **`UNIQUE (plan_id, occurrence_date)` is the idempotency key**, and the writer answers it with
  `INSERT … ON CONFLICT DO NOTHING`. The alternative — read which dates exist, insert the missing
  ones — races: two concurrent generators both see a date missing and both insert it, and the
  second either fails or, without the constraint, duplicates. With the constraint the second
  blocks on the first's key until it commits and then does nothing, so any number of runs over any
  overlapping windows converge on the same set. Dates are written in ascending order so
  overlapping runs take their locks in one order and cannot deadlock.
- **`prudent.plan.OccurrenceGenerator.generate(plan, from, to)`** is the one writer. It is
  `@Transactional` (REQUIRED), so a caller's failure after generating rolls the window back rather
  than leaving half of one. It returns how many occurrences the window holds and how many this run
  created.
- **The window is required and bounded:** inclusive on both ends, `from <= to`, at most 3660 days
  (`MAX_WINDOW_DAYS`). A rule with no end is therefore never asked for "all of it", and a daily
  rule costs a few thousand rows at worst. Violations are a 400.
- **Generation only adds.** It never deletes or rewrites, so extending a window cannot disturb
  occurrences already generated — and once they carry state, cannot discard a confirmed one.
- **A plan's occurrences do not outlive it:** deleting a plan (and the retention cascade) deletes
  them first, the FK carrying no `ON DELETE CASCADE` as everywhere else in the schema. RLS is on
  and `prudent_plan_occurrence` joins the `zen_runtime` policy list in the repeatable.
- **Replacing a plan with a changed recurrence rule deletes its occurrences**, because generation
  only adds and rows the old rule produced would otherwise sit beside the new ones for good. A
  replacement that leaves the rule alone (a title, amount or note edit) keeps them.

### What this supersedes, and why

Nothing is reversed. There is **no HTTP surface and no client change**: the only readers and
triggers are the lifecycle and views task (#56) and confirmation (#57), and a route that writes
rows nothing can yet show would be a wire contract designed with no consumer. `OccurrenceGenerator`
is the seam they call.

### Consequence

- **#56 must revise the rule-change deletion above.** It is only correct while no occurrence
  carries state; once one can be completed or skipped, a rule edit has to keep those and drop only
  the open ones that the new rule no longer produces.
- Nothing calls the generator in production yet. Deciding when it runs (on plan save, on opening
  the upcoming list, or on a schedule) belongs with the views that need the rows.

## ADR-037 — Plans are their own table, and a recurrence is a rule computed from its anchor

**Date:** 2026-09-28. **Status:** accepted. **Follows:** ADR-014 (balance is derived from records),
ADR-002 (timestamp migration versions; every new table ships RLS in the same change), ADR-008 (a
record's currency must be one its account holds). **Numbered 037** because ADR-036 is taken by the
`zen_ui_widgets` decision drafted in parallel.

### Decision

The first M2 task (jlogicsoftware/prudent#34 — "support one-off, daily, weekly, monthly, yearly and
custom intervals with explicit timezone and end conditions") models a **plan**: money the user
expects to move, once or on a schedule.

- **A new table, `prudent_plan`** (`V20260928090000__prudent_plans.sql`), not a flag on
  `prudent_record`. Balance is the sum of records (ADR-014) and analytics reads the same rows, so a
  planned row stored there would move the balance and the totals before anything happened, and
  every existing query would need an exclusion — the one that forgot being silently wrong. That is
  the opposite of ADR-031/ADR-035, where a transfer leg and a correction *are* money that moved and
  so belong in the ledger.
- **The recurrence is flat columns on the plan** — `frequency`, `recurrence_interval`,
  `start_date`, `time_zone`, `until_date`, `occurrence_count` — because a plan has exactly one rule.
  On the wire it is a nested `Recurrence` message (`proto/prudent/v1/plans.proto`).
- **Frequencies:** `ONCE`, `DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY`. **Custom intervals** are
  `interval` units of the frequency (2 × weekly is fortnightly, 3 × monthly is quarterly), 1..1000.
  Weekly repeats on the start date's weekday; multiple weekdays per week are not modelled — adding
  them later is a backward-compatible proto field.
- **End conditions** are a proto `oneof`: an inclusive `until_date`, an `occurrence_count`
  (1..10000, counting the first occurrence), or neither (never ends). `ONCE` takes neither and no
  interval.
- **Every occurrence is a civil date computed from the anchor**, never stepped from the previous
  one: occurrence *n* is `start_date + n × interval` units. Monthly on the 31st therefore gives 31
  Jan, 28 Feb, 31 Mar — a month-end that recovers after a short month instead of drifting to the
  28th — and a 29 February yearly anchor falls on 28 February in common years. Because each date
  is a pure function of the rule and its index, occurrence generation (jlogicsoftware/prudent#55)
  can be repeated and agree with itself. `prudent.plan.RecurrenceRule` is the one place this
  arithmetic lives, with `occurrencesBetween(from, to)` as its bounded read.
- **The time zone is an explicit IANA id, required, and it moves no date.** It decides which
  calendar day is *today* for the plan — so when an occurrence is due or overdue (#56) — because
  the server runs in UTC and a Warsaw user's plan due on the 1st must not turn overdue at 01:00
  local time. Fixed offsets (`+02:00`, `Z`, `GMT+2`) are refused: they do not follow daylight
  saving. Validation is against the tz database's own id list, not whatever `ZoneId.of` parses.
- **A plan carries what a record needs:** a signed nonzero `amount_minor` (same sign convention as
  `Record`, so confirmation copies rather than translates), a currency its account holds, the
  caller's own account and category. It is refused at save time for anything a record would
  refuse, while the user can still fix it — not later, at confirmation (#57).
- **`/api/v1/plans`** — list, get, create, full-replacement update, hard delete — in the shape
  every other resource uses. Saving a plan writes no record and moves no balance; a test asserts
  exactly that.
- **What a plan protects:** deleting an account or category a plan references is refused (409)
  and the message names `/api/v1/plans`; dropping a currency a plan is denominated in is refused
  the way dropping one with records is. The FKs carry no `ON DELETE CASCADE`, as on
  `prudent_record`. The retention cascade deletes plans after records and before accounts.
- **The schema holds the rule's structural invariants as named `CHECK`s** — interval range, count
  range, at most one end, until not before start, `ONCE` has neither — because each names a row
  the arithmetic cannot give one answer for. `frequency` itself is **not** `CHECK`ed, for the
  reason the init migration gives for `prudent_account.kind`. RLS is enabled in the versioned
  migration and `prudent_plan` joins the `zen_runtime` policy list in the repeatable.

### What this supersedes, and why

Nothing is reversed. The backlog's M2 tasks 2-5 (#55 generation, #56 lifecycle and views, #57
confirmation, #58 overview cash flow) are deliberately **not** in this change: no occurrence is
materialised or stored yet, and there is no client screen. The client gains repository methods
(`listPlans`/`createPlan`/`updatePlan`/`deletePlan`) and nothing that renders them — a plan editor
needs the date, amount and select fields ADR-036 routes through `zen_ui_widgets`, and building a
fifth ad-hoc copy of those is what that ADR asks new screens not to do.

### Consequence

- The occurrence generator (#55) consumes `RecurrenceRule.occurrencesBetween`, and the lifecycle
  (#56) consumes `RecurrenceRule.today`; neither re-derives dates.
- A plan's `occurrence_count` is counted by index from the anchor, so a skipped or edited
  occurrence (#56/#57) never shifts the ones after it — the lifecycle state will live on the
  generated occurrence, not on the rule.

## ADR-036 — Interactive widgets are sourced from jZen's `zen_ui_widgets`, not maintained ad hoc in Prudent

**Date:** 2026-09-19. **Status:** accepted, blocked on upstream work. **Follows:** ADR-013 ("the
client becomes a jZen application"), ADR-026 (the flat capability layout these widgets currently
live inside).

### Decision

Prudent's client currently hand-rolls every interactive widget directly against stock Material —
buttons, text/amount fields, dropdowns, a segmented control, switch rows, date pickers, and (worst
duplicated) the dialog-vs-bottom-sheet presentation chrome, each reimplemented per screen with no
shared shape. Going forward, Prudent does not keep building or fixing these ad hoc: it sources
them from jZen's `zen_ui_widgets` package (proposed in `jZenDev/jZen#106`, scope broadened in
`jZenDev/jZen#107`), the same way navigation already comes from `zen_ui_navigation` and auth
screens from `zen_ui_identity` (ADR-013). Concretely:

- **What moves:** the adaptive dialog/bottom-sheet presentation (`client/lib/popup.dart`,
  `account_list.dart`'s two copies, `records_screen.dart`'s), date pickers and the date-range
  filter pair, amount/money fields and the amount-range filter pair, dropdown/selects, buttons,
  the segmented type control, and switch rows. The concrete Prudent source files feeding each
  target widget are inventoried in `jZenDev/jZen#107`.
- **What does not move:** anything genuinely Prudent-specific — the minor-units parsing/formatting
  in `client/lib/money.dart`, and any business logic currently sitting next to a widget (e.g. the
  balance-correction validation in `reconcile_account.dart`). jZen's widgets own the field *shape*
  (keyboard type, focus, semantics, adaptive rendering); Prudent keeps owning what the field
  *means*.
- **Platform rendering is jZen's decision, not Prudent's.** `zen_ui_widgets` renders Cupertino on
  iOS and macOS and Material everywhere else (Android, Linux, Windows, web), gated by a new
  `zen_core` constant (`zenIsApplePlatform = zenIsIOS || zenIsMacOS`) the same compile-time,
  tree-shaken way `zenIsMobile`/`zenIsDesktop` already work — extending the `zenIsIOS`-gated
  Cupertino branching `zen_ui_navigation`'s `navigation_mobile.dart` already does, now also to
  macOS. Prudent does not choose or override this per screen; it inherits whatever jZen's package
  renders, matching how Prudent has never owned a UI-toolkit choice for navigation or auth either.
- **Accessibility is jZen's contract too.** `zen_ui_widgets` is required to meet the WCAG bar
  `jZenDev/jZen#105` is defining (keyboard focus, semantics beyond labels, WCAG AA contrast) from
  its first commit, per `jZenDev/jZen#107`. Prudent does not re-audit framework widgets locally;
  it verifies its own screens are wired to them correctly.

### What this supersedes, and why

- **The unstated assumption in every widget added so far** (`docs/DECISIONS.md` ADR-013's "the
  client becomes a jZen application" never named UI *widgets*, only navigation/auth/repository/
  transport) — every form screen built since then (records, accounts, categories, transfers,
  corrections) added its own raw Material usage rather than treating that as a gap. This ADR names
  it explicitly: the same "consume, don't reimplement" rule ADR-013 applied to navigation and auth
  applies to the smaller building blocks too.
- **jlogicsoftware/prudent#93's original plan** ("implement a local `showResponsiveModal` helper
  in the meantime, migrate later") → **reversed.** Building a local helper now and migrating later
  means maintaining two implementations of the same fix across one release. #93 is instead
  formally blocked (GitHub issue-dependencies, not just a text reference) on `jZenDev/jZen#106` and
  `#107` — Prudent waits and consumes the published package once, rather than building then
  replacing.

### Consequence

- Prudent's own `client/lib/popup.dart`, the duplicated dialog/bottom-sheet blocks, and the ad hoc
  Material widgets named above are **not** deleted yet — they stay exactly as they are until
  `zen_ui_widgets` exists and is depended on as a `path:` dependency (the same "sibling checkout by
  path" shape every other jZen dependency already uses — `CLAUDE.md` "How Prudent depends on
  jZen"). No new Prudent widget work should add another ad hoc copy of anything in the extraction
  list above; new screens needing one of these widgets wait on the same blocker rather than adding
  a fifth duplicate.
- Tracked upstream: `jZenDev/jZen#106` (package + adaptive presentation + Cupertino/tree-shaking),
  `jZenDev/jZen#107` (broader extraction + accessibility bar), both linked as formal blockers on
  `jlogicsoftware/prudent#93`.

## ADR-035 — Balance corrections: one marked record, not a rewrite of the opening balance

**Date:** 2026-09-19. **Status:** accepted. **Follows:** ADR-014 (balance is derived, not stored),
ADR-031/ADR-032 (a transfer is two linked records, no header table).

### Decision

A balance correction (M1, jlogicsoftware/prudent#53 — "reconciliation records an auditable
correction instead of silently rewriting opening balance or transaction history") is modeled as a
single `RecordEntity` row, exactly like a transfer leg is two:

- `prudent_record` gains one column, `is_correction BOOLEAN NOT NULL DEFAULT false`
  (`V20260919070615__prudent_corrections.sql`) — no new table, because balance is derived
  (ADR-014) and persisting the delta row *is* the correction.
- `POST /api/v1/corrections` (`CorrectionResource`) takes the account's TRUE balance as the caller
  observed it (e.g. from a bank statement) — never a delta — computes the difference against the
  account's current derived balance, and refuses the call if that difference is zero (a correction
  that changes nothing is not a correction, the same refusal `Record.amount_minor` already applies
  to a zero-amount ordinary record). It persists exactly one `RecordEntity` carrying that
  difference as `amount_minor`, with `is_correction = true`, no `category_id` (neither income nor
  expense, like a transfer leg), and an optional free-text `note` for *why*.
- `RecordResource.replace`/`delete` refuse a row with `is_correction = true` (409), the same
  guard already in place for `transfer_id`. `DELETE /api/v1/corrections/{id}` is the only way to
  remove one.
- `RecordType` (the `type` query-param enum) gains `CORRECTION`; `RecordEntity.expenseRows` (the
  query every analytics endpoint shares) excludes `is_correction = true` the same way it already
  excludes transfer legs — without this a correction that lowers a balance would count as spend
  under a null category.
- The client gets a "Reconcile balance" action on each account tile (`client/lib/account/
  reconcile_account.dart`), which asks for the true balance and calls the new endpoint —
  `RecordsNotifier.addCorrection` invalidates `accountsProvider` the same way `addTransfer`
  already does, since a correction moves a derived balance without touching an `Account` row.

### What this supersedes, and why

- Nothing is reversed. `UpdateAccountRequest.balances`'s existing full-replacement behavior (which
  can re-base a derived balance with no record of why — accounts.proto's own comment already names
  this) is **left as is**, deliberately out of scope here: it is account-setup/edit behavior, not
  the reconciliation flow the issue asks for, and closing it off is a separate, back-compat-facing
  decision this ADR does not make. The new `/api/v1/corrections` endpoint is *the* auditable
  reconciliation path; nothing about the account-edit path changed.

### Consequence

- `task verify:contracts` passes with the regenerated Dart messages and admin TS schema (no other
  drift). `task test:server` (131 tests, including the new `CorrectionResourceTest`) and
  `task zen:test:client` (89 tests) are green; `flutter analyze` is clean on the new
  `reconcile_account.dart` and the `account_list.dart` wiring.
- Analytics, exports and account/category-deletion lifecycle rules for corrections beyond "exclude
  from `expenseRows`" are **not** addressed here — that is the backlog's own next M1 task
  ("Integrate transfers and corrections with lifecycle rules"), not this one.

## ADR-034 — Record search and filters: server-side query params, no new proto messages

**Date:** 2026-09-18. **Status:** accepted. **Follows:** the unpaginated-listing decision recorded
under ADR-014 ("Listing is unpaginated, and that was already decided").

### Decision

`GET /api/v1/records` (`jlogicsoftware/prudent#52`) gains eight optional, independently composable
query parameters, all filtered server-side in one new `RecordEntity.search(...)` query:

- `dateFrom`/`dateTo` — ISO-8601, inclusive, matched against `date`.
- `accountId`/`categoryId` — UUID, matched against the field of the same name.
- `type` — `income`/`expense`/`transfer`. Reuses `RecordEntity.expenseRows`'s own split exactly
  (`expense` is `amountMinor < 0` with no `transferId`; `income` is the positive counterpart;
  `transfer` is any row with a `transferId`), so a record's type here never disagrees with what
  `AnalyticsResource` already calls it.
- `amountMin`/`amountMax` — non-negative minor units, matched against `abs(amountMinor)`,
  **deliberately ignoring currency**. A record's amount and currency are independent (ADR-008);
  scoping the filter to one currency would need a currency picker wired to the amount fields for a
  small accuracy gain, against a personal-finance user who mostly holds one currency. The tradeoff
  taken is a nominal comparison across units that are not really comparable, for a simpler filter
  UI.
- `search` — case-insensitive substring match against `title`, `payee`, or `note`.

None of the eight are proto fields. Query params are a REST-layer concern in this codebase
already — `AnalyticsResource`'s `currency`/`year`/`month`/`granularity`/`count` are plain
`@QueryParam`s with no request message in `analytics.proto`, documented only in prose. Records
filtering follows the same convention: `records.proto`'s `GET /api/v1/records` doc comment gained
a prose description of the eight params; `ListRecordsResponse` is unchanged.

### What this supersedes, and why

- **ADR-014's framing of a future retrofit as "page parameters ... a backward-compatible
  addition"** → **extended, not reversed.** The same reasoning ADR-014 used for pagination
  ("query parameters on the GET ... cheap") is the reasoning this entry uses for filters: neither
  needed the contract redesigned, both landed as additive query params on the same endpoint.

### Consequence

- No schema change, no Flyway migration — every filterable field (`date`, `accountId`,
  `categoryId`, `amountMinor`, `transferId`, `title`, `payee`, `note`) already existed on
  `RecordEntity`.
- A malformed `dateFrom`/`dateTo`, `accountId`/`categoryId`, or `type`, or a negative
  `amountMin`/`amountMax`, is a 400 (`ZenError` code `invalid`) — never a silently ignored
  parameter or a 500.
- Client-side: `RecordFilter` (`client/lib/record/record_filter.dart`) mirrors the eight params
  1:1 and is not proto-generated, matching the server's own choice not to model them in the
  contract. `recordFilterProvider` holds the active filter; clearing it (`RecordFilterNotifier
  .clear()`) re-fetches the unfiltered list — nothing is mutated or deleted by filtering, so
  clearing never loses data.
- Verified: `RecordResourceTest` (server) covers each filter alone, filters composed together, no
  filters (identical to the pre-#52 unfiltered list), clearing, and every malformed-input 400 —
  full suite green. `record_filter_test.dart` and the extended `prudent_repository_test.dart`
  (client) cover `RecordFilter`'s query-parameter mapping and `isEmpty`/equality — green.
  `task verify:contracts` regenerated `records.pb.dart` and `admin/src/api/schema.generated.ts`
  cleanly (doc-comment/OpenAPI-description-only diffs, no structural change) and reports no drift.

---

## ADR-033 — Bump CI's jZen pin to #97: the committed admin schema had already drifted past it

**Date:** 2026-09-18. **Status:** accepted. **Follows:** ADR-030 (prior `JZEN_REF` bump),
ADR-027 (the contract loop `verify:contracts` gates).

### Decision

`jlogicsoftware/prudent#50`'s PR (`feature/cross-currency-transfers`) hit a `gates` job failure —
"Contracts are OUT OF SYNC" on `admin/src/api/schema.generated.ts` — on a change that never
touches an admin or auth file. Investigation (two identical CI reruns, then a temporary CI step
printing the actual diff) found the drift was pre-existing and unrelated to this PR: the committed
schema already carried `@APIResponse` description text for `AdminUserResource`/`AuthResource`
(e.g. "Unknown role value or unsupported language (ZenError)") that only exists in jZen commit
`7edf7b9` ("Java/Quarkus code review remediation (F1-F23)", jZen #97) — six commits **past**
`ci.yml`/`audit.yml`'s pinned `JZEN_REF` (`8a21f83`, ADR-030's pin). Regenerating against the
pinned SHA therefore always overwrote that text with SmallRye's generic defaults ("Bad Request"),
and would have kept doing so on every PR, unrelated to what that PR touched.

- **`JZEN_REF` in both `ci.yml` and `audit.yml` moves from `8a21f83` to `7edf7b94fd4d5c522e2
  29d3886673d23c15693a8`** (jZen #97), confirmed pushed to `jZenDev/jZen`'s `main`. Bumped in both
  files together, as `audit.yml`'s own comment already requires.
- **Verified the bump actually closes the gap**, not just moves it: `admin/src/api/
  schema.generated.ts` regenerated against jZen at `7edf7b9` (`./mvnw install -DskipTests` in a
  freshly checked-out jZen worktree at that SHA, then `task generate`) produces **zero** diff
  against what is already committed on this branch — confirming the committed file was generated
  against #97 or later, not the old pin, and that #97 is the right, minimal target rather than
  jZen's current tip.
- **Six commits between the two pins** (`8a21f83..7edf7b9`): `#91` (stop storing 8 public config
  values as secrets), `#92` (cleanup-policy docs fix), `#94`/`#95` (code-review prompts),
  `#96` (code-review docs/execution plans), `#97` itself. None of the other five touch generated
  contract surface; only `#97`'s `AdminUserResource`/`AuthResource` annotation changes are
  contract-relevant, which is why regenerating against `#97` alone (not jZen's current tip) is
  enough and the minimal correct target.
- **Why this is a `JZEN_REF` bump and not a schema regeneration to match the old pin**: the
  alternative — regenerating `schema.generated.ts` against `8a21f83` to match the *stale* pin —
  would have shipped in this PR as a **regression**, deleting real, already-reviewed descriptive
  text from the admin API surface to satisfy a gate that was itself out of date. Asked directly,
  the answer was to fix the pin, not the (already-correct) generated output.

### What this supersedes, and why

- **ADR-030's `JZEN_REF: 8a21f83e0be6013765d03430e17132c635a90664`** → **superseded**, not
  reversed: ADR-030's reasoning for pinning-not-floating still holds; only the pinned value moves,
  exactly the "deliberate, reviewed step" `ci.yml`'s own header comment calls for.
- Implicitly corrects an unrecorded fact: **the admin schema on `main` has been out of sync with
  `ci.yml`'s stated pin since whichever earlier commit generated it against a newer jZen than
  `8a21f83`** (before this PR, and not caught then because `git status --porcelain` only compares
  the working tree to what's committed — it cannot tell a "correct but ahead of the stated pin"
  regeneration from a "correct and matching the pin" one). No ADR recorded that mismatch at the
  time; this entry is the first place it is named.

### Consequence

- CI's `verify:contracts` gate, run against the new pin, no longer drifts on files this PR did not
  touch. Verified locally by full regeneration against jZen `7edf7b9` (Maven install + `task
  generate`) producing a clean `git status` for `admin/src/api/schema.generated.ts`.
- The five contract-irrelevant commits swept up in this bump (`#91`, `#92`, `#94`, `#95`, `#96`)
  are accepted as part of the same deliberate step rather than cherry-picked around, matching
  ADR-030's own precedent of bumping to the next commit that closes a real gap rather than
  hand-picking individual commits out of jZen's history.

---

## ADR-032 — Cross-currency transfers: each leg carries its own amount and currency, no FX ever

**Date:** 2026-09-18. **Status:** accepted. **Follows:** ADR-031 (same-currency transfers),
ADR-014 (derived balance), ADR-008 (multi-currency accounts).

### Decision

`jlogicsoftware/prudent#50` ("Add explicit cross-currency transfers") generalizes
`TransferResource` rather than adding a second, parallel cross-currency path:

- **`CreateTransferRequest` gains independent `to_amount_minor`/`to_currency` fields**, alongside
  the renamed `from_amount_minor`/`from_currency` (was `amount_minor`/`currency`). Both amounts are
  positive magnitudes the caller enters explicitly; the server negates `from_amount_minor` for the
  source leg and keeps `to_amount_minor` positive for the destination leg, exactly as ADR-031
  already did for one shared amount.
- **A same-currency transfer is not a distinct mode.** It is simply the case where
  `from_currency == to_currency` and the caller happened to enter the same amount on both sides.
  `TransferResource` enforces no equality between the two legs — not on currency, not on amount.
  Requiring the amounts to match when the currencies match was considered and rejected: it would
  be an invariant this issue's acceptance criteria never asked for, and it does nothing to prevent
  the one thing the criteria does forbid — an inferred rate. What the rule can't do, a validation
  branch shouldn't pretend to do.
- **No FX rate is computed anywhere on this path.** There is no rate table, no external lookup, no
  `amount * rate` arithmetic in `TransferResource` at all — each leg's `RecordEntity` is populated
  directly from the matching request field. This isn't a simplification of a richer design; it is
  the whole design. A future FX-assisted entry mode (suggesting a rate the user can override) is
  explicitly out of scope and would be a new, separately-reviewed feature, not an extension of this
  endpoint's validation.
- **Both currencies are validated independently against their own account** — `from_currency`
  against `from_account`'s held currencies, `to_currency` against `to_account`'s held currencies —
  the same `Currencies.isValid`/`AccountEntity.holds` checks ADR-031 introduced, just run twice
  instead of once.
- **No schema or migration change.** `prudent_record` already stores `amount_minor` and `currency`
  per row, not per transfer (ADR-031's two-independent-legs design, not a header table), so a
  transfer whose two legs disagree on currency was already representable — this issue only removes
  the validation that refused to create one.
- **The client (`NewTransfer`) drops the "shared currency" constraint entirely.** It no longer
  intersects the two accounts' currency sets; each account's dropdown offers that account's own
  held currencies, and the two amount fields are entered independently. The removed
  `transfersNoSharedCurrency` string and the `_sharedCurrencies` helper it described no longer
  correspond to anything the UI does.

### What this supersedes, and why

- **"Cross-currency transfers (two user-entered amounts, no inferred rate) … are a separate,
  later issue"** (ADR-031, "Decision") → **fulfilled, not reversed**. ADR-031's
  two-independent-legs shape is exactly what makes this a validation change rather than a schema
  change.
- **`CreateTransferRequest.amount_minor`/`currency`** (ADR-031) → **renamed** to
  `from_amount_minor`/`from_currency` rather than kept alongside the new `to_*` fields. *Why:*
  nothing has ever targeted a real environment (CLAUDE.md, "the deploy path … has never targeted a
  real environment"), so there is no deployed client depending on the old wire names — a rename is
  the honest contract change, not a backward-compatibility shim for a compatibility problem that
  doesn't exist yet.

### Consequence

- `TransferResource.create` reads two independent request sub-shapes instead of one shared one; the
  two `if (fromAmount <= 0)` / `if (toAmount <= 0)` and the two currency-validation blocks are
  intentionally parallel and not merged into a loop — the code mirrors the two independent legs it
  produces.
- Verified: `task generate` / `task verify:contracts` clean; `./mvnw test` green, including
  `TransferResourceTest`'s new independent-amount and independent-currency cases; `flutter analyze`
  and `flutter test` clean on the client, including a new cross-currency `CreateTransferRequest`
  wire round-trip case.

---

## ADR-031 — Same-currency transfers: two linked records, no header table, and a category that can now be absent

**Date:** 2026-09-17. **Status:** accepted. **Follows:** ADR-014 (derived balance), ADR-008
(multi-currency accounts).

### Decision

`jlogicsoftware/prudent#32` ("Add atomic same-currency transfers") is built as:

- **A `transfer_id UUID` column on `prudent_record`** (nullable, partial index on non-null), not a
  separate `prudent_transfer` header table. The two leg rows a transfer creates — a negative-amount
  source leg and a positive-amount destination leg, sharing one `transfer_id` — carry everything a
  transfer needs (amount, currency, date, accounts); a header table would add a second RLS surface
  and a second migration path for no information the two rows don't already have.
- **`prudent_record.category_id` becomes nullable** (`Record.category_id` is now proto3
  `optional`). A transfer leg is neither income nor expense, so it carries no category. Ordinary
  create/replace through `RecordResource.apply` still requires one — this only makes "no category"
  a sayable wire and database state for the one case that legitimately has it, rather than a
  reserved sentinel value.
- **`RecordEntity.expenseRows`** (the one query both analytics endpoints share, ADR-014) gains
  `and r.transferId is null`. A transfer's negative leg has `amountMinor < 0` exactly like an
  expense; this is the one place that distinction is made, matching how income exclusion already
  works there.
- **New `TransferResource`** at `/api/v1/transfers`: `POST` validates both accounts are the
  caller's, distinct, and both hold the requested currency (no FX — ADR-008/ADR-009), then persists
  both legs in one `@Transactional` method. Because balance is derived, not stored (ADR-014),
  persisting both rows in one transaction **is** the atomic balance update — no `Account` row is
  ever touched. `DELETE /{transferId}` removes both legs by their shared id, or 404s.
- **`RecordResource.replace`/`delete` refuse any record with a non-null `transfer_id`** (409
  `conflict`). Without this, one leg could be edited or deleted through the pre-existing
  single-record endpoints, silently breaking the pairing the moment the feature shipped. `GET` is
  unaffected — a leg still reads like any other record.
- Cross-currency transfers (two user-entered amounts, no inferred rate) and deletion/export
  lifecycle integration are the two sibling M1 backlog tasks this issue does not close
  (`docs/github-backlog.md`, M1 tasks 2 and 6).

### What this supersedes, and why

- **CLAUDE.md's "Flyway version band"** (superseded already by ADR-002; restated here because this
  migration is the concrete instance) → the new migration is
  `V20260917184255__prudent_transfers.sql`, a real UTC timestamp, not a reserved number.
- No prior ADR named transfers; this is new ground, not a reversal.

### Consequence

- A transfer leg is indistinguishable from an ordinary record to every endpoint except analytics
  (which excludes it) and `RecordResource`'s write path (which refuses it) — `GET`, list, and the
  derived-balance arithmetic (`RecordEntity.netByAccount`) treat it identically to any other row,
  which is what "atomic balance update" reduces to under ADR-014.
- **`%dev`/`%test` now widen `zen.ratelimit.global.burst-limit`**
  (`server/src/main/resources/application.properties`) to 10000, mirroring jZen's own reference app
  (`apps/zen_demo`, jZen ADR-029). This was not part of the feature's design — it surfaced because
  the backend suite's own mutating-request volume, growing with `TransferResourceTest`, crossed the
  framework's production global burst limit (120/minute) within a single `@QuarkusTest` run, 429-ing
  unrelated tests (`UserScopingTest`) that happened to run in the same window. `%prod` is untouched.
- Verified: `task generate` / `task verify:contracts` clean; `./mvnw test` green (95 tests,
  including 15 new `TransferResourceTest` cases and the analytics-exclusion case added to
  `AnalyticsResourceTest`); `flutter analyze` and `flutter test` clean on the client (the one
  pre-existing, unrelated `prudent_l10n_test.dart` load failure reproduces identically on `main`),
  including a new `Record`/`Transfer`/`CreateTransferRequest` wire round-trip case and a
  `PrudentRepository.createTransfer`/`deleteTransfer` suite.

---

## ADR-030 — `run:dev`'s one-Ctrl-C teardown: jZen #84 + #88 + #89

**Date:** 2026-09-01. **Status:** accepted. **Follows:** ADR-029.
**Consumes:** [jZen#83](https://github.com/jZenDev/jZen/issues/83) →
[jZen#84](https://github.com/jZenDev/jZen/pull/84), then
[jZen#87](https://github.com/jZenDev/jZen/issues/87) →
[jZen#88](https://github.com/jZenDev/jZen/pull/88), then
[jZen#89](https://github.com/jZenDev/jZen/pull/89) → jZen `8a21f83`.

### Context

ADR-029 recorded jZen#82 as closing jZen#80 — "one Ctrl-C ends `run:dev` at once". It did not
hold, and took two more rounds:

- **jZen#82** ran the client with stdin closed. On Flutter 3.47.1 the client still needs two
  SIGINTs, and the backgrounded `quarkus:dev` shared the terminal's process group so the first
  Ctrl-C killed the server directly, not `stop_all`. (jZen#82 was verified against a mock.)
- **jZen#84** moved the rollup into `scripts/run-dev.sh` (real bash: `set -m` per-child process
  groups, `trap INT TERM` → ordered `stop_all`). Fixed the teardown — but broke startup: under
  `set -m` the backgrounded server subshell hit **SIGTTIN** on Quarkus dev's aesh TTY read and
  was stopped, so `run:dev` failed every run with "server did not become healthy".
- **jZen#88** closed the server subshell's stdin (`< /dev/null`), like the client. Server booted
  again — but `run:dev` still could not be *stopped*: `set -m` was left on for the whole script,
  so the `sleep` in the wait loop grabbed the controlling terminal each second and a terminal
  Ctrl-C landed on `sleep`, not the script — `stop_all` never fired.
- **jZen#89** switches `set -m` on only around each `&`, off again for the rest, so the poll
  loops keep the terminal and the script's `trap` fires on the first Ctrl-C.

### Decision

- **`JZEN_REF` moves to `8a21f83`** (jZen#89 merge) in `ci.yml` and `audit.yml`.
- Prudent's `run:dev` stays a one-line delegation to `zen:run:dev` — no Prudent-side code change.
- `Taskfile.yml`'s `run:dev` comment and `summary` are corrected: the mechanism is
  `scripts/run-dev.sh` (per-`&` process groups + a trapped INT/TERM teardown, both children
  stdin-closed), not "stdin closed … (jZen #82)".

### What this supersedes, and why

- **"jZen#82 closed #80 … so one Ctrl-C ends `run:dev` at once"** (ADR-029, *Context* /
  *Consequence*) → **corrected.** *Why:* jZen#82 was verified against a mock, not a live terminal
  run; it fixed neither the two-SIGINT client nor, once #84 landed, the startup hang or the
  `set -m` terminal-signal bug. jZen#84 + #88 + #89 together are the real fix.
- **"`task run:dev` verified end to end against `b74b73a`: … one SIGINT … exited in ~1.5 s"**
  (ADR-029, *Consequence*) → **that run did not go through a real terminal Ctrl-C**, which is the
  path that stayed broken until `8a21f83`.

### Consequence

- `task run:dev` **verified end to end** against jZen `8a21f83` under a pseudo-terminal: server
  healthy, client launched on `:8090`, then a single Ctrl-C (`0x03` to the pty) → `stop_all` ran,
  `prudent-server stopped`, `:8085` / `:8090` free.
- `docs/jzen/README.md` records the #83→#84→#87→#88→#89 arc as fixed and consumed.

---

## ADR-029 — The whole local run stack is jZen's: `run:server` / `run:client` deleted and delegated

**Date:** 2026-08-31. **Status:** accepted. **Follows:** ADR-028 (which deferred these two).
**Consumes:** [jZen#79](https://github.com/jZenDev/jZen/issues/79) →
[jZen#81](https://github.com/jZenDev/jZen/pull/81), and
[jZen#80](https://github.com/jZenDev/jZen/issues/80) →
[jZen#82](https://github.com/jZenDev/jZen/pull/82) → jZen `b74b73a`.

### Context

ADR-028 consumed the `run:*` operator guards (jZen#78) but kept Prudent's own `run:server` and
`run:client` because jZen's single-tier primitives had two gaps (jZen#79): `zen:run:server` did
not wire the local Supabase anon key, and `zen:run:client` passed a custom-scheme auth redirect
on every platform. It also noted `zen:run:dev`'s one-Ctrl-C teardown hung ~15 s (jZen#80).

jZen#81 closed #79 — `zen:run:server` now `deps: [run:supabase]` and evals `SUPABASE_URL` /
`SUPABASE_KEY`; `zen:run:client` / `zen:run:dev` pass `AUTH_REDIRECT_URI` only when the resolved
platform is not `web`. jZen#82 closed #80 — the client runs with stdin closed and is killed from
a `--pid-file` by the exit handler, so one Ctrl-C ends `run:dev` at once.

### Decision

**`run:server` and `run:client` are deleted and become one-line delegations** to `zen:run:server`
/ `zen:run:client` — the whole `run:*` family (`run:supabase`, `run:server`, `run:client`,
`run:admin`, `run:dev`) is now a bare-name alias to a jZen task, the way jZen's own `Taskfile.yml`
aliases them for zen_demo (ADR-049). `run:admin` is folded in too; it was already `pnpm dev` in
`admin/`, identical to `zen:run:admin`.

The Prudent-specific wiring the deleted bodies carried is passed **once, on the include**, not
re-implemented per task:

- `ZEN_WEB_PORT: 8090` (from ADR-028) — the origin `application.properties`' CORS allowlist is
  written for.
- `APP_CLIENT_DIR: client` (from ADR-028) — Prudent's client tier is the Flutter package itself.
- `ZEN_AUTH_REDIRECT_URI: prudent://auth-callback` — Prudent's native deep-link scheme.
  `zen:run:client` / `zen:run:dev` now apply it only for a native target (jZen#81), so setting it
  globally is safe: a `task run:client` web run does not get it, a `DEVICE=macos` run does.

The unused local `APP_PORT` var is dropped — the run tasks that read it are jZen's now (they
default `APP_PORT` to 8085) and `test:e2e` reads `ZEN_APP_PORT` from the environment.

`JZEN_REF` moves to `b74b73a` in `ci.yml` and `audit.yml`.

### What this supersedes, and why

- **"`run:server` and `run:client` stay Prudent's own, pending jZen#79 … When it lands, both
  tasks are deleted and delegated, completing this consumption"** (ADR-028, *Decision* point 4)
  → **done.** *Why:* jZen#81 landed with exactly the two fixes ADR-028 named, so the reason to
  keep a Prudent body is gone.
- **"One Ctrl-C does not cleanly end `run:dev`" and the Taskfile `run:dev` summary's slow-teardown
  note** (ADR-028, *Consequence*) → **resolved.** *Why:* jZen#82. The `run:dev` `desc` is back to
  "one Ctrl-C tears it down"; the workaround note is removed.

### Consequence

- `task --list` parses; `task zen:info` reports `b74b73a`.
- `task run:dev` verified end to end against `b74b73a`: full stack up, then **one SIGINT to the
  process group and the task exited in ~1.5 s** — backend and Chrome gone, ports `:8085` /
  `:8090` free, no trace of the ~15 s hang ADR-028 recorded.
- `task run:server` verified: `deps: [run:supabase]` brought the stack up, Quarkus dev reached
  "Profile dev activated" on `:8085`, and `POST /api/v1/auth/restore-password` answered `204`
  (not `500`) — the anon key `zen:run:server` wired is what lets the server reach Supabase's auth
  API at all.
- Prudent's `Taskfile.yml` now owns no local-stack process management at all — every finding the
  hand-rolled versions were built around (the CORS-403 trap, the platform-inference guard, the
  mailbox hint, the teardown) lives upstream, exercised by jZen's own zen_demo runs.
- `docs/jzen/README.md` records #79 and #80 as fixed and consumed; no `run:*` row reads "awaiting".

---

## ADR-028 — The local run stack: `run:dev` is jZen's, `run:supabase` is delegated, `run:server`/`run:client` wait on one more fix

**Date:** 2026-08-30. **Status:** accepted. **Follows:** ADR-007, ADR-027 (the consume-and-delete pattern).
**Consumes:** [jZen#77](https://github.com/jZenDev/jZen/issues/77) →
[jZen#78](https://github.com/jZenDev/jZen/pull/78) → jZen `0038919` (jZen ADR-049).
**Defers:** [jZen#79](https://github.com/jZenDev/jZen/issues/79).

### Context

ADR-027 recorded that the `run:*` tasks stayed Prudent's own "pending jZen#77" — jZen's generic
`run:client` / `run:dev` dropped the four operator guards Prudent's tasks carry (a wrong platform
compiles clean and fails at runtime; a missing backend reads as an opaque browser error; a web
origin outside the CORS allowlist is a 403 three layers from its cause; a local Supabase mails
nothing, so the confirmation link is in a mailbox a developer has to be told about).

jZen#78 folded all four into `Taskfile.app.yml`, against vars, closing #77. `run:supabase` is now
idempotent and prints the Studio/mailbox/Postgres URLs from `supabase status` (port-agnostic —
Prudent's shifted ports need no special case). `run:dev` starts Supabase, exports its URL and
anon key, brings the backend up with a CORS allowlist that already names the web origin, waits
for `/health`, and runs the client — with the platform-inference and CORS guards inline.

### Decision

**1. `run:dev` is added as a straight delegation to `zen:run:dev`.** Prudent had none. Issue #20
asked for "one command to run the stack"; this is it — `zen:run:dev` does the Supabase
credential wiring itself, so it needs nothing from Prudent's own `run:server`.

**2. `run:supabase` becomes a one-line delegation** to `zen:run:supabase` (idempotent,
port-agnostic, prints the Studio/mailbox/Postgres URLs) — the bare name kept as a thin alias, the
same way jZen's own `Taskfile.yml` aliases `run:supabase` / `run:server` / `run:demo` for
zen_demo (jZen ADR-049), and the same way ADR-027 kept `generate` / `deps` / `verify:contracts`.
CI, the docs and the skills say the bare name; the `zen:` prefix is an implementation detail.
`run:server`'s `deps:` stays `[run:supabase]`.

**3. Two include vars are set for the delegated run tasks.** `ZEN_WEB_PORT: 8090` — jZen defaults
the web client to `:5200`, but Prudent's `server/src/main/resources/application.properties` CORS
allowlist is written for `:8090`, so passing the port makes a delegated `run:dev` and a
hand-started `task run:server` agree without either naming the other's number. `APP_CLIENT_DIR:
client` — `zen:run:*` default the Flutter package to `<client>/<app>_client`, and Prudent's
client tier is `client/` itself (the same override reason as `PROTO_DART_OUT`).

**4. `run:server` and `run:client` stay Prudent's own, pending jZen#79.** Two gaps remain in the
single-tier primitives: `zen:run:server` does not eval the local Supabase credentials the way
`zen:run:dev` does (so `SUPABASE_KEY` is unset and auth 500s), and `zen:run:client` passes
`AUTH_REDIRECT_URI` on every platform when a custom-scheme redirect is native-only. Both are
app-agnostic — filed as jZen#79. When it lands, both tasks are deleted and delegated, completing
this consumption.

### What this supersedes, and why

- **"Prudent's `run:supabase` / `run:server` / `run:client` stay as they are until #77 lands,
  then are deleted and delegated"** (`docs/jzen/README.md`, the #77 findings row; ADR-027's
  *Consequence*) → **partially done.** *Why:* #78 closed #77 but left the two primitive gaps
  above, which #77 as filed did not cover. `run:supabase` is delegated and `run:dev` is added
  now; `run:server` / `run:client` follow on jZen#79 rather than being kept indefinitely.

### Consequence

- `JZEN_REF` moves to `0038919` in `ci.yml` and `audit.yml` — CI's jZen in step with what
  `run:dev` delegates to. `task --list` parses; `task zen:info` reports `0038919`.
- `task run:dev` brings up the full local stack in one command (verified against jZen `0038919`:
  `zen:run:supabase` printed the Studio/mailbox URLs, the backend reached "Profile dev activated"
  and passed the `/health` wait, and `flutter run -d chrome` compiled and served the web client on
  `:8090` with its debug service connected). `APP_CLIENT_DIR: client` is set on the include —
  `zen:run:*` default the Flutter package to `<client>/<app>_client`, and Prudent's client tier
  is `client/` itself (same override reason as `PROTO_DART_OUT`).
- `task run:server` and `task run:client` are unchanged in behaviour — same four guards, now
  duplicated with jZen's until #79 lets them be deleted. The duplication is stated, not hidden:
  `docs/jzen/README.md` carries the #79 row.
- **One Ctrl-C does not cleanly end `run:dev`** (jZen#80): the apps stop within a second but the
  task then sits ~15 s with `flutter run`'s leftover prompt before exiting — `flutter run` traps
  SIGINT and `zen:run:dev` has `trap … EXIT` only, no `INT`/`TERM` handler. A second Ctrl-C ends
  it at once. Reproduced against `0038919`; filed upstream since `run:dev` is a one-line alias.
  The Taskfile `run:dev` summary carries the workaround.

---

## ADR-027 — The rest of the contract loop is consumed from jZen, and `server/openapi.json` is no longer tracked

**Date:** 2026-08-30. **Status:** accepted. **Follows:** ADR-007 (the consume-and-delete pattern).
**Consumes:** [jZen#74](https://github.com/jZenDev/jZen/issues/74) → jZen `b443780`
([jZen ADR-049](https://github.com/jZenDev/jZen/blob/main/docs/architecture/DECISIONS.md)).
**Supersedes:** ADR-011's tracked-artifact half.

### Context

ADR-007 set the pattern for the contract loop: when jZen makes a task app-agnostic in
`Taskfile.app.yml`, Prudent deletes its hand-rolled copy, delegates, and proves the regenerated
artifacts byte-identical — "a task that exists in two files is drift waiting to happen". ADR-007
did this for `generate:proto:dart` alone and named the rest as "separate migrations to consume
when jZen makes them app-agnostic, on this same pattern".

jZen #74 makes them app-agnostic. jZen's `Taskfile.app.yml` now carries the whole loop written
against vars — `deps` (+ per-tier), `generate` / `generate:proto*` / `generate:api*` /
`generate:l10n`, and `verify:contracts` (+ its internal `verify:contracts:check`) — plus the
local-stack `run:*` tasks. jZen's own `Taskfile.yml` delegates to every one, so the framework
runs the same code Prudent does.

### Decision

**1. Prudent deletes its copies and delegates.** `Taskfile.yml` loses `generate:proto`,
`generate:proto:java`, `generate:proto:dart`, `generate:api`, `generate:api:schema`,
`generate:api:ts`, `generate:l10n`, `sync:contracts`, `sync:verify`, and `deps:admin`. Three
thin local aliases remain for the names CI and the `sync-contracts` skill type — `generate`,
`verify:contracts`, `deps` — each a one-line delegation to `zen:<name>` (the same reason ADR-007
kept the `generate:proto:dart` name).

**2. `sync:contracts` / `sync:verify` are retired, not aliased under the old names.** The gate is
`task verify:contracts`; regeneration on its own is `task generate` (always green — jZen ADR-049's
split, so "regenerate my code" never fails you because the regeneration worked). A stale
`sync:contracts` reference now fails with "task not found" rather than silently resolving.

**3. `server/openapi.json` is no longer tracked.** jZen's model — openapi.json stays in
`server/target/openapi/` (under the ignored `target/`), and the tracked downstream artifact the
drift gate watches is the admin panel's `admin/src/api/schema.generated.ts`. `git rm --cached
server/openapi.json`; a `.gitignore` line stops it coming back. `admin/package.json`'s
`generate:types` script now reads `../server/target/openapi/openapi.json` (matching
`zen_demo_admin`).

**4. `JZEN_REF` in `ci.yml` moves to `b443780`.** The tasks the workflow calls (`verify:contracts`,
the all-tier `zen:deps`) do not exist in jZen before that commit. `zen:deps` is now an aggregate,
so CI jobs that only need one tier call `zen:deps:client` / `zen:deps:admin` by name rather than
paying for a Maven `go-offline` (or, on the Windows runner, failing on a JDK it does not have).

### What this supersedes, and why

- **"So `generate:api:schema` copies the document to `server/openapi.json`, which is tracked …
  Prudent has no admin panel until Phase 5, so until then the document itself is the artifact
  worth tracking. `generate:api:ts` joins the task then"** (ADR-011, *`openapi.json` is tracked,
  because otherwise the gate checks nothing*) → **refined: the "until then" has arrived.** *Why:*
  ADR-011 tracked the document only as a stand-in for a tracked downstream artifact, to keep the
  drift gate from checking nothing (everything Maven writes is under gitignored `target/`). The
  admin panel exists now, `schema.generated.ts` is tracked and watched by
  `zen:verify:contracts:check`, so the stand-in has a real thing to stand down for. ADR-011's
  *component-schema* findings (framework messages an application must declare in its static
  `openapi.yaml`, dangling `$ref` detection) are untouched — that document is the hand-authored
  source and stays tracked.
- **"the rest of the loop is still Prudent's own … Each is a separate migration to consume when
  jZen makes it app-agnostic, on this same pattern — report, wait, delete the local copy, prove
  it green"** (ADR-007, *Consequence*) → **done for the contract loop and `deps`.** The server
  *build* (native image, web/admin staging), the `run:*` tasks and the deploy stay Prudent's own —
  the first two genuinely prod-shaped, `run:*` pending
  [jZen#77](https://github.com/jZenDev/jZen/issues/77).

### Consequence

- One cost, recorded: regenerating admin types now needs a packaged server (a JDK), where the
  tracked `server/openapi.json` let a Node-only developer do it. Mitigation: `schema.generated.ts`
  stays tracked, so *compiling* the panel never needs regeneration — only a contract change does,
  and that is already a backend/JDK change. This is jZen's own model (jZen ADR-005; `zen_demo`).
- `task generate` produces **byte-identical** `client/lib/generated/**/*.pb.dart` and
  `admin/src/api/schema.generated.ts` — the delegation changed the mechanism, not the artifact,
  which is the only evidence the swap was faithful (the same check ADR-007 used).
- `task verify:contracts`, `task zen:test:client`, `task test:admin`, `task test:server` green
  against jZen `b443780`.
- The `run:*` operator guards Prudent's tasks carry (CORS-allowlist preflight, pre-launch health
  check, `DEVICE`→`ZEN_PLATFORM` inference, local-Supabase mailbox hints) are app-agnostic and
  filed as jZen#77 — Prudent's `run:*` are left as-is until it lands, then deleted on this same
  pattern.
- `docs/jzen/README.md`'s findings table records #74 reported → landed → consumed; no row reads
  "awaiting".

---

## ADR-026 — A Zen layout: client code lives flat in `lib/`, server code in `prudent.*`, and a directory must be a capability

**Date:** 2026-08-29. **Status:** accepted. **Not yet executed** — the work is driven by
`docs/prudent-restructure-prompt.md`; this entry is the decision it carries out.

### Context

Phases 0–5 left the source tree in a shape that no phase ever designed and that contradicts
`docs/zen-architecture.md` ("Packages as capabilities … not layers, tiers, or technical
boundaries"):

- **The client is half-migrated.** Phase 0 moved the original `lib/` into `client/` "changing no
  file contents", so the app's own feature code stayed at `client/lib/{account,category,record,
  chart,screens,widgets}/`. Phases 1 and 3 then put every *new* file under `client/lib/src/`
  (`prudent_repository.dart`, `providers.dart`, `l10n/`, `generated/`, later `app.dart`,
  `auth_deep_links*.dart`, `src/screens/`). Nothing ever reconciled the two. `lib/src/` is a
  published-package privacy convention; Prudent's client is an application, and the split is just
  drift.
- **Layer folders and lone containers.** `lib/screens/` holds five unrelated screens — a layer,
  not a capability. `lib/widgets/popup/` and `lib/record/records_list/` wrap one or two files in a
  directory that names a role. `lib/src/screens/` holds `home_shell.dart` and `auth_flow.dart`
  next to unrelated files.
- **The server package is `prudent.server.*` under `server/`.** `server/` already scopes the tier;
  `prudent/server/` is a wrapper package whose only child is `server` and whose root holds seven
  loose files (`CurrentUser`, `HealthResource`, `PrudentStatus`, `PrudentException`,
  `PrudentExceptionMapper`, `Currencies`, `Ids`) with no capability around them.

### Decision

**One layout rule, both tiers:**

1. A directory names a **product capability**, never a technical role. `screens/`, `widgets/`,
   `services/`, `mappers/`, `models/`, `utils/` are not directory names.
2. A directory must hold **two or more files** of one capability. A single-file concern is a file
   at the parent level, not a lone-child directory.
3. A wrapper directory with exactly **one child directory** is removed.
4. **Exception to (2):** a cross-cutting single-file utility may sit flat at the package root
   (`prudent/Ids.java`, `prudent/Currencies.java`).
5. The pass is **pure structure** — `git mv` plus `package` / `import` / path-string edits, zero
   behaviour change, no test lost.

**Client** — `client/lib/src/` is deleted; everything moves up to `client/lib/`.
`lib/{screens,widgets,chart}/` and `lib/record/records_list/` are dissolved. Capabilities that
earn a directory: `account/`, `category/`, `record/`, `overview/`, `analytics/` (the charts fold
in here), `auth/` (the deep-link files plus `auth_flow.dart`), `l10n/`, `generated/`. Everything
else is a flat file at `lib/`: `main.dart`, `app.dart`, `home_shell.dart`,
`prudent_repository.dart`, `providers.dart`, `money.dart`, `settings.dart`, `popup.dart`. Full map
in `docs/prudent-restructure-prompt.md`.

**Server** — the base package `prudent.server` becomes `prudent` (main and test). `server/` the
directory stays; `prudent/server/` the package goes. New capability packages `health/` and
`error/`; existing `record/ account/ category/ settings/ retention/` keep their shape.
`onboarding/` and `analytics/` collapse to flat files (`NewUserSetup.java`,
`AnalyticsResource.java`) until a second class joins each. `CurrentUser.java`, `Ids.java`,
`Currencies.java` are flat. **No `prudent/auth/` package** — auth is `zen-identity`'s; `CurrentUser`
is Prudent's only auth class, so rule 2 keeps it flat.

The generated-DTO namespace **`prudent.proto.v1`** (proto `java_package`, ADR-006) is unchanged.

### What this supersedes, and why

- **"today's root package moves here" / `client/lib/src/prudent_repository.dart` /
  `client/lib/src/l10n/prudent_{en,uk,pl}.arb`** (`docs/implemented-plans/prudent-migration-plan.md`
  §2, §2.5, Phase 3) → **refined.** The plan named `lib/src/` for new client code by following
  `zen_demo`'s package layout; a `zen_demo` *package* is imported by URI by other packages, which
  is why its implementation sits under `src/`. Prudent's client is a leaf application imported by
  nobody, so the privacy split buys nothing and the plan's own Phase 0 ("changing no file
  contents") guaranteed it would only ever be half-applied.
- **`prudent.server.*` as the server package** (implicit since Phase 2; the path appears in ADR-001
  "Proving it" and throughout `server/pom.xml`) → **changed** to `prudent.*`. It was convention,
  never a decision; `server/` the directory already carries the tier, so the `server` package
  segment is rule 3's wrapper-with-one-child.
- **"Each package owns `lib/src/l10n/*.arb`"** (`CLAUDE.md`, "Typed, generated i18n") → **changed**
  to `lib/l10n/*.arb`. Prose updated in the same change.
- ADR-001's reference to `server/src/main/java/prudent/server/PrudentStatus.java` is **not edited**
  (ADRs are append-only); the file moves to `prudent/health/PrudentStatus.java` and this entry is
  the record of it.

*Why now:* the tree is small (≈40 Java files, ≈35 Dart), the seam is fully tested, and every extra
week of feature work deepens the `import` graph that has to be rewritten. A half-migrated `lib/`
also teaches every new session the wrong convention by example.

### Consequence

When executed and green, the following hold — to be **verified**, not assumed, by
`task sync:contracts && task test:server && task zen:test:client && task verify:boundaries` plus a
web build, with no drop in either suite's test count:

- One place for client code (`client/lib/`), one base package for server code (`prudent`).
- Every directory in either tier answers "what capability is this?"; none answers "what layer?".
- `client/l10n.yaml`, `client/analysis_options.yaml`, both `.gitattributes`, `Taskfile.yml`'s
  `PROTO_DART_OUT`, and `.claude/hooks/skill-map.json` point at `client/lib/generated` /
  `client/lib/l10n/generated`; `scripts/verify_boundaries.py` needs no change (its scope is
  `client/lib` and it excludes `/generated/` by substring).
- The path-dependency imports (`package:zen_core/…`, `zen-parent`) are untouched — this pass does
  not interact with ADR-001's seam or its exit.

---

## ADR-001 — Three tiers under a language-neutral root, and jZen consumed from a sibling checkout

**Date:** 2026-08-15. **Status:** accepted.

### Context

Prudent is a minimalist personal-finance application built on **jZen**, a framework for full-stack
applications (Quarkus server, Flutter client, a Protobuf contract). jZen is a **declared
dependency** — Prudent is its consumer, not part of it.

Every jZen package is `0.1.0` and unpublished: `publish_to: none` on the Dart side, `-SNAPSHOT` on
the Maven side, no npm registry entry. So the framework has to be consumed from somewhere other
than a registry, and the repository has to be shaped to hold three tiers rather than one Flutter
package.

### Decision

**The repository root is language-neutral.** No root `pom.xml`, no root `pubspec.yaml`, no root
`package.json` (jZen STANDARDS, "Package modularity"). The tiers are `client/`, `server/`, and —
from Phase 1 — `proto/`. `Taskfile.yml` is the single entry point and **includes**
`../jZen/Taskfile.app.yml` rather than copying it (jZen ADR-046), so jZen and Prudent run the same
orchestration code rather than two copies that resemble each other.

**jZen is consumed from a sibling checkout at `../jZen`**, one mechanism per ecosystem:

- **Dart** — plain `path:` dependencies, package by package, in `client/pubspec.yaml`. Imports stay
  `package:zen_core/…` — character for character what a published consumer writes. jZen ADR-026
  evaluated a facade package that re-exports the framework and **rejected it for exactly this
  reason**: a facade compiles, but it changes every import to `package:<facade>/…`, so the day the
  packages are published every import changes again. A `path:` dependency makes that migration a
  pubspec edit with zero code churn. The facade also erases the signal the dependency exists to
  produce — a dependency list naming six framework packages *is the finding*, and one umbrella name
  hides it.
- **Java** — `server/pom.xml` declares `zen-parent` as its parent with an **empty
  `<relativePath/>`**, resolving the parent and the framework artifacts from the **local Maven
  repository**.
- **Admin**, when it arrives — `@jzen/admin-core` from `../jZen/admin/src` via a TypeScript `paths`
  alias plus a Vite `resolve.alias`, not a pnpm dependency edge.

### The divergence from jZen ADR-026, and why Prudent's rule wins

jZen ADR-026 specifies how a second product consumes the framework, and on the **Maven half**
Prudent does something different. ADR-026 puts a **root aggregator POM in a folder above both
repositories** and gives the product's server a filesystem `<relativePath>` into the jZen checkout,
so both build in one reactor with no `~/.m2` install at all. That is a real advantage and it was
verified to work.

Prudent does not do it, for two reasons:

1. **CLAUDE.md requires that all work happen inside this repository**, and that nothing reach
   outside the repo root to create or modify a file. A root aggregator POM in the parent directory
   is a file above the root, owned by neither repository and created by neither one's tooling.
2. **A cross-repository `<relativePath>` couples the build to a directory layout instead of to a
   version.** The empty form couples it to a *coordinate* — which is what the eventual published
   dependency will also be, so publishing changes a version string and deletes nothing else.

The repository's own boundaries are **Prudent's concern, not the framework's**, so Prudent's rule
wins here and this entry is the record of it. This is a divergence in *mechanism*, not in intent:
ADR-026's actual finding — that of the three ecosystems only Java cannot reach across repositories
on its own — is what both approaches are answering.

**The cost of diverging** is a prerequisite Maven cannot express: something must install the
framework artifacts into the local repository first, and no POM can say "go build another
repository". That step is `task zen:framework:install`. Its failure mode is a *non-resolvable parent
POM* error that reads like a broken or malformed file rather than a missing sibling — which is why
it is documented at length in `server/pom.xml`, where someone hitting it will actually look, rather
than only here.

### Proving it, rather than asserting it

The seam is proven by **one class that compiles against a framework type**:
`server/src/main/java/prudent/server/PrudentStatus.java` extends `zen.core.http.ZenStatus`.
`ZenStatus` is the type jZen ADR-026 used to verify the same question from the other side. A module
that compiles because it depends on nothing would have proven nothing.

### The cost, stated plainly

**There is no version boundary between the two repositories.** In consequence:

- the two checkouts move in **lockstep**, and a `git pull` in `../jZen` can break Prudent's build
  with no version to point at;
- **CI needs both checkouts**, jZen pinned at a revision and installed before Prudent's Java build;
- a contributor needs the sibling checkout at **exactly** `../jZen`;
- **`task zen:info` reporting a *dirty* jZen means the build is not reproducible** — the only
  honest answer to "which framework is this?" is a commit, and the only warning that the answer is
  unstable is a dirty tree. Run it first when a build behaves oddly.

Per jZen ADR-026, the trigger for publishing is **Prudent's first CI run, Java first**: a lone clone
has no sibling checkout and no local repository, so CI either checks jZen out at a pinned revision
or forces the publishing decision.

### The exit

When jZen publishes its packages, every `path:` becomes a version range, `zen-parent` becomes a
released version, the admin alias becomes a pnpm dependency, and **`docs/jzen/` is deleted** — a
versioned dependency's documentation travels with the package, and there is no sibling checkout
left to point at. That is **an ADR, not a cleanup**, because it changes what Prudent is coupled to.
`docs/zen-architecture.md` is unaffected: it is Prudent's own cornerstone and does not depend on
jZen.

### Consequence

A contributor loses `flutter run` from the repository root, because the root is not a Dart package
any more. It is `cd client && flutter run`. That is the price of a language-neutral root, and it is
written in `README.md` where someone hits it.

---

## ADR-002 — Flyway migration versions are UTC timestamps

**Date:** 2026-08-15. **Status:** accepted. **Written before the first migration exists.**

### Context

Flyway is the **single migration authority** for Prudent's database — never two migration systems
on one database. But Prudent is not the only thing migrating it: `zen-identity` ships its own
migrations and runs them into **Prudent's** database. Two independent authors are numbering
migrations against one schema history.

CLAUDE.md's instruction was to **reserve a version band** that cannot collide with `zen-identity`'s.

### Decision

**Prudent adopts jZen ADR-033's scheme instead: a UTC timestamp.**

```
V<YYYYMMDDHHMMSS>__prudent_<what>.sql
```

This is **stronger than a reserved band**, and the difference is the reason for the change. A band
prevents *collisions* — two migrations claiming the same version — but it cannot guarantee that a
newly written migration sorts **above everything already applied**. That second property is the one
that matters operationally, because Flyway **refuses to start** when it finds an out-of-order
migration below the current schema-history high-water mark. A band lets a developer pick any free
number inside it, including one below a version already deployed.

A timestamp gives both properties **by construction**: it is monotonic, so a new migration always
sorts last; it cannot collide, because two authors cannot generate the same second and any Prudent
timestamp is far from `zen-identity`'s range; it sits above the advisory 1000-floor by orders of
magnitude; and it **cannot be got wrong by omission** — there is no free number to choose badly.

This supersedes CLAUDE.md's "pin the band in an ADR" instruction, which is exactly what an ADR is
for.

### Three rules that ship with it

- **Every new table ships RLS *and* a `zen_runtime` application policy in the same migration.**
  Both, always, together. A table created in `public` without them is published to the internet
  through Supabase's Data API; and RLS enabled *without* a policy is the worse failure, because it
  returns **zero rows rather than raising** (jZen ADR-036). A migration that adds RLS in one change
  and the policy in the next leaves a window where the application silently reads nothing — which
  passes a smoke test that only checks for the absence of errors.
- **Repeatable migrations (`R__prudent_*.sql`) are for grants and policies only.**
- **An applied migration is immutable, including its comments.** Flyway checksums the whole file, so
  fixing a typo in a comment breaks validation on every environment that already ran it.

---

## ADR-003 — Prudent ships six platforms, and each desktop target costs a CI runner

**Date:** 2026-08-15. **Status:** accepted.

### Context

`client/` carries platform folders for all six Flutter targets. Today `linux/` and `windows/` are
`flutter create` scaffolding that nothing has ever built, which normally argues for deleting them:
unbuilt scaffolding is a claim the repository does not honour.

### Decision

**Prudent ships Android, iOS, web, macOS, Linux and Windows** — the full jZen set (jZen ADR-045).
All six platform folders are kept **on that basis**, as a deliberate product decision rather than by
inheritance from `flutter create`.

They stop being leftovers the moment CI builds them, which is Phase 5. Deleting them now would only
mean recreating them then — and a recreated platform folder loses any configuration it had
accumulated in between.

### The cost, which is the part worth recording

**Desktop builds are host-only.** Flutter refuses `build linux` off a Linux host and `build windows`
off a Windows host, and the Apple targets need Xcode. This is not a policy that can be waived; there
is no cross-compilation path.

In consequence:

- **CI needs `ubuntu-latest` *and* `windows-latest`.** The desktop claims can be proven nowhere
  else. Each platform Prudent claims costs a runner, so the platform list is a budget line, not just
  a manifest.
- **No single machine verifies the full set.** `task zen:build:runners` builds every runner *the
  current host can* and **announces what it skipped** rather than passing silently — a skip that
  looked like a pass is how a platform list becomes untrue.
- macOS and iOS are built on the delivery machine and skipped audibly in CI, on jZen's cost
  reasoning.

**Why runner builds are a separate gate from tests.** No test compiles a runner: unit and widget
tests run on the Dart VM and the flutter tester, which never invoke Xcode, Gradle, CMake or MSBuild.
A Flutter dependency does not enter one platform, it enters all of them, and each has its own build
system that can reject it on its own terms — so a change can leave every suite green and every
shippable artifact broken.

### The application id

The application id is **`com.jlogicsoftware.prudent`**, set in this phase across all six platforms:
Android's `namespace` and `applicationId` plus the Kotlin package directory, the iOS and macOS bundle
identifiers (including the `RunnerTests` variants), and Linux's `APPLICATION_ID`.

It replaced `com.example.prudent`, a `flutter create` default. This was changed **now rather than
later** because it is not merely cosmetic: it is what a store submission, a custom URI scheme and
App Links / Universal Links all key on, and App Links verify against a domain the publisher actually
controls — so `com.example.*` cannot ship, and the longer it sits the more places key on it.

**Still open:** the auth callback scheme (`prudent://auth-callback`), which the server must be
configured to accept by exact match. It is decided in Phase 3, where auth is wired and there is
something to accept it.

---

## ADR-004 — The third-party backend call is removed now, before its replacement exists

**Date:** 2026-08-15. **Status:** accepted. **Supersedes:** the migration plan's sequencing, which
placed this removal in Phase 3 alongside the client rewiring.

### Context

Records were read and written over `package:http` directly to a Firebase Realtime Database URL held
as a `const` in `lib/main.dart`. Accounts and categories were already process memory.

This is precisely what the framework's central client rule forbids: **no client package calls a
third party directly — the client talks to one server, and it is ours.**

The plan sequenced the removal into Phase 3, where the replacement (`ZenClient` against Prudent's
own server) is built, so that the call would be replaced rather than merely deleted. That is the
tidier sequence, and it was not chosen.

### Decision

**The call is removed now**, in the repository-shaping phase, ahead of anything that replaces it.
`recordsProvider` is backed by the `registeredRecords` seed list that already existed in the file
and was previously unused, which leaves all three providers consistent: accounts, categories and
records are process memory, lost on restart. `package:http` is dropped as a dependency and the
hardcoded URL is gone.

### Why not wait for the replacement

The rule this breaks **fails silently**. An application talking to someone else's backend renders,
authenticates and passes every test — there is no failing check, no error, and nothing in a code
review that looks urgent. A rule whose violation produces no symptom is one that survives every
sequencing argument made for postponing it, so the removal is not made contingent on other work.

The cost of removing it early is real and is accepted: **records no longer persist across a
restart.** That is a genuine regression in the one feature that had a backend, and it is preferred
to the alternative, because what that feature actually did is set out below.

### What was lost, which is less than it appears

Three defects went with the call rather than being carried across. Each was invisible until it
fired, and together they mean the persistence being given up was not working:

- **The create response was decoded as a record.** Firebase answers a create with
  `{"name":"-Nxyz…"}`; that `Map` was pushed straight into a `List<Record>`, making every
  *successful* save a runtime type error.
- **Category ids did not survive a restart.** `Category`'s constructor mints a fresh uuid and the
  seed list is rebuilt on every boot, so the ids stored beside persisted records never matched
  again. The lookup threw rather than degrading, so the records list failed outright for anything
  written in an earlier session — the one feature with a backend was broken across the only
  boundary that mattered.
- **Every fetch error rendered as an empty list**, because consumers read `asData?.value ?? []`. A
  thrown fetch was indistinguishable from having no records at all.

Deletes and edits were also local-only and never reached the server.

### Consequence

Phase 3 rewires all three providers over `ZenClient` in one uniform change rather than converting
one path and deleting another. The seed lists become server data created on first login, and record
identity is minted server-side rather than by the client constructors — an id from an untrusted
client is not identity.

`task verify:boundaries` (Phase 3) is what will keep this true; until it exists, the rule is held by
this entry and by the comments at the two places where the temptation recurs
(`client/lib/record/records_provider.dart`, `client/pubspec.yaml`).

**Not covered by this entry:** the Firebase project itself, its API key and its billing are not this
repository's to leave running. Decommissioning it is an open question in the plan (§5.6) and is
outside the repository.

---

## ADR-005 — One Java version everywhere; the build toolchain is delegated, never pinned to a literal

**Date:** 2026-08-15. **Status:** accepted.

### Context

Prudent's Android build could not run at all. `flutter build apk` failed with a message whose entire
text was `25.0.3` — naming no tool, no version, and nothing about a version being unsupported.

The cause: Gradle compiles `build.gradle.kts` with the Kotlin compiler embedded in the **Gradle
distribution** (`org.gradle.kotlin.dsl.support.KotlinCompiler`). That compiler is not swappable,
overridable or pinnable, and under Gradle 8.x it cannot parse a two-digit Java feature version. Java
25 support arrives in **Gradle 9.1**.

Two things about this are worth recording, because both cost real time here:

- **The `org.jetbrains.kotlin.android` plugin version is not a lever.** It governs compilation of
  the application's own Kotlin sources and has no bearing on how the build scripts themselves are
  compiled. Bumping it under Gradle 8.x changes nothing. The only way to change that compiler is to
  change the Gradle distribution.
- **`android/` had simply never been rolled forward.** It was scaffolded from an older
  `flutter create` template. This was not a policy question about which Java to support; it was
  drift in one directory, against a reference application that already builds on a current JDK.

### Decision, part one: one Java version everywhere

**The Java version is the same everywhere; only the distribution differs.**

| Where | Distribution |
|---|---|
| Maven, Quarkus, native image | GraalVM 25 (jZen pins `25.0.2-graalce` in `.sdkmanrc`) |
| Android / Gradle | Temurin 25 |

Two distributions are necessary rather than untidy: AGP's `jdkImage` transform shells out to
`jlink`, and GraalVM's `jlink` cannot run it, so the Android build needs a standard JDK. That is why
the split exists at all.

**Installing an older JDK to satisfy Android is rejected.** Flutter takes its JDK from
`flutter config --jdk-dir`, which outranks `JAVA_HOME`, `GRADLE_OPTS` and `org.gradle.java.home`,
and which is a **machine-wide** setting applying to every Flutter project on the machine. Pinning a
second Java version for Prudent's benefit would silently change every other Flutter Android build on
that machine, jZen's reference application included — fixing this repository by breaking another
one. A repository may not buy its own correctness with a global side effect.

The consequence is that the *toolchain in the repository* must support the JDK, rather than the
developer downgrading the JDK to suit the repository. Hence Gradle 9.1.0 / AGP 9.0.1 / KGP 2.3.20,
matching what the reference application already builds against.

### Decision, part two: delegate the toolchain, never pin a literal

**Where the Flutter SDK exposes a version, use it rather than copying its current value.**
Concretely, `ndkVersion = flutter.ndkVersion`, not a version string.

This is the more transferable half of the entry, because the failure mode is invisible. Prudent
pinned `ndkVersion = "27.0.12077973"` — the AGP 8.x-era default, drift from the same stale template
as the Gradle wrapper — and it stayed hidden until the toolchain upgrade got far enough to resolve
plugin projects at all.

**Flutter actively steers you into re-making the mistake.** When a plugin requires a newer NDK than
the pin, the tool prints:

```
Fix this issue by using the highest Android NDK version (they are backward compatible).
    ndkVersion = "<version>"
```

with the version interpolated from whatever the current plugin set happens to need. Accepting that
suggestion re-pins to a **snapshot of today's dependency graph**, and the next plugin that wants
newer — or the next Flutter SDK bump — reopens the identical failure. The suggestion is correct
about the value and wrong about the mechanism.

A literal that is right today is worse than an obviously wrong one: it passes review and every
build, and fails later for a reason disconnected from the change that caused it.
`flutter.ndkVersion` tracks the AGP-default NDK for whatever Flutter is in use, which is the version
the plugin ecosystem converges on anyway.

**`jvmTarget` is the deliberate exception and stays at 17.** It is the bytecode level of the shipped
APK, pinned by Android's desugaring surface, and is independent of the JDK running the build. It is
not raised to "match" the toolchain.

### Consequence: the Flutter version must be pinned

Delegating to the SDK moves the variable rather than removing it. `flutter.ndkVersion` is only
stable across a team if the **Flutter version** is, so two developers on different Flutter releases
would resolve different NDKs and hit this asymmetrically.

Prudent therefore pins Flutter in **`.fvmrc`** at the repository root (`3.44.2`), matching jZen. The
pin is advisory until CI enforces it: jZen's workflows pass `flutter-version` explicitly to the
setup action, and Prudent's must do the same when they are written in Phase 5. A pin nothing checks
is documentation, not a constraint.

### Consequence: the daemon outlives the change

After changing the Gradle distribution, kill the daemon — one started under the old distribution
survives a wrapper change and keeps serving the old Gradle, so the first build after the upgrade
fails exactly as it did before it.

---

## ADR-006 — The wire contract: what crosses it, and which side of the tracking rule each generated artifact falls on

**Date:** 2026-08-15. **Status:** accepted.

### Context

Prudent's models existed only as Dart classes holding Flutter types: `double` money, an `IconData`
icon, a `Color` colour, and client-minted uuids. None of that can cross a wire, and jZen's
contract-first rule (`../jZen/docs/architecture/STANDARDS.md`, "Source of truth") makes `.proto`
canonical for models with every other language derived from it.

This entry records the shape that was settled and, for each representation, the defect the
alternative would have introduced. It also settles the question a contract phase cannot leave
open: which generated output is committed and which is built.

### Decision — the contract

`proto/prudent/v1/{records,accounts,categories}.proto`, package **`prudent.v1`**, Java package
**`prudent.proto.v1`**, `java_multiple_files = true`, and an explicit `java_outer_classname`
(`RecordsProto`, …) rather than one defaulted from the filename. The directory mirrors the proto
package the way `../jZen/proto/zen/v1/` mirrors `zen.v1`. **`v1` is the API version and is
independent of the product version.**

**Every endpoint declares its own request and response message.** There is no envelope and no
generic payload: HTTP status carries the status, `X-Request-ID` carries the request id, and errors
are a `zen.v1.ZenError` body. Messages are named for the Phase 2 REST surface they serve
(`CreateRecordRequest`, `Record`, `ListRecordsResponse`, …).

| Concern | The contract carries | The defect the alternative has |
|---|---|---|
| Money | `int64 amount_minor` / `balance_minor` + `string currency` (ISO-4217) | binary floating point cannot represent 0.10, and an expense tracker sums thousands of values. Note proto3 JSON encodes `int64` **as a string**; both clients handle that, and the round-trip suite pins it |
| Category colour | `uint32 color_argb` | a colour is a value and ARGB is its portable form; it survives a user picking outside today's ten swatches. `dart:ui`'s `Color` stays at the widget boundary |
| Category icon | `string icon_key`, **never a code point** | `IconData(codePoint)` built from data defeats `--tree-shake-icons`, shipping the whole Material font in every bundle. The client holds a `const Map<String, IconData>`; an unknown key renders a documented fallback rather than throwing |
| Record date | `string date`, ISO-8601 `YYYY-MM-DD` | a purchase happens on a calendar day. An epoch timestamp forces every reader to pick a timezone, and at a DST boundary a record shifts a day — at a month edge, into the wrong month, which is a wrong total |
| Identity | ids are server-minted; a create request carries **no id** | an id from an untrusted client is not identity |
| Ownership | **`user_id` never appears on the wire, in either direction** | it is the JWT `sub`. A client that can name an owner can name someone else's |
| Account type | `ACCOUNT_TYPE_UNSPECIFIED = 0` first, then `CASH/CARD/CHECKING/SAVINGS` | proto3 requires a zero value and decodes every omission to it; a default meaning "cash" is a silent data defect, because cash is a valid answer |

Four questions the plan left open are closed here:

- **A `Record` carries a required `account_id`** (plan §5.1). Records and accounts were previously
  unconnected, which is why `totalBalance()` never moved when money was spent. An optional link
  would make every later piece of arithmetic branch on its absence, forever.
- **The default currency is `PLN`, and an account's and a record's currency cannot disagree**
  (plan §5.2, no FX). Not by validation but **by construction**: `CreateRecordRequest` and
  `UpdateRecordRequest` carry no currency field at all, and the server copies the owning account's
  onto the `Record` response so a list renders without loading accounts. `Account.currency` is also
  not replaceable by `UpdateAccountRequest` — changing it would reinterpret every existing record's
  amount without converting it, turning 100 PLN into 100 EUR silently.
- **All four `Account` booleans are kept; `Account.description` is dropped.** `is_active` and
  `include_in_total` are already read by `totalBalance()`; `include_in_overview` and
  `include_in_total` are both named by the overview arithmetic; `is_default` pairs with the new
  required `account_id` as the pre-selected account. `description` was an always-null field nothing
  could set and nothing rendered — carrying it would commit a decision nobody has made. Field
  number 10 is left for it. (`Category.description` stays: the category form sets it today.)
- **Updates are FULL REPLACEMENTS, not patches.** A `PUT` carries every mutable field and every one
  is applied. Plain proto3 scalars have no presence, so an absent field and an explicitly-sent
  default are byte-identical on the wire — which matters most for the four `Account` booleans,
  where a partial-update message would silently write `false` for anything the client forgot.
  Replacement makes the semantics readable from the message alone. A `PATCH` surface, if ever
  wanted, gets `optional` fields and its own messages rather than a reinterpretation of these.

**`analytics.proto` is deliberately not written.** Analytics is new product work with no endpoint
and no agreed arithmetic behind it; a message written before either exists is a guess committed to
a contract, and a contract is the one place a guess is expensive to withdraw. This narrows the
plan's Phase 1 file list (`docs/prudent-migration-plan.md` §4, "Phase 1 — The contract"), which
named `analytics.proto` alongside the other three.

### Decision — the tracking rule, and why the two sides differ

| Side | Output | Tracked? |
|---|---|---|
| Java | `server/target/generated-sources/protobuf/` | **No** |
| Dart | `client/lib/src/generated/prudent/v1/*.pb*.dart` | **Yes** |

This is a **toolchain-boundary** question, not a preference. `protobuf-maven-plugin` resolves the
`protoc` binary from Maven Central itself, so anyone with the Maven wrapper regenerates the Java
side hermetically and committing it would only add a second copy to keep honest. The Dart side
needs a **system `protoc`** plus **`protoc-gen-dart`** — tools a Flutter developer has no other
reason to install — so the output is committed, `.gitattributes` marks it `linguist-generated`, and
`flutter test` and `flutter build` keep working for someone who has neither.

Either way, **a tracked generated file is never hand-edited.** Fix the `.proto` and regenerate.

### Framework messages are referenced, not imported — measured, not assumed

`ZenError` and `PageRequest` live in `../jZen/proto/zen/v1/common.proto` and are **never copied
here**. Prudent's files reference them in comments and **import nothing** — which is what jZen's
own protos do: not one of `admin.proto`, `demo.proto`, `identity.proto` or `jobs.proto` imports
`common.proto` either. `ZenError` is an error *body*, returned in place of a response rather than
embedded in one, and `PageRequest`'s fields are query parameters on a `GET`.

Both halves of a cross-repository import were nevertheless **run** before this was settled, against
a throwaway proto importing `zen/v1/common.proto` with `-I proto -I ../jZen/proto`:

- **Java — clean.** `--java_out` emitted only Prudent's classes; `zen.v1` resolves from the
  `zen-proto` jar already on the classpath. Nothing is generated twice.
- **Dart — broken.** `--dart_out` emitted `import '../../zen/v1/common.pb.dart'`, a **relative**
  path resolving to a file that does not exist in Prudent's tree. `protoc_plugin` has no
  package-mapping option, so the only way to satisfy it is to generate the framework's messages
  into Prudent's tree — producing a **second `ZenError` type** beside the one
  `package:zen_transport` exports. Two Dart classes from one message are not assignable, so the
  transport's decoded error and the app's would be different types that look identical. That is
  worse than the missing file, because it compiles.

**Recorded as a jZen-side finding, not worked around** (it extends the plan's §3.7 finding 1). The
fix belongs in jZen: either its published Dart package maps generated imports to `package:` URIs,
or the framework states that application protos must not import `zen.v1`. Nothing is blocked here,
because Prudent's contract needs no import.

### The generate/verify loop is Prudent's own

jZen's contract tasks are hardcoded to its own tree — `generate:proto:dart` writes into
`client/zen_transport/lib/src/generated` and `sync:verify` globs `proto/zen/v1` — so
`Taskfile.app.yml` does not carry them and Prudent cannot include them. `Taskfile.yml` gains
`generate:proto:{java,dart}`, `generate:l10n`, `sync:contracts` and `sync:verify` of its own.

Two properties of that loop are load-bearing and easy to lose:

- **No task a gate composes is fingerprinted with `sources:`/`generates:`.** A skipped regeneration
  leaves a clean working tree, `sync:verify` then finds nothing dirty, and the gate reports
  "Contracts in sync." **without having regenerated anything** — precisely the drift it exists to
  catch. Regeneration is cheap; a gate that passes vacuously is not.
- **`generate:proto:dart` fails, rather than skipping, on an empty contract directory.** jZen's
  equivalent prints "No .proto files yet, skipping" and exits 0, which was right for a framework
  shipping an empty `proto/` skeleton. For Prudent an empty contract directory is a broken
  checkout.

**The OpenAPI half arrives in Phase 2, and its absence now is sequencing rather than an omission.**
`openapi.json` is emitted by SmallRye from annotated resources, and Prudent has none yet — a
`generate:api` task today would package a backend with no routes, write a document describing
nothing, and report success.

### Consequence

- `task sync:contracts` reports "Contracts in sync." and "Generated localizations correctly
  untracked." The localization half is a **guard before the fact**: there are no ARB files until
  Phase 3, and the assertion that none of their output is ever tracked has to be in place before
  the first one lands, not after.
- `task zen:test:client` is green: 14 tests in `client/test/contract/wire_round_trip_test.dart`,
  the repository's first. Every domain message round-trips through **both** `ZenTransportFormat`
  modes over the real `ZenProtoCodec` — the two are different code paths (binary uses generated
  descriptors, canonical proto3 JSON resolves accessors reflectively), and jZen's own history
  records a revision that served Protobuf perfectly and 500'd on every JSON response. The suite
  also asserts the two modes agree with **each other**, that money is exact where `0.1 + 0.2 != 0.3`
  is not, and that an amount beyond a double's exact integer range survives.
- **The gate was demonstrated failing**, not merely asserted — and the demonstration corrected the
  mental model, which is the reason for running it. `sync:contracts` **regenerates first and then
  diffs against `HEAD`**, so an uncommitted hand-edit to a `.pb.dart` does **not** fail the gate:
  regeneration overwrites the edit before the diff runs, and the tree comes back clean. That is the
  gate doing its job rather than a hole in it, but "the gate catches hand-editing" is only true at
  the point the edit would enter the repository. The two failures that do fire were both run and
  then reverted: a `.proto` changed without its output regenerated (fails naming all three files),
  and a hand-edited `.pb.dart` that reached a **commit** (fails naming that file). The distinction
  is written into `Taskfile.yml`'s `sync:verify` summary, where someone debugging a passing gate
  will look.
- `client/pubspec.yaml` gains `protobuf`, `fixnum` and a `path:` dependency on `zen_transport`. The
  transport is present for one reason — the round-trip suite has to exercise the real codec rather
  than a local reimplementation of it. `ZenClient` itself arrives in Phase 3.
- **Phase 2 inherits these as constraints**, not as suggestions: entities store `BIGINT` +
  `CHAR(3)` and a `DATE`; `PUT` handlers replace rather than merge; the server mints ids, resolves
  ownership from the JWT `sub` and never accepts a `user_id`; it validates `icon_key` against a
  known set, rejects `ACCOUNT_TYPE_UNSPECIFIED`, rejects an `account_id` that is not the caller's,
  and copies the account's currency onto every record rather than accepting one; and
  `sync:contracts` grows its OpenAPI half with the first resource.

---

## ADR-007 — The Dart codegen workaround is deleted the day jZen ships the fix

**Date:** 2026-08-16. **Status:** accepted. **Refines:** ADR-006's "The generate/verify loop is
Prudent's own", on the Dart half only.

### Context

ADR-006 recorded two findings that came out of building the contract, and both were reported
upstream as [jZenDev/jZen#54](https://github.com/jZenDev/jZen/issues/54):

1. `protoc-gen-dart` writes imports as **filesystem-relative paths** and has no equivalent of Go's
   `M` mapping, so an application proto importing `zen/v1/common.proto` generated an import
   resolving to nothing inside the application's package — and the obvious repair, regenerating
   `zen.v1` into the application's tree, is worse and silently so, because the copy is a
   **different Dart type** and the framework's own API stops type-checking against it.
2. jZen's contract loop was hardcoded to its own tree, so an application could not include it, and
   its `generate:proto:dart` *skipped* with exit 0 on an empty proto directory.

Prudent's answer at the time was a hand-rolled `generate:proto:dart` in its own `Taskfile.yml`.
That was correct **as a consequence of the gap**, never as a design: jZen consumes the same
`Taskfile.app.yml` for its own reference application, which is what makes an included task shared
code rather than a lookalike that drifts.

jZen fixed both in [PR #55](https://github.com/jZenDev/jZen/pull/55), merged to its `main`.

### Decision

**Prudent deletes its copy and delegates.** `generate:proto:dart` now has one command,
`task: zen:generate:proto:dart`, and `PROTO_DART_OUT: client/lib/src/generated` is declared on the
include. The task name is kept because `generate:proto` composes it and the docs say it; the body
is gone.

The framework's version does what Prudent's could not: it passes protoc **both** contract roots
with `-I` but only the application's protos as **arguments**, so `zen/v1` is resolved for typing
and never emitted; it rewrites the dangling relative imports into
`package:zen_transport/generated/zen/v1/…`, which resolves because jZen moved those messages
outside `lib/src` for exactly this purpose; and it **refuses** if a `zen/v1` file lands in the
application's tree — the duplicate-type rule enforced rather than documented.

**Deleting rather than keeping both is the decision.** A task that exists in two files is drift
waiting to happen: the copy keeps working, so nothing forces the two to stay equal, and the day
they differ the difference is invisible until it produces a wrong artifact.

**What does NOT change:** the tracking rule. The Dart output stays committed and the Java DTOs stay
untracked, for the toolchain-boundary reason in ADR-006. That is Prudent's decision about its own
repository, and consuming a framework task does not hand it over — `PROTO_DART_OUT` points inside
`lib/src/` rather than at the framework's public `lib/generated` default for the matching reason:
jZen's messages are public because other packages import them by URI, and nothing outside Prudent's
client package imports Prudent's.

### What this changes about ADR-006's measurement

ADR-006 recorded, correctly at the time, that a cross-repository proto import **cannot** work on
the Dart side. **It can now.** The capability was verified here rather than taken on trust: a
throwaway proto importing `zen/v1/common.proto` produced one import re-pointed at
`package:zen_transport/generated/zen/v1/common.pb.dart`, emitted no `zen/v1` into `client/`, and
analyzed clean. The probe was deleted.

**Prudent's contract still imports nothing from `zen.v1`, and that is now a choice rather than a
constraint.** `ZenError` is an error *body* returned in place of a response, and `PageRequest`'s
fields are query parameters on a `GET`; neither belongs inside a Prudent message. Nothing in the
contract changes as a result of this ADR — which is the point worth recording, because a capability
arriving is not a reason to use it.

### Consequence

- `task sync:contracts` and `task zen:test:client` are green against jZen `b2de16b`, and the
  regenerated messages are **byte-identical** to what ADR-006 committed — the delegation changed
  the mechanism and not the artifact, which is the only evidence that the swap was faithful.
- **`task zen:info` is now load-bearing rather than advisory.** Prudent consumes jZen by path, so
  "which fix am I on" has no version to name — only a commit. This ADR is the first time a jZen
  revision is a prerequisite for Prudent's build behaving as documented, and `zen:info` is the only
  thing that reports it.
- The rest of the loop is still Prudent's own: the server build, the local stack, the deploy and
  every gate remain `zen_demo`-shaped upstream. Each is a separate migration to consume when jZen
  makes it app-agnostic, on this same pattern — report, wait, delete the local copy, prove it green.
- `docs/jzen/README.md` carries the findings table, with state (reported / fixed and consumed), so
  a later session does not re-report a fixed finding or re-fork a consumed one.

---

## ADR-008 — An account holds several currencies at once

**Date:** 2026-08-16. **Status:** accepted. **Supersedes:** ADR-006's currency decision.

### Context

ADR-006 gave each account exactly one currency: `Account.balance_minor` + `Account.currency`, with
a record **inheriting** its account's currency and no way to say otherwise. Multi-currency was
possible only by holding several accounts, one per currency.

That is not the product. A multi-currency account is one account holding balances in several
currencies — the shape a real bank or fintech account has, and the shape a traveller with one card
actually has. Discovered before Phase 2 built entities against the single-currency shape, which is
the last moment it is cheap.

### Decision

**`Account` carries a list of balances, one per currency it holds.**

```proto
message CurrencyBalance {
  string currency = 1;      // ISO-4217
  int64  amount_minor = 2;
}
```

- `Account.balances` (field 10) replaces `balance_minor` (4) and `currency` (5). The same swap
  happens on `CreateAccountRequest` (balances at 9, retiring 3 and 4) and `UpdateAccountRequest`
  (balances at 8, retiring 3).
- **The retired numbers are `reserved`, not recycled**, in every one of the three messages. Nothing
  has ever served this contract — no deployed server, no persisted row, no shipped client — so
  recycling them would have been free. It was rejected anyway: `reserved` is what makes the
  retirement visible in the file, and the discipline is worth more than two field numbers.
- **The currency set is declared, not inferred.** `balances` is never empty, holds at most one
  entry per currency, and the server rejects both violations. Declaring the set is what lets the
  server reject a record in a currency the account does not hold, rather than silently opening a
  new balance because someone mistyped a code.
- **A repeated message, not `map<string, int64>`.** A map's ordering is undefined and its proto3
  JSON form differs more sharply between the two transport modes; and a balance is likely to grow
  fields — an as-of date, a hidden flag — that a bare `int64` has nowhere to put.
- **Two refusals `UpdateAccountRequest` cannot express**, both server-side: a currency with records
  cannot be dropped (it would orphan money that left an account no longer admitting it exists), and
  a currency code is never edited in place (there is no rename; dropping PLN and adding EUR is two
  operations, and the first rule catches the case where it would have reinterpreted 100 PLN as 100
  EUR). **Adding** a currency is always allowed — that is how an account becomes multi-currency
  after the fact.

**`Record.currency` becomes client-supplied and required.** Field 4 keeps its number and type; only
its meaning changes, so the wire shape is untouched. `CreateRecordRequest` and
`UpdateRecordRequest` gain `currency` at field 6.

### What this costs, stated rather than glossed

ADR-006 made a record's currency **impossible to contradict** — not by a validation rule but by
there being no field in which to say it. That was the stronger design and it is now gone: with
several currencies in an account there is nothing to inherit, and only the record knows which
balance it moved.

What replaces it is a **refusal**: the server rejects a currency the owning account does not hold.
That is a weaker guarantee — an enforced rule rather than an unsayable state — and it is the price
of the feature. It is named here, and in `records.proto` beside the field, so Phase 2 implements it
as a rule it knows it owns rather than discovering the gap.

**Still no FX**, unchanged from ADR-006 and the plan's §5.2. The balances are independent; nothing
converts between them; a total is per-currency, and summing across currencies is refused rather
than done at a rate nobody chose. Multi-currency accounts make this *more* load-bearing, not less:
one account can now show two numbers that must never be added.

### Consequence

- `task sync:contracts` green; `task zen:test:client` green at **20 tests**, up from 14. The new
  ones assert what the reshape introduced: three currencies in one account round-trip in order (a
  repeated field is a list, and the client renders the order the server sent); a **zero-amount**
  pocket survives, since `amount_minor = 0` is the proto3 default and absent from both encodings,
  so the entry rides on its currency alone; an **empty** balance list decodes as empty rather than
  looking like a decode failure; two equal amounts in different currencies stay separate and are
  never summed; and `CreateRecordRequest` names a currency while still having no `id` field to set.
- **Phase 2 inherits two new rules**: reject an account with no balances, with a duplicate
  currency, or dropping a currency that has records; and reject a record whose currency the owning
  account does not hold — validated together with `account_id`, because moving a record between
  accounts and changing its currency are one operation.
- **Phase 3 inherits an open UI question this ADR deliberately does not answer**: which currency a
  record form pre-selects. `is_default` marks a default *account*, and there is no
  `primary_currency` on `Account` — adding one is a field number and an ADR when the screen that
  needs it exists, not a guess made now.
- The Postgres shape changes with it: a `prudent_account_balance` table keyed by
  (account, currency), rather than `BIGINT` + `CHAR(3)` columns on the account row.

---

## ADR-009 — A main currency that labels, and never converts

**Date:** 2026-08-16. **Status:** accepted. **Extends:** ADR-008.

### Context

With an account holding several currencies (ADR-008), the overview shows more than one number, and
the obvious next question is whether Prudent shows a single total balance in one currency.

That question hides two different features wearing one name:

- a **label** — which currency a record form pre-selects, which per-currency total is shown first,
  what an empty state names. No arithmetic.
- a **conversion target** — one total across PLN, EUR and USD. This is **FX**, and it needs a rate
  source, a base currency, and a rate **date** stored on every record, because a 2024 purchase
  converted at today's rate is a wrong number that looks right. Under the one-server rule the rate
  provider is reached through Prudent's own server, never from a client.

### Decision

**The label. `Settings.main_currency`, ISO-4217, and it is never used to convert or to sum.**

A new `proto/prudent/v1/settings.proto` carries it, because Prudent's contract had nowhere to put a
per-user preference — it was records, accounts and categories only.

- **A singleton, not a collection.** One `Settings` per user, so there is no id, no create, no
  delete and no list message: `GET /api/v1/settings`, `PUT /api/v1/settings`. The row is created on
  first login, not by the client. **No `user_id` field** — on a singleton the token is the entire
  addressing scheme, which is why the URL carries no id either.
- **`PUT` responds with the resulting `Settings`**, not an empty body: the server may have
  substituted a default, and a client that must re-read to learn what it just wrote is a round trip
  the response could have saved.
- **`main_currency` is not required to be a currency any of the user's accounts holds.** It is a
  display preference; a user who picks PLN before opening their first account is a normal state,
  not an inconsistency to reject.
- **The empty string is given a meaning on each side rather than left ambiguous.** proto3 has no
  presence for a string, so `""` and unset are the same bytes. On a **response** it never appears —
  the server resolves the default before answering, so a `GET` always names a real currency. On a
  **request** it means *reset to the default*, which is the full-replacement rule applied to a
  one-field message.

**Deriving it instead — "the default account's first balance" — was rejected.** It needs no new
surface and no new field, and it breaks the moment a user reorders their balances or has no
accounts yet. A preference that silently changes because a list was reordered is worse than a
field.

### Why not the conversion target

FX is a product feature with a third-party dependency, and it was deferred rather than declined —
the plan's §5.2 assumed no FX and ADR-006 and ADR-008 both hold to it. A single total computed at
an unstated rate on an unstated date is precisely the class of plausible-wrong-number the int64
minor-units type exists to prevent, and a budget app is the worst place to show one.

**Nothing here forecloses it.** Records already carry a currency and a date, so if FX is added it
arrives as its own ADR with its own fields — a rate and a rate date — rather than as a
reinterpretation of `main_currency`. This entry is what makes that a deliberate later step instead
of a meaning quietly attached to an existing field.

### Consequence

- `task sync:contracts` green; `task zen:test:client` green at **24 tests**, up from 20. The new
  ones assert `Settings` round-trips in both formats and names an owner nowhere, and that an empty
  `main_currency` survives the wire — without which neither side of the empty-string rule above
  could be implemented.
- **Phase 2 inherits** a fourth resource (`SettingsResource`, `@Authenticated`, `GET` + `PUT`), a
  one-row-per-user table created on first login beside the seeded default categories, ISO-4217
  validation, and the default-resolution rule so a `GET` never answers with an empty currency.
- **Phase 3 inherits** the pre-selection question ADR-008 left open, now with an answer: a record
  form defaults to `main_currency` when the chosen account holds it, and otherwise to that
  account's first balance. `Account` still has no `primary_currency`, and does not need one.
- **Phase 4's overview** shows per-currency totals with `main_currency` first. It does not show a
  combined total, and the round-trip suite's "balances in different currencies stay separate, and
  are never summed" is the test that fails if someone later adds one.

---

## ADR-010 — The backend's shape: policies in a repeatable, port 8085, and the four rules the resources own

**Date:** 2026-08-17. **Status:** accepted. **Refines:** ADR-002's "same migration" instruction, on
mechanism only.

### Context

Phase 2 built Prudent's server: Panache entities, one Flyway migration and its row-level security,
MapStruct mappers, four REST resources, the static OpenAPI document and the suites that prove them.
Most of it follows rules already recorded. Five things it settled are not, and this entry is those.

### The policies live in a repeatable, and the reason is ordering rather than taste

**ADR-002 says every new table ships RLS *and* a `zen_runtime` policy in the same migration. The
policies are in `R__prudent_row_level_security.sql` instead, and they had to be.**

`zen_runtime` is created by `zen-identity`'s **repeatable** `R__identity_application_role.sql`, and
Flyway runs every repeatable **after** every versioned migration. A `CREATE POLICY … TO zen_runtime`
inside `V20260817090000__prudent_init.sql` would therefore reference a role that does not exist yet
on a fresh database — which is every `@QuarkusTest` run, since Dev Services provisions one per run.
The migration would not degrade; it would fail outright.

**ADR-002's intent is honoured and its mechanism is not.** What that entry is actually protecting
against is a *release* that enables RLS and leaves the policy for later, opening a window where the
application silently reads nothing. Both files land together in one change, so no such window
exists. The versioned migration enables RLS on all five tables; the repeatable creates the five
policies, guarded on the role existing.

The boot log confirms the order rather than asserting it:

```
Migrating schema "public" to version "20260817090000 - prudent init"
Migrating schema "public" with repeatable migration "identity application role"
Migrating schema "public" with repeatable migration "prudent row level security"
```

### The port is 8085, and it is a collision avoided

`quarkus.http.port=8085`. jZen's local stack holds 8080, and `Taskfile.app.yml` already defaults an
application's API to 8085 — so this is the value the shared orchestration already expects.

**Prudent runs its own local Supabase project on shifted ports, 54331 (API) and 54332 (db)**, rather
than sharing jZen's 54321/54322. This closes plan §5.4. The alternative — only one product running
at a time — is not a decision anyone holds; it is a state discovered when `supabase start` fails to
bind, mid-task, on whichever product was started second. And the ports are the smaller half: one
shared project would put jZen's demo users and Prudent's in a single `auth.users`, which is a data
problem wearing a port problem's clothes. Nothing in Phase 2 depends on it — Dev Services gives the
suite a plain Postgres with no `auth` schema — so it is decided here and wired in Phase 3.

### Validation, and the two places a refusal replaced a guess

- **`currency` is validated against the JDK's ISO-4217 table**, not a list in this repository. A
  hand-maintained set is a second copy of a standard that changes without asking, and its failure
  mode is rejecting a currency that legitimately exists. This is a second reason `quarkus.locales`
  matters: a native image bakes that table at build time.
- **`icon_key` is validated against a set of five**, duplicated on the client and named as a cost in
  `IconKeys`. Generating both from one source means moving the keys into the `.proto` as an enum,
  which forecloses a user-supplied icon set — a product question nobody has asked. Until it is
  asked, the duplication is documented rather than designed away.
- **`ACCOUNT_TYPE_UNSPECIFIED` is refused**, never defaulted. It is what proto3 decodes an omitted
  field to, and cash is a valid answer, so a default would make "the client forgot" and "the client
  meant cash" the same row.
- **A malformed date is refused**, never rolled. `LocalDate.parse` rejects `2026-02-30` rather than
  moving it to March; a rolled date files a record in a month the user did not choose, which is a
  wrong total in two months at once.

### Deletes are hard, and a delete that would orphan data is refused

**Hard deletes everywhere**, closing the plan's open question. A soft delete's stated appeal is that
Phase 4's analytics could still read the rows, and that is the problem rather than the feature: a
user who deletes a mistyped 5,000 PLN entry and still sees it in a total is looking at a wrong
number that looks right — the class of defect the integer money type exists to prevent. A soft
delete the product gives no way to undo is a table that grows.

**Deleting an account or category that still has records is refused at 409**, not cascaded. This is
ADR-008's rule about dropping a currency with records, applied to the case it obviously generalises
to, rather than a second philosophy. The migration carries no `ON DELETE CASCADE` on either
reference, so the database enforces it as a last resort and the resource refuses first with a
message a user can act on.

### Listing is unpaginated, and that was already decided

`records.proto` settles it: **unpaginated in v1**. This entry records only that Phase 2 implemented
what the contract said rather than reopening it — a `PageRequest` on records was proposed during
planning and withdrawn on reading the contract, because page parameters are query parameters on the
`GET` and response page metadata is a backward-compatible proto3 addition. The retrofit is cheap,
so pre-empting it buys nothing.

### Default categories arrive on first login, through the framework's event

Five starter categories — Food, Restaurant, Leisure, Health, Work — and the `Settings` row are
created by `NewUserSetup`, an `@ObservesAsync` observer of `zen-identity`'s `UserRegistered`. This
is jZen ADR-007's split used as intended: the framework knows *that* a user registered, the
application supplies what happens next. Flyway cannot do this — it is per-user data, not schema.

They are **ordinary deletable rows**, because a default a user cannot clear is clutter; their icon
keys are the five the client ships, because seeding a key the client cannot render would show the
fallback icon on day one. **Their titles are English, and that is a named gap**: the event carries
the registering user's language, and localising them needs a server-side message bundle that has no
other caller yet.

### Consequence

- `task test:server` green at **55 tests**; `(cd server && ./mvnw -B package)` green with the
  `openapi` profile active by default.
- **`zen-identity` and `zen-ratelimit` are assembled; `zen-email` and `zen-jobs` are not.**
  `zen-email` is genuinely unnecessary — `UserRegistered`'s own contract states that firing an event
  is what keeps `zen-identity` free of any dependency on it. **`zen-jobs` is an obligation deferred,
  not a need declined:** `zen-identity` ships `UserRetentionJob` and `zen-jobs` is what triggers it,
  so Prudent's GDPR retention cycle is currently **unrun**. It is assembled in the deploy phase,
  where there is an external trigger to fire it.
- **Phase 3 inherits** entities named with an `Entity` suffix (the proto types own `Account`,
  `Record`, `Category`, `Settings`, and `Record` would additionally shadow `java.lang.Record`); a
  404 rather than a 403 for another user's row, so an id cannot be used as an existence oracle; and
  a `PUT` that replaces rather than merges on every resource.

---

## ADR-011 — The OpenAPI half of the contract gate needs a tracked artifact, and framework schemas are the application's to declare

**Date:** 2026-08-17. **Status:** accepted. **Extends:** ADR-006's "the generate/verify loop is
Prudent's own".

### Context

ADR-006 deferred the OpenAPI half of `sync:contracts` to Phase 2, correctly: `openapi.json` is
emitted by SmallRye from annotated resources, and there were none. Phase 2 added four resources and
with them the task. Two things about wiring it up were not obvious and cost real time.

### `openapi.json` is tracked, because otherwise the gate checks nothing

SmallRye writes `target/openapi/openapi.json`, and `target/` is gitignored. A gate that regenerated
the document there and then diffed the working tree would find nothing dirty **always**, and report
the contracts in sync having verified nothing about the REST surface.

That is exactly the vacuous-gate failure ADR-006's no-fingerprinting rule exists to prevent, wearing
a different disguise — and it is more dangerous than the fingerprinting one, because there is no
`sources:` line to notice.

**So `generate:api:schema` copies the document to `server/openapi.json`, which is tracked**,
`linguist-generated`, and watched by `sync:verify`. REST-surface drift now shows up in a diff the
way a `.proto` change does.

In jZen the tracked downstream artifact is the admin panel's `schema.generated.ts` and
`openapi.json` stays in `target/`. Prudent has no admin panel until Phase 5, so until then the
document itself is the artifact worth tracking. `generate:api:ts` joins the task then; its absence
now is sequencing.

### An application declares component schemas for framework messages, and there are more than expected

`zen-identity`'s `AuthResource` and `AdminUserResource` and `zen-jobs`' `JobTriggerResource` ship
their **paths** inside the framework jars, and SmallRye scans them into Prudent's document
automatically. Their **schemas** are not carried by the merge. Paths come from the annotations;
schemas come from the application — including for messages the application did not write.

**Ten components in Prudent's `openapi.yaml` describe framework messages**: `Identity`, `ZenError`,
the five auth request bodies, `AdminUser`/`AdminUserList`, and `JobTickResult`/`JobRun`. The last
pair is declared even though Prudent does not assemble `zen-jobs`: the path is scanned in from a
transitive dependency regardless of whether anything serves it.

**Eight of the ten were missing on the first pass, and nothing said so.** A `$ref` with no component
behind it is a dangling reference: the document generates, the build succeeds, and the failure
surfaces later in whatever consumes it — for Prudent, Phase 5's `openapi-typescript`. It was found
by checking the generated document for unresolved references, not by reading it, and that check is
worth keeping as the document grows.

**jZen's own document does not declare `ZenError` at all**, because its resources never `$ref` it —
they describe error responses with a description and no schema. Prudent's do reference it, so
Prudent declares it. This extends the plan's §3.7 finding 5: the static document being hand-authored
means every application re-declares schemas for framework messages, and there is nothing to keep the
copies honest with the framework or with each other.

### Consequence

- `sync:contracts` now runs `generate:proto`, `generate:api`, `generate:l10n`, `sync:verify`. The
  document holds **27 component schemas and 21 paths, with zero dangling and zero unreferenced
  references**.
- The transport seam is visible in the document: every response and request body is declared for
  both `application/json` and `application/x-protobuf`.
- **`server/openapi.json` must be committed for the gate to pass.** It diffs against `HEAD`, so a
  newly tracked generated file reads as drift until it lands — correct behaviour, and worth knowing
  before someone debugs it.

---

## ADR-012 — The no-Jackson rule stands, but its documented failure mode does not reproduce

**Date:** 2026-08-17. **Status:** accepted. **Records a measurement that contradicts a rule this
repository asserts.**

### Context

Both `server/pom.xml` and CLAUDE.md state the rule absolutely: **no `quarkus-rest-jackson`, not at
any priority, not later** — because it registers itself for `application/json` through a build-time
path that ignores writer priority, wins over `zen-transport`'s writer, tries to reflect over a
protobuf-generated class, and **returns 500 on every proto response body**.

A rule whose violation is invisible deserves a demonstration, so Phase 2 ran one: add the
dependency, confirm a proto response 500s, remove it. **It did not 500.**

### What was measured

With `quarkus-rest-jackson` added and confirmed active — `rest-jackson` present in Quarkus's
`Installed features` line, `quarkus-rest-jackson:jar:3.38.0` in the dependency tree — the full
`CategoryResourceTest` suite passed unchanged, in both transport modes.

Suspecting the trigger was the *bare proto return type* the rule's own wording names (every Prudent
resource returns `jakarta.ws.rs.core.Response`), a throwaway probe resource returning a bare
`Category` was added and hit in JSON mode. With Jackson installed:

```
status=200  content-type=application/json;charset=UTF-8
body={"id":"1111…","title":"Probe","iconKey":"food","colorArgb":4283215696}
```

That is correct canonical proto3 JSON — `colorArgb` carries the unsigned value, and there is none of
the builder-internal output Jackson produces on a protobuf class. The negative control, the same
probe with Jackson removed, returned a **byte-identical** body. `zen-transport`'s writer served both.
The probe was deleted.

### Decision

**The rule stands and the dependency stays absent.** Nothing here is an argument for adding an
extension this server has no use for: it would still bake a scanner and its dependencies into every
image for a capability nothing wants, and the reasoning that keeps `quarkus-smallrye-openapi` in a
profile applies to it with more force.

**What changes is the justification's status.** On Quarkus 3.38.0 with this `zen-transport`, the
stated mechanism — Jackson hijacking `application/json` and 500ing on proto — is **not
reproducible**, including through the bare-return-type shape the rule names as its trigger. The rule
is now held by "do not ship what you do not need", which is sound, rather than by a failure anyone
can currently demonstrate.

### Why record a negative result at all

Because the alternative is worse in a specific way. A rule justified by a dramatic failure that
nobody can reproduce is a rule the next person tests, finds harmless, and drops — and if the
mechanism is real on some other Quarkus version, configuration or resource shape, they will have
removed a guard for a good reason and been wrong. Writing down that the demonstration was attempted
and did not fire is what stops the rule from being either blindly trusted or casually deleted.

**Reported as a jZen-side finding**, since the rule is the framework's and the claim appears in its
STANDARDS: either the mechanism was fixed by a Quarkus upgrade or by `zen-transport` gaining writer
precedence, in which case the wording should say so, or it survives under conditions not identified
here, in which case those conditions are what the rule should name. Prudent is not changed either
way.

### Consequence

- The pairing gate **was** demonstrated for the other silent failure: dropping the `zen_runtime`
  policies from the repeatable made `PrudentRowLevelSecurityTest` fail with
  `zen_runtime read 0 rows from prudent_account but the table holds 1` — zero rows, no error,
  exactly the shape the policy exists to prevent. Restored and re-verified green.
- One of this phase's two named silent failures therefore has a working demonstration and the other
  has a recorded non-reproduction. That asymmetry is the honest state and is not resolved by
  asserting the second.

---

## ADR-013 — The client becomes a jZen application: repository, auth, shell, and what Phase 3 settled

**Date:** 2026-08-18. **Status:** accepted.

### Context

Phase 3 of `docs/prudent-migration-plan.md` rewires the client onto `ZenClient`, `zen_ui_identity`
and `zen_ui_navigation`, deletes the Firebase call, and writes the boundary gate that proves it
cannot return. Several things had to be decided rather than assumed, and two real defects surfaced
only by running the actual stack — neither is visible from `task test:server` alone.

### Decisions

- **The whole app sits behind login.** No signed-out screen exists besides the auth flow itself
  (`lib/src/app.dart`'s `_Root`): anonymous → `AuthFlow`, authenticated → `HomeShell`. There is no
  partial signed-out surface to keep consistent as the product grows.
- **Delete-with-undo fires the delete immediately; undo re-creates.** `records_screen.dart`'s
  `_removeRecord` calls `DELETE` right away and undo issues a fresh `POST`, which the server answers
  with a new id. No deferred-delete timer, no client-side pending-delete state to keep honest against
  a server that might already have acted.
- **The bundled font is the platform default, not a bundled asset.** `google_fonts` is deleted
  outright (`main.dart` no longer references `GoogleFonts.latoTextTheme`); `ThemeData` falls back to
  each platform's system font. Zero bundle cost, zero licence file to carry, and it is what
  `verify_boundaries.py` check D now asserts is absent.
- **Native auth redirects use the custom scheme only** — `prudent://auth-callback`, registered as
  the sole entry in `AUTH_REDIRECT_URIS` and mirrored in `supabase/config.toml`'s
  `additional_redirect_urls`. App Links (verified `https` universal links) are deferred: they need a
  real domain and a hosted verification file, which this phase has neither.
- **macOS session persistence is accepted as absent for this phase.** `SecureTokenStore` needs a
  Keychain entitlement Xcode will not sign without a certificate; none is available. Verified by
  launching the macOS build twice with the same result both times — this is a known jZen-side
  platform boundary, not a Prudent defect, and every suite passes identically either way.
- **An unknown `icon_key` renders `prudentUnknownCategoryIcon`** (`lib/category/category_icons.dart`)
  rather than throwing — a category created by a newer client must not break an older one
  (proto/prudent/v1/categories.proto §2.2). Covered by
  `test/category/category_icons_test.dart`.
- **Money never touches `double`, on either the parse or the format path.**
  `lib/src/money.dart`'s `parseMinorUnits`/`formatMinorUnits` work entirely in `Int64` and decimal
  string arithmetic, including for a value beyond a double's exact integer range
  (`test/src/money_test.dart`). Display therefore stays a plain `"<amount> <currency>"` string
  rather than routing through `NumberFormat.currency`, which would reintroduce a `double` conversion
  this phase specifically removes.
- **Prudent's own Polish chrome for `zen_ui_identity`/`zen_ui_navigation`** — `PlIdentityLocalizations`
  / `PlNavigationLocalizations` subclass the packages' exported `*LocalizationsEn`, wrapped in
  delegates (`PlIdentityDelegate`/`PlNavigationDelegate`) returning a `SynchronousFuture` and
  composed **before** `identityLocaleDelegate`/`navigationLocaleDelegate` in
  `lib/src/app.dart`. The ordering and the synchronous load are both pinned by
  `test/l10n/prudent_l10n_test.dart`, including a negative case (composed last) that must render in
  English to prove the test discriminates at all — the failure mode jZen ADR-044 found by testing
  rather than by reading.
- **Prudent's own `task verify:boundaries`** (`scripts/verify_boundaries.py`) — deliberately not
  jZen's `scripts/verify-boundaries.py`, whose scan scopes are module-level constants with no
  override and therefore cannot be pointed at a second repository
  (`docs/prudent-migration-plan.md` §3.7, finding 2). Four checks: (A) no provider SDK or
  `firebase_*` dependency, (B) no provider host or credential — including Prudent's own retired
  Firebase project (`firebaseio.com`, `prudent-60fcf`), (C) no absolute URL literal outside the one
  compile-time `zenApiUrl`, (D) Prudent's own additions — `package:http` stays in the composition
  root (`lib/main.dart`), `google_fonts` is gone entirely. Keeps jZen's `StaleScope` guard: a scan
  scope matching nothing is a failure, not a vacuous pass.
- **Prudent runs its own local Supabase project, ports shifted +10 from jZen's** (`supabase/config.toml`:
  54331 API / 54332 db / 54330 shadow / 54333 studio / 54334 SMTP / 54339 pooler / 54337 analytics /
  8093 edge-runtime inspector) — the answer to the open question in
  `docs/prudent-migration-plan.md` §5.4. A developer working on both products can now run both
  simultaneously; the smaller reason is the port shift itself, the larger one is that a shared
  project would put jZen's demo users and Prudent's users in one `auth.users`.

### What running the real stack found, that no test caught

Two genuine gaps in Phase 2's `application.properties`, invisible to `task test:server` because
`@QuarkusTest` calls the server directly — not a browser, and not through the real Supabase REST
client:

1. **No `quarkus.rest-client.supabase-auth.url` and no `mp.jwt.verify.*`/`mp.jwt.token.*`
   properties.** `SupabaseAuthClient` (`configKey = "supabase-auth"`) had no base URI to resolve,
   so the first real `POST /api/v1/auth/register` 500'd with
   `Unable to determine the proper baseUrl/baseUri`; once that was fixed, every cookie-authenticated
   request still 401'd because `mp.jwt.token.header=Cookie` / `mp.jwt.token.cookie=zen_access_token`
   were never set, so SmallRye JWT kept reading the (absent) `Authorization` header and every
   session-cookie request looked anonymous. Both fixed in `application.properties`, matching the
   wiring `../jZen/apps/zen_demo/zen_demo_server` already carries.
2. **No CORS configuration at all.** A browser client is cross-origin from this server in local dev
   (the Flutter web build serves its own port), and `@QuarkusTest` sends no preflight, so this
   passed every backend suite and then failed the first real browser request with an opaque
   `ClientException: Failed to fetch`. Added `quarkus.http.cors.*`, including
   `access-control-allow-credentials=true` — required because the session lives in a cookie, and a
   cross-origin cookie is dropped without it.

Both were found by actually registering a user, signing in through the real `LoginScreen`, and
reading records back through the real UI — not by reading the properties file. A third thing was
found and **not** fixed: Hibernate's dev-mode post-boot schema validation reports a type mismatch
between the `CHAR(3)` currency columns the migration creates and the `VARCHAR`-mapped
`@Column(length = 3)` Hibernate expects. An attempted fix (`columnDefinition = "char(3)"`) changed
the DDL Hibernate would generate but not the JDBC type code it validates against, so the warning
persisted; reverted rather than chased further, because `CHAR` and `VARCHAR` bind and read
identically through `setString`/`getString` and the warning is dev-mode-only (`%test` uses
`schema-management.strategy=none` against a fresh throwaway database and never sees it; `%prod`
validates at deploy, not at request time). **Left as a known, non-blocking cosmetic finding.**

### Consequence

- `task verify:boundaries`, `task sync:contracts`, `task zen:test:client` (47 tests, including the
  three repository/money/icon suites and the four l10n suites added this phase), and
  `flutter build web --wasm` are all green.
- Verified against the **real** local stack, not just compiled: registered a user through
  `POST /api/v1/auth/register` with `Accept-Language: pl`, confirmed `users.language = 'pl'`,
  created an account and a record through the authenticated REST surface, then ran the actual
  Flutter app — one native target (macOS) and one web target (Chrome, via `flutter run -d
  web-server`) — signed in through the real `LoginScreen`, saw the record created via the API render
  in the real `RecordsScreen`, and switched the running app to Polish live, including the framework
  login screen's chrome.
- Icon tree-shaking survived the `icon_key` → `const Map<String, IconData>` design:
  `flutter build web --wasm` reduced `MaterialIcons-Regular.otf` by 99.4%.
- What Phase 4 inherits: full ARB coverage for Prudent's own strings landed in this phase (not
  deferred), so Phase 4's new screens (Overview, Analytics, Chart) start from zero hardcoded
  strings rather than retrofitting them later.

---

## ADR-014 — Analytics is server-side arithmetic over a signed ledger; balance is derived, not stored

**Date:** 2026-08-18. **Status:** accepted.

### Context

Phase 4 built the parts of Prudent that never worked: `analytics.proto` and its two endpoints,
the real Overview, the chart, `CategoryRecords`, account edit and delete, and the Settings items
that were inert labels. Several of the plan's open questions (§"Ask me before assuming") had to be
settled before any of that arithmetic could be written, and this entry is where they were settled.

### Decision

- **`Record.amount_minor` is signed.** Negative is an expense (money leaving the account),
  positive is income (money entering it), and zero is refused server-side — a record that moves
  nothing is not a transaction. This reopens `docs/prudent-migration-plan.md`'s §"Do records have
  a sign" question: Phase 1's `int64` always permitted a negative value; the product now uses it.
- **An account's balance is DERIVED, not stored.** `Account.balances` (accounts.proto) carries the
  OPENING amount set at create/update time; the CURRENT balance a `GET`/`POST`/`PUT` response
  reports is that opening amount plus the sum of the account's `Record.amount_minor` in that
  currency — computed on every read (`RecordEntity.netByAccount`/`netByAccountForUser`,
  `AccountMapper.toProto`), never written back to a column. Because the amount is already signed,
  the formula is a plain sum with no separate sign flip. This answers §"Is Account.balance stored
  or derived" and is the change accounts.proto's own comments already pointed at
  ("every later change to an amount is an act of the records, not of this field") without this ADR
  having existed yet to say so plainly.
- **The period anchor is UTC, and it barely matters.** ADR-006 already made `Record.date` a civil
  date with no time-of-day or zone — so a record's own bucket never depends on the answer. UTC is
  used only to resolve "today" for `spend-by-period`'s trailing window
  (`LocalDate.now(ZoneOffset.UTC)` in `AnalyticsResource`), which decides how many months back the
  window reaches, not which bucket any individual record lands in.
- **Granularity is month and year, both, on one endpoint.** `Granularity.GRANULARITY_MONTH` /
  `GRANULARITY_YEAR` on `spend-by-period`, `year` + optional `month` on `spend-by-category`. No
  week and no custom range in this phase.
- **Currency is a required query parameter on both analytics endpoints, never inferred.** This is
  the same refusal-by-construction ADR-008/009 already use: there is no field two currencies could
  be summed into, because the caller names exactly one. `spend-by-category` and `spend-by-period`
  both sum only the negative (expense) side of the ledger and report it as a POSITIVE magnitude —
  "spend" excludes income by definition, named in `analytics.proto` rather than left to be
  discovered from the arithmetic.
- **The empty case is an empty list, never a zero-amount row.** Both response shapes
  (`SpendByCategoryResponse.items`, `SpendByPeriodResponse.periods`) omit a category or period with
  no expenses rather than reporting a `CategorySpend`/`PeriodSpend` of zero, so a caller can tell
  "no data" from "zero was spent" from the shape of the response alone.

### What the client does with it

- **A record form gains an Expense/Income toggle** (`new_record.dart`); the amount field is
  always a magnitude, and the toggle supplies the sign sent on the wire. Existing records render
  signed: red with no prefix for an expense, green with a `+` for income
  (`records_list/record_item.dart`).
- **Overview totals are per-currency, honouring three flags nothing could previously set:**
  `is_active` gates both the account list and the totals; `include_in_overview` controls the
  account list; `include_in_total` controls the totals. The two inclusion flags are independent —
  a savings account can be visible without counting toward spendable funds. Pulled out of the
  widget into `lib/src/overview_totals.dart` (`totalsByCurrency`, `accountsForOverview`)
  specifically so the flag combinations are unit-testable without pumping a screen.
- **The chart (spend by category, a donut) and Analytics (spend by month, a bar chart) are both
  `CustomPainter`s** (`lib/chart/donut_chart_painter.dart`, `lib/chart/bar_chart_painter.dart`),
  not a charting package — see ADR-015.
- **`CategoryRecords` is reachable**: tapping a category tile now opens it; editing moved to a
  small pencil `Popup` overlaid on the tile, since the tile's main gesture was the only way to
  reach the screen at all.
- **Account edit and delete are real.** Edit is `AccountEdit`, reachable by tapping an account row;
  it resends the account's existing `balances` unchanged on every save (a `PUT` is a full
  replacement, so silently dropping them would trigger ADR-008's currency-with-records refusal).
  Delete confirms, then surfaces the server's own message on a 409 — `ZenTransportError.message` is
  already the decoded `ZenError.message` regardless of which `ZenError` subclass jZen's own domain
  code might construct elsewhere, so the dialog reads it directly rather than special-casing a
  type that a REST response never actually produces client-side.

### Consequence

- `task test:server` green at **73 tests**, up from 55: `AnalyticsResourceTest` (14 tests — the
  empty case, income excluded from spend, month/year boundaries, single-currency and
  missing-currency refusal, user scoping) plus a derived-balance test on `AccountResourceTest` and
  a zero/negative-amount pair on `RecordResourceTest`.
- `task zen:test:client` green at **67 tests**, up from 47: `overview_totals_test.dart` (the flag
  combinations and the multi-currency presentation), `donut_chart_painter_test.dart` (zero, one and
  many slices), and three new cases in `prudent_repository_test.dart` for the analytics query
  strings and the empty-list decode.
- Verified against the real local stack, not just the suites: registered a user, created an
  account with a 100.00 PLN opening balance, posted a -50.00 PLN expense and a +200.00 PLN income,
  and confirmed `GET /api/v1/accounts` answered **250.00 PLN** (100 − 50 + 200) — the derived-balance
  formula, not asserted, computed. `spend-by-category` answered 50.00 PLN in Food (the income
  excluded); `spend-by-period` answered the same 50.00 PLN in the current month and nothing in the
  other eleven. Then ran the actual Flutter app against that server (Chrome, `flutter run -d
  chrome`): Overview showed the 250.00 PLN total, Records showed the expense in red and the income
  in green with a `+`, the donut chart showed one full green slice at 100%/50.00 PLN, the bar chart
  showed one bar in the current month among eleven empty ones, and the account edit/delete flow
  (including the 409 message) worked end to end.
- **Phase 5 inherits** nothing new here beyond what earlier phases already left it: the admin panel
  and `test:e2e` are unaffected by this phase's arithmetic, since they exercise the same REST
  surface.

---

## ADR-015 — Charts are `CustomPainter`, no dependency; Corespondents and Help are deleted, not built

**Date:** 2026-08-18. **Status:** accepted.

### Context

The plan's open questions asked which chart(s) ship, whether a charting dependency is worth its
cost against a `CustomPainter`, and the fate of two Settings labels (`Corespondents` [sic] and
`Help`) that rendered as inert `Text` widgets nothing could act on.

### Decision

- **Two charts ship: spend by category (a donut, on the Chart screen) and spend by month (a bar
  chart, on the Analytics screen).** Both consume the two `analytics.proto` endpoints this phase
  adds, so shipping only one would have left the other endpoint with no client at all.
- **Both are hand-rolled `CustomPainter`s, not a charting package.** A donut is arcs summing to one
  turn; a trailing-window bar chart is rectangles scaled to a maximum — neither shape earns a
  dependency, and Zen Architecture's "utilities over abstractions" principle names exactly this
  trade-off. The alternative cost was concrete, not hypothetical: ADR-024 (jZen) requires any
  Flutter dependency to be proven Wasm-clean via `flutter build web --wasm`, which is a real
  verification step a `CustomPainter` never has to pass because it adds nothing to the dependency
  graph a web build's generated plugin registrant would need to import.
- **`Corespondents` and `Help` are deleted, not built.** Neither is in this phase's deliverable
  list, and CLAUDE.md's own words are exact: "an inert label that survives this phase is a promise
  the app does not keep." `Corespondents` would have implied a payee/counterparty concept that
  exists nowhere in the domain model; building it now would be inventing a product decision nobody
  asked for, in the phase the migration prompt itself names as "the one most likely to grow into"
  new products. `Help` needs real content this phase has none of.
- **`Profile` is wired, not written** — `zen_ui_identity`'s `ProfileScreen`, reached from the same
  `TextButton` slot the label occupied. This is the case the plan's own wording anticipated
  ("Profile is `zen_ui_identity`'s ProfileScreen, so it is wired, not written") and settles nothing
  new; it is recorded here only so this ADR accounts for all four Settings items in one place.

### Consequence

- `flutter build web --wasm` is green with icon tree-shaking unaffected
  (`MaterialIcons-Regular.otf` still reduced 99.4%) — direct evidence the CustomPainter choice cost
  nothing on the one platform a dependency choice could have.
- `task zen:build:runners` is green on this host: iOS (simulator) and Android build; Linux and
  Windows are skipped audibly (Darwin host, per ADR-003).
- Settings now has exactly the items it can act on: Language, Profile (wired), Log Out. Two ARB
  keys per locale (`settingsCorrespondents`, `settingsHelp`) are removed along with the labels —
  deleting a hardcoded string is part of deleting the feature it labelled, not a separate cleanup.

---

## ADR-016 — The admin panel: only `users`, and the first admin exists by an operator's own hand

**Date:** 2026-08-18. **Status:** accepted.

### Context

Phase 5 built `admin/`, the last of the three client tiers CLAUDE.md's target structure names.
jZen ships the scaffold (`@jzen/admin-core`) as a data provider, an auth provider and a login page;
an application assembles it and registers its own resources.

### Decision

**`admin/` imports `@jzen/admin-core` from source**, via a TypeScript `paths` alias
(`admin/tsconfig.json`) plus a Vite `resolve.alias` (`admin/vite.config.ts`) into
`../jZen/admin/src` — not a pnpm dependency edge. This is the same mechanism as the Dart `path:`
deps into `client/` and the Java empty-`<relativePath/>` parent (ADR-001): the repository root
stays language-neutral, the app owns the single copy of React, and publishing later is a config
edit rather than a rewrite.

**Only the `users` resource is registered.** `zen-identity`'s `AdminUserResource` ships its path
inside the framework jar (scanned into `server/openapi.json` automatically, ADR-011), so
`admin/src/resources/User.tsx` is the whole of Prudent's own admin surface today. Accounts,
categories and records are **not** administered: every one of Prudent's own resources is
user-scoped by construction (`@Authenticated`, filtered on the JWT `sub`) with no cross-user
listing endpoint, so there is nothing for a `<Resource>` to point at without first building one —
and CLAUDE.md's own deliverable list does not ask for one. Adding cross-user visibility into a
personal-finance app's transaction history is a product decision with its own privacy weight, not
a byproduct of wiring a panel.

**Role model: the framework enforces it, Prudent bootstraps the first holder.**
`AdminUserResource` is `@RolesAllowed` on the `admin` role, resolved from the `users` table on
every request — never from the JWT, so a role change takes effect on the next request rather than
the next login. There is no self-serve admin signup: the first admin account is created by
registering through the ordinary flow like any other user, then an operator runs one `UPDATE
users SET role = 'admin' WHERE email = '<the operator's own address>'` against the deployed
database. That single manual step is the entire bootstrap — deliberately outside any code path, so
there is no admin-creation endpoint for the boundary or the auth gate to have to reason about.

### Two gates this phase extended, and one it added

- **`task verify:boundaries` gained TypeScript scopes** (`scripts/verify_boundaries.py`,
  `admin/src`, checks A–C — no provider SDK, no provider host/credential, no absolute URL outside
  the one compile-time base), with two exemptions: `admin/src/api/schema.generated.ts` (generated,
  describes the API rather than calling it) and `admin/src/config.ts` (the one file allowed to
  name the API base, mirroring the Dart side's `zen_identity_config.dart` exemption). **Demon­
  strated failing**: a fake `@supabase/supabase-js` line was added to `admin/package.json`, the
  gate caught it and named the exact line and file, and the line was reverted.
- **CORS gained the Vite dev origin** (`http://localhost:5173`) and **exposed
  `Content-Range`/`Accept-Ranges`** — `ra-data-simple-rest`'s pagination convention reads the
  total off `Content-Range`, and a cross-origin `fetch` cannot read a header the server has not
  explicitly exposed.
- **`task generate:api:ts`** (openapi-typescript over `server/openapi.json`) joined
  `generate:api`/`sync:contracts`. `admin/src/api/schema.generated.ts` is **tracked**,
  `linguist-generated` — the same toolchain-boundary reasoning ADR-006 gives for the Dart side,
  applied to the third language: a frontend developer must be able to compile the panel without a
  JDK.

### Consequence

- `pnpm exec tsc -b` and `pnpm build` are both clean; `task sync:contracts` regenerates
  `schema.generated.ts` deterministically from the current `openapi.json`.
- `task verify:boundaries` is green with all four checks passing, including the two new
  TypeScript ones, and was proven to fail on a real violation rather than only asserted to.
- What Prudent inherits going forward: the day a domain resource needs administering, it arrives
  with its own `@RolesAllowed(ADMIN)` listing endpoint on the server and its own `<Resource>` in
  `admin/src/App.tsx` — this entry is not a ceiling on the panel, only a record of where it starts.

---

## ADR-017 — `task test:e2e`: a pure-Dart VM release gate, and the race it caught on its first run

**Date:** 2026-08-18. **Status:** accepted.

### Context

Phase 5 built Prudent's end-to-end release gate: the real Supabase + Quarkus stack, no mocks,
proving register → create → read-back the way no `@QuarkusTest` or widget test can, because
neither drives the real cookie jar or the real HTTP boundary. `../jZen/apps/zen_demo`'s own
`test:e2e` suite is the pattern: a pure-Dart VM suite over `package:test` (not `flutter_test`), so
it runs headless under plain `dart test` and its import graph can never reach `dart:ui` — a
`flutter_test`-based suite would not even compile that way.

### Decision

**`client/integration_test/e2e_test.dart`**, six cases against the live stack: the session cookie
survives across requests after registration; an account is created with a 100.00 PLN opening
balance; a record is created against it and read back, with the account's *derived* balance
confirmed to have moved by the record's signed amount (ADR-014's formula, exercised against a real
server rather than only asserted in `AccountResourceTest`); the same records endpoint is read
through two independently-configured `ZenClient`s, one pinned to JSON and one to Protobuf, and
both must decode to the same set of ids; an anonymous request is refused; logout clears the
session.

**`prudent.server.HealthResource`** (`GET /api/v1/health`, `@PermitAll`, returns the framework's
`zen.proto.v1.HealthStatus`) is new — Prudent had no liveness endpoint before this phase, and
`task test:e2e` needs one to poll before it can safely drive the suite against a server that might
still be starting. Same shape as `zen_demo`'s own `HealthResource`; `HealthResourceTest` proves
both transport modes, matching every other resource's suite.

**`task test:e2e`** boots Prudent's own local Supabase project (ADR-010's `+10`-shifted ports),
builds and runs the packaged server on `:8085` under the `%dev` profile, polls `/api/v1/health`,
runs the suite, tears the server down by whatever is bound to the port, and propagates the suite's
exit code. **Linux-only**, per the migration plan: Supabase needs Linux containers a Windows
runner cannot practically host, so a Windows `test:e2e` would be a different, weaker test wearing
the same name.

### What the first run actually caught

The very first run of the suite failed — not a synthetic demonstration, the real first attempt.
`prudent.server.onboarding.NewUserSetup` is a jZen `@ObservesAsync` observer (ADR-010: it seeds
Prudent's five default categories on the framework's `UserRegistered` event), and an async
observer genuinely races the HTTP response that fired it: the suite's `listCategories()` call,
made immediately after a successful `register`, came back empty. **Fixed with a poll** (up to 20
attempts, 250ms apart) rather than a longer fixed sleep, because the actual wait is a function of
machine load and container scheduling, not a constant — a fixed sleep long enough to be reliable
on a loaded CI runner would be needlessly slow on every quiet developer machine, and a fixed sleep
short enough to be fast would eventually flake again. This is the seeding race genuinely existing
in the product, not a test artifact: any real client that creates a record in the instant after
registration is racing the same observer.

### Consequence

- `task test:e2e` is green: 6/6, against the live stack, server torn down cleanly and the port
  freed on both the failing and the passing run.
- **The gate was demonstrated failing before it was demonstrated passing** — the category race
  above — which is the strongest form of "a gate nobody has seen fail is a gate nobody knows
  works" this phase produced anywhere.
- `docs/prudent-migration-plan.md`'s Phase 5 suite table gains `test:e2e` as done, six cases,
  Linux-only.

---

## ADR-018 — CI on two operating systems, and jZen pinned at a SHA rather than published now

**Date:** 2026-08-18. **Status:** accepted.

### Context

Prudent had no CI. jZen ADR-026 named the trigger for this moment in advance: Dart's `path:`
dependencies and the admin panel's TypeScript alias need no CI-side accommodation at all — they
resolve against whatever is checked out at `../jZen`, on any machine — but **Java cannot reach
across repositories on its own**, and a lone CI clone has neither a sibling checkout nor a
populated local Maven repository. The first CI run is exactly the moment that stops being
theoretical.

### Decision

**`.github/workflows/ci.yml`**, five jobs: `gates` (the boundary gate first, then
`zen:framework:install`, `sync:contracts`, `zen:test:client`, `test:admin`, and a Wasm
web-bundle-compiles gate — compiling the bundle *is* the gate, since no test does, and a
non-Wasm-clean Flutter dependency would otherwise leave every suite green and the web app
unbuildable); `backend` (`test:server`); `android-runner` (`zen:build:runners` on
`ubuntu-latest` — Android and the Linux desktop app; Apple targets stay off CI per ADR-003's cost
reasoning, covered locally instead); `windows-runner` (`zen:build:runners` on `windows-latest` —
the only place the Windows app is ever built, build-only, no `test:e2e` there); `e2e`
(`test:e2e`, Linux-only, matching ADR-017).

**Every job checks out `../jZen` at a pinned SHA** (`env.JZEN_REF`, currently
`5a36d1f7081527bef6e5045f586fa35ed5352154`, confirmed pushed to `jZenDev/jZen`'s `main`) into a
sibling `jZen/` directory alongside `prudent/` under the runner's workspace, and any job building
Java additionally runs `task zen:framework:install` before it. **This is the decision the ground
rules asked to be made explicitly, and it is: pin at a SHA, do not force the publishing decision
now.** The cost is stated plainly rather than hidden in a comment nobody reads: the pin is a
dependency version like any other, and it is stale the moment `jZen`'s `main` moves past it —
bumping it is a deliberate, reviewed step, the same as bumping any other pinned dependency, never
a side effect of an unrelated change. This is the cost of deferring publication, not a substitute
for it; the publishing ADR jZen ADR-026 anticipates remains open.

**`task audit` stands outside `task test` and `ci.yml`, in its own `.github/workflows/audit.yml`**
(weekly schedule + `workflow_dispatch`) — the same reasoning as jZen's own equivalent: it asks a
remote service a question that changes when nothing in the repository changed, and folding it into
the merge gate would make an unrelated PR red over an overnight advisory. `task audit:server`
(`scripts/audit_maven.py`, Prudent's own — jZen's equivalent is `zen_demo`-shaped and not
reusable through the include this repository consumes) resolves the Maven dependency tree and
queries OSV in a batch; `task audit:admin` runs `pnpm audit` against `admin/`'s own dependencies.
Suppressions (`scripts/audit-suppressions.txt`) require a reason on the same line as the advisory
id or the file fails to parse — an unexplained suppression is a parse error, not a silent skip.

### What it found on the first run

`task audit:server` found a real, unsuppressed advisory on its first run:
`io.netty:netty-codec-http:4.1.136.Final` — pinned transitively by Quarkus 3.38.0's own BOM in
`zen-parent` — is vulnerable to **GHSA-8c42-7qj2-3j46** (`CorsHandler` silently overwriting an
existing `Vary` header, enabling cache poisoning). **Fixed, not suppressed**: `server/pom.xml`
gained a `<dependencyManagement>` override to `4.1.137.Final`, the same patch-release-override move
`admin/package.json`'s `pnpm.overrides` already makes for `react-router` and others. A suppression
was available and was rejected: the fix costs one dependency version and closes the finding
outright, where a suppression would only have argued the exploit path is unreachable.

### Consequence

- `task audit:server` reports zero unsuppressed findings against 334 Java dependencies;
  `task audit:admin` reports none. `task test:server` stayed green at 79/79 after the override.
- **The audit gate was demonstrated failing before it was demonstrated passing** — the netty
  finding above — on the very first run, not a synthetic injection.
- Bumping `JZEN_REF` is now a named, deliberate act with a place to make it (`ci.yml`'s and
  `audit.yml`'s `env:` block), rather than an implicit consequence of whoever next touches CI.

---

## ADR-019 — GDPR: Prudent's own tables are swept when `zen-identity` anonymises an account

**Date:** 2026-08-18. **Status:** accepted.

### Context

`zen-identity` ships `UserRetentionService`, a GDPR Art. 5(1)(e) **dormancy-based** retention
cycle — not a self-service "delete my account" flow; no such flow exists in `zen-identity` today.
After two confirmed-delivered warnings, `anonymiseExpiredAccounts()` mutates a dormant `users` row
directly, inside its own transaction, and **fires no event** an application could observe —
unlike `UserRegistered`, which exists for exactly the symmetric case on the way in (jZen ADR-007).
ADR-010 already named the consequence: with `zen-jobs` absent, "Prudent's GDPR retention cycle is
currently UNRUN rather than unneeded... an obligation deferred to the deploy phase." This is that
phase, and the obligation has a second half ADR-010 could not yet see: even a *running* retention
cycle only anonymises `users`, leaving every Prudent row still keyed to that `user_id` — the
account's financial history — in the database indefinitely.

### Decision

**Prudent's financial records do not outlive the account they belong to.** `server/pom.xml` now
assembles `zen-jobs` (keeping `zen-ratelimit`; `zen-email` stays absent, unchanged from ADR-010 —
Prudent sends no mail). Two `ZenJob`s, both under `prudent.server.retention`, both daily:

- **`UserRetentionZenJob`** wires the framework's own `UserRetentionJob.runCycle()` as a scheduled
  job — identical in shape to `zen_demo`'s own registration of the same class, because the
  framework offers the cycle as a plain callable and knows nothing about scheduling.
- **`PrudentRetentionCleanupJob`**, Prudent's own, sweeps what the framework cannot reach. It
  scans `users` for the anonymisation marker `UserRetentionService` writes
  (`anon_<uuid>@deleted.invalid` — package-private there, so the literal is **duplicated** here
  rather than referenced, a coupling worth naming plainly), and for every match hard-deletes every
  Prudent row still keyed to that `user_id`: records first (a bulk delete — `RecordEntity` owns no
  child collection), then accounts **entity-by-entity** (so Hibernate cascades the
  `@ElementCollection` balances table, `prudent_account_balance`, that a bulk HQL delete would
  bypass and orphan), then categories and the singleton settings row (both bulk deletes). Running
  it twice is exactly as harmless as running it once: a swept user has nothing left to find.

### What this doesn't fix, and is reported rather than forked

`UserRetentionService`'s silence is a framework gap, not a Prudent one, and `../jZen` is
read-only from here: the fix — `UserRetentionService` firing a `UserAnonymised(UUID userId)`
event mirroring `UserRegistered`'s own shape — is recorded in `docs/jzen/README.md`'s findings
table rather than built here. Until it exists, Prudent's job is a scan against a private naming
convention that could change without warning; that fragility is the cost of not waiting for the
framework to grow the hook first.

### Consequence

- `task test:server` green at **79 tests**, up from 76: `PrudentRetentionCleanupJobTest` asserts
  every row for an anonymised user is swept, that running the job twice is harmless, and that a
  live user (the suite's fixed `ALICE` identity) is left untouched.
- The boot log now registers three jobs (`user-retention`, `prudent-retention-cleanup`,
  `zen-ratelimit-cleanup`), confirmed by reading it rather than only by the tests passing.
- **Still open, and named as such rather than left implicit**: the `users` row itself is never
  touched by Prudent's job — its retention (or eventual removal) is `zen-identity`'s to own, and
  this entry does not extend Prudent's authority into a table it does not own.

---

## ADR-020 — The deploy path is proven against a throwaway environment; a real deploy is not this phase's

**Date:** 2026-08-18. **Status:** accepted.

### Context

Phase 5 asked whether a real deploy happens this phase or whether it ends at "the deploy path
exists and is proven against a throwaway environment." Answered explicitly: **throwaway only.**
No GCP project, no Cloud Run service, nothing billable, and — regardless of the answer — CLAUDE.md
already forbids a committed cloud account, project, region or service name, since this repository
outlives any one environment.

### Decision

**Built and proven, entirely locally:**

- `server/src/main/docker/Dockerfile.native-micro` — the same base image and shape as jZen's own
  `zen_demo_server` reference (`ubi9-quarkus-micro-image`), `EXPOSE 8085` matching ADR-010's port
  rather than the framework's default `8080`.
- `task build:server:native` — a `linux/amd64` container build
  (`quarkus.native.container-build=true`) so the image matches Cloud Run regardless of the
  developer's own CPU architecture, `clean`ing the module first so a file removed from the staged
  web bundle cannot survive in `target/classes` and be baked in anyway.
- `task build:web` — stages the Flutter Wasm bundle into
  `server/src/main/resources/META-INF/resources` so the native image serves it **same-origin**,
  which is load-bearing for the `zen_access_token` `SameSite=Lax` cookie, not cosmetic.
  `WEB_API_URL` is **required**, with no `gcloud`-lookup fallback — CLAUDE.md forbids the
  committed project/service name such a lookup would need. The task discards the previous Flutter
  web-build cache before rebuilding (the cache does not invalidate on a `--dart-define` change
  alone) and then **byte-searches the built `main.dart.wasm`** for the configured host, because a
  build define that silently fails to apply must fail the build rather than report success.
- `task build:web:admin` — stages the react-admin panel at `/admin/`, same-origin, same reason.
- **Migration is an act of the deploy, not of a boot** (jZen ADR-038) — and needed **zero new
  code**: `zen-identity`'s `MigrateOnlyRunner` already reads `zen.migrate-only` /
  `ZEN_MIGRATE_ONLY` and `zen.allow-schema-rollback` / `ZEN_ALLOW_SCHEMA_ROLLBACK`, and Prudent
  already assembles `zen-identity`. The only work here was assembling `zen-jobs` (ADR-019) and
  setting the right environment variables at the right moment.
- **`task test:native`** — Prudent's own local proof, in Docker, against a throwaway Postgres,
  the same shape as jZen's own `test:native`: runs the packaged image with
  `ZEN_MIGRATE_ONLY=true` to completion first and asserts exit 0, that migrations were actually
  applied (not a vacuously-clean exit against a schema nothing touched), and that no HTTP port was
  bound; asserts the schema-rollback gate refuses a database whose `flyway_schema_history` is
  ahead of the image with exit 2, and that `ZEN_ALLOW_SCHEMA_ROLLBACK=true` is a deliberate
  override that lets it through; only then starts the same image serving and runs
  `task verify:endpoints` (Prudent's adaptation of jZen's own endpoint-assertion shape) — both
  transport modes on `/api/v1/health` and 401s on every owned resource, the admin surface
  correctly answering 406 rather than 500 on Protobuf (JSON-only by design), `/` serving the
  Flutter shell, `/main.dart.wasm` served with the correct content type, `/admin/` serving the
  react-admin shell.

### The native locale check, folded into the same gate

`quarkus.locales` bakes JDK locale data into the native image at **build** time; a JVM run cannot
see whether it was set correctly. `task test:native` registers a user with
`Accept-Language: pl-PL` against the **actual native binary** (real Supabase auth is needed to
mint the session, so this reuses Prudent's own local Supabase project rather than a second
fabricated identity provider) and reads `users.language` back from Postgres directly, bypassing
the API. This is the one assertion in the gate that a `@QuarkusTest` — which always runs on the
JVM — structurally cannot make on Prudent's behalf.

### A real gap found and fixed while wiring this

`zen.i18n.supported` was **hardcoded** to `en,uk,pl` in `application.properties`, with no
environment-variable override at all — directly contradicting the requirement that a deploy carry
`ZEN_I18N_SUPPORTED` explicitly (a `--set-env-vars` deploy replaces the whole environment, so a
value set by hand on a live service is silently wiped by the next deploy). Changed to
`zen.i18n.supported=${ZEN_I18N_SUPPORTED:en,uk,pl}`. The existing default preserves every
current test's behaviour, confirmed by running the full suite again (still green, 79/79) —
including `ApplicationLocaleSetTest`, whose `@TestProfile` config override was unaffected, since a
profile override always wins over `application.properties` regardless of this expression.

### What stays an explicit placeholder rather than silently unset

`AUTH_REDIRECT_URIS` and a real custom domain / App Links host have no value yet, and per the
decision behind this entry they are **not** left implicitly unset: the placeholder is
`prudent.invalid` (RFC 2606's reserved `.invalid` TLD — the same convention
`UserRetentionService`'s own `@deleted.invalid` anonymisation marker already uses), named as a
placeholder everywhere it appears rather than a value someone could mistake for real.

### The secret inventory a real deploy would need

Recorded here because none of it exists yet, and this is where whoever does the real deploy will
look first: `SUPABASE_URL` / `SUPABASE_KEY` (service role, server-side only, never reaching a
client); `DB_URL` / `DB_USERNAME` / `DB_PASSWORD` for **two** roles — the runtime role and
Flyway's separate DDL role; `AUTH_REDIRECT_URIS`; `ZEN_I18N_SUPPORTED`; `CORS_ORIGINS`;
`WEB_API_URL` (build-time only — it is baked into the Wasm bundle, never a runtime secret). None
of these may ever be committed (CLAUDE.md). `task test:native`'s `smoke_env` is the shape a real
deploy's `--set-env-vars` would carry — every value in it deliberately fake except the throwaway
datasource and, for the native-locale check specifically, the local Supabase project's own
(already-local, already-non-secret) anon key.

### A second real finding, caught by running the gate rather than by inspection

The first full run of `task test:native` failed at the serving-container check: the assertion
that %prod logs no Flyway activity grepped the raw log for the bare word `flyway`, and Quarkus's
own "Installed features" boot banner **always** names the `flyway` extension because it is present
on the classpath — regardless of whether `migrate-at-start` ever ran. The check was failing a
serving container that had correctly migrated nothing. Narrowed to the actual migration verbs
(`Migrating schema`, `Successfully applied`, `schema history`) rather than the extension's own
name; re-run, green.

### Consequence

- **`task test:native` is fully green, run against the real linux/amd64 native image**: both
  migrate-only schema-gate directions (refuses ahead-of-image with exit 2, the override lets it
  through), an empty database actually migrated (not a vacuous exit 0), a serving container with
  zero migration log activity, every owned resource answering 401 in all three probes and the
  admin surface's JSON-only 406, the Flutter shell at `/`, the Wasm bundle served with the correct
  content type, the react-admin shell at `/admin/` — and **the native-only locale check itself**:
  registering with `Accept-Language: pl-PL` against the actual native binary left `users.language
  = 'pl'` in Postgres, which is the one assertion in this whole phase a JVM-only run structurally
  cannot make. Docker containers and network torn down cleanly on both the failing and the
  passing run.
- `task test:native` is Prudent's release gate for everything a deploy would exercise before the
  first `gcloud run deploy` is ever typed, and it runs on nothing but a local Docker daemon.
- **What remains open, named rather than glossed over**: the publishing decision jZen ADR-026
  anticipates (no Prudent ADR yet — it is explicitly not this phase's to close), a real cloud
  project/region/service name, and `AUTH_REDIRECT_URIS` resolving to something other than
  `prudent.invalid`. None of the three is this phase's to close.

---

## ADR-021 — The deploy contract: every environment fact is passed in, and the gap that writing it exposed

**Date:** 2026-08-18. **Status:** accepted. **Refines:** ADR-020. **Closes:** ADR-020's "a real
cloud project/region/service name" only in the sense that it defines how one is supplied — none is
named here, and none ever will be.

### Decision

`task deploy:cloudrun` and `task verify:deploy` exist. ADR-020 built the artifact half — the native
image, the staged Wasm and admin bundles, `test:native` — and deliberately stopped before the cloud.
This is the other half, written **without deploying anything**: no project, no billing, nothing
billable, no live service.

- **Six required variables, no defaults, and their absence is a loud failure naming each one:**
  `GCP_PROJECT`, `GCP_REGION`, `SERVICE_NAME`, `ARTIFACT_REPO`, `RUNTIME_SERVICE_ACCOUNT`,
  `WEB_API_URL`. This is CLAUDE.md's "no deployed environment fact is written into the repository"
  applied literally, including to the service name. The reason is teardown: this repository outlives
  any environment it deploys to, and a stale task *default* is worse than a stale doc line because
  the task keeps working while pointing every build at a host that no longer exists.
- **`WEB_API_URL` is not resolved automatically**, and the chicken-and-egg is stated rather than
  hidden: client config is compile-time, so the bundle is built before the service exists, and the
  first deploy of a new service is two — deploy to learn the URL, re-run with it set. Looking it up
  would require the task to know the service name it is forbidden to commit.
- **Eleven secrets**, fewer than jZen's fourteen because Prudent assembles no `zen-email`:
  `SUPABASE_URL`, `SUPABASE_KEY`, `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `APP_DB_USERNAME`,
  `APP_DB_PASSWORD`, `SITE_URL`, `AUTH_REDIRECT_URI`, `AUTH_REDIRECT_URIS`, `CORS_ORIGINS`, plus
  `ZEN_JOBS_TRIGGER_TOKEN` (see below). `--set-secrets` fails the deploy when one is missing, which
  is the point: a service that boots without one has a security control that is *absent* rather than
  failing.
- **Migrate, then deploy, and the exit code is the gate** (jZen ADR-038). The image just pushed runs
  as a one-shot Cloud Run Job with `ZEN_MIGRATE_ONLY=true` on the DDL credentials — `APP_DB_*` is
  deliberately absent from that job's secret list — and the service deploys only on exit 0. Exit 2
  means the database is ahead of the image's migrations and aborts; `ALLOW_SCHEMA_ROLLBACK=true`
  overrides it deliberately and gives up the only remaining check that binary and schema agree.
- **`ZEN_I18N_SUPPORTED` is carried on every deploy, and blank is refused.** `--set-env-vars`
  replaces the whole environment, so a value set by hand on the service is wiped by the next deploy;
  and a blank variable — what an unset export actually produces — is *unconfigured*, not an empty
  set (jZen ADR-044).
- **`verify:deploy` asserts configuration, not only code**: both transport modes, guarded resources,
  the web shell, the Wasm bundle, `/admin/`, `/openapi` **absent** from the native image, and the
  redirect allowlist via a `restore-password` for a nonexistent account (204 regardless of whether
  the account exists, so it reads the allowlist and nothing else, and mails no one).

### The gap writing it exposed, and where the fault actually lies

`application.properties` had **no `zen.jobs` configuration at all**, so `zen.jobs.trigger.token` was
unset in `%prod`. Prudent assembles `zen-jobs` for exactly one reason — ADR-019's
`PrudentRetentionCleanupJob`, which sweeps Prudent's own tables when `zen-identity` anonymises a
dormant account — and that job could never have run in production.

Nothing would have reported it. The trigger endpoint fails closed, which is correct; every suite was
green (79/79), every request would have been served correctly, and every assertion in `verify:deploy`
would have passed. A GDPR erasure control was present in the code and absent in production.

**The configuration is Prudent's** (jZen ADR-007's split: the framework provides the mechanism, the
application supplies the credential), and it is now supplied — `%prod.zen.jobs.trigger.token` reads
`ZEN_JOBS_TRIGGER_TOKEN`, **empty by default** so an unset secret keeps the endpoint refusing rather
than falling back to a token committed in this repository and therefore known to anyone who can read
it. The scheduler entry is step 3 of `deploy:cloudrun`'s runbook.

**The unobservability is jZen's**, filed as [jZen#65](https://github.com/jZenDev/jZen/issues/65) and
tracked in [`docs/jzen/README.md`](jzen/README.md)'s findings table, which is where the state of every
framework finding lives — reported / filed / fixed and consumed — so a later session can tell them
apart without re-reading this log: the
framework's only warning is call-time, and an application that has not configured the token has not
created the scheduler entry either — so nothing calls it and the warning never fires. jZen is loud
about a half-configured deployment and silent about a wholly unconfigured one.

**Prudent does not wait on that.** (jZen fixed it on 2026-08-19 — see ADR-023; the sentence below described the state on the day this was written and stays as written, because the decision it justifies is unchanged: the two checks cover different halves.) `verify:deploy` asserts the Cloud Scheduler entry exists, so the
inert state fails a gate Prudent owns, today, whatever upstream does. Where the scheduler cannot be
inspected (no `GCP_PROJECT`/`GCP_REGION`), the check **announces itself as skipped** — "not checked
here" and "passed" must never look alike.

### What this supersedes, and why

- **"What remains open … a real cloud project/region/service name"** (ADR-020, Consequence) →
  **refined, not closed.** *Why:* the values remain unchosen and unnamed on purpose. What changes is
  that there is now a defined way to supply them and a gate that refuses to proceed without them —
  the open item was never "pick a project", it was "there is no path".
- **`docs/prudent-migration-plan.md` §3.4's "every migration ships RLS + a `zen_runtime` policy in
  the same change"** → **corrected in the plan itself** to name the repeatable, per ADR-010. *Why:*
  the rule was right and the file placement was wrong, and the plan is kept as a record, so the
  correction is annotated at the point of the claim rather than silently rewritten.
- **`docs/prudent-migration-plan.md`'s status line, "proposed, awaiting approval"** → **updated to
  implemented**, with the plan reframed as the record of how the application was built rather than a
  description of what it now is. `docs/prudent-migration-prompt.md` gained a "historical — do not run
  it again" banner for the same reason.

### Consequence

The deploy is a written, reviewable path rather than a set of commands someone types once. It has
been exercised as far as it can be without an account: `task deploy:cloudrun` with nothing set fails
naming all six variables and exits non-zero, `task verify:deploy` reports every check against an
unreachable host as a failure and announces the scheduler check as skipped, and the Taskfile parses
with both tasks discoverable in `task --list`.

Verified green after the configuration change: `task test:server` **79/79**, `./mvnw test-compile`
clean. Nothing was deployed, nothing billable was created, and `gcloud`'s active project — an
unrelated one — was never used, because every call in these tasks passes `--project` explicitly and
neither task touches global `gcloud` config.

**Still open, and named rather than glossed over:** the publishing decision jZen ADR-026 anticipates
(no Prudent ADR yet); a real cloud project, region, service name and Supabase production project;
and the first actual deploy, which is the only thing that can prove the runbook's one-time setup
steps are complete and correctly ordered.

---

## ADR-022 — The retention cascade becomes an observer, and the test that "proved" it is replaced because it could not fail

**Date:** 2026-08-18. **Status:** accepted. **Supersedes the mechanism of:** ADR-019.
**Consumes:** [jZen#63](https://github.com/jZenDev/jZen/issues/63) → jZen PR #66.

### Decision

jZen now fires `UserAnonymised(UUID)` per row, synchronously, from inside the transaction that
anonymises it — the shape Prudent proposed. Prudent consumes it:

- **`PrudentRetentionCleanupJob` is deleted**, along with the marker literal
  `email like 'anon\_%@deleted.invalid'` it matched on.
- **`PrudentRetentionCleanup` replaces it**: `void onUserAnonymised(@Observes UserAnonymised)`,
  annotated `@Transactional(MANDATORY)`. `MANDATORY` states the requirement rather than assuming
  it — the cascade must join the framework's transaction, so a cascade that throws rolls the
  anonymisation back with it rather than leaving an anonymised identity beside orphaned financial
  data. An event fired outside a transaction fails loudly instead of quietly committing alone.
- **`JZEN_REF` is bumped to `9a0b5cc`** in `ci.yml` and `audit.yml`. Until this, the local checkout
  was at the post-fix merge while CI pinned the commit before it — the two disagreed about whether a
  data-protection control worked, and nothing said so.
- `zen-jobs` is still assembled and the trigger token still matters: `UserRetentionZenJob` drives the
  framework cycle that fires the event. If the trigger never fires, nothing is anonymised and no
  cascade runs — the erasure path is inert end to end, which is what `verify:deploy`'s scheduler
  assertion (ADR-021) exists to catch.

### The part that matters more than the class: the test could not fail

`PrudentRetentionCleanupJobTest` built its fixture by writing the anonymisation marker as a literal
in the test, then asserted that a job matching *that same literal* swept it. Both sides were
Prudent's own assumption about jZen, so it asserted a tautology. Had the framework renamed the
marker, the sweep would have matched nothing, the GDPR cascade would have stopped, **and the test
would have stayed green** — a data-protection control failing in complete silence, with a passing
suite over it.

`PrudentRetentionCleanupTest` replaces it and fabricates no anonymised user. It seeds a genuinely
expired account — final warning delivered ten years ago, not premium, not already anonymised, which
is what `UserRetentionService.anonymiseExpiredAccounts()` actually selects on — and calls the
framework's own service. The ten years are deliberate: any plausible
`zen.identity.retention.anonymise-offset-days` is shorter, so the test does not duplicate a config
value, which is the same mistake in a smaller costume.

**Verified by breaking it.** With the cascade short-circuited, the suite fails on "the record must be
gone"; restored, it passes. A test that has never been seen to fail is not evidence.

### What this supersedes, and why

- **ADR-019's mechanism — "a second `ZenJob` that scans `users` for the anonymisation marker"** →
  **replaced.** *Why:* the scan existed only because no event did. ADR-019's *decision* — that a
  GDPR erasure must cascade into Prudent's tables — is unchanged and is now implemented properly.
- **`docs/jzen/README.md`'s row for #63, "Filed upstream, awaiting a fix"** → **fixed and consumed**,
  with the consumption described rather than asserted.
- **`UserRetentionZenJob`'s "runs before `PrudentRetentionCleanupJob` by id ordering"** →
  **moot, and said to be moot.** *Why:* an observer inside the anonymising transaction has no
  ordering relationship to reason about. The old reasoning is kept, marked, because it is the
  question the next reader will ask.

### Consequence

Prudent no longer depends on any framework implementation detail for its erasure path, and the
dependency it does have is asserted against the framework's real behaviour on every CI run — so a
future change upstream fails a test at the moment `JZEN_REF` moves, which is the only moment it can
matter. `task test:server` green, **79/79**, against jZen `9a0b5cc`.

**The general lesson, recorded because it is not about retention.** Watching an upstream issue is a
human process and will fail eventually; this repository's answer to a coupling it cannot control is a
test that goes red when the coupling breaks. The finding that started this (#63) was ultimately less
valuable than noticing that the test defending against it asserted nothing.

**Still open:** #64 and #65 remain filed and unfixed upstream, both with working local workarounds —
and both, unlike this one, fail loudly rather than silently if the framework moves (#64 breaks the
build; #65 is gated by `verify:deploy`).

---

## ADR-023 — Both remaining framework findings are consumed; where a workaround survives, it survives for a stated reason

**Date:** 2026-08-19. **Status:** accepted.
**Consumes:** [jZen#64](https://github.com/jZenDev/jZen/issues/64) → jZen PR #67,
[jZen#65](https://github.com/jZenDev/jZen/issues/65) → jZen PR #68. **Follows:** ADR-021, ADR-022.

### Decision

`JZEN_REF` moves to `36c0ca8` in `ci.yml` and `audit.yml`, and both fixes are consumed:

- **#64 — `zen:framework:prepare`.** The `gates` job calls it, and **both** hand-written
  workarounds are deleted: the `task zen:generate:l10n` run with `working-directory: jZen`, and the
  `pnpm install` scoped to `jZen/admin`.
- **#65 — the boot-time inertness warning.** No Prudent code changed. `JobScheduler` now checks
  both facts at startup, so an application that registers jobs with no trigger token is told so on
  the first `%prod` boot rather than at whatever later moment someone audits secrets.

### Two consequences that are not "delete the workaround"

**`%test.zen.jobs.trigger.token` had to be set, and the reason is the point of the finding.** The
new warning fired on **every Prudent test run** — correctly, by its own logic: `%test` registers two
jobs and had no token. But it is true of nothing there, since a `@QuarkusTest` calls its jobs
directly and needs no trigger. A warning that always fires is a warning nobody reads, which would
have cost exactly the signal #65 was filed to gain. Consuming a fix includes not drowning it.

**The two Flutter runner jobs still reach into the sibling checkout by hand**, and that is recorded
rather than quietly kept. `zen:framework:prepare` does two things — generate jZen's l10n *and*
`pnpm install` its admin scaffold — and `android-runner` and `windows-runner` have no Node toolchain
at all, so calling it would fail on the half they never consume. Adding Node to two jobs to satisfy a
task's shape would cost minutes per run for an install nothing reads. So those jobs keep
`task zen:generate:l10n` with `working-directory: jZen`, with a comment saying it is deliberate and
why. **Follow-up finding, filed as [jZen#69](https://github.com/jZenDev/jZen/issues/69):** `prepare`
is all-or-nothing, and the l10n half is what a Flutter runner job needs on its own. Prudent's
two-line CI workaround stays until it is answered, and is commented as deliberate rather than
left to look like an oversight.

**`verify:deploy`'s scheduler assertion stays** (ADR-021). The startup warning proves a *token*
exists; it cannot see whether anything actually calls the trigger. A deployment with a token and no
Cloud Scheduler entry is silent under both checks individually and caught by Prudent's. They cover
different halves, and neither is the other's backstop.

### What this supersedes, and why

- **`docs/jzen/README.md`'s rows for #64 and #65, "Filed upstream, awaiting a fix"** → **fixed and
  consumed**, with the surviving workaround and its reason stated in the row rather than left to be
  rediscovered. No row in that table now reads "awaiting".
- **ADR-021's implication that the jobs-token gap is invisible until a deploy** → **narrowed.** *Why:*
  it is now visible at the first `%prod` boot, upstream. Prudent's own gate is no longer the only
  thing standing between a misconfiguration and an inert erasure path — it is the second thing.

### Consequence

Every framework finding Prudent has raised is now consumed (#54, #61, #63, #64, #65), and the only
outstanding item is a follow-up worth one issue rather than a workaround worth carrying. `task
test:server` green **79/79** against jZen `36c0ca8`, with the startup warning correctly silent.

**What made this cheap, stated because it will not always be:** three findings were filed on
2026-08-18 and all three were fixed and consumable within a day, because the framework and its second
consumer are being developed together by the same hands. That is a property of today, not of the
architecture. The moment jZen is published and versioned, "consume the fix" becomes "wait for a
release", and the workarounds recorded above become things Prudent carries for months rather than
hours. That is an argument for the publishing ADR to be taken deliberately, not an argument against it.

---

## ADR-024 — The last hand-written reach into the framework checkout is gone

**Date:** 2026-08-19. **Status:** accepted. **Extends:** ADR-023.
**Consumes:** [jZen#69](https://github.com/jZenDev/jZen/issues/69) → jZen `3a450b2`.

### Decision

jZen split `zen:framework:prepare` into `prepare:l10n` and `prepare:admin`, keeping the combined
task, which is the shape Prudent proposed. Applied here:

- `android-runner` and `windows-runner` call **`task zen:framework:prepare:l10n`** from Prudent's own
  root. The `working-directory: jZen` + `task zen:generate:l10n` pair ADR-023 kept deliberately is
  deleted, and with it the comment explaining why it had to stay.
- `gates` continues to call the combined `zen:framework:prepare`; it wants both halves.
- `JZEN_REF` moves to `3a450b2` in `ci.yml` and `audit.yml`.

**No CI job now names a path inside the framework checkout.** The only place `.github/workflows/`
mentions `jZen` as a directory is the `actions/checkout` step that creates it; every other touch goes
through a `zen:` task. That was #64's whole point, and it took two rounds to actually reach — the
first fix removed the coupling from the job that needed both halves and left it in the two that
needed one.

### What this supersedes, and why

- **ADR-023's "the two Flutter runner jobs still reach into the sibling checkout by hand … Prudent's
  two-line CI workaround stays until it is answered"** → **resolved.** *Why:* it was answered, in
  under a day. The entry stands as written; the workaround it justified no longer exists.

### Consequence

Verified: `task zen:framework:prepare:l10n` runs green from Prudent's root, both workflows parse with
five jobs intact, and `grep 'working-directory: jZen'` over `.github/workflows/` returns nothing.

Nothing in Prudent's Java, Dart or TypeScript changed, so no suite could have caught a regression
here and none was run for show — the change is orchestration, and the only honest proof of it is a
fresh multi-repo CI clone, which is what the next push exercises.

**Six findings, six consumed.** Worth stating once, plainly, because the number will not stay
flattering: every framework gap Prudent has hit since the conversion began has been reported and
fixed upstream rather than worked around permanently here, and the reason is that jZen and its second
consumer are the same hands on the same day. ADR-023 already names what changes when publishing puts
a release boundary between them; this entry is the last cheap one.

---

## ADR-025 — The auth callback scheme was configured everywhere except the operating system

**Date:** 2026-08-19. **Status:** accepted. **Corrects a claim in:** ADR-013.

### Decision

`prudent://auth-callback` is now registered where the OS actually reads it: a `BROWSABLE`
intent-filter in `client/android/app/src/main/AndroidManifest.xml`, and `CFBundleURLTypes` in the
iOS and macOS `Info.plist`s. Prudent also gains `run:supabase`, `run:server` and `run:client`, so
the stack can be brought up interactively rather than only inside `test:e2e`.

### What this corrects, and why it survived a whole phase

ADR-013 recorded: **"Native auth redirects use the custom scheme only — `prudent://auth-callback`,
registered as the sole entry in `AUTH_REDIRECT_URIS` and mirrored in `supabase/config.toml`'s
`additional_redirect_urls`."** Both halves were true, and both are server-side. **No client platform
claimed the scheme**, so nothing on the device would ever have received the link.

Every participant behaved correctly, which is why nothing reported it: the server permits the
return address, Supabase mails it, `app_links` (a declared dependency) listens for it, and the OS
delivers it to nobody because no app claims `prudent://`. Password recovery and email confirmation
would have done nothing on Android, iOS and macOS — while the web build, being same-origin, worked
perfectly. No suite could see it: widget tests never register a URL scheme, and `test:e2e` drives
the API directly rather than following a mail link.

It was found by asking what a live local run would need, not by a gate. That is the honest account:
this class of defect — configuration that is complete on every side except the platform manifest —
has no test in this repository today, and adding one would mean driving a real link through a real
device.

### Consequence

Verified against the running stack rather than by reading: registration through
`POST /api/v1/auth/register` with `Accept-Language: pl-PL` leaves **`pl`** in `users.language`; an
account, a category and a record round-trip; the same list returns `application/x-protobuf` under
`X-Zen-Transport: protobuf`; and the account's derived balance reads **248001** after a −1999 record
against a 250000 opening balance — ADR-014's "balance is derived, not stored", proven live rather
than in a fixture.

**Not verified, and stated rather than implied:** that a mail link actually opens the app. That needs
a device, the local mailbox at `http://localhost:54334`, and a human tapping it. The registration is
necessary and is not by itself sufficient.
