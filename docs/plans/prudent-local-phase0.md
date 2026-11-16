# Prudent Local — phase 0, decisions 0.1 to 0.5

> **Status:** written 2026-11-15 for `docs/plans/PRUDENT-LOCAL-PLAN.md` (jlogicsoftware/prudent#245).
> **All five are decided.** The user accepted every recommendation of 0.1, 0.2 and 0.4 as proposed:
> 0.1 is ADR-101, 0.2 is ADR-102, 0.4 is ADR-103, 0.5 (the threat model) is ADR-100, and 0.3 (the
> inventory) is folded into the plan. The sections below keep the analysis as it was put to the
> person; where they say "proposal" or "STOP", the ADR now holds. Nothing here is built, and nothing
> here was run on a device. Prudent Local inherits every "not verified" of jZen Local
> (jZenDev/jZen#231). The nine jZen limitations below are filed as jZenDev/jZen#232–#240.

Sources read: `CLAUDE.md`, `docs/zen-architecture.md`, `docs/DECISIONS.md` (ADR-014, 071, 081,
088–097), the plan, all 22 Flyway migrations and the repeatable RLS script, every resource and
service under `server/src/main/java/prudent/`, every message in `proto/prudent/v1/`, and in
`../jZen` (read-only, at `fdef7e8`): ADR-065, 073, 075–081, `JZEN-LOCAL-PLAN.md`,
`apps/zen_demo_local/README.md`, and the sources of `zen_store`, `zen_store_key`,
`zen_store_sync` and `zen_store_cloudkit` where an ADR did not settle a question.

## What jZen Local actually gives a ledger (the facts every decision below rests on)

Read from the code, not only the ADRs, because several decisions turn on them:

1. **The unit of merge is a top-level proto field of one record** (`zen_proto_fields.dart`). Edits
   to different fields merge; the *same* value set on two devices merges; **any other concurrent
   edit of one field is a conflict for the person**. There is no per-field policy: no field can be
   declared "merge silently" when two devices set it to different values. A nested message or a
   repeated field is one field and conflicts as a whole.
2. **A delete against an edit the deleter had not seen is a conflict**, kept on every device until
   `resolve`. A record in conflict refuses `put` and `delete`.
3. **There is no multi-record write.** `ZenCollection.put` writes one record; the store rewrites
   the one shard it lives in (64 shards, one file each). Two records may sit in two shards, so even
   two sequential `put`s are not atomic on one device, and **the transport delivers record by
   record**: another device may receive one record of a pair before the other, or one only.
4. **Rules across records are the application's** (`zen_store` README, "What it does not do").
   Merging can produce a combination neither device wrote and that breaks a rule spanning records
   (one default account, an envelope below zero). The store cannot see it.
5. **A record id is any printable ASCII string of 1–190 characters**, so an application may derive
   an id from a natural key instead of using `newId()`. Two devices that derive the same id are
   writing the *same* record, and a uniqueness rule becomes a same-record field conflict, which the
   store does surface.
6. **CloudKit record names are `<collection>:<id>` in plaintext** (`ZenCloudKitBridge.swift:12`);
   only the record's state is in `encryptedValues`. The shared-folder transport, by contrast, names
   files by an HMAC under a key derived from the sync key (jZen ADR-076). An id derived from data is
   therefore visible to Apple unless it is keyed.
7. **`ZenFolderCloud` stores payloads unencrypted** (`zen_folder_cloud.dart:22`) and nothing stops a
   release build from selecting it; only a comment says the define is empty in release.
8. **A second, unsynced store is possible today**: `ZenDeviceStoreKey.load` takes a key `name`, so an
   application can open a second `ZenStore` in another directory with its own key and no transport.
9. **Tombstones are kept for ever**; ids are never reused safely after a delete except by the
   same-record rules in 1–2.

---

## 0.1 Shape — how the Local app sits beside the server-connected app

**Status: decided — ADR-101** (every recommendation below accepted as proposed). The analysis is kept as it was put to the person.

### The options

| | A. Shared package + second app (the plan's recommendation) | B. One app, runtime mode | C. One app, compile-time flag (`ZEN_MODE=local`) |
|---|---|---|---|
| Allowed by the rules? | Yes | **No** — runtime client config is forbidden (CLAUDE.md, "Compile-time config on the client") | Yes in letter |
| Server code in the Local binary's source graph | None: the Local app's `pubspec.yaml` does not list `zen_transport`, `zen_identity`, `app_links` or the auth deep links | All of it | All of it (one `pubspec.yaml`); conditional imports only hide it from the *compiled* graph, and native plugins register on every platform they declare regardless |
| Local code in the web build | None | All of it | `zen_store`, `cryptography`, `flutter_secure_storage`, `local_auth` resolve into the web build's graph; each needs a web stub or a conditional import |
| `verify:boundaries` rule ("Local imports neither `zen_transport` nor `zen_identity`") | A package-level fact: `pubspec.yaml` of the Local app, checkable by reading one file | Impossible | An import-graph analysis per build target, which is fragile and easy to fool with a transitive import |
| Bundle id, entitlements (CloudKit container), app name, icons | Each app has its own runners; nothing to switch | One app id for two products | **Flavors** in every runner: Xcode schemes and configurations (SwiftPM-only runners, ADR-083), Android `productFlavors`, Windows/Linux CMake variables, plus `task` plumbing for each |
| Both installed side by side on one device | Yes, naturally | No | Only with flavors done right on all five platforms |
| Cost now | Unit 2 moves most of `client/lib` into a package (a large `git mv`, like ADR-026's flattening), path dependencies, per-package l10n | — | Lower at first, rising with every platform runner |
| Zen fit (`docs/zen-architecture.md` §3, §5) | The repository interface of unit 1 has **two real implementations**, so it is an abstraction that earns its place, not a passthrough | — | A mode switch threaded through one app is the "implicit wiring" §2 warns about |

Other shapes considered and dropped: a Local app that depends on `client/` as a path package (its
graph would then carry everything `client/` carries — option C by another name), and a Local app
that copies the screens (two copies of every screen drift; `verify:controls` would have to watch
both).

### Recommendation: A, with four Dart packages

The repository root stays language-neutral (no root `pubspec.yaml`, jZen STANDARDS), so the
packages are linked by `path:` dependencies, exactly as Prudent already consumes jZen.

```
client/                          the server-connected app (Flutter): main.dart, app.dart, auth/,
                                 ServerPrudentRepository (today's prudent_repository.dart),
                                 its runners (bundle id unchanged), web build. Depends on prudent_ui.
packages/prudent_ui/             shared Flutter package: every screen, view model, money formatting,
                                 the abstract PrudentRepository (unit 1), the generated Dart of
                                 proto/prudent/v1/ (moved from client/lib/generated), en/uk/pl ARB
                                 files for the shared screens. No zen_transport, no zen_identity,
                                 no zen_store.
local/prudent_local_core/        pure Dart (dart test, no Flutter): the local store model (its own
                                 protos, see 0.2), the rules of 0.3 units 3–8, the calculators,
                                 the Erste importer, the integrity checks, and the parity harness's
                                 local side. Depends on zen_store and the generated proto Dart.
local/prudent_local_client/      the Local app (Flutter): main.dart, LocalPrudentRepository over
                                 prudent_local_core, ZenSync.start, zen_ui_lock, zen_ui_store,
                                 zen_store_key, zen_store_folder; its own runners and bundle id;
                                 no web runner.
```

Why a separate pure-Dart core: the parity suite runs the same scenario through the real server
(`task test:e2e` is already a pure-Dart VM gate, ADR-017) and through the local rules, and that is
only possible when the local rules do not need Flutter. `zen_store` is pure Dart for the same
reason (jZen ADR-065).

Where the generated proto Dart lives changes the contract loop: `PROTO_DART_OUT` on the jZen
include moves from `client/lib/generated` to `packages/prudent_ui/lib/generated`, and
`verify:contracts` follows it. The Local store's own protos (0.2) are generated into
`local/prudent_local_core/lib/generated` the way `zen_demo_local` does it (jZen ADR-080).

### What the person must decide

1. **A (shared package + second app) or C (one app, flavors)?** Recommended: A.
2. **Three packages or four?** Folding `prudent_local_core` into the Local app saves a package but
   puts the local rules behind Flutter, so the parity harness needs a Flutter test runner beside
   the server. Recommended: four.
3. **Identity of the second app:** a separate bundle id and the name "Prudent Local" (both
   installable on one device, two separate data sets), or something else. Recommended: separate id.

---

## 0.2 Money under merge

**Status: decided — ADR-102** (every recommendation below accepted as proposed; the table below is frozen as of jlogicsoftware/prudent#249 and changes only by a new ADR). The ground rule holds throughout: **no
last-writer-wins anywhere**, wall-clock time is shown and never decides.

### The plan's own sentence needs correcting

The plan says "amount and account are conflicts; note and category are not". Under `zen_store`
that second half cannot be true: **two devices setting a note to two different texts is a conflict,
and nothing can make it otherwise without picking a winner** (last-writer-wins, or an invented text
merge). What *is* true and is the real choice: which fields are separate store fields (so that an
edit to the note on one device and to the amount on another merge without a question), which are
grouped (so that edits to coupled fields conflict together), which are written once, and which are
not stored at all. The table below uses five classes:

| Class | Meaning |
|---|---|
| **Merge** | A store field of its own. Edits to it alongside edits to *other* fields merge silently; two devices setting it to *different* values is a conflict for the person (the store has no other answer); equal values merge. |
| **Group** | Part of a nested store message whose fields always conflict together, because a combination of two devices' halves would be a value neither wrote and could be wrong money. |
| **Immutable** | Written once at creation, never edited; cannot conflict. |
| **Derived** | Not stored; computed from stored records on every read, as on the server. Cannot conflict. |
| **Device** | Kept only in an unsynced store on this device; never travels. |

### The six decisions

**D1 — Every figure is derived.** Balance (opening amount + net of records, ADR-014,
`AccountMapper.java:86`), budget summary and carry-over (ADR-044/045), envelope and free money
(ADR-050/051), goal progress (ADR-052), analytics, overdue, due reminders. Nothing that two devices
could both change is a stored total. The opening amount per account and currency is stored and
editable; two devices changing it differently is a conflict on that one value.

**D2 — The local store has its own messages; the wire messages are produced from them.** Storing
`proto/prudent/v1/` messages as they are would (a) store `Account.balances`, which on the wire is
the *derived current* balance, not the opening amount; (b) let a currency change on one device and
an amount change on another merge into "60 EUR" that neither wrote; (c) make every account's
`balances` list conflict as a whole when two devices each add a currency. So the store gets its
own messages (`local/prudent_local_core/proto/prudent_local/v1/`, as jZen ADR-080 does for its
demo), and a mapper produces the wire messages the shared screens already understand. The parity
suite compares wire messages, so the difference stays inside unit 4.

**D3 — Uniqueness becomes identity: deterministic ids for every natural key.** Where the server
holds a unique index on a natural key, the local record id is derived from that key, so two devices
that create "the same" thing write the same record:

| Server rule | Local id |
|---|---|
| one settings row per user (`init.sql:147`) | the constant `settings` |
| one balance per account and currency (`init.sql:69`) | `H(account_id, currency)` in `account_currencies` |
| one budget per category, month, currency (`budgets.sql:29`) | `H(category_id, month, currency)` |
| one occurrence per plan and date (`plan_occurrences.sql:27`) | `H(plan_id, date)` |
| one record per occurrence (`record_plan_link.sql:29`) | the confirming record's id is `H("confirm", occurrence_id)` |
| one record per (account, fingerprint, occurrence) (`import_fingerprints.sql:59`) | `H("import", account_id, fingerprint, occurrence)` |
| one default account (`AccountEntity.java:174`) | not an id: the default moves to the settings record as `default_account_id`, one field |
| starter categories (`NewUserSetup.java:88`) | `H("starter", key)`, and seeded only by "Start fresh on this device", never by "Join" |

`H` is a hash of the components that are themselves random ids plus the month, currency or date.
**Exposure:** on CloudKit the record name is visible to Apple (fact 6), so `H(category_id, month,
currency)` lets Apple test which months and currencies a budget exists for, and `H(plan_id, date)`
which dates a plan falls on. No amount, title or account number ever enters an id. Closing this
needs CloudKit record names to be keyed (jZenDev/jZen#236 below); it is a threat-model row (ADR-100,
row T7).

**D4 — A transfer is one store record.** The server writes two `Record` rows with a shared
`transfer_id` (`TransferResource.java:74`), never editable, delete only (`RecordResource.java:217`).
Locally a transfer is **one immutable record** holding both legs (from account, amount, currency;
to account, amount, currency; date; title). It arrives whole or not at all, so **a leg can never
arrive alone**, which removes the question rather than answering it. The two leg `Record`s the
screens show are produced on read with ids `H(transfer_id, "from")` and `H(transfer_id, "to")`.
Delete against delete merges; delete against nothing else is possible because nothing else can be
written. If the person does not accept D4 and keeps two records, the honest fallback is: a leg
whose sibling is missing is shown as "incomplete transfer, waiting for the other device", is
**counted** in its account's balance (removing it would make two devices disagree about a figure
that both can see), and after a stated number of syncs with no sibling becomes an integrity issue
the person settles (delete the leg, or re-enter the other).

**D5 — Edit against delete is the person's.** `zen_store` already does this: the record shows a
"Deleted on this device" side and the edited side; until settled the record refuses writes. For a
transfer (immutable) and an envelope entry (immutable) the case cannot occur. Deleting an account
with its records (ADR-081) is many deletes: each record may conflict separately, and a record
another device added to that account meanwhile is left pointing at a deleted account — an
**integrity issue** (D6), offered as "move these records to another account" or "delete them".

**D6 — Rules across records are checked after every sync and shown as integrity issues.** The
store cannot see them (fact 4), so `prudent_local_core` re-evaluates every cross-record rule of 0.3
after each merge and lists what fails, with actions; nothing is silently "fixed". The list:

| Integrity issue (after a merge) | Offered actions |
|---|---|
| A record, plan, budget or reset references a category, account, goal or plan that is deleted | move to another / delete / (account, category) restore from the last version this device holds |
| A record's currency is not held by its account (account edited on one device, record on another) | add the currency to the account / edit the record |
| A record's sign contradicts its category's kind (kind changed on one device) | change the category / change the kind back |
| An envelope below zero (two withdrawals) | a compensating `ALLOCATE`, never a delete (the history stays append-only) |
| Money in an archived goal, or an entry into a goal archived meanwhile | reactivate / withdraw |
| Two live carry-over resets for one slot | revoke one |
| An occurrence skipped on one device and confirmed on another | keep the payment (the occurrence becomes completed) / delete the payment |
| A correction whose effect changed (see D7) | keep / adjust to the intended balance / delete |
| Two accounts with the same account number | edit one (the number stays unique per person, ADR-090) |

Free money below zero is **not** an issue: the server already allows it after a later spend
(ADR-051), so two concurrent `ALLOCATE`s that end there are a state the product shows, not a break.

**D7 — A correction keeps the server's meaning and remembers its intent.** On the server a
correction stores the *delta* between the requested balance and the balance at that moment
(`CorrectionResource.java:95–110`). Two devices correcting the same account offline would both
store a delta, and the merged balance would overshoot. Keeping the delta (needed for "same figures
as the server") and adding two immutable local fields — the balance it was asked for and the
balance it saw — lets the integrity check notice that a correction no longer achieves its intent
after a merge and ask. The alternative (a correction as a balance assertion whose delta is
recomputed) would give different figures from the server whenever an earlier record changes, so it
is rejected unless the server changes too.

**Goal allocations** need nothing new: they are append-only on the server (trigger,
`goal_allocations.sql:72–82`) and immutable locally, each with a random id, so two devices' entries
never conflict; the envelope is a sum (D1); the rules that two entries together can break are
integrity issues (D6).

**Same-intent timestamps.** Revoking a reset on two devices sets `revoked_at` to two different
clock readings: a conflict about *when*, not *whether*. The same holds for `status_changed_at`
(two devices completing one goal) and the reminder-read time. These are the only fields where an
automatic answer is honest: when every side carries the *same* new state, the earliest timestamp
is kept. That is not last-writer-wins — no side's intent is dropped, and the answer does not depend
on which device wrote last. It needs a declared per-field policy in `zen_store` (jZenDev/jZen#235);
until then the same rule is applied by `prudent_local_core` through `resolve`, only for these
listed fields, and every other conflict goes to the person.

### Per-field merge table — every message in `proto/prudent/v1/`

Stored messages (as they will be stored locally; the reason is in the last column).

**`Account`** (`accounts.proto`)

| Field | Class | Why |
|---|---|---|
| `id` | Immutable | device-minted, never edited |
| `name` | Merge | a label; two different names is a real question |
| `type` | Merge | |
| `is_default` | **Moved** → `settings.default_account_id` (Merge) | "one default" is a rule across records (`AccountEntity.java:174`); as one field it conflicts instead of producing two defaults |
| `is_active` | Merge | equal values merge; differing is a question |
| `include_in_total`, `include_in_overview` | Merge | |
| `balances` | **Not stored here**; Derived on the wire | the wire value is opening + net. The opening amount lives in `account_currencies` (below) |
| `eligible_for_goals` | Merge | |
| `account_number` | Merge, plus integrity check | uniqueness per person spans records (D6) |

**`CurrencyBalance`** → local `AccountCurrency` record, id `H(account_id, currency)`

| Field | Class | Why |
|---|---|---|
| `currency` | Immutable | part of the id |
| `amount_minor` (opening amount) | Merge | the one stored money figure of an account; two different openings is a question |
| position | Merge | order of display only; equal positions on two devices are ordered by currency code |
| (deleted) | delete | dropping a currency is a delete; a record in that currency made meanwhile is an integrity issue |

**`Category`** (`categories.proto`)

| Field | Class | Why |
|---|---|---|
| `id` | Immutable | random, or `H("starter", key)` for a starter |
| `title`, `icon_key`, `description`, `color_argb` | Merge | labels |
| `archived` | Merge | a boolean: archiving on two devices merges as equal |
| `kind` | Merge, plus integrity check | a kind change against a new record of the other sign is a rule across records |

**`Record`** (`records.proto`) — ordinary and correction records; transfers are D4

| Field | Class | Why |
|---|---|---|
| `id` | Immutable | random; `H("confirm", occurrence)` or `H("import", …)` where D3 says |
| `title` | Merge | |
| `account_id`, `currency`, `amount_minor` | **Group** (`posting`) | where the money is and how much: a combination of two devices' halves (a new currency with an old amount) would be money nobody entered |
| `date` | Merge | moving a date alone is safe; it changes which month and budget it counts in, which is derived |
| `category_id` | Merge, plus integrity check (kind, archived, deleted) | classification; kept apart from the posting so re-categorising on one device and correcting the amount on another merge |
| `payee`, `note` | Merge | text; two different texts is a question (see the correction of the plan's wording above) |
| `transfer_id` | — | not used: a transfer is its own record (D4) |
| `is_correction` | Immutable | a correction is never edited directly (`RecordResource.java:232`) |
| correction intent (local: target and seen balance) | Immutable | D7 |
| `plan_id`, `plan_occurrence_id` | Immutable | set by confirmation; "detached" is derived (a link to a deleted plan reads as no link), so deleting a plan writes no record |
| import fingerprint, occurrence (local; **not on the wire `Record`**) | Immutable | needed to recognise a re-import (ADR-091); see finding F-02 |

**`Transfer`** (`records.proto`) → one local `Transfer` record

| Field | Class | Why |
|---|---|---|
| every field (`id`, both accounts, amounts, currencies, date, title) | Immutable | the server never edits a transfer; delete only. One record, so no leg alone (D4) |

**`Budget`** (`budgets.proto`), id `H(category_id, month, currency)`

| Field | Class | Why |
|---|---|---|
| `category_id`, `month`, `currency` | Immutable | the id |
| `amount_minor` | Merge | two different plans for one slot is a question; delete against edit is the store's conflict |

**`BudgetCarryOverReset`** (`budgets.proto`), random id

| Field | Class | Why |
|---|---|---|
| `id`, `category_id`, `month`, `currency`, `discarded_minor`, `note`, `created_by`, `created_at_ms` | Immutable | an audit entry, never edited (ADR-046); `created_by` is the device id locally |
| `revoked_by`, `revoked_at_ms` | Group (revocation), same-intent rule | revoking twice is the same intent; the earliest time is kept (jZenDev/jZen#235). Two live resets in one slot are an integrity issue (D6) |

**`Goal`** (`goals.proto`)

| Field | Class | Why |
|---|---|---|
| `id`, `currency`, `created_at_ms` | Immutable | the server has no route to change a goal's currency (`UpdateGoalRequest`) |
| `name`, `target_amount_minor`, `target_date` | Merge | each a question of its own |
| `status`, `status_changed_at_ms` | Group (status); same-intent rule on the time | completing on two devices merges; completing on one and archiving on another is a question. Transition legality is re-checked after merge (an archived goal with money is D6) |

**`GoalAllocation`** (`goal_allocations.proto`)

| Field | Class | Why |
|---|---|---|
| every field | Immutable | append-only on the server (trigger); random ids, so two devices' entries never meet. Breaks across entries are D6 |

**`Plan`** (`plans.proto`)

| Field | Class | Why |
|---|---|---|
| `id` | Immutable | |
| `title`, `payee`, `note` | Merge | |
| `account_id`, `currency`, `amount_minor` | Group (`posting`) | the same reason as on a record |
| `category_id` | Merge, plus integrity check | |
| `recurrence` (nested `Recurrence`) | Group (one field already) | a rule is one unit: an interval from one device and an end date from another would be a schedule nobody chose |
| `reminder` (nested `Reminder`) | Group (one field already) | `enabled` and `lead_days` belong together (ADR-054) |

**`PlanOccurrence`** (`plans.proto`), id `H(plan_id, date)`; stored only when it differs from the default

| Field | Class | Why |
|---|---|---|
| `plan_id`, `occurrence_date` | Immutable | the id |
| skipped (local state) | Merge | skip on two devices merges; skip against restore is a question |
| `status` COMPLETED | Derived | completed means a live record with this `plan_occurrence_id` exists; no second write, so record and state cannot disagree |
| `status` OVERDUE | Derived | as on the server |
| reminder read time (local) | Merge, same-intent rule | read on two devices keeps the earliest time |
| `title`, `amount_minor`, `currency`, `account_id`, `category_id` | Derived | copied from the plan on read, as the server does |

**`Settings`** (`settings.proto`), id `settings`

| Field | Class | Why |
|---|---|---|
| `main_currency` | Merge | a label (ADR-009) |
| `default_account_id` (local, moved from `Account.is_default`) | Merge | one field makes "one default" structural |

**`ImportSession`, `ImportRow`** (`imports.proto`)

| Field | Class | Why |
|---|---|---|
| every field | Device | a session holds normalised statement rows for 24 hours and is deleted at its end (ADR-089); syncing it would copy statement text to every device and the sync service for no gain. It lives in a second, unsynced store (fact 8). Only the committed records travel, and two devices committing the same statement converge by D3 |

Messages that are never stored (requests, responses, calculated views) — **no merge question**:
`CreateAccountRequest`, `UpdateAccountRequest`, `ListAccountsResponse`; `CategorySpend`,
`SpendByCategoryResponse`, `PeriodSpend`, `SpendByPeriodResponse`; `SetBudgetRequest`,
`ListBudgetsResponse`, `CategoryBudgetSummary`, `BudgetSummaryResponse`,
`ResetBudgetCarryOverRequest`, `ListBudgetCarryOverResetsResponse`; `CreateCategoryRequest`,
`UpdateCategoryRequest`, `ListCategoriesResponse`; `CreateGoalAllocationRequest`,
`ListGoalAllocationsResponse`, `GoalEnvelope`, `ListGoalEnvelopesResponse`, `CurrencyFreeMoney`,
`GetFreeMoneyResponse`; `CreateGoalRequest`, `UpdateGoalRequest`, `ListGoalsResponse`,
`GoalProgress`, `ListGoalProgressResponse`; `CreateImportSessionRequest`,
`PreviewImportSessionRequest`, `UpdateImportRowRequest`, `UpdateImportRowResponse`,
`SetImportDefaultsRequest`, `CommitImportSessionRequest`, `ListImportSessionsResponse`;
`Recurrence` and `Reminder` (stored only inside `Plan`), `CreatePlanRequest`, `UpdatePlanRequest`,
`ListPlansResponse`, `ListOccurrencesResponse`, `ConfirmOccurrenceRequest`,
`ConfirmOccurrenceResponse`; `ExportProfile`, `DataExport`, `EraseAccountRequest` (see 0.4);
`CreateRecordRequest`, `UpdateRecordRequest`, `ListRecordsResponse`, `CreateTransferRequest`,
`CreateCorrectionRequest`; `DueReminder`, `ListRemindersResponse`; `UpdateSettingsRequest`.

### Is the table honest everywhere?

Yes, with D2–D7 accepted, and with one cost that must be said plainly: **an import made on two
devices with different category choices produces one conflict per differing row**, each settled
one at a time in `zen_ui_store` today (jZenDev/jZen#234 asks for "keep this device's version for all").
Where it would not be honest is option "store the wire protos as they are" (D2 rejected): currency
and amount would merge apart, and every account's currency list would conflict whole. If the person
rejects D2, the narrower fallback the plan names applies: **one writer device** (other devices
read-only, edits refused with a sentence) until the store model is split.

### What the person must decide

1. **Accept the store model of D2–D4** — Local's own store messages, deterministic ids for natural
   keys, a transfer as one record — or keep the wire messages and fall back to one writer device.
   Recommended: accept.
2. **Accept the field classes**, in particular: the posting group (account, currency, amount) on
   records and plans; note, payee and category as plain merge fields that still conflict when both
   devices change the same one; the default account moved into settings. Recommended: accept.
3. **Accept integrity issues (D6) as a second list beside conflicts**, including the correction
   intent of D7 and the same-intent timestamp rule, applied by Prudent until jZen offers it.
   Recommended: accept.

---

## 0.3 Inventory of what the server enforces

**Status: complete after review.** Every `CHECK`, unique index, foreign key with a delete meaning, trigger and
RLS policy in the 22 migrations and `R__prudent_row_level_security.sql`, every refusal
(`PrudentException.invalid/conflict`, 153 call sites) and calculation in
`server/src/main/java/prudent/`, and — added after the review of jlogicsoftware/prudent#249, which
found the record-list rules missing — **every `@QueryParam` of every resource (24 parameters in 11
methods) and every list order** (each `order by` and `Comparator` in the server). Those are the rows
marked "list" below and the block "List, filter and order semantics" after unit 5. File paths are relative to `server/src/main/` (`db/` is
`resources/db/migration/`, the date prefix shortened; `java/` is `java/prudent/`). Plain
`NOT NULL` columns are covered by the "required" rows of each entity, not listed one by one.

"Test" names the local test that will prove the rule and the server test it mirrors; a parity
scenario runs through both implementations (unit 3's harness).

### Unit 3 — domain core (9 rules)

| # | Rule | Where it lives today | Test that will prove it locally |
|---|---|---|---|
| 3.1 | Money is an integer count of minor units, never a float | `db/…prudent_init.sql:50–61`; `Record.amount_minor` int64 | `money_test` golden vectors from Java |
| 3.2 | A currency is ISO-4217 and upper-cased | `java/Currencies.java`; `RecordWriter.java:86`; `CHECK currency = upper(currency)` in `budgets.sql:36`, `carry_over_resets.sql:40`, `goals.sql:34`, `goal_allocations.sql:61`, `import_sessions.sql:55` | `currencies_parity_test` (the Java list exported as a golden file) |
| 3.3 | Nothing is ever summed across currencies | `AnalyticsResource.java:191`; `BudgetResource.java:121`; ADR-008/009 | parity scenario `multi_currency` |
| 3.4 | Dates are ISO-8601 `YYYY-MM-DD` | `RecordWriter.java:137–145`; `TransferResource.java:183`; `CorrectionResource.java:179`; `RecurrenceRule.java:237` | `dates_test` |
| 3.5 | A month is `YYYY-MM`, stored as its first day | `BudgetResource.java:325–331`; `budgets.sql:34`; `carry_over_resets.sql:39` | `months_test` |
| 3.6 | Account number normalisation: white space removed, root-locale upper case, 10–34 of `A-Z0-9`, Polish prefix handling, identity digest | `AccountNumbers.java:41–125`; `account_number.sql:25` | `account_numbers_parity_test` (golden vectors, mirrors `AccountNumberTest`) |
| 3.7 | Text is trimmed; blank required text refused; blank optional text becomes absent | `RecordWriter.java:43,97,124` (and each entity, units 5–6) | `text_rules_test` |
| 3.8 | A note is at most 500 **characters** | `carry_over_resets.sql:41`; `goal_allocations.sql:62`; `import_commit.sql:36`; `GoalAllocationResource.java:51` | `text_rules_test` with astral characters (finding F-04) |
| 3.9 | Ids are minted by the server; a client-sent id is not identity | `java/Ids.java:62–67` | changes meaning: device-minted or derived (0.2 D3); `ids_test` in unit 4 |

### Unit 4 — store model and merge (new obligations, not server rules)

| # | Obligation | Source | Test |
|---|---|---|---|
| 4.1 | Store messages and the mapper to wire messages (0.2 D2) | 0.2 | `store_mapping_test`: every wire message round-trips |
| 4.2 | Deterministic ids for every natural key (0.2 D3) | the natural keys of rows 5.4, 5.8, 5.43, 5.44, 6.1, 6.35, 6.39, 8.11 | `two_devices_test`: both devices create the same slot, one record results |
| 4.3 | The integrity check runner (0.2 D6), each unit adding its checks | none — **no unit in the plan owns it** (finding F-05) | `integrity_test` per rule |
| 4.4 | Same-intent timestamp rule (0.2) | none | `two_devices_test` |

### Unit 5 — ledger: accounts, records, transfers, corrections, categories, settings (53 rules)

Categories are here, not in unit 6 as the plan says: a record cannot be written without its
category's kind and archived checks (finding F-01).

| # | Rule | Where it lives today | Test |
|---|---|---|---|
| 5.1 | An account needs a name | `AccountResource.java:258` | `accounts_test` (mirrors `AccountResourceTest`) |
| 5.2 | An account needs a type; `UNSPECIFIED` is refused | `AccountResource.java:265` | `accounts_test` |
| 5.3 | An account holds at least one currency | `AccountResource.java:341` | `accounts_test` |
| 5.4 | Each currency once per account, ISO-4217 | `AccountResource.java:350,355`; unique `init.sql:69` | `accounts_test`; deterministic id (4.2) |
| 5.5 | The declared order of an account's currencies is kept | `init.sql:64`; `AccountEntity.java:127` | `accounts_test` |
| 5.6 | A currency with records cannot be dropped | `AccountResource.java:367` | `accounts_test`; integrity check after merge |
| 5.7 | A currency with plans cannot be dropped | `AccountResource.java:375` | `accounts_test`; integrity check |
| 5.8 | At most one default account | `AccountEntity.java:174` | settings field (0.2); `two_devices_test` |
| 5.9 | An account number is unique per person | `AccountResource.java:288,306`; unique `account_number.sql:27` | `accounts_test`; integrity check |
| 5.10 | An account with records cannot be deleted (no cascade) | `AccountResource.java:200`; FK `init.sql:113` | `accounts_test` |
| 5.11 | An account with plans cannot be deleted | `AccountResource.java:210`; FK `plans.sql:24` | `accounts_test` |
| 5.12 | Delete with records removes every record, both legs of a transfer, and reopens confirmed occurrences | `AccountResource.java:172`; `RecordEntity.java:268`; ADR-081 | `account_delete_test` (mirrors `AccountResourceTest`); orphan integrity check |
| 5.13 | `eligible_for_goals` is off by default | `account_goal_eligibility.sql:15` | `accounts_test` |
| 5.14 | Balance = opening + net of records per currency, derived | `AccountMapper.java:86`; `RecordEntity.java:332,544`; ADR-014 | parity scenario `balances` |
| 5.15 | A record needs a title | `RecordWriter.java:43` | `records_test` |
| 5.16 | A record's amount is nonzero; the sign is its direction | `RecordWriter.java:52` | `records_test` |
| 5.17 | A record's account and category are the person's | `RecordWriter.java:62,68` | `records_test` |
| 5.18 | The account holds the record's currency | `RecordWriter.java:92` | `records_test`; integrity check |
| 5.19 | The category's kind accepts the record's sign | `CategoryEntity.java:76–89` | `records_test`; integrity check |
| 5.20 | An archived category takes no new record | `CategoryEntity.java:103–106` | `records_test` |
| 5.21 | A transfer leg is not edited directly | `RecordResource.java:217–221` | structural (transfer is immutable, 0.2 D4) |
| 5.22 | A correction is not edited directly | `RecordResource.java:232–236` | `records_test` |
| 5.23 | A record's date is a valid date | `RecordWriter.java:137` | `records_test` |
| 5.24 | Deletes are hard; no soft delete | `init.sql:125–128` | `records_test` (a deleted record is in no figure) |
| 5.25 | Plan link: both ids or neither | `CHECK record_plan_link.sql:21` | `records_test` |
| 5.26 | Deleting a confirming record reopens its occurrence | `RecordResource.java:193` | structural (completion is derived, 0.2) |
| 5.27 | A transfer's amounts are positive | `TransferResource.java:78,81` | `transfers_test` |
| 5.28 | A transfer needs two different accounts, both the person's | `TransferResource.java:87,92,95` | `transfers_test` |
| 5.29 | Each side's account holds its currency | `TransferResource.java:104,115` | `transfers_test` |
| 5.30 | A transfer is two legs written together, with no category | `transfers.sql:9–15`; `TransferResource.java:74` | one record (0.2 D4); parity scenario `transfer` |
| 5.31 | Deleting a transfer deletes both legs | `TransferResource.java:163` | `transfers_test` |
| 5.32 | A transfer's date is valid | `TransferResource.java:183` | `transfers_test` |
| 5.33 | A correction is the delta from the current derived balance | `CorrectionResource.java:95–110` | parity scenario `correction` |
| 5.34 | A correction that changes nothing is refused | `CorrectionResource.java:115` | `corrections_test` (mirrors `CorrectionResourceTest`) |
| 5.35 | A correction's account is the person's and holds the currency | `CorrectionResource.java:81–91` | `corrections_test` |
| 5.36 | A correction's default title | `CorrectionResource.java:118–121` | `corrections_test` |
| 5.37 | A correction is marked as such | `corrections.sql:8` | `corrections_test` |
| 5.38 | A category needs a title | `CategoryResource.java:266` | `categories_test` (mirrors `CategoryResourceTest`) |
| 5.39 | A category's icon is from the permitted set | `CategoryResource.java:268`; `IconKeys` | `categories_test` |
| 5.40 | A category's kind is 0, 1 or 2 | `CategoryResource.java:273`; `CHECK category_kind.sql:10` | `categories_test` |
| 5.41 | Archive only what is active; restore only what is archived | `CategoryResource.java:168,191` | `categories_test` (mirrors `CategoryLifecycleTest`) |
| 5.42 | A category with records, plans, budgets or resets cannot be deleted | `CategoryResource.java:220–242`; FKs `init.sql:110`, `plans.sql:25`, `budgets.sql:21`, `carry_over_resets.sql:25` | `categories_test`; integrity check |
| 5.43 | Starter categories are seeded once | `NewUserSetup.java:88` | `first_run_test` (first device only, deterministic ids) |
| 5.44 | One settings record; its main currency defaults and is ISO-4217 | `init.sql:147`; `NewUserSetup.java:81`; `SettingsResource.java:82` | `settings_test` |
| 5.45 | The main currency is a label, not checked against accounts | `SettingsResource.java:84`; ADR-009 | `settings_test` |
| 5.46 | list — record filters `dateFrom`/`dateTo` (inclusive), `accountId`, `categoryId`; malformed dates or ids refused | `RecordResource.java:72–75,245–270`; `RecordEntity.java:486–515` | parity scenario `record_list_filters` |
| 5.47 | list — `type`: expense = negative, no transfer, not a correction; income = the positive counterpart; transfer = any transfer leg; correction = any correction. Trimmed, case-insensitive; an unknown type refused | `RecordType.java:24–35`; `RecordEntity.java:516–524` | `record_list_filters` |
| 5.48 | list — `amountMin`/`amountMax` compare `abs(amount)`, inclusive, in any currency; a negative bound refused | `RecordResource.java:77–78,273–276`; `RecordEntity.java:525–532` | `record_list_filters` |
| 5.49 | list — `search`: blank ignored (`String.isBlank`); otherwise trimmed (`String.trim`), folded by the simple per-code-point lower-case rule, and matched as a plain substring of the folded title, payee or note; `%`, `_`, `\` are ordinary characters | `TextRules.java`; `RecordEntity.search` (was SQL `LIKE`, `RecordEntity.java:533–538`) | `search-vectors.json` (unit 4a, ADR-106); `record_list_filters` (finding F-09, fixed) |
| 5.50 | list — records ordered `date desc, id` | `RecordEntity.java:196,539` | `record_list_order` (finding F-11) |
| 5.51 | list — accounts ordered by `TextRules.compareNames` (folded primary weights with Polish and Ukrainian letters placed in their alphabets, then exact code points, then id text) | `AccountEntity.listOwnedBy` (was `order by name`, `AccountEntity.java:132`) | `name-order-vectors.json` (unit 4a, ADR-106); `accounts_test` (finding F-10, fixed) |
| 5.52 | list — categories ordered by `TextRules.compareNames` | `CategoryEntity.listOwnedBy` (was `order by title`, `CategoryEntity.java:112`) | `name-order-vectors.json` (unit 4a, ADR-106); `categories_test` (finding F-10, fixed) |
| 5.53 | list — `deleteRecords` defaults to false (the refusal stands) | `AccountResource.java:180–182` | `account_delete_test` |

#### List, filter and order semantics (units 5 and 6)

The shared screens rely on what the server's list routes return, so the local repository answers the
same requests with the same rows in the same order. Three things need saying because the local model
differs (ADR-102):

- **A transfer is one record, listed as two legs.** The local `listRecords` first expands every transfer
  into its two derived leg `Record`s (ids `H(transfer_id, "from")`, `H(transfer_id, "to")`, no category,
  no payee or note), then applies every filter to each leg exactly as the server applies it to each row.
  So `type=transfer` returns both legs; with `accountId` only the leg on that account; `amountMin`/`amountMax`
  test each leg's own `abs(amount)`, so a cross-currency transfer of 100.00 PLN to 23.00 EUR can match one
  leg and not the other, as on the server; `categoryId` and `type=expense`/`income` never match a leg;
  `search` sees the shared title only. Filtering the transfer record as a whole would silently disagree.
- **The `id` tie-break.** Within one date the server orders by `id`, which in Postgres compares UUIDs
  byte by byte — the same order as their lower-case hex text. Locally ids are lower-case 32-hex strings
  compared as text, which is that same order, and every device holds the same ids, so every device shows
  the same order. Server and Local mint different ids, so **order within a date is not a parity property**:
  the parity suite compares rows by date order and, within a date, as a set. Ids carried over from the
  server (0.4) are normalised to 32 lower-case hex characters (dashes removed) so text order stays byte
  order. Two server routes tie-break with Java's `UUID.compareTo`, which compares signed halves and is a
  different order (`OccurrenceResource.java:302`, `ReminderResource.java:192`; finding F-11).
- **Name order is a stated rule (ADR-106).** Accounts, categories and free-money accounts were ordered by
  the database's default collation, which no migration pins; Dart's `compareTo` orders by UTF-16 code unit,
  and Polish and Ukrainian names differ (finding F-10). Unit 4a replaced it with `TextRules.compareNames`,
  which Dart reproduces from `name-order-vectors.json`.

Parity scenarios: **`record_list_filters`** (ordinary records, a correction, a cross-currency transfer
with different amounts on each side; each filter alone and combined; compared as multisets of (date,
kind, account, amount, currency, title) in date order) and **`record_list_order`**; **`goal_lists`** and
**`budget_lists`** for unit 6's rows 6.46–6.54.

### Unit 6 — budgets, resets, goals, allocations, plans, occurrences, reminders (54 rules)

| # | Rule | Where it lives today | Test |
|---|---|---|---|
| 6.1 | One budget per category, month and currency | unique `budgets.sql:29` | deterministic id; `budgets_test` (mirrors `BudgetSchemaTest`) |
| 6.2 | A budget amount is positive; no budget is a delete | `BudgetResource.java:242`; `CHECK budgets.sql:33` | `budgets_test` |
| 6.3 | A budget month is a first day | `CHECK budgets.sql:34` | `budgets_test` |
| 6.4 | A new budget slot refuses an archived category | `CategoryEntity.java:103` via `BudgetResource` | `budgets_test` |
| 6.5 | Actual = net spending from posted records, refunds included | `BudgetCalculator.java:45`; ADR-044 | parity scenario `budget_summary` (mirrors `BudgetSummaryTest`) |
| 6.6 | Carry-over = Σ (plan − actual) over earlier budgeted months, through months with no budget | `BudgetCalculator.java:103–138`; ADR-045 | parity scenario `carry_over` |
| 6.7 | Remaining includes carry-over | `BudgetCalculator.java:45–100` | parity scenario `carry_over` |
| 6.8 | A reset's month is a first day, its currency upper-case, its note ≤ 500 | `CHECK carry_over_resets.sql:39–41`; `BudgetCarryOverResetResource.java:122` | `resets_test` (mirrors `BudgetCarryOverResetTest`) |
| 6.9 | One live reset per slot | unique partial `carry_over_resets.sql:50`; resource `:137` | integrity check (random ids); `resets_test` |
| 6.10 | A reset is revoked once; revocation is whole | `CHECK carry_over_resets.sql:43`; resource `:184` | `resets_test` |
| 6.11 | A reset is never deleted | no route; `CategoryResource.java:240` | structural (no delete in the local repository) |
| 6.12 | The carry-over sum stops at a live reset and records what it discarded | `BudgetCalculator.java:141`; resource `:133` | parity scenario `carry_over_reset` |
| 6.13 | A goal's name is not blank, its target positive, its currency upper-case, its status known | `CHECK goals.sql:31–35`; `GoalResource.java:269–285` | `goals_test` (mirrors `GoalSchemaTest`) |
| 6.14 | Goal transitions: active ↔ completed, either → archived, archived → active | `GoalState.java:37–39`; `GoalEntity.java:71` | `goals_test` |
| 6.15 | An archived goal is read-only | `GoalResource.java:170` | `goals_test` |
| 6.16 | A goal holding money cannot be archived | `GoalResource.java:247` | `goals_test`; integrity check |
| 6.17 | A goal is never deleted | no route | structural |
| 6.18 | A goal's currency never changes | `UpdateGoalRequest` has none | structural (immutable field) |
| 6.19 | Entry shape: allocate has a target only, withdraw a source only, move both and different | `CHECK goal_allocations.sql:54–59`; `GoalAllocationResource.java:183,293,298,310` | `allocations_test` (mirrors `GoalAllocationTest`) |
| 6.20 | An entry's amount is positive, its note ≤ 500 | `CHECK goal_allocations.sql:60–62`; resource `:170,174` | `allocations_test` |
| 6.21 | An entry's currency is its goals' currency | composite FKs `goal_allocations.sql:47–50`; resource `:203` | `allocations_test` |
| 6.22 | Entries are append-only | trigger `goal_allocations.sql:72–82` | structural (immutable records) |
| 6.23 | Money goes into an active goal and out of an active or completed one | resource `:208,213` | `allocations_test`; integrity check |
| 6.24 | An envelope never goes below zero | resource `:218` | `allocations_test`; integrity check |
| 6.25 | An envelope cannot overflow | resource `:225` | `allocations_test` |
| 6.26 | An allocation is at most the free money | resource `:234` | `allocations_test` (at write time only; after merge free money may be negative, ADR-051) |
| 6.27 | Free money = balances of active eligible accounts − envelopes, per currency, may be negative | `FreeMoney.java:61–111`; ADR-051 | parity scenario `free_money` (mirrors `GoalFreeMoneyTest`) |
| 6.28 | Progress: whole percent rounded down; monthly contribution rounded up over inclusive months; guidance reasons | `GoalProgressCalculator.java:49–105`; ADR-052 | parity scenario `goal_progress` (mirrors `GoalProgressTest`) |
| 6.29 | A plan needs a title, a nonzero amount, its account and category, a held currency | `PlanResource.java:187–221` | `plans_test` (mirrors `PlanResourceTest`) |
| 6.30 | Recurrence invariants: interval 1–1000, count 1–10000, one end, end not before start, once is single | `CHECK plans.sql:50–58`; `RecurrenceRule.java:60–92` | `recurrence_test` (mirrors `PlanSchemaTest`) |
| 6.31 | An explicit IANA time zone, no fixed offset | `RecurrenceRule.java:140–144` | `recurrence_test` |
| 6.32 | Reminder lead is 0, 1, 2, 3 or 7 days; off by default; kept when off; absent resets it | `ReminderSetting.java:30–56`; `CHECK plan_reminders.sql:22` (0–365, wider) | `plans_test` (mirrors `PlanReminderSchemaTest`) |
| 6.33 | A plan is replaced whole on update | `PlanResource.java:116` | `plans_test` |
| 6.34 | Deleting a plan detaches its records and deletes its occurrences | `PlanResource.java:143–155`; `RecordEntity.java:244` | structural (detached is derived, 0.2) |
| 6.35 | One occurrence per plan and date | unique `plan_occurrences.sql:27` | deterministic id |
| 6.36 | Generation is idempotent and bounded (≤ 3660 days) | `OccurrenceGenerator.java:42,67–75,101` | `occurrences_test` |
| 6.37 | Occurrence transitions: planned → skipped/completed, skipped → planned, completed → none (except by deleting its record) | `OccurrenceState.java:38–47`; `PlanOccurrenceEntity.java:85,105` | `occurrences_test` (mirrors `OccurrenceResourceTest`) |
| 6.38 | Overdue is derived: planned and past | `OccurrenceResource` | parity scenario `occurrences` |
| 6.39 | Confirming creates exactly one record carrying both plan ids; a double confirm cannot make two | `OccurrenceResource.java:190–205`; unique `record_plan_link.sql:29` | deterministic id; `confirm_test` (mirrors `OccurrenceConfirmationTest`) |
| 6.40 | Confirmation overrides are validated as a record | `OccurrenceResource.java:190–230` | `confirm_test` |
| 6.41 | The upcoming horizon is bounded (the window itself is 6.51) | `OccurrenceResource.java:105` | `occurrences_test` |
| 6.42 | A reminder is due for a planned occurrence of a plan whose reminder is on, within the lead or past, in the plan's own calendar day | `ReminderResource.java`; ADR-055 | parity scenario `reminders` |
| 6.43 | Read/unread/read-all; a reminder ends on confirm or skip | `ReminderResource.java:151`; `occurrence_reminder_read.sql:17` | `reminders_test` |
| 6.44 | Notifications: next 30 days, 09:00 device time, no amount, reconciled | `client/lib/notification/` (already client-side, ADR-056/057) | moves with the shared package; existing client suite |
| 6.45 | The goal "today" defaults to the server's UTC date | `GoalResource.java:305`; ADR-052 | parity pins `asOf` (finding F-07) |
| 6.46 | list — goals by `status` (exact constant name, an unknown one refused), ordered `created_at, id` | `GoalResource.java:68–69,308–316`; `GoalEntity.java:86–88` | parity scenario `goal_lists` |
| 6.47 | list — envelope history by `goalId` (as source or target; a malformed id refused), ordered `created_at desc, id` | `GoalAllocationResource.java:69–70`; `GoalAllocationEntity.java:83–86` | `goal_lists` |
| 6.48 | list — budgets by optional `month` and `categoryId`, ordered month, currency, category | `BudgetResource.java:86–92`; `BudgetEntity.java:120–148` | parity scenario `budget_lists` |
| 6.49 | list — the budget summary needs `month` and `currency` | `BudgetResource.java:115–122` | `budget_lists` |
| 6.50 | list — reset history by optional `categoryId` and `currency`, ordered `created_at desc, id` | `BudgetCarryOverResetResource.java:75–83`; `BudgetCarryResetEntity.java:153` | `budget_lists` |
| 6.51 | list — upcoming: `days` defaults to 30, 1–366, today through today + days inclusive; overdue is its own route; ordered date, id | `OccurrenceResource.java:74–77,102–106,286–303` | parity scenario `occurrences` (finding F-11) |
| 6.52 | list — due reminders ordered by occurrence date, id | `ReminderResource.java:192` | `reminders_test` (finding F-11) |
| 6.53 | list — plans ordered `start_date, id`; a plan's occurrences by date | `PlanEntity.java:122`; `PlanOccurrenceEntity.java:113,148,160` | `plans_test` |
| 6.54 | list — free-money accounts ordered by `TextRules.compareNames` (which ends in id text) | `FreeMoney.calculate` (was `Comparator` on `String.compareTo`, i.e. UTF-16 order, not the database's; `FreeMoney.java:72`) | `name-order-vectors.json` (unit 4a, ADR-106); `free_money` (finding F-10, fixed) |

### Unit 7 — analytics (4 rules)

| # | Rule | Where it lives today | Test |
|---|---|---|---|
| 7.1 | Spend by category for a year or a month, one currency | `AnalyticsResource.java:78–85`; `RecordEntity.java:379–409` | parity scenario `analytics_large` (mirrors `AnalyticsResourceTest`) |
| 7.2 | Spend by period: count 1–60, month or year | `AnalyticsResource.java:141,205` | same |
| 7.3 | Transfer legs and corrections are not spending | `RecordEntity.java:381–383` | same |
| 7.4 | Planned cash flow per currency, apart from balances | `client/lib/overview/planned_cash_flow.dart` (client-side, ADR-042) | moves with the shared package; reads occurrences from the local repository |

### Unit 8 — Erste statement import (25 rules; row 8.6 alone is 44 rule codes and ~220 catalogue cases)

| # | Rule | Where it lives today | Test |
|---|---|---|---|
| 8.1 | Three phases and their transitions (parsed → previewed (→ previewed) → committed; discarded; expired) | `CHECK import_sessions.sql:49`; `ImportWorkflow.java:179–261` | `import_workflow_test` |
| 8.2 | A statement is read once and never stored | `ImportWorkflow.java:93–120`; ADR-089 | `import_workflow_test` (no file bytes in either store) |
| 8.3 | A session expires after 24 hours; a read ends an overdue one; a sweep deletes the rest | `ImportWorkflow.java:86,133,393` | `import_expiry_test` (sweep at launch and on a timer) |
| 8.4 | Bounds: empty or oversized upload, row count, open sessions ≤ 10, field length, list size | `ImportWorkflow.java:68–101`; `ImportSessionResource.java:81` | catalogue cases |
| 8.5 | Destination: the person's, active, holding the currency, accepted by the importer's identity check, at preview and again at commit | `ImportWorkflow.java:458–505` | catalogue cases |
| 8.6 | The whole file is validated before any row (44 rule codes) | `ErsteStatementImporter.java`; `ErsteCsv.java`; `ParsedStatements.java`; ADR-090/094 | `ImportFailureCatalogue` ported; `import_failure_matrix_test` |
| 8.7 | An own-account transfer becomes a plain record with `transfer.own_account` | `ErsteStatementImporter.java`; ADR-092 | catalogue case |
| 8.8 | A moved amount column is refused whole (`layout.amount_column`) | `ErsteStatementImporter.java`; ADR-094 | catalogue case |
| 8.9 | Fingerprint: versioned SHA-256 of the row's fields plus an occurrence number | `RowFingerprints.java:108–178`; `CHECK import_fingerprints.sql:28–38` | `fingerprints_parity_test` (golden vectors) |
| 8.10 | Duplicates are rows whose key a record of the destination already holds | `ImportDuplicateStage.java:37–79` | `import_duplicates_test` |
| 8.11 | One record per (account, fingerprint, occurrence) | unique `import_fingerprints.sql:59`; shape `:43–49` | deterministic id; `two_device_import_test` |
| 8.12 | Row decisions: category, note ≤ 500, include only a duplicate, rejected rows unchangeable | `ImportWorkflow.java:300–377`; `CHECK import_commit.sql:30–40` | `import_rows_test` |
| 8.13 | Defaults per direction only while open | `CHECK import_commit.sql:57`; `ImportWorkflow.java` | `import_rows_test` |
| 8.14 | Every accepted row has a category at commit | `ImportWorkflow.java:254–261` | `import_commit_test` |
| 8.15 | The commit names the accepted count it confirms | `ImportWorkflow.java:242–247` | `import_commit_test` |
| 8.16 | One transaction, account locked, ordinary records through the record writer | `LedgerImportCommitter.java:54–172`; ADR-092 | `import_commit_test` — **locally all-or-nothing needs jZenDev/jZen#232; until then an idempotent, resumable commit (D3 ids) and a validation pass before the first write** |
| 8.17 | A repeated commit answers the stored counts | `CHECK import_commit.sql:48–55` | `import_commit_test` |
| 8.18 | Failures between preview and commit have rule codes | `LedgerImportCommitter.java:144,172`; ADR-094 | `ImportCommitFailureTest` ported |
| 8.19 | Rows are deleted when a session ends | `ImportWorkflow.java:393–425` | `import_expiry_test` |
| 8.20 | Row invariants: number positive and unique, writable rows complete, code iff rejected, amount nonzero | `CHECK import_sessions.sql:86–96` | `import_rows_test` |
| 8.21 | The statement identity is a 64-hex digest, kept only while open | `CHECK import_sessions.sql:51` | `import_workflow_test` |
| 8.22 | No statement text in an answer or a log line | `ImportRejectedException.java`; ADR-094 | `import_logging_test` (mirrors `ImportKeyLoggingTest`) |
| 8.23 | The bank's sequence number is not an identifier for Erste | `StatementImporter.java` (`stableExternalId`) | `fingerprints_parity_test` |
| 8.24 | list — sessions by `state` (exact name, an unknown one refused), `limit` 1–100 defaulting to 50, ordered `created_at desc, id` | `ImportSessionResource.java:73–81,338–345`; `ImportSessionEntity.java:157–182` | `import_workflow_test` |
| 8.25 | An unknown format id is refused without echoing it; formats are listed sorted | `ImportFormats.java:64,76–82` | `import_failure_matrix_test` |

### Unit 9 — the application (5 rules)

| # | Rule | Where it lives today | Test |
|---|---|---|---|
| 9.1 | A copy of every row the person owns, in any state | `PrudentDataExporter.java`; ADR-071 | `data_copy_test` (every collection appears; mirrors `PrivacyCoverageTest`) |
| 9.2 | Erasure deletes everything the person owns | `PrudentDataEraser.java`; ADR-071 | `erase_test` — "this device" only; "everywhere" needs jZenDev/jZen#239 |
| 9.3 | Erasure must be confirmed deliberately (the address repeated) | `PrivacyResource.java:104` | `erase_test` (a typed phrase, as `DeleteAccountForm`) |
| 9.4 | A failure is logged as one line without data | `UnhandledExceptionMapper.java`; ADR-072 | `logging_test` |
| 9.5 | list — the export lists rows in a stable order (`created_at, id` where there is one) | `PrudentDataExporter.java:127` | `data_copy_test` |

### No local owner

By design (recorded so they are not mistaken for gaps):

| # | Rule | Where it lives today | Why it has no local meaning |
|---|---|---|---|
| X.1 | Row-level security on every table, one application policy each | `init.sql:171–175` and each migration's `ENABLE ROW LEVEL SECURITY`; `R__prudent_row_level_security.sql:85–108` | one person per store; the store's encryption is the boundary |
| X.2 | Every query filtered by `user_id` (`findOwned`, `listOwnedBy`) | e.g. `RecordEntity.java:195,204` | as X.1 |
| X.3 | Operator erasure | `OperatorErasureResource.java` | there is no operator |
| X.4 | Dormancy warnings and erasure | `DormancyWarningMailer.java`; `java/retention/` | there is no account to go dormant |
| X.5 | Sign-in record deletion | `SignInRecordEraser.java` | there is no sign-in |
| X.6 | Readiness, request ids | `HealthResource.java`; `RequestIdFilter` | there is no request |
| X.7 | Row locks (`FOR UPDATE` on goals, the import's account, a confirmed occurrence) | `GoalEntity.java:102,131`; `LedgerImportCommitter.java`; `OccurrenceResource.java:192` | on one device the store serialises writes; across devices the answer is 0.2 (ids, integrity checks), not a lock |

### Findings

- **F-01 — Categories belong to unit 5, not unit 6.** Rows 5.17, 5.19, 5.20 refuse a record by its
  category's kind and archived flag; unit 5 cannot finish without categories.
- **F-02 — The wire `Record` has no import fingerprint.** `prudent_record.import_fingerprint` and
  `import_occurrence` exist (`import_fingerprints.sql:40–49`) but `records.proto` carries neither,
  so a store that kept only the wire message, and every privacy export, loses what recognises a
  re-imported statement (affects 0.4).
- **F-03 — The wire `Account.balances` is the derived current balance** (`AccountMapper.java:86`),
  not the stored opening amount, so it cannot be stored as it arrives and an export's balances must
  be turned back into openings (affects 0.2 D2 and 0.4).
- **F-04 — "500 characters" is counted differently.** Postgres `char_length` counts code points;
  Dart `String.length` counts UTF-16 units, so a note with emoji the server accepts the local code
  would refuse. Unit 3 counts runes.
- **F-05 — No unit owns the integrity checks (0.2 D6).** Thirteen rules here (5.6, 5.7, 5.9, 5.18,
  5.19, 5.42, 6.9, 6.16, 6.23, 6.24, and the dangling references behind 5.10, 5.11, 5.12) can be
  broken by a merge and are not caught by any write-time check. Unit 4 should own the runner.
- **F-06 — Atomic writes.** Rows 5.12, 5.30 and 8.16 are one transaction on the server; `zen_store`
  has no multi-record write (jZenDev/jZen#232). 5.30 is solved by modelling (0.2 D4); 5.12 and 8.16 are not.
- **F-07 — "Today" differs.** The server's goal and reminder "today" is UTC or the plan's zone; the
  device's is local. The parity suite must pass `asOf` explicitly or it will fail near midnight.
- **F-08 — Reminder lead days are narrower in Java than in the schema** (`{0,1,2,3,7}` against
  `0–365`). Locally the Java set is the rule; the schema's range is irrelevant.
- **F-09 — The record search is a SQL `LIKE` whose wildcards are not escaped** (`RecordEntity.java:533–538`):
  a `%` or `_` the person types matches anything, and `lower()` follows the database's locale while
  Dart's `toLowerCase` does not. Local cannot copy this faithfully and should not; the server should
  escape the pattern (its own small change and ADR) and both then do a plain case-insensitive
  substring. **Resolved by unit 4a (ADR-106):** the server now applies the match in Java by a fixed rule
  (`TextRules`), with expected behaviour in `server/src/test/resources/text-rules/search-vectors.json`;
  unit 5 implements the same rule in Dart and reads that file.
- **F-10 — Name order is the database's unpinned collation** (accounts, categories, free-money
  accounts). Owner: units 5 and 6a: pin one collation on both sides (or compare names in parity by a
  stated rule) before the parity suite covers lists. **Resolved by unit 4a (ADR-106):** a stated rule,
  `TextRules.compareNames`, applied in Java to all three lists (the free-money list was in fact
  `String.compareTo`, not the database's order), with expected behaviour in
  `server/src/test/resources/text-rules/name-order-vectors.json`; units 5 and 6a implement it in Dart and
  read that file.
- **F-11 — Three id orders.** Postgres orders UUIDs by bytes (= lower-case hex text, which is Local's
  order); Java's `UUID.compareTo` (used at `OccurrenceResource.java:302` and `ReminderResource.java:192`)
  compares signed halves. Ids differ between server and Local anyway, so order within one date is
  compared as a set; Local uses text order everywhere. Owner: unit 3 (id rules), unit 6b (the two
  routes).

### Counts, and whether units 6 and 8 must split

| Unit | Rules | Server code it ports (lines, `java/prudent/`) |
|---|---|---|
| 3 | 9 | ~300 (Currencies, AccountNumbers, Ids, parsing helpers) |
| 4 | 4 obligations (no server rule) | — |
| 5 | 53 | ~3,200 (account, record, category, settings) |
| 6 | 54 | ~4,400 (budget 1,079, goal 1,386, plan 1,909) |
| 7 | 4 | ~200 |
| 8 | 25 rows, 44 rule codes, ~220 catalogue cases | ~3,250 |
| 9 | 5 | ~800 (privacy) |
| none | 7 by design | — |

**Recommendation: split both.** Unit 6 into **6a — budgets, resets, goals, allocations** (34
rules: 6.1–6.28, 6.46–6.50, 6.54; three calculators, the most integrity checks) and **6b — plans, occurrences, reminders**
(20 rules: 6.29–6.45, 6.51–6.53; a state machine and time-zone arithmetic). Unit 8 into **8a — the Erste parser and
fingerprints** (pure functions: rows 8.6–8.9, 8.20–8.23, 8.25, the whole failure catalogue) and **8b —
sessions, duplicates, commit and the two-device import** (8.1–8.5, 8.10–8.19, 8.24).

---

## 0.4 Moving existing data

**Status: decided — ADR-103** (every recommendation below accepted as proposed). The analysis is kept as it was put to the person.

### What exists

`GET /api/v1/privacy/export` answers one `DataExport` (`privacy.proto`): profile, settings, every
account, category, record, plan, occurrence, budget, reset, goal, envelope entry and import
session/row, in any lifecycle state, as canonical proto3 JSON; the client copies it **to the
clipboard** (ADR-071), because no file save existed when it was built.

### The options

| | A. Fresh start | B. One-time import of the export into an empty Local store | C. Ongoing bridge |
|---|---|---|---|
| Effort | none (a sentence in the app and the docs) | unit 10, medium | large; rejected: two sources of truth for one ledger |
| Ids | — | server UUIDs kept, so links survive | — |
| Risk | the person re-enters everything or keeps both apps | the export's gaps below | — |

### What an import must repair (B)

0. **Ids** are kept, normalised to 32 lower-case hex characters so their text order stays the
   server's byte order (§0.3, list semantics).
1. **Opening amounts** (F-03): an exported account balance is the current derived balance; the
   opening amount is `exported balance − Σ exported records` per account and currency. This makes
   the strongest check available: after the import, every derived Local balance must equal the
   exported balance **to the cent**, or the import is refused and nothing is kept.
2. **Transfers**: two exported legs with one `transfer_id` become one transfer record (0.2 D4); a
   transfer with one leg missing is refused (it cannot happen in a consistent export).
3. **Corrections**: the export carries the delta only; the intent fields of 0.2 D7 are filled from
   the balance before it, computed at import.
4. **Occurrences** get `H(plan_id, date)` ids; each record's `plan_occurrence_id` is remapped.
5. **Budgets** get their slot ids; the default account moves into settings.
6. **Import fingerprints are not in the export** (F-02). Without them, importing a statement that
   was already imported on the server is not recognised and writes every row a second time.
   Either the server adds the two fields to the export (a contract change: `records.proto` or a
   separate list in `DataExport`, its own ADR), or the person is told that statements imported
   before the move are not recognised.
7. **Dropped on purpose:** the profile (Local has no account), open import sessions and rows
   (device-local and transient), reminder-read times (not in the export), archive times (the export
   has a boolean).
8. **Refused:** an unknown `format_version`; a store that is not empty (merging two histories has
   no identity story); a file that fails to parse (nothing kept).

### Getting the file across

The export is a plaintext copy of a person's finances. The clipboard reaches clipboard managers,
Universal Clipboard and Windows' cloud clipboard history; it is the wrong channel for moving a
ledger (ADR-100, row T14). So B also needs **"Save to a file"** in the server-connected app
(`file_selector`'s save location on desktop, the share sheet on mobile) and **"Open a file"** in the
Local app, with a warning on both sides that the file is not encrypted and should be deleted after.
The server account is **not** erased by the move; the app says how to do it after the person has
checked the figures.

### Recommendation

**B**, gated as above: empty store only, every balance checked to the cent, refused whole on any
mismatch, file rather than clipboard, and the fingerprints added to the export first (a small
server change, contract-first) so that statement re-imports stay safe.

### What the person must decide

1. **B (one-time import) or A (fresh start)?** Recommended: B.
2. **Add the import fingerprints to the export** (a server contract change before unit 10), or
   accept that statements imported before the move are not recognised. Recommended: add them.
3. **A file save in the server-connected app** (new in `client/`), or keep the clipboard for this
   one path with a warning. Recommended: file.

---

## 0.5 Threat model

**Status: decided — ADR-100 in `docs/DECISIONS.md`.** The refuse/warn list and the jZen
dependencies are there; it is reviewed again before unit 9 lands.

---

## jZen limitations met (filed as jZenDev/jZen#232–#240)

Nothing below is patched around in Prudent. Each is filed in jZenDev/jZen and has a row in
`docs/jzen/README.md`.

| # | Package | Limitation | Why it matters to Prudent | Acceptance test |
|---|---|---|---|---|
| J1 ([#232](https://github.com/jZenDev/jZen/issues/232)) | `zen_store` | No multi-record write; each `put` persists one shard, so two writes can be half-done after a crash | A ledger has one-transaction operations: an account deleted with its records (ADR-081), a statement import commit (ADR-092) | `writeAll` over records in different shards; a crash injected between shard renames leaves either all or none on reopen |
| J2 ([#233](https://github.com/jZenDev/jZen/issues/233)) | `zen_ui_store` | Only per-record field conflicts are shown; an application cannot list its own cross-record "integrity issues" beside them | Every rule across records (envelope below zero, a record on a deleted account) must be shown where conflicts are, with actions | an app-supplied issue appears in the conflict banner count and list, with its own actions, in en/uk |
| J3 ([#234](https://github.com/jZenDev/jZen/issues/234)) | `zen_ui_store` | Conflicts are settled one record at a time | One statement imported on two devices with different categories yields one conflict per row | "Keep this device's version for all N" settles N conflicts from one device in one action, with a count shown first |
| J4 ([#235](https://github.com/jZenDev/jZen/issues/235)) | `zen_store` | No declared per-field merge policy; every differing value is a conflict | Revocation, status-change and read times set by two devices for the same intent conflict about *when* only | a field declared "earliest" merges two different timestamps to the earlier without a conflict; no policy can choose by write order |
| J5 ([#236](https://github.com/jZenDev/jZen/issues/236)) | `zen_store_cloudkit` | CloudKit record names are `<collection>:<id>` in plaintext | Collection names, counts per collection and any derived id are visible to Apple; the folder transport hides them (ADR-076) | record names are an HMAC under a key kept in a synchronizable iCloud Keychain item; Apple's view of a record shows no collection or id |
| J6 ([#237](https://github.com/jZenDev/jZen/issues/237)) | `zen_store_sync` / `zen_ui_store` | No rekey and no way to remove a paired device | A lost or sold device that keeps the sync key keeps reading new data and can write valid records into the folder | "Remove a device": a new sync key, the remaining devices re-paired, the old key's files no longer read; a test shows the removed device's new writes are ignored |
| J7 ([#238](https://github.com/jZenDev/jZen/issues/238)) | `zen_store_sync` | `ZEN_SYNC=folder` (`ZenFolderCloud`, unencrypted payloads) is not refused in a release build | A release build made with the define would write the whole ledger unencrypted | `ZenSync.start` in release mode with `ZEN_SYNC` set answers a `ZenValidationError` |
| J8 ([#239](https://github.com/jZenDev/jZen/issues/239)) | `zen_store` / transports | Erase is this device only; there is no "erase everywhere" (all devices, the folder, the CloudKit zone) | The Local counterpart of ADR-071's erasure has no way to delete the person's data from the sync service | one call deletes every record on every device at its next sync and removes the folder directories / the zone; the folder holds no file of the store afterwards |
| J9 ([#240](https://github.com/jZenDev/jZen/issues/240)) | `zen_ui_lock` | No screen-capture protection (Android `FLAG_SECURE`, a hidden snapshot on iOS); Flutter does not set it (ADR-078) | Balances appear in Android's recents and in screen recordings | an option sets `FLAG_SECURE` while the app holds data; verified on a device as part of #231 |
