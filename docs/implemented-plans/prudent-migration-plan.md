# Prudent — the plan for becoming a full-stack jZen application

**Status:** implemented. Phases 0–5 landed between 2026-08-15 and 2026-08-18; `main` is green on
both CI operating systems. **Written against:** this repository at `d6d6373`, before any of it
existed. **Date:** 2026-08-15, completed 2026-08-18.

This document is the analysis and the sequence that produced the application, and it is kept as the
record of both.

> **Completion status (reviewed 2026-08-29 against the working tree).** Every phase 0–5 has landed
> and is verifiable in the repo. Phase-level and item-level markers are inline below:
> **`[DONE]`** — built, tested, present in the tree · **`[DONE — scoped down]`** — delivered, but
> to a narrower scope than originally written, with the divergence recorded in an ADR ·
> **`[NOT DONE — deliberate]`** — explicitly out of scope, not a gap.
>
> | Phase | Status | Proof in tree |
> |---|---|---|
> | 0 — Repo scaffolding + the seam | **`[DONE]`** | `client/`, `server/`, `Taskfile.yml`, `docs/DECISIONS.md` ADR-001/002 |
> | 1 — The contract | **`[DONE]`** | `proto/prudent/v1/*.proto` (5 files), `client/lib/src/generated/`, ADR-006/007 |
> | 2 — The server | **`[DONE]`** | 6 resources, `V20260817090000__prudent_init.sql` + `R__prudent_row_level_security.sql`, 12 `@QuarkusTest` classes, ADR-010/011/012 |
> | 3 — The client rewired | **`[DONE]`** | `prudent_repository.dart` over `ZenClient`, `l10n/` with `{en,uk,pl}` + `pl` delegates, Firebase call gone (ADR-004), ADR-013 |
> | 4 — Overview / analytics / chart | **`[DONE]`** | `AnalyticsResource`, `analytics.proto`, `CustomPainter` charts, ADR-014/015; "stubbed" column emptied (see table below) |
> | 5 — Admin / e2e / deploy / docs | **`[DONE — scoped down]`** | `admin/` (users only, ADR-016), `task test:e2e` (ADR-017), CI `ci.yml` + `audit.yml` on ubuntu+windows (ADR-018), retention cascade (ADR-019/022), native locale check. **Real Cloud Run deploy: `[NOT DONE — deliberate]`** (ADR-020) — the path exists and is proven against throwaway environments only; no cloud account, project or billable service. |
>
> The open questions in §5 are all resolved — see the per-question markers there.
>
> **Follow-on, not part of this plan:** the source layout Phases 0–5 produced is being flattened
> onto a Zen capability-folder layout — client code moves out of `client/lib/src/` into
> `client/lib/`, the server package `prudent.server.*` becomes `prudent.*`, and layer folders
> (`lib/screens/`, `lib/widgets/`) are dissolved. That is **`docs/DECISIONS.md` ADR-026**, driven
> by **`docs/implemented-plans/prudent-restructure-prompt.md`**. Every `lib/src/…` and `prudent.server.…` path in
> this document is superseded by ADR-026 once that pass lands. Where the work disproved it, the text says so at the point of the claim rather than
being quietly corrected — `docs/DECISIONS.md` is where each phase's outcome is actually recorded,
and it wins on conflict. The one thing this document is not is a description of the app as it
stands today; read the ADRs for that.

**Not done, deliberately:** a real deploy. The deploy path is built and proven against throwaway
environments only (ADR-020) — no cloud project, nothing billable, no live service.

Prudent is a minimalist personal-finance application — accounts, categories, records, an overview
and analytics. It is its own product and its own repository, and it is built on **jZen**, which
arrives as a declared dependency. The philosophy both share is
[`zen-architecture.md`](zen-architecture.md); jZen's rules are read from `../jZen` and indexed by
[`jzen/README.md`](jzen/README.md).

## Decisions already taken (they shape everything below)

| Decision | Answer |
|---|---|
| Money | **`int64` minor units + ISO-4217 currency code.** `amount_minor` on the wire, `BIGINT` + `CHAR(3)` in Postgres. |
| Auth | **Required from day one.** Every row is scoped to the JWT `sub`; there is no anonymous mode to unwind later. |
| Platforms | **Android, iOS, web (Wasm), macOS, Linux, Windows** — the full jZen set. |
| Framework chrome in Polish | **Yes** — Prudent supplies `pl` delegates for `zen_ui_identity` and `zen_ui_navigation`. |
| Admin panel | **In scope**, as the last phase. |
| WebSocket surface | **Out of scope.** |
| Existing Firebase data | **Disposable.** Nothing is migrated. |

Locales are settled by CLAUDE.md and are not reopened here: **Prudent ships `{en, uk, pl}`**.

---

# Phase 1 — The application as it actually is

29 Dart files, 1,765 lines, one Flutter package rooted at the repository root. No server, no
contract, no auth, no tests, no CI, no orchestration.

## 1.1 Domain model

**`Record`** — `lib/record/record.dart`

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | minted client-side in the constructor: `uuid.v4()` |
| `title` | `String` | free text, `maxLength: 50` at the input |
| `amount` | `double` | binary floating point |
| `date` | `DateTime` | |
| `category` | `Category` | an **object reference**, not an id |

`formattedDate` formats through a file-level `DateFormat.yMd('pl_PL')`. There is **no link to an
`Account`** — the two halves of the domain never meet.

**`RecordByCategory`** — same file. A grouping helper (`forCategory` filters by category identity,
`totalRecords` sums `amount`). Nothing in the app constructs it; it is dead code today.

**`Category`** — `lib/category/category.dart`

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | `Uuid().v4()` in the constructor |
| `title` | `String` | |
| `icon` | `IconData` | a **Flutter type** — `dart:ui` |
| `description` | `String` | defaults `''` |
| `color` | `Color` | a **Flutter type** — `dart:ui`; defaults `Colors.black` |

Beside it: `CategoryIcon` (a `{value, icon}` pair), `selectableCategoryIcons` (5 entries) and
`selectableCategoryColors` (10 entries) — the palette a user actually picks from. `toJson()`
exists (icon as `codePoint`, color as `toARGB32()`) and **is never called**.

**`Account`** — `lib/account/account.dart`

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | `Uuid().v4()` |
| `name` | `String` | |
| `type` | `AccountType {cash, card, checking, savings}` | |
| `balance` | `double` | |
| `currency` | `String` | free text; the UI hardcodes `'USD'` |
| `isDefault` / `isActive` / `includeInTotal` / `includeInOverview` | `bool` | **not constructor parameters** — hardcoded `false/true/true/true` |
| `description` | `String?` | always `null`; nothing can set it |

## 1.2 State layer

Three Riverpod providers, no code generation, `flutter_riverpod: ^3.0.0-dev.17`.

