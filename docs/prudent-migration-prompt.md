# Prompt — analyze this app and plan its conversion to jZen

> Paste everything below the line into a fresh Claude Code session started in
> `/Users/amerezhanyi/Developer/jZenDev/prudent`.

---

You are working in the **Prudent** repository. Read `CLAUDE.md` first, then
`docs/zen-architecture.md` — Prudent's cornerstone, the philosophy this product is built on.

Then read the framework's rules from the sibling checkout, indexed by `docs/jzen/README.md`:
`../jZen/docs/architecture/{MANIFESTO,BLUEPRINT,STANDARDS}.md`. jZen's ADR archive at
`../jZen/docs/architecture/DECISIONS.md` **wins on conflict** with those three — skim at minimum
ADR-001, ADR-005, ADR-006, ADR-007, ADR-009, ADR-010, ADR-017, ADR-026, ADR-028, ADR-031. Those
documents constrain Prudent where it consumes the framework; they are not Prudent's house style,
and where a rule concerns something **Prudent** owns, Prudent decides and records an ADR. The
`jzen-reference` skill maps where everything lives.

**Task: produce a migration plan** (a document, not code — see "Deliverable") for converting
Prudent from a standalone Flutter app into a **full-stack application built on the jZen framework**,
staying its own product and its own repository.

Prudent is a minimalist personal-finance / expense tracker: accounts, categories, records
(transactions), an overview, and analytics.

## Ground rules

- **`../jZen` is a sibling checkout and is read-only.** Read it freely for reference
  implementations; never write to it, never copy framework source into this repository. If Prudent
  needs a framework change, that change belongs in jZen and is consumed as a dependency — name it
  as such instead of forking a copy here.
