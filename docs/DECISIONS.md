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