- `recordsProvider` (`lib/record/records_provider.dart`) — an `AsyncNotifier<List<Record>>` whose
  `build()` performs an HTTP `GET`. `addRecord` POSTs. `removeRecord`, `editRecord` and
  `insertRecord` mutate **local state only** and never reach the server.
- `categoryProvider` (`lib/category/category_provider.dart`) — a `Notifier<List<Category>>` over the
  module-level `registeredCategories` seed list (2 entries).
- `accountProvider` (`lib/account/account_provider.dart`) — a `Notifier<List<Account>>` over
  `registeredAccounts` (2 entries), plus `totalBalance()`, which is called from nowhere.

`registeredRecords` (2 seed records) is declared and unused — `build()` always fetches.

## 1.3 Persistence as it stands

Records are read and written over `package:http` **straight to a Firebase Realtime Database URL
hardcoded in `lib/main.dart`**:

```dart
const serverUrl = 'https://prudent-60fcf-default-rtdb.firebaseio.com/';   // lib/main.dart:22
final url = Uri.parse('$serverUrl/records.json');                          // records_provider.dart:25
```

Accounts and categories are process memory and are lost on restart. The defects this arrangement
hides, each verified by reading the code:

1. **The POST response is decoded as if it were a `Record`.** Firebase answers a create with
   `{"name":"-Nxyz…"}`; `addRecord` does `jsonDecode(response.body)` and pushes that `Map` into
   `state = AsyncValue.data([...state.value!, newRecord])` (`records_provider.dart:68-69`). The list
   is a `List<Record>`, so this is a runtime type error on every successful save.
2. **Category ids do not survive a restart.** `Category`'s constructor mints a fresh `uuid.v4()`,
   and `registeredCategories` is rebuilt on every boot — so the ids stored beside persisted records
   never match again. `build()` resolves them with
   `firstWhere(…, orElse: () => throw Exception('Category not found'))`, which means **the records
   list throws for any record written in an earlier session**. This is the single most consequential
   defect in the app: the one feature with a backend is broken across the only boundary that matters.
3. **`print` debugging** on three lines of the fetch path (`records_provider.dart:31,34,48`).
4. **Ids are minted client-side**, by the client, for a shared store.
5. **Deletes and edits are local.** Swipe-to-delete removes a row from memory; the record is still
   in Firebase and returns on the next launch.
6. **Errors are invisible.** Every consumer reads `ref.watch(recordsProvider).asData?.value ?? []`
   (`records_screen.dart:26`, `records_list.dart:16`), so a thrown fetch renders as the empty-state
   message "No records found. Start adding some!".
7. **`late final` fields capture `ref.watch` once.** `records_screen.dart:25` and
   `account_screen.dart:23` initialize state fields from `ref.watch(...)`, which reads the value
   once and never rebuilds on change.

## 1.4 UI surface

- **Shell** — `Navigation` (`lib/navigation/navigation.dart`) picks `NavigationMobile`
  (a `NavigationBar`) or `NavigationDesktop` (a `NavigationRail`) from
  `isMobile(context)` → `Theme.of(context).platform` (`lib/utils.dart`). Four tabs from three
  parallel lists in `navigation_list.dart` (`navigationPages` / `navigationTitles` /
  `navigationIcons`).
- **Overview** (`lib/screens/overview.dart`) — **placeholder.** An `AppBar` with two icon buttons
  (chart, accounts) over a body containing the literal `Text('Chart')` and
  `Text('Accounts overview')`.
- **Records** (`lib/record/records_screen.dart`) — the only real screen. List, add via bottom
  sheet/dialog, swipe-left to delete with undo, swipe-right to edit.
- **Analytics** (`lib/screens/analytics.dart`) — **stub.** "Analytics Overview / Detailed analytics
  will be available soon."
- **Settings** (`lib/screens/settings.dart`) — two working buttons (Accounts, Categories) and four
  **inert `Text` labels**: Corespondents [sic], Language, Profile, Help.
- **Accounts** (`account_screen.dart`, `account_list.dart`, `account_new.dart`) — list split into
  "Banks and Cards" / "Other Accounts", create form. Add works (in memory); `onTap` is an empty
  comment; there is no edit or delete.
- **Categories** (`categories_screen.dart`, `category_grid_items.dart`, `category_item.dart`,
  `new_category.dart`) — grid, create and edit with a colour picker and a 5-icon picker.