- **Reuse beats reimplementation, but do not widen the framework to suit one app.** Anything
  auth-shaped almost certainly already exists in `zen-identity`. Conversely, a Prudent-specific
  need does not justify a change to a jZen library (jZen ADR-010's second-consumer bar). For each
  item, say plainly which of the two it is.
- Never run `git commit` / `git push` without explicit approval.
- Do not write code in this pass, and do not restructure the repository yet.

## Phase 1 — Inventory the app as it actually is

Read every file under `lib/` (~29 Dart files, ~1.8k lines) plus `pubspec.yaml`,
`analysis_options.yaml`, `README.md`, and the platform folders. Produce a factual inventory:

- **Domain model**, field by field: `Record` (title, amount `double`, date, category),
  `RecordByCategory`, `Category` (title, `IconData` icon, description, `Color`), `Account` (name,
  `AccountType {cash,card,checking,savings}`, balance, currency, isDefault/isActive/
  includeInTotal/includeInOverview, description).
- **State layer**: the three Riverpod notifiers (`recordsProvider` is an `AsyncNotifier` that
  fetches; `categoryProvider` / `accountProvider` are in-memory `Notifier`s over the hardcoded seed
  lists `registeredCategories` / `registeredAccounts`).
- **Persistence as it stands**: records are read/written over `package:http` straight to a
  **Firebase Realtime Database URL hardcoded in `lib/main.dart`** (`serverUrl`); everything else is
  process memory, lost on restart. Note the defects this hides — the POST response decoded as if it
  were a `Record`, `print` debugging, ids minted client-side by `uuid`, and categories resolved by
  id against an in-memory list whose members get a *new* uuid on every boot.
- **UI surface**: the responsive shell (`navigation_mobile` / `navigation_desktop`, chosen by
  `Theme.of(context).platform`), the four tabs (Overview, Records, Analytics, Settings), the
  account/category/record list and create screens, the popup widget, the chart screen — and which of
  these are real versus placeholder ("Analytics Overview … coming soon", Overview's literal
  "Chart"/"Accounts overview" `Text`s, Settings' inert `Corespondents`/`Language`/`Profile`/`Help`
  labels).
- **Cross-cutting**: hardcoded English strings throughout; `intl` with a hardcoded `pl_PL` date
  locale; `google_fonts` (fetches fonts at runtime); `uuid`; theming from two `ColorScheme.fromSeed`s
  in `main.dart`; portrait-locked orientation; no auth, no user concept, no tests, no CI.

State explicitly what is **feature-complete**, what is **stubbed**, and what is **broken**. The plan
must not promise to port behavior that never worked.

## Phase 2 — Map each piece onto jZen, and name the frictions

For every inventoried item, give the destination and the rule that forces it. At minimum:

| Prudent today | Destination | The rule |
|---|---|---|
| Dart model classes | `proto/prudent/v1/*.proto` → generated Java DTOs + `.pb.dart` | contract-first; models are canonical in proto, everything else derived |
| `Color` / `IconData` fields inside `Category` | proto carries a *portable* value; Flutter types stay in the UI layer | a proto model cannot import `dart:ui` — decide the wire representation (ARGB int? named token? icon key?) and justify it |
| `uuid.v4()` in constructors | server-minted ids | the server owns identity; an id from an untrusted client is not identity |
| `amount` as `double` | choose and justify (int64 minor units vs. decimal string vs. double) | money in binary floating point is a defect; this is a decision, not a port |
| Firebase RTDB over `package:http` | Quarkus resource + Panache entity + MapStruct + Flyway migration, reached through `ZenClient` | "the client talks to one server, and it is ours" — a third-party URL or SDK in a client package is precisely what this forbids, and it breaks *silently* |
| Riverpod notifiers over seed lists | a repository over `ZenClient` plus Riverpod providers | pattern: `../jZen/apps/zen_demo/zen_demo_client/lib/src/{demo_repository,providers}.dart`; no ad-hoc `http` |
| hardcoded English strings | per-package `lib/src/l10n/*.arb` + `l10n.yaml`, `flutter gen-l10n` | jZen ADR-009 (typed accessors) and ADR-044 (the supported set is Prudent's) — see "Languages" below |
| `serverUrl` const in `main.dart` | `String.fromEnvironment` build defines (`ZEN_ENV`, `ZEN_PLATFORM`) | runtime config on the client is forbidden; it is load-bearing for tree-shaking |
| no auth | `zen_identity` + `zen_ui_identity`; records scoped to the JWT `sub` user | auth is framework-side — `AuthResource`/`AdminUserResource` are inherited, not rewritten |
| the hand-rolled navigation shell | evaluate `zen_ui_navigation` first; keep Prudent's shell only for what the framework genuinely lacks | reuse-or-report, per the ground rules |
| `google_fonts` | a bundled font asset or a system font | a runtime font fetch is a third-party call from the client and a startup dependency |

### Languages: Prudent ships `{en, uk, pl}`

**This is settled, not open.** Prudent is a Polish-market product — `lib/record/record.dart`
already formats dates `DateFormat.yMd('pl_PL')` while rendering English strings — so Polish is a
requirement of the app, and English and Ukrainian come along because jZen ships them and the
server can answer in them.

jZen used to make this impossible: one `ZenLocales.supported` was read as both "what jZen has
strings for" and "what the product supports", and an unknown tag was *erased* rather than passed
through. That is fixed upstream (jZen **ADR-044**, already landed). Work with the mechanism as it
now stands, and do not reintroduce the old shape:

- **`ZenLocales.shipped` is jZen's inventory** (`{en, uk}`), a floor and not a ceiling. Never edit
  it, and never ask jZen to add `pl` — `../jZen` is read-only and a framework does not ratify a
  product's language list.
- **Prudent declares its own supported set**, per tier, the way that tier does config: a
  compile-time `const List<String>` on the client (handed to `MaterialApp.supportedLocales`), and
  the runtime property `zen.i18n.supported=en,uk,pl` on the server. The server property is what
  keeps `users.language` holding `pl` instead of being clamped to `en`, which in turn is what makes
  a Polish user's email Polish.
- **Prudent's own strings** are ARB files per package: `*_en.arb`, `*_uk.arb`, `*_pl.arb`.
- **Framework chrome under `pl` degrades to English by default.** Compose the framework packages'
  degrading delegates (`identityLocaleDelegate`, `navigationLocaleDelegate`), *not* the generated
  `XLocalizations.delegate`, which refuses an unshipped locale and crashes the first screen that
  reads a string.
- **To render framework screens in Polish**, subclass the exported per-locale class
  (`IdentityLocalizationsEn`, `NavigationLocalizationsEn`), override the getters, wrap it in a
  delegate that returns a **`SynchronousFuture`**, and compose that delegate **first** —
  `Localizations` takes the first delegate per type that supports the locale, and an `async` load
  silently loses to jZen's. Decide explicitly whether Prudent does this or accepts English chrome;
  if it does, note that the override is deleted the day jZen ships `pl`.
- **Two properties, not one, and they live at different times.** `zen.i18n.supported=en,uk,pl` is
  *runtime* config (an env var on Cloud Run: `ZEN_I18N_SUPPORTED`). The native image additionally
  bakes JDK locale data at **build** time and defaults to `en-US` only, so a budget app formatting
  money and dates server-side must also set the build-time `quarkus.locales=en,uk,pl`. Miss the
  second and a native deployment accepts `pl` at runtime and silently formats it as English —
  which for an expense tracker means wrong currency and date rendering, not a cosmetic slip. Plan
  a check that runs against the **native** binary, not just the JVM one.
- **The deploy must pass the variable through.** jZen's `deploy:cloudrun` uses `--set-env-vars`,
  which replaces the whole environment — a variable set by hand on the service is wiped by the
  next deploy. Prudent's own deploy task must carry `ZEN_I18N_SUPPORTED` explicitly, and treat a
  blank value as unconfigured rather than as an empty set.
- **Server-side wording Prudent owns** — its Qute `@MessageBundle` variants and its
  `templates/mail/*_pl.html` — is Prudent's to write; `EmailService` resolves the template locale
  against `zen.i18n.supported`, so a `_pl` template is found once the property lists `pl`.
- **The `pl_PL` date format** stays, but as a consequence of the locale rather than a hardcoded
  literal: date and currency formatting follow the chosen `Locale`, and hardcoding one locale's
  format while another renders is the defect being removed.

Plan the verification for this explicitly: a test that a Prudent screen renders Polish, one that a
framework screen renders (English or Polish, per the decision above) under `pl` rather than
throwing, and one that a registration with `Accept-Language: pl-PL` leaves `pl` in the user's row.

Also cover: the server's `META-INF/openapi.yaml` component schemas (SmallRye cannot introspect
protobuf — resources return `jakarta.ws.rs.core.Response` with `@Schema(ref = …)`); whether Prudent
needs a WebSocket surface; and whether an admin panel is in scope at all.

## Phase 3 — The repository Prudent has to become, and the cross-repo seam

This is the most valuable part of the analysis: today this repo is a single Flutter package with a
root `pubspec.yaml` and no build orchestration whatsoever. Report concretely:

1. **Target layout.** The root must become **language-neutral** — no root `pom.xml`, `pubspec.yaml`
   or `package.json`. Plan the move of today's root package into `client/`, and the arrival of
   `proto/`, `server/`, optionally `admin/`, and `Taskfile.yml`. Say what happens to `android/`,
   `ios/`, `web/`, `macos/`, `linux/`, `windows/`, `.metadata` and `analysis_options.yaml`.
2. **`Taskfile.yml` — include jZen's, do not copy it.** `task` becomes the single entry point and
   must **trigger native tools, never replace them** (`mvnw` owns Java, `dart pub` owns Dart,
   `pnpm` owns TypeScript). jZen now ships the application-facing half of its orchestration as
   **`../jZen/Taskfile.app.yml`** (jZen **ADR-046**, already landed), which Prudent includes:

   ```yaml
   version: '3'
   includes:
     zen:
       taskfile: ../jZen/Taskfile.app.yml
       vars: {APP_NAME: prudent, CLIENT_DIR: client, SERVER_DIR: server, PROTO_DIR: proto}
   tasks:
     test: {cmds: [{task: 'zen:test:client'}]}
   ```

   Included tasks run in **Prudent's** directory, and jZen consumes the same file for zen_demo, so
   this is shared code rather than a copy that resembles one. Available today: `zen:info`,
   `zen:framework:install`, `zen:deps`, `zen:generate:l10n`, `zen:test:client`,
   `zen:build:runners`. **Run `task zen:info` first** — it reports which jZen checkout is in use,
   at which revision, and whether that checkout is dirty, which is the only honest answer to
   "which framework version is this?" while the dependency is a path.

   Everything else Prudent needs — the contract loop, the server build, the local stack, the
   deploy — has **not** moved into that file yet and is still zen_demo-shaped in
   `../jZen/Taskfile.yml`. Prudent writes those itself for now. Where one turns out to be
   app-agnostic, say so: the migration is meant to continue, and Prudent is the evidence for
   which task moves next.
2a. **Target platforms are now a real choice, not new ground.** jZen supports macOS, iOS,
   Android, web **and, since ADR-045, Linux and Windows** — `zen_demo` builds runner directories
   for all of them and `zen:build:runners` compiles every target the host can. Two consequences
   for Prudent's plan:

   - **Desktop builds are host-only.** Flutter refuses `build linux` off Linux and `build windows`
     off Windows, measured, by name. So Prudent's CI needs `ubuntu-latest` **and**
     `windows-latest` for any desktop target it claims, and no developer machine can verify the
     full set. Decide the platform list deliberately: each one added is a CI job, and a platform
     claimed without a build is a claim nobody can reproduce.
   - **Today's app already carries `linux/` and `windows/` directories** (from `flutter create`),
     which is not the same as supporting them. Say in the plan which platforms Prudent actually
     ships, and delete or keep those directories on that basis rather than by inheritance.

   Note the existing UI already branches on desktop-vs-mobile via `Theme.of(context).platform`,
   while jZen's `zen_ui_navigation` branches on the compile-time `zenIsDesktop`. Those are two
   different mechanisms answering the same question; reconcile them rather than running both.

3. **The jZen dependency seam, and its cost.** Dart via `path:` into `../jZen/client/*`; Java via
   `zen-parent` with an **empty `<relativePath/>`** resolved from the local Maven repository, which
   makes `(cd ../jZen/server && ./mvnw -B install -DskipTests)` a build prerequisite; admin (if any)
   via a TypeScript `paths` + Vite alias into `../jZen/admin/src`. Spell out the consequences: **no
   version boundary**, the two checkouts must move in lockstep, CI needs both, and a contributor
   needs the sibling checkout at exactly that path. Then state the exit: what changes when jZen
   publishes its packages, and why that is an ADR rather than a cleanup.
4. **Flyway band coordination.** jZen's `zen-identity` owns framework migrations and runs them into
   Prudent's database. Flyway is the **single migration authority** — pick Prudent's version band so
   it can never collide with jZen's present or future bands, and write the rule down before the
   first migration exists.
5. **Database and local stack.** Prudent needs Postgres, and jZen's auth path needs Supabase
   (server-side only — `SUPABASE_URL`/`SUPABASE_KEY` never reach a client). Decide what the local
   stack is, whether it collides with a running jZen stack (ports 8080/54322), and what the test
   story is (`@QuarkusTest` + Dev Services needs Docker).
6. **Verification and CI.** Prudent has no tests today. Define the suites the plan must create
   (backend `@QuarkusTest`, Dart/Flutter unit, an end-to-end gate) and the equivalents of jZen's
   `verify:boundaries` (the client-talks-to-one-server gate — the single most important one here,
   given the Firebase call) and `sync:contracts` (the contract-drift gate).
7. **Findings to report upstream.** jZen has only ever had one application. Anything you hit that is
   hardcoded to `zen_demo`, or that assumes the framework and the app share a repository, is a
   jZen-side finding — list it as such. Do not work around it silently here, and do not fix it by
   editing `../jZen`.
8. **Docs.** The plan includes this repository's README, `docs/DECISIONS.md`, and **an ADR** (use the
   `add-adr` skill, Prudent's own numbering from ADR-001) recording every rule the conversion
   settles: repo shape, the path-dependency seam, Flyway band, money type, namespace, locale set.

## Phase 4 — Sequence the work

Deliver a phased plan where **every phase ends green and verifiable**, each with the exact command
that proves it. A suggested spine — challenge it if the analysis says otherwise:

0. Repo scaffolding: language-neutral root, `client/` move, `Taskfile.yml`, the jZen dependency seam
   wired and proven by a build that does nothing else. The Flutter app still runs.
1. Contract: `proto/prudent/v1/*.proto` plus the generate/verify loop and its committed output.
2. `server/`: Panache entities, Flyway migration, MapStruct mappers, resources +
   `META-INF/openapi.yaml`, backend tests covering both transport modes and the `ZenError` path.
3. `client/`: repository and providers over `ZenClient`, auth via `zen_ui_identity`, the Firebase
   call deleted, screens rewired, strings moved to ARB.
4. Analytics and the chart, then whatever was stubbed — labeled as **new work**, not "porting".
5. Admin panel (if in scope), the end-to-end gate, a deploy target, docs and the ADR.

For each phase list the files created/changed, the tests that must exist, and the risk it carries.

## Non-negotiables to check the plan against

- No `quarkus-rest-jackson` server-side; JSON is canonical proto3 JSON.
- Every module contributing CDI beans or JAX-RS providers runs `jandex-maven-plugin` — omission
  fails **silently**.
- Tracked generated files are never hand-edited; fix the source and regenerate.
- Nothing swallows a failure — no `|| true`, no discarded exit code, no null on a decode error.
- No client package calls Firebase, Supabase, or any third party directly.
- Comments and docs explain Prudent on its own terms, as an application built on jZen — its
  declared dependency — never as something "ported" or "derived". The conversion's own record
  (`docs/DECISIONS.md`, this file) is where the before-state is discussed.

## Ask me before assuming

Stop and ask, do not guess: whether Prudent requires authenticated per-user data from day one; the
money representation; multi-currency and FX; whether existing Firebase data must be migrated or is
disposable; whether an admin panel and a WebSocket surface are in scope; whether framework chrome is translated to Polish or left in English; the locale set (today's
the target platforms — the app force-locks portrait yet ships a
desktop navigation, and Linux/Windows are now supported by the framework but cost a CI runner
each; Prudent's own package/namespace; and the deployment target.

## Deliverable

A single Markdown document at `docs/prudent-migration-plan.md` containing: the Phase 1 inventory,
the Phase 2 mapping table with rationale, the Phase 3 repository and cross-repo findings with file
references, the Phase 4 sequenced plan with per-phase verification commands, an explicit **open
questions** section, and an explicit **out of scope / deliberately not ported** section. Then
summarize the top five decisions I need to make, and stop — write no application code until I
approve the plan.