- **Chart** (`lib/chart/chart_screen.dart`) — **stub**, `Text('Chart diagram')`.
- **`CategoryRecords`** (`lib/category/category_records.dart`) — **stub** ("Category Records
  Screen"), declares a `routeName` that `main.dart` leaves commented out; unreachable.
- **`Popup`** (`lib/widgets/popup/popup.dart`) — the one genuine piece of shared UI: an
  `IconButton` that opens a full-screen bottom sheet on mobile and a 400×300 `Dialog` elsewhere.

## 1.5 Cross-cutting

- **Hardcoded English strings** in every widget; no `l10n`, no ARB, no `flutter_localizations`.
- **`intl` with a hardcoded `pl_PL`** date locale (`main.dart:27`, `record.dart:6`) while the UI
  renders English — the exact defect a locale set exists to remove.
- **`google_fonts: ^6.2.1`** (`main.dart:56`) — `GoogleFonts.latoTextTheme` **fetches fonts over
  the network at runtime**, from a third party, on first launch.
- **`uuid: ^4.3.3`** for client-side ids; **`http: ^1.5.0`** for the Firebase call.
- Theming: two `ColorScheme.fromSeed`s at the top of `main.dart` (a pure-green seed and a dark
  variant), applied inline.
- **Orientation is locked to portrait** (`main.dart:26`) — while the app ships a desktop
  navigation rail.
- `analysis_options.yaml`: `flutter_lints` + `custom_lint`/`riverpod_lint`. A stale
  `custom_lint.log` and a `build/` directory are committed at the root.
- Platform folders exist for **all six** targets (`android/`, `ios/`, `web/`, `macos/`, `linux/`,
  `windows/`) — `flutter create` scaffolding, none of it verified by anything.
- Identifiers are `flutter create` defaults: `com.example.prudent` (`android/app/build.gradle.kts`,
  `ios/…/project.pbxproj`).
- **No tests, no CI, no `Taskfile.yml`.**

## 1.6 Feature-complete / stubbed / broken

| | |
|---|---|
| **Feature-complete** | Category CRUD-in-memory (create, edit, palette, icon set); account create + list; the records list, add-sheet, swipe-to-edit and swipe-to-delete-with-undo *within one session*; the responsive shell; the `Popup` widget. |
| **Stubbed** | Overview, Analytics, Chart, `CategoryRecords`; Settings' Corespondents/Language/Profile/Help; account tap; `Account.description`, `isDefault`, `includeInOverview`; `RecordByCategory`; `Category.toJson`; `AccountNotifier.totalBalance`. |
| **Broken** | Records fetch after any restart (category-id mismatch throws); record save (POST response decoded as a `Record`); delete and edit never persist; every fetch error renders as an empty list; `late final ref.watch` state fields do not rebuild; accounts and categories vanish on restart. |

**The plan does not promise to port behaviour that never worked.** Everything in the "stubbed"
column is **new product work**, labelled as such in Phase 4, and everything in the "broken" column
is fixed by construction rather than transcribed.

**As of 2026-08-18, Phase 4 has emptied the "stubbed" column above.** The table itself is left
unedited as the historical record of what the *original* application was — that record is what
"never worked" refers to throughout this document, and rewriting it in place would blur the line
between the before-state and the product Prudent has become. What actually happened to each item:

| Was stubbed | Now |
|---|---|
| Overview | Real per-currency totals (`docs/DECISIONS.md` ADR-014), honouring `isActive`, `includeInTotal`, `includeInOverview`. |
| Analytics | Spend-by-month bar chart over `GET /api/v1/analytics/spend-by-period`. |
| Chart | Spend-by-category donut over `GET /api/v1/analytics/spend-by-category`. Both charts are `CustomPainter`s, no dependency (ADR-015). |
| `CategoryRecords` | Reachable — tapping a category opens it; editing moved to a small overlay so the tile's main gesture could carry the navigation. |
| Settings' Corespondents | **Deleted**, not built (ADR-015) — no domain concept backs it and none was invented for it. |
| Settings' Language | Unchanged; was already working. |
| Settings' Profile | Wired to `zen_ui_identity`'s `ProfileScreen`. |
| Settings' Help | **Deleted**, not built (ADR-015) — no content exists for it. |
| Account tap | Opens `AccountEdit`; a trailing delete action was added alongside it, with the 409 "still has records" refusal surfaced to the user. |
| `Account.description` | Still absent — ADR-006 dropped it from the contract entirely; nothing in Phase 4 needed it. |
| `Account.isDefault` | Editable in both the create and edit forms, alongside `isActive`, `includeInTotal`, `includeInOverview`. |
| `Account.includeInOverview` | Editable (see above), and now has an actual effect on the Overview screen. |
| `RecordByCategory` | Still dead code — superseded by the server-side `spend-by-category` endpoint, which is where that aggregation actually belongs (ADR-014). |
| `Category.toJson` | Still dead code — categories cross the wire as `prudent.v1.Category` (ADR-006); nothing calls the old Dart method. |
| `AccountNotifier.totalBalance` | Superseded — the Riverpod notifier layer this method lived on was replaced in Phase 3 (ADR-013); its job is now the derived balance `AccountMapper` computes server-side (ADR-014). |

Two things new in Phase 4 that were never stubs, because Phase 1 never had them: **records now
carry a sign** (`Record.amount_minor` — negative expense, positive income) rather than being
expense-only, and **an account's balance is derived from its records** rather than a number nobody
updates. Both are ADR-014.

---

# Phase 2 — Where each piece goes, and the rule that forces it

| Prudent today | Destination | The rule |
|---|---|---|
| `Record`, `Account`, `Category` Dart classes | `proto/prudent/v1/{records,accounts,categories}.proto` → generated Java DTOs (`prudent-proto`) + `.pb.dart` | contract-first; `.proto` is canonical for models, everything else derived (STANDARDS "Source of truth") |
| `Category.icon` (`IconData`), `Category.color` (`Color`) | proto carries `string icon_key` + `uint32 color_argb`; the `IconData`/`Color` mapping stays in the client UI layer | a proto model cannot import `dart:ui`; §2.2 below justifies the two representations |
| `uuid.v4()` in three constructors | server-minted `UUID`, returned in the create response | the server owns identity; an id from an untrusted client is not identity |
| `amount` as `double` | `int64 amount_minor` + `string currency` | binary floating point cannot represent 0.10; §2.1 |
| Firebase RTDB over `package:http` | Quarkus resource + Panache entity + MapStruct + Flyway migration, reached through `ZenClient` | "the client talks to one server, and it is ours" — and it breaks *silently* |
| the three Riverpod notifiers | `PrudentRepository` over `ZenClient` + Riverpod providers | pattern: `../jZen/apps/zen_demo/zen_demo_client/lib/src/{demo_repository,providers}.dart` |
| `registeredCategories` / `registeredAccounts` seeds | a Flyway-seeded default category set per user, created on first login | seed data is server data |
| hardcoded English strings | `client/lib/src/l10n/prudent_{en,uk,pl}.arb` + `l10n.yaml` → `flutter gen-l10n` | jZen ADR-009 (typed accessors), ADR-044 (the supported set is Prudent's) |
| `serverUrl` const | `String.fromEnvironment` build defines (`ZEN_ENV`, `ZEN_API_URL`, `ZEN_PLATFORM`) | runtime config on the client is forbidden; it is load-bearing for tree-shaking |
| no auth | `zen_identity` + `zen_ui_identity`; every row scoped to the JWT `sub` | auth is framework-side — `AuthResource` is inherited, not rewritten |
| `Navigation` / `navigation_{mobile,desktop}` / `navigation_list` | **deleted**, replaced by `ZenNavigation` + four `ZenNavigationItem`s | reuse-or-report; §2.4 |
| `isMobile(context)` (`Theme.of(context).platform`) | `zenIsDesktop` / `zenIsWeb` from `zen_core` | §2.4 — two mechanisms answering one question |
| `google_fonts` | a bundled font asset, or the platform default | a runtime font fetch is a third-party call from a client and a startup dependency |
| `Popup` | **kept**, as Prudent's own widget | the framework has no equivalent; it is product UI, not framework UI |
| `DateFormat.yMd('pl_PL')` | `DateFormat.yMd(locale.toLanguageTag())` from the locale provider | the format follows the locale; hardcoding one while rendering another is the defect |

## 2.1 Money: `int64` minor units

`amount_minor` (int64) + `currency` (ISO-4217, 3 chars) on the wire; `BIGINT NOT NULL` +
`CHAR(3) NOT NULL` in Postgres; `NumberFormat.currency` on the client for display, and a parser on
input that rejects rather than rounds. Rationale: an expense tracker sums thousands of values, and
`0.1 + 0.2 != 0.3` in binary floating point — a totals column that is wrong by cents is wrong. int64
minor units are exact under addition, are what proto3 JSON already encodes as a string for `int64`
(so the JSON and Protobuf modes agree), and need no decimal library on either stack.

**The currency lives on both `Account` and `Record`.** Today `Account.currency` is free text and the
record form hardcodes `$`/`USD`. Prudent is a Polish-market product, so the default is `PLN`, and
`currency` is validated against ISO-4217 server-side. **Multi-currency arithmetic (FX) is an open
question** — see §5.2; the plan assumes a record inherits its account's currency and that totals
sum only within one currency, refusing to add across them rather than silently doing so.

## 2.2 Colour and icon: what actually crosses the wire

Neither `Color` nor `IconData` can appear in a `.proto` — protobuf has no `dart:ui` and the Java
side would have nothing to map to. The two fields are **not** the same problem:

- **Colour → `uint32 color_argb`.** A colour is a value; ARGB is its portable form, it is what
  `Color.toARGB32()` already produces in the dead `toJson`, and it survives a user later picking a
  colour outside today's ten-swatch palette. The client converts with `Color(value)` at the widget
  boundary and nowhere else.
- **Icon → `string icon_key`, never a code point.** A code point would round-trip perfectly and
  **break icon tree-shaking**: Flutter's `--tree-shake-icons` requires `IconData` constants to be
  statically known, and constructing `IconData(codePoint)` from data defeats it — the whole Material
  icon font then ships in every bundle. So the contract carries a stable key (`"work"`, `"leisure"`,
  `"food"`, `"restaurant"`, `"medicine"`), and the client holds a `const Map<String, IconData>`
  containing exactly the icons it ships. An unknown key renders a documented fallback icon rather
  than throwing — a category created by a newer client must not break an older one.

The server validates `icon_key` against a known set, so the contract stays honest about what a client
can be asked to render.

## 2.3 Ownership, and what "scoped to the user" means

Every Prudent table carries `user_id UUID NOT NULL` referencing the `users` row `zen-identity`
upserts on first login (no FK to Supabase's `auth.users` — BLUEPRINT "Reconciling with Supabase
`auth.users`" explains why the framework does not have one either). Every query filters on the
authenticated `sub`; resources are `@Authenticated` (**not** `@RolesAllowed(USER)` — STANDARDS
"Authorization": roles are single and unhierarchical, so gating on `USER` would 403 an admin).
Each table ships RLS + a `zen_runtime` application policy in the *same* migration (jZen ADR-036: a
table created in `public` without them is published to the internet through Supabase's Data API,
and a policy-less RLS returns **zero rows** rather than raising).

## 2.4 The navigation shell: reuse, and the two platform mechanisms

`zen_ui_navigation` provides exactly what Prudent hand-rolled: `ZenNavigation` takes
`items: List<ZenNavigationItem>` (`id`, `label`, `icon`, `builder`, `badgeCount`), `selectedIndex`
and `onItemSelected`, and branches to a native/web/stub implementation by conditional import; it
handles mobile overflow (>4 items get a "more" screen) with its own localized label. Prudent's four
tabs map onto it one-for-one, and `lib/navigation/` is **deleted**, not adapted. Nothing here calls
for a framework change — this is reuse, not a jZen gap.

`utils.dart`'s `isMobile`/`isApple` go with it. They read `Theme.of(context).platform`, which is a
*runtime, themeable* value — it is wrong for a browser on a phone, it can be overridden by a
`Theme`, and it is a different question from the one jZen answers with the compile-time
`zenIsDesktop` constant. Running both would put two answers in one app. `Popup` keeps a
mobile-vs-desktop branch, rewritten against `zenIsDesktop`.

**The portrait lock is deleted.** `SystemChrome.setPreferredOrientations([portraitUp])` in a build
that ships a desktop navigation rail and six platforms is a contradiction; orientation is left to the
platform.

## 2.5 Localization, in the shape ADR-044 left behind

- `ZenLocales.shipped` is jZen's inventory (`{en, uk}`) and is **never edited**, and jZen is never
  asked to add `pl`.
- Prudent declares `const List<String> prudentSupportedLocales = ['en', 'uk', 'pl'];` on the client
  (handed to `MaterialApp.supportedLocales`), and `zen.i18n.supported=en,uk,pl` on the server.
  The server property is what keeps `users.language` holding `pl` instead of clamping to `en`, which
  is what makes a Polish user's email Polish.
- Prudent's strings live in `client/lib/src/l10n/prudent_{en,uk,pl}.arb`; the generated accessors are
  **built, not committed**, and the contract gate asserts they are untracked.
- **Framework chrome is translated to Polish** (the decision taken above). Prudent subclasses the
  exported `IdentityLocalizationsEn` and `NavigationLocalizationsEn`, overrides the getters, wraps
  each in a delegate returning a **`SynchronousFuture`**, and composes those delegates **first** —
  `Localizations` takes the first delegate per type that supports a locale, and an `async` load
  silently loses to jZen's. Each override carries a comment saying it is deleted the day jZen ships
  `pl`.
- **Two locale properties, not one, living at different times.** `zen.i18n.supported` is runtime
  config (`ZEN_I18N_SUPPORTED` on Cloud Run). The native image additionally bakes JDK locale data at
  **build** time and defaults to `en-US`, so Prudent must also set `quarkus.locales=en,uk,pl`. Miss
  the second and a native deployment accepts `pl` and formats money and dates as English — for a
  budget app that is wrong output, not a cosmetic slip. **The check runs against the native binary**
  (Phase 5), because a JVM run cannot see it.
- The deploy must pass `ZEN_I18N_SUPPORTED` explicitly (`--set-env-vars` replaces the whole
  environment) and treat a blank value as unconfigured rather than as an empty set.
- Server-side wording Prudent owns: its Qute `@MessageBundle` variants and `templates/mail/*_pl.html`.

## 2.6 OpenAPI

SmallRye cannot introspect protobuf-generated classes — it documents their builder internals and
emits 130+ garbage schemas — so every Prudent resource method returns
`jakarta.ws.rs.core.Response` and declares its schema by reference,
`@APIResponse(… @Schema(ref = "Record"))`, with the clean component schemas supplied by Prudent's
own `server/src/main/resources/META-INF/openapi.yaml`. Paths come from the annotations (including
`AuthResource`'s, which ship inside `zen-identity`); **schemas come from the application**, so
Prudent's static document must also carry the framework's `Identity`, `ZenError` and admin schemas.
`quarkus-smallrye-openapi` lives in an `openapi` Maven profile, active unless `-Dnative` is passed —
inverting that would make the contract gate pass without checking anything.

## 2.7 WebSocket and admin

- **WebSocket: not in scope.** Nothing in the product needs push today; a live records feed would be
  new work with a second wire surface to maintain. If it is ever wanted, `zen_transport`'s
  `ZenWebSocket` + `quarkus-websockets-next` is the path, single-format Protobuf frames.
- **Admin: in scope, last.** `admin/` assembling `@jzen/admin-core` (jZen ADR-005) over
  `openapi-typescript` types generated from Prudent's own `openapi.json`. It is a **client** by the
  one-server rule and is covered by the boundary gate, not exempt from it.

---

# Phase 3 — The repository Prudent has to become, and the cross-repo seam

## 3.1 Target layout

The root becomes **language-neutral** — no root `pom.xml`, `pubspec.yaml` or `package.json`
(STANDARDS "Package modularity").

```
prudent/
├── Taskfile.yml            includes ../jZen/Taskfile.app.yml
├── proto/prudent/v1/       records.proto, accounts.proto, categories.proto, analytics.proto
├── server/                 Quarkus backend (packaging: quarkus), parent zen-parent
├── client/                 today's root package, moved wholesale
├── admin/                  react-admin panel (last phase)
├── scripts/                Prudent's own gates
├── docs/                   this plan, DECISIONS.md, zen-architecture.md, jzen/
└── .github/workflows/      ubuntu-latest + windows-latest
```

What happens to each thing currently at the root:

| Today | Then | Why |
|---|---|---|
| `lib/`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.metadata` | move into `client/` | they are the Flutter package, and the package is one tier of three |
| `android/`, `ios/`, `web/`, `macos/`, `linux/`, `windows/` | move into `client/` — **all six kept** | all six are shipped platforms (the decision above); `linux/` and `windows/` stop being `flutter create` leftovers only once CI builds them (§3.6) |
| `com.example.prudent` | **changed** before any store submission | a `flutter create` default is not an identifier; it is also what a custom scheme and App Links key on |
| `build/`, `custom_lint.log` | deleted and gitignored | build output does not belong in git |
| `README.md` | rewritten at the root, describing the three tiers | it is the front door |
| `LICENSE` | stays at the root | |

`git mv` preserves history; the move is one commit that changes no file contents.

## 3.2 `Taskfile.yml` — include jZen's, do not copy it

```yaml
version: '3'
includes:
  zen:
    taskfile: ../jZen/Taskfile.app.yml
    vars: {APP_NAME: prudent, CLIENT_DIR: client, SERVER_DIR: server, PROTO_DIR: proto}
tasks:
  test: {cmds: [{task: 'zen:test:client'}, …]}
```

Included tasks run in **Prudent's** directory (`ROOT_DIR` is Prudent's root, `TASKFILE_DIR` is
jZen's), and jZen consumes the same file for `zen_demo` — so this is shared code, not a lookalike.
**Run `task zen:info` first**: it names the jZen checkout, its revision, and whether it is dirty,
which is the only honest answer to "which framework version is this?" while the dependency is a path.

**Available from jZen today:** `zen:info`, `zen:framework:install`, `zen:deps`, `zen:generate:l10n`,
`zen:test:client`, `zen:build:runners`.

**Prudent writes itself, because jZen has not made them app-agnostic yet** (jZen ADR-046 names this
limit): the contract loop (`generate:proto:*`, `generate:api:*`, `sync:contracts`), the server build,
the local stack, the deploy, and every gate. `task` triggers native tools and never replaces them —
`mvnw` owns Java, `flutter`/`dart pub` owns Dart, `pnpm` owns TypeScript — and **no task is
fingerprinted with `sources:`/`generates:` if a gate composes it**: a skipped regeneration leaves a
clean tree and the drift gate reports success without having checked anything.

## 3.3 The jZen dependency seam, and its cost

- **Dart** — `path:` dependencies, package by package, in `client/pubspec.yaml`:
  `../../jZen/client/{zen_core,zen_transport,zen_identity,zen_secure_store,zen_ui_identity,zen_ui_navigation}`.
  Imports stay `package:zen_core/…` — character for character what a published consumer writes, so
  publishing later is a pubspec edit with zero code churn (jZen ADR-026 rejected a facade for exactly
  this reason). The dependency list naming six framework packages **is the finding**, and it is meant
  to be visible.
- **Java** — `server/pom.xml` declares `zen-parent` as its parent with an **empty
  `<relativePath/>`**, resolving the parent and the framework artifacts from the **local Maven
  repository**. The build therefore has a prerequisite:
  `(cd ../jZen/server && ./mvnw -B install -DskipTests)`, which is `task zen:framework:install`.
- **Admin** — `@jzen/admin-core` from `../jZen/admin/src` via a TypeScript `paths` alias + a Vite
  `resolve.alias`, not a pnpm dependency edge.

**This diverges from jZen ADR-026 on the Maven half, deliberately.** ADR-026 puts a root aggregator
POM in a parent folder *above both repositories* and gives the product a filesystem
`<relativePath>` into `jzen/`. Prudent cannot do that: CLAUDE.md requires that **all work happens
inside this repository** and that nothing reaches outside the repo root, and a `<relativePath>`
across repositories couples the build to a directory layout instead of to a version. Prudent uses
the empty-`<relativePath/>`-plus-local-repository form instead. This is a Prudent-owned concern, so
Prudent's rule wins and **the divergence is recorded as a Prudent ADR** (Phase 0).

**The cost, stated plainly:** there is **no version boundary** between the two repositories. They
must move in lockstep; a `git pull` in `../jZen` can break Prudent's build with no version to point
at; CI needs both checkouts; and a contributor needs the sibling checkout at exactly that path.
`task zen:info` reporting a *dirty* jZen is a warning that the build is not reproducible.

**The exit** is publishing. When jZen publishes its packages, every `path:` becomes a version range,
`zen-parent` becomes a released version, the admin alias becomes a pnpm dependency, and
`docs/jzen/` is **deleted** — a versioned dependency's documentation travels with the package. That
is an ADR, not a cleanup, because it changes what Prudent is coupled to. Its trigger, per jZen
ADR-026, is **Prudent's first CI run, Java first** — a lone clone has no sibling checkout and no
local repository, so §3.6 either checks out jZen in CI or forces the publishing decision.

## 3.4 Flyway

Flyway is the **single migration authority**; `supabase/migrations/` stays empty. `zen-identity`
runs its migrations into *Prudent's* database, so Prudent's versions must never collide with jZen's
present or future ones.

**Prudent adopts jZen ADR-033's scheme: a UTC timestamp,
`V<YYYYMMDDHHMMSS>__prudent_<what>.sql`.** This is stronger than the "reserve a band" instruction in
CLAUDE.md, and it is what actually solves the problem: a band prevents collisions but cannot
guarantee a new migration sorts above everything already applied, and Flyway **refuses to start**
on an out-of-order version. A timestamp does both by construction, is above the advisory 1000-floor
by orders of magnitude, and cannot be got wrong by omission. Recorded as a Prudent ADR before the
first migration exists.

Three further rules that come with it: every table ships **RLS and a `zen_runtime` policy** in the
same change (§2.3); repeatables (`R__prudent_*.sql`) are for grants and policies only; **an applied
migration is immutable, including its comments** — Flyway checksums the whole file.

> **Corrected in build (ADR-010).** This section originally said the policy ships *in the same
> migration*, which does not work: `zen_runtime` is created by `zen-identity`'s own **repeatable**
> `R__identity_application_role.sql`, and repeatables run after every versioned migration — so a
> versioned `CREATE POLICY … TO zen_runtime` references a role that does not exist yet on a fresh
> database. The table creation and its `ENABLE ROW LEVEL SECURITY` are versioned; the policies live
> in `R__prudent_row_level_security.sql`, which is what `zen-jobs` and `zen-ratelimit` already do.
> "In the same change" is the rule; "in the same file" was the mistake.

## 3.5 Database and the local stack

- **Postgres**, reached by Hibernate Panache in active-record style (entities extend
  `PanacheEntityBase`; there are no repository classes on the server — the repository pattern lives
  on the *client*, over `ZenClient`).
- **Supabase is needed server-side only**, for auth. `SUPABASE_URL`/`SUPABASE_KEY` are server runtime
  config and never reach a client.
- **Port collisions are real and must be chosen deliberately.** jZen's local stack uses **8080**
  (server) and **54321/54322** (Supabase). `Taskfile.app.yml` already defaults an application's API
  to **`http://localhost:8085`**, so Prudent's server takes `quarkus.http.port=8085`. The Supabase
  stack is the harder one: a running jZen Supabase holds 54321/54322, and two projects cannot share
  them — Prudent either runs its own on shifted ports in its own `supabase/config.toml`, or accepts
  that only one stack runs at a time. **This is an open question** (§5.4) because the answer depends
  on whether both products are ever developed simultaneously.
- **Tests:** `@QuarkusTest` with Dev Services provisions a throwaway Postgres per run and **needs
  Docker**. `%dev` and `%test` migrate at boot; `%prod` neither migrates nor validates — migration is
  an act of the deploy (jZen ADR-038).

## 3.6 Verification and CI

Prudent has no tests today. The suites the plan creates:

| Suite | What it covers | Command |
|---|---|---|
| Backend | `@QuarkusTest` per resource: both transport modes (`X-Zen-Transport: json` and `protobuf`), the `ZenError` path, auth scoping (user A cannot read user B's records), the locale row (`Accept-Language: pl-PL` → `users.language = 'pl'`) | `task test:server` |
| Client | Flutter widget + unit: repository over a fake `ZenClient`, money formatting, the icon-key map, a Prudent screen rendering Polish, a framework screen rendering Polish under the app's delegate | `task zen:test:client` |
| Contract drift | regenerate everything, fail if a tracked generated file changed, and fail if any generated l10n **is** tracked | `task sync:contracts` |
| Boundaries | no provider SDK, no third-party host or credential, no absolute URL literal outside the one base URL — **plus Prudent-specific checks for `firebaseio.com`, `package:http` used directly, and `google_fonts`** | `task verify:boundaries` |
| Runners | every delivery runner the host can build | `task zen:build:runners` |
| End-to-end | the real stack (Supabase + Quarkus + client), one record created and read back | `task test:e2e` |

**`verify:boundaries` is the single most important gate here**, because the defect it catches is the
one currently in the repository and it fails *silently*: an app talking to Firebase authenticates,
renders, and passes every unit test.

**CI** runs on `ubuntu-latest` **and** `windows-latest` — Flutter refuses `build linux` off Linux
and `build windows` off Windows, so the desktop claims can be proven nowhere else (jZen ADR-045).
macOS and iOS are built on the delivery machine and **skipped audibly** in CI, on jZen's cost
reasoning. Every CI job must first check out `../jZen` at a pinned revision and run
`task zen:framework:install` — which is precisely the moment the path-dependency seam stops being
free (§3.3).

## 3.7 Findings to report upstream (jZen-side, not worked around here)

None of these are fixed by editing `../jZen`; they are reported.

1. **The contract loop is hardcoded to jZen's own tree.** `generate:proto:dart` writes to
   `client/zen_transport/lib/src/generated` and globs `proto/zen/v1/*.proto`; `generate:api:*` names
   `DEMO_SERVER_DIR`/`DEMO_ADMIN_DIR`; `sync:verify` hardcodes the proto glob. An application cannot
   reuse any of it, and Prudent writes its own — the second consumer is the evidence for which task
   ADR-046 should move next.
2. **`scripts/verify-boundaries.py` cannot be pointed at another repository.** `DART_LIB_SCOPES`,
   `TS_SRC_SCOPES`, `PUBSPEC_ROOTS` and `TS_PACKAGE_GLOBS` are module-level constants with no CLI or
   env override, and its `StaleScope` guard means running it in Prudent fails loudly rather than
   passing vacuously — correct behaviour, but it means the framework's most load-bearing gate is not
   reusable. Prudent writes an equivalent, and the deliberate duplication is a finding, not a design.
3. **`ADR-026`'s Maven mechanic assumes a shared parent folder** (a root aggregator POM above both
   repositories), which conflicts with "all work happens inside this repository". §3.3 diverges.
4. **`ZenLocales.shipped` is `{en, uk}`**, so Prudent supplies `pl` for framework chrome itself.
   That is exactly the seam ADR-044 designed, and it is only a finding in the sense that Prudent's
   override is deleted the day jZen ships `pl`.
5. **The static `openapi.yaml` is hand-authored.** jZen's own file says it should eventually be
   generated from the protos; until it is, every application hand-maintains component schemas for
   framework messages it did not write (`Identity`, `ZenError`).
6. **Deploy, local stack and `test:e2e` are `zen_demo`-shaped**, including the Supabase port
   assumptions — the second application is what makes the collision concrete (§3.5).

## 3.8 Docs

- **`README.md`** at the root: what Prudent is, the three tiers, the sibling-checkout prerequisite,
  `task zen:info` first.
- **`docs/DECISIONS.md`**: Prudent's own log, numbering from **ADR-001**, append-only.
- The conversion settles these, and each gets an entry (Phase 0 and Phase 1 write most of them):
  repository shape; the path-dependency seam and its divergence from jZen ADR-026; the Flyway
  timestamp scheme; the money type; the proto/Java/platform namespaces; the locale set and the
  Polish chrome override; the platform list and its CI cost.
- Prudent is described **on its own terms** — an application built on jZen, its declared dependency.
  Never "ported", "migrated from", or "derived". This document and `docs/DECISIONS.md` are the only
  places the before-state is discussed.

---

# Phase 4 — The sequence

Every phase ends **green and verifiable**, with the exact command that proves it.

## Phase 0 — Repo scaffolding and the seam, proven by a build that does nothing else — `[DONE]`

**Creates/changes:** `git mv` of `lib/`, `pubspec.*`, `analysis_options.yaml`, `.metadata` and the
six platform folders into `client/`; `Taskfile.yml`; `.gitignore` (drop `build/`,
`custom_lint.log`); `server/pom.xml` (a Quarkus module with **no endpoints** yet, parent
`zen-parent`, empty `<relativePath/>`); `docs/DECISIONS.md` with ADR-001 (repo shape + the seam) and
ADR-002 (Flyway timestamps); root `README.md`.

**Tests:** none yet — this phase's proof is that both toolchains resolve.

**Verification:**
```
task zen:info                                  # names the jZen checkout, revision, dirty state
task zen:framework:install                     # installs zen-* into ~/.m2
(cd server && ./mvnw -B package -DskipTests)   # resolves zen-parent with an empty relativePath
task zen:deps && (cd client && flutter run)    # the app still runs, unchanged
```

**Risk:** low, and it is the one phase where the app must behave identically afterwards. The trap is
the empty `<relativePath/>`: forget `zen:framework:install` and Maven reports a missing parent, which
reads like a broken POM.

## Phase 1 — The contract — `[DONE]`

**Creates:** `proto/prudent/v1/{records,accounts,categories,analytics}.proto` (package `prudent.v1`,
`java_package = "prudent.proto.v1"`); `server/` compiles them via `protobuf-maven-plugin`; Dart
messages generated into `client/lib/src/generated/`; `Taskfile.yml` gains `generate:proto:{java,dart}`,
`sync:contracts` and `sync:verify` (Prudent's own — §3.7 finding 1).

**Rules this phase pins:** every endpoint declares its own request and response messages; there is no
envelope and no generic payload; cross-cutting shapes come from jZen's `common.proto` (`ZenError`,
`PageRequest`). `.pb.dart` is **tracked** (regenerating it needs a system `protoc` + `protoc-gen-dart`
that a Flutter developer should not have to install); the Java DTOs are **not** (Maven resolves
`protoc` itself).

**Tests:** a Dart test that round-trips one message through both JSON and binary, proving the
generated code is present and correct.

**Verification:** `task sync:contracts` → "Contracts in sync."

**Risk:** the money and icon-key decisions are baked in here. Getting `amount_minor` wrong is a
migration later; getting `icon_key` wrong costs the icon tree-shaking §2.2 protects.

## Phase 2 — The server — `[DONE]`

_Delivered with more than planned: a `SettingsResource` + `settings.proto` and a `HealthResource`
beyond the three CRUD resources originally listed._

**Creates:** Panache entities (`Record`, `Account`, `Category`, each with `user_id`); one Flyway
migration `V<ts>__prudent_init.sql` creating three tables **with RLS and a `zen_runtime` policy
each**; MapStruct mappers entity ⇄ proto; `RecordResource`, `AccountResource`, `CategoryResource`
(all `@Authenticated`, all returning `Response` with `@Schema(ref=…)`);
`META-INF/openapi.yaml`; `application.properties` with `quarkus.http.port=8085`,
`zen.i18n.supported=en,uk,pl` and `quarkus.locales=en,uk,pl`; Prudent's `@MessageBundle` and
`templates/mail/*_{en,uk,pl}.html` if any mail is sent.

**Non-negotiables checked here:** **no `quarkus-rest-jackson`** (it hijacks `application/json` at
build time and 500s on proto messages — it must be *absent*, not out-prioritized); any Prudent module
contributing CDI beans or JAX-RS providers runs **`jandex-maven-plugin`** (without
`META-INF/jandex.idx` Quarkus never discovers them — no error, the filters just do nothing).

**Tests (`@QuarkusTest`):** CRUD per resource in **both** transport modes; a `ZenError` path
(validation failure, unknown id); **user-scoping** (A cannot read, update or delete B's rows);
`Accept-Language: pl-PL` at registration leaves `pl` in `users.language`; an unknown `icon_key` is
rejected.

**Verification:** `task test:server` green; `task sync:contracts` still green (the resources changed
`openapi.json`).

**Risk:** the two silent failures above, plus RLS-without-a-policy, which returns zero rows instead
of raising. All three pass a naive smoke test.

## Phase 3 — The client rewired — `[DONE]`

**Creates/changes:** `client/lib/src/prudent_repository.dart` over `ZenClient` (pattern:
`../jZen/apps/zen_demo/zen_demo_client/lib/src/demo_repository.dart`); providers rewritten over it;
`main.dart` becomes a composition root wiring `createSessionClient` + `SecureTokenStore` +
`SupabaseIdentityRepository` + the locale provider (pattern: `zen_demo_client/lib/main.dart`);
`zen_ui_identity` screens for login/register/restore; `ZenNavigation` replacing `lib/navigation/`;
ARB files for `{en, uk, pl}` + `l10n.yaml`; Prudent's `pl` delegates for the two framework packages;
a bundled font replacing `google_fonts`.

**Deleted:** `lib/main.dart`'s `serverUrl`, the whole Firebase call path in `records_provider.dart`,
`package:http` as a direct dependency, `uuid`, `google_fonts`, `lib/utils.dart`, `lib/navigation/`.

**Tests:** repository unit tests against a fake transport; a widget test that a Prudent screen renders
Polish; a widget test that a **framework** screen renders Polish through Prudent's delegate (and does
not throw); a test pinning that the app's delegate is composed **first** and returns a
`SynchronousFuture` — the failure mode ADR-044 found by testing rather than reading.

**Verification:**
```
task verify:boundaries    # the Firebase call is gone — this is the gate that proves it
task zen:test:client
task zen:build:runners    # every runner this host can build; skips are audible
```

**Risk:** the highest of any phase. It is where the one-server rule is actually satisfied, where
sessions have to work on six platforms, and where any Flutter dependency added must be **Wasm-clean**
(a web build compiles a generated registrant importing *every* web plugin, so no conditional import
or `zenIsWeb` guard can keep a `dart:html` plugin out). Run a web build after any dependency change.

## Phase 4 — Overview, analytics and the chart — **new work, not a port** — `[DONE]`

Everything here was a placeholder `Text` or a "coming soon" screen; none of it is being transcribed.

**Creates:** an analytics endpoint (spend by category and by period, computed server-side, its own
proto messages); the Overview screen (real totals, honouring `includeInOverview`/`includeInTotal`,
refusing to sum across currencies); the chart screen; `CategoryRecords` made reachable; account edit
and delete; the Settings items that are inert labels today — **or their deliberate removal**. A
`Record` gains its missing link to an `Account`, which is the domain hole Phase 1's contract has to
decide on (§5.1).

**Tests:** analytics arithmetic server-side (including the empty and single-currency cases); widget
tests for the overview totals.

**Verification:** `task test:server && task zen:test:client`.

**Risk:** scope. This is product design, not conversion, and it is the phase most likely to grow.

## Phase 5 — Admin, the end-to-end gate, deploy and docs — `[DONE — scoped down]`

_Admin, `test:e2e`, CI, native locale check, retention cascade and the ADRs are all done. The
**real Cloud Run deploy is `[NOT DONE — deliberate]`** (ADR-020): `deploy:cloudrun` /
`verify:deploy` exist and are proven only against throwaway environments; there is no cloud
account, project, region or service. ADR-021/022/023/024/025 were added while doing the work._

**Creates:** `admin/` over `@jzen/admin-core` with `openapi-typescript` types generated from
Prudent's `openapi.json`; `task test:e2e` against the real stack; `task deploy:cloudrun` carrying
`ZEN_I18N_SUPPORTED` explicitly; `.github/workflows/` (ubuntu + windows); the remaining ADRs.

**Tests:** an end-to-end run creating a record through the API and reading it back; **a check against
the native binary** that `pl` formats as Polish, not English (§2.5 — a JVM run cannot see this).

**Verification:** `task test` (the composed gate), `task build:server:native`, `task deploy:cloudrun`
followed by `task verify:deploy`.

**Risk:** the deploy is the first time the whole configuration surface is exercised, and jZen's own
history says configuration is where it fails — a missing env var produces a working-looking service
that is quietly wrong.

**As of 2026-08-18, Phase 5 is done to the scope actually decided, which is narrower than this
section originally described in two explicit, asked-and-answered ways.** `task deploy:cloudrun` and
`task verify:deploy` against a **real** environment are **not built** — the deploy was scoped to
"the path exists and is proven against a throwaway environment," not a real Cloud Run deploy, so
there is no cloud account, project, region or service name anywhere, committed or otherwise. What
*is* built and green: `admin/` (only the framework's `users` resource — Prudent's own resources are
user-scoped with no cross-user listing endpoint to administer); `task test:e2e` (six cases against
the live local Supabase + Quarkus stack, which caught a real registration/category-seeding race on
its first run); CI on `ubuntu-latest` and `windows-latest` with `../jZen` pinned at a SHA
(`docs/DECISIONS.md` ADR-018); `task audit` on its own schedule (which found and fixed a real CVE on
its first run); GDPR retention now sweeps Prudent's own tables when `zen-identity` anonymises an
account (ADR-019, not originally scoped in this section at all — found necessary while doing the
work); `task build:server:native`, `task build:web`, `task build:web:admin` and `task test:native`
(the local Docker smoke gate that stands in for `deploy:cloudrun` + `verify:deploy` against a
throwaway Postgres, including the native-only locale check this section names). See ADR-016 through
ADR-020 for the full record of each decision and what each gate found.

---

# 5 — Open questions — all resolved

_Every question below was settled during the build; the resolving ADR is named inline._

**5.1 Does a `Record` belong to an `Account`?** Today it does not — accounts and records are
unconnected, and `totalBalance()` never changes when money is spent. An expense tracker almost
certainly wants `Record.account_id`, but adding it changes the create form, the seed data and the
overview arithmetic. **Assumed in the plan: yes, `account_id` is required**, decided in Phase 1
because the contract cannot be vague about it. **`[RESOLVED]` — yes; `account_id` is on `records.proto` and the domain link exists (ADR-006, ADR-014).**

**5.2 Multi-currency and FX.** Accounts already carry a currency string. Does Prudent convert
between currencies (which needs a rate source, a rate date on every record, and a base currency), or
does it keep per-currency totals and refuse to add across them? **Assumed: no FX** — totals are
per-currency, and mixing currencies is refused rather than silently summed. FX is a product feature
with a third-party rate dependency, which the one-server rule routes through Prudent's own server. **`[RESOLVED]` — no FX; an account holds several currencies and the main currency labels but never converts (ADR-008, ADR-009).**

**5.3 Prudent's namespaces.** Four separate identifiers, only one of which is cosmetic:
proto package `prudent.v1` / Java `prudent.proto.v1`; Maven `groupId prudent`, `artifactId
prudent-server` (mirroring jZen ADR-006's bare `zen`); the application id
`com.example.prudent`, which is a `flutter create` default and **must change** before any store
submission or App Links configuration; and a custom URI scheme for auth email links
(`prudent://auth-callback`), which the server must be configured to accept by exact match.
**Assumed: the above**, with the application id awaiting a real reverse-DNS domain. **`[RESOLVED]` — namespaces as assumed; the auth callback scheme is now configured at the OS level too (ADR-025). Application id still `com.example.prudent`, still awaiting a real domain before store submission.**

**5.4 The local Supabase stack.** Does Prudent get its own Supabase project with shifted local ports,
or does only one of the two products run at a time? **Assumed: Prudent's own project and its own
ports**, because a developer working on both otherwise cannot. **`[RESOLVED]` — Prudent has its own `supabase/` config; server on 8085.**

**5.5 Deployment target.** Cloud Run, following jZen's model (single instance, scale-to-zero, native
image), is assumed — Prudent inherits the whole deploy path that way. A different target means
writing the deploy from scratch and re-deciding migration-at-deploy. **`[RESOLVED]` — Cloud Run, native image, migration-at-deploy; the deploy contract passes every environment fact in (ADR-020, ADR-021). Not exercised against a real project.**

**5.6 Does anything about the current Firebase project need decommissioning?** The data is
disposable, but the project, its API key and its billing are not this repository's to leave running.
**`[OPEN — outside this repo]` — no ADR; decommissioning the old Firebase project is an operator
action, not conversion work. The code-side removal is complete (ADR-004).**

---

# 6 — Out of scope / deliberately not ported

- **The Firebase Realtime Database call, and its data.** Deleted, not migrated. It is what the
  one-server rule forbids, and its removal is the spine of this work.
- **Client-minted ids (`uuid`).** The server owns identity.
- **`double` money.** Replaced, not carried.
- **`google_fonts`.** A runtime font fetch is a third-party call from a client and a startup
  dependency.
- **`lib/utils.dart` and `lib/navigation/`.** Replaced by `zenIsDesktop` and `ZenNavigation`.
- **The portrait lock.** Contradicted by the platform list.
- **`RecordByCategory` and `Category.toJson`.** Dead code; the equivalents are generated or
  computed server-side.
- **A WebSocket surface.** Nothing in the product needs push.
- **Any change to `../jZen`.** Framework needs are reported (§3.7), never forked.
- **Payment, premium tiers and GDPR retention policy.** `zen-identity` carries the columns and the
  retention job; Prudent implements no checkout (jZen ADR-010: application work, and there is no
  second-consumer case for it in the framework).
- **Running the built Linux app under `Xvfb` in CI.** jZen has this as a named next step; Prudent
  builds the runner and does not launch it.
