# Prompt — flatten Prudent onto a Zen layout (client `lib/`, server `prudent.*`)

> **Historical.** This is the brief that drove the ADR-026 flattening. That pass is done —
> `client/lib/src/` and the `prudent.server.*` package are gone, the tests are flattened to match,
> and `task test:server` / `task zen:test:client` / `task sync:contracts` are green. The outcome
> is recorded in `docs/DECISIONS.md` ADR-026, which supersedes this brief wherever they disagree.
> Kept as the record of what was asked for — **do not run it again;** every `lib/src/…` and
> `prudent.server.…` path below describes the *before* state.

> Paste everything below the line into a fresh Claude Code session started in
> `/Users/amerezhanyi/Developer/jZenDev/prudent`. This is a **pure structural pass** — `git mv` and
> import rewrites only, no behaviour change. The decision it executes is `docs/DECISIONS.md`
> **ADR-026**; read that first, it is authoritative on every rule below.

---

You are working in the **Prudent** repository. Read `CLAUDE.md`, then `docs/zen-architecture.md`
(the cornerstone — "Packages as capabilities"), then `docs/DECISIONS.md` **ADR-026** in full.

**Task:** carry out the layout flattening ADR-026 describes. The client's half-migrated
`lib/` / `lib/src/` split is completed into `lib/`; every "dumb container" directory (a folder that
only groups by technical role, or that wraps a single file or a single child directory) is removed;
the server's `prudent.server.*` package is flattened to `prudent.*`. Reference layout for the
capability-folder style: `../jZen/apps/zen_demo` and `../../bugeater/bugeater-quarkus/src/main/java`
(read-only, both).

## The layout rule (ADR-026, restated so you can check every move against it)

1. **A directory names a product capability, never a technical role.** `screens/`, `widgets/`,
   `services/`, `mappers/`, `models/` are banned as directory names — they are layers, not
   capabilities.
2. **A directory must earn itself with two or more files** that belong to one capability. A
   single-file concern is a **file at the parent level**, not a lone-child directory
   (`lib/shell/home_shell.dart` → `lib/home_shell.dart`).
3. **A wrapper directory with exactly one child directory is removed** (`java/prudent/server/` →
   `java/prudent/`, because nothing else will ever sit beside `server/`).
4. **Cross-cutting single-file utilities may sit flat at the package root** — this is the one
   narrow exception to rule 2. On the server that is `Ids.java`, `Currencies.java`. It does not
   license a `util/` bucket.
5. **No behaviour change.** Every file keeps its contents; only its path and its `package` /
   `import` lines change. `git mv` preserves history — use it.

## Client — target `lib/` layout

Delete `lib/src/`, `lib/screens/`, `lib/chart/`, `lib/widgets/`, `lib/record/records_list/` as
directories. Result:

```
lib/
  main.dart                 (unchanged — composition root)
  app.dart                  ← lib/src/app.dart
  home_shell.dart           ← lib/src/screens/home_shell.dart
  prudent_repository.dart    ← lib/src/prudent_repository.dart
  providers.dart            ← lib/src/providers.dart
  money.dart                ← lib/src/money.dart
  settings.dart             ← lib/screens/settings.dart          (one screen, no other settings file)
  popup.dart                ← lib/widgets/popup/popup.dart
  account/                  (unchanged — 4 files)
  category/                 (unchanged — 6 files, incl. category_records.dart)
  record/                   new_record.dart, records_screen.dart,
                            record_item.dart, records_list.dart   ← records_list/ flattened in
  overview/                 overview.dart      ← lib/screens/overview.dart
                            overview_totals.dart ← lib/src/overview_totals.dart
  analytics/                analytics.dart     ← lib/screens/analytics.dart
                            chart_screen.dart, bar_chart_painter.dart, donut_chart_painter.dart
                                               ← lib/chart/*   (analytics + its charts are one capability)
  auth/                     auth_deep_links.dart, auth_deep_links_native.dart,
                            auth_deep_links_stub.dart   ← lib/src/*
                            auth_flow.dart     ← lib/src/screens/auth_flow.dart
  l10n/                     pl_identity_delegate.dart, pl_identity_localizations.dart,
                            pl_navigation_delegate.dart, pl_navigation_localizations.dart,
                            prudent_en.arb, prudent_uk.arb, prudent_pl.arb   ← lib/src/l10n/*
    generated/              (built by `task zen:generate:l10n`, untracked — output-dir moves here)
  generated/                ← lib/src/generated/**   (tracked proto messages)
```

Rejected on purpose (rule 2): `lib/shell/`, `lib/money/`, `lib/settings/`, `lib/data/`,
`lib/repository/` — each would hold one file.

Then rewrite imports: `package:prudent/src/<x>` → `package:prudent/<x>` (or the new capability
path), across every Dart file under `lib/` and `test/`. Fix the relative imports the moved files
carry, including the `auth_deep_links` conditional-import bodies.

## Server — target `prudent.*` layout

Rename the base package `prudent.server` → `prudent` (main **and** test), then:

```
java/prudent/
  Ids.java                  ← prudent/server/Ids.java            (flat util — exception, rule 4)
  Currencies.java           ← prudent/server/Currencies.java     (flat util — exception, rule 4)
  CurrentUser.java          ← prudent/server/CurrentUser.java    (one file; no prudent/auth/ package for it)
  NewUserSetup.java         ← prudent/server/onboarding/NewUserSetup.java   (one file)
  AnalyticsResource.java    ← prudent/server/analytics/AnalyticsResource.java   (one file; becomes
                              prudent/analytics/ only when a service class joins it)
  health/                   HealthResource.java, PrudentStatus.java   ← prudent/server/{HealthResource,PrudentStatus}.java
  error/                    PrudentException.java, PrudentExceptionMapper.java   ← prudent/server/*
  record/                   RecordEntity, RecordMapper, RecordResource        (rename package only)
  account/                  AccountEntity, AccountMapper, AccountResource, AccountBalance, AccountKind
  category/                 CategoryEntity, CategoryMapper, CategoryResource, IconKeys
  settings/                 SettingsEntity, SettingsMapper, SettingsResource
  retention/                UserRetentionZenJob, PrudentRetentionCleanup
```

Tests move in lockstep: `prudent/server/*Test.java` → `prudent/*Test.java`,
`prudent/server/retention/PrudentRetentionCleanupTest.java` → `prudent/retention/`.

**No `prudent/auth/` package.** Prudent delegates auth entirely to `zen-identity`; `CurrentUser`
(a `@RequestScoped` JWT-`sub` accessor) is its only auth-related class, so by rule 2 it is a flat
file. If a second auth class ever appears, `prudent/auth/` forms then. *(If you want a
`prudent/auth/` package regardless, stop and ask — it contradicts rule 2 and needs a decision.)*

The generated DTO namespace `prudent.proto.v1` (proto `java_package`, ADR-006) is **unchanged** —
it is already a distinct, sensible namespace and no hand-written code lives in it.

## Ripple checklist — every file that references the old paths

Work through all of these; a missed one is a broken build or a silently vacuous gate.

**Client / Dart**
- `Taskfile.yml` — `PROTO_DART_OUT: client/lib/src/generated` → `client/lib/generated`, and the
  surrounding comment block that explains the `lib/src/` choice (rewrite it to explain the flat
  `lib/generated/` choice, or delete it).
- `client/l10n.yaml` — `arb-dir: lib/src/l10n` → `lib/l10n`; `output-dir: lib/src/l10n/generated`
  → `lib/l10n/generated`; rewrite the header comment.
- `client/analysis_options.yaml` — exclude `lib/src/generated/**` → `lib/generated/**`.
- `client/.gitattributes` **and** root `.gitattributes` — `client/lib/src/generated/**` →
  `client/lib/generated/**` (search both; the root one has three `linguist-generated` lines).
- `client/pubspec.yaml` — check `flutter: assets:` / `fonts:` for any `lib/src/...` path (bundled
  font from ADR-013).
- After the moves: `task zen:generate:l10n` to regenerate accessors into the new dir, then confirm
  `git status` shows `lib/l10n/generated/` **untracked** (the `sync:contracts` gate asserts it).

**Server / Java**
- `server/pom.xml` — comment references to `prudent.server.retention` and
  `prudent.server.account.AccountBalance` (there are at least two, in the jandex note and the PMD
  note); `<relativePath/>` and `groupId` are unaffected.
- `server/pmd-ruleset.xml` — any package-scoped `<rule>` or suppression path.
- `server/src/main/resources/application.properties` — grep for package-scoped keys
  (`quarkus.hibernate-orm.*.packages`, `quarkus.index-dependency.*`, `*.packages`); the
  `prudent://auth-callback` lines are a URI scheme, not a package — leave them.
- `server/src/main/resources/META-INF/openapi.yaml` — hand-authored, no package refs expected, but
  check `x-` extensions.
- MapStruct `@Mapper` types resolve by moving the source; no `componentModel` change.
- Regenerate `META-INF/jandex.idx` as part of the build (it is not tracked).

**Gates / hooks**
- `.claude/hooks/skill-map.json` — `client/lib/src/generated/*` → `client/lib/generated/*`.
- `scripts/verify_boundaries.py` — verify no change needed (`CLIENT_LIB_SCOPE = "client/lib"` and
  the `/generated/` substring exclusion both still hold) and say so; do **not** edit it blindly.
- `Taskfile.yml` `sync:contracts` / `sync:verify` globs — `*.pb.dart` and `*/l10n/generated/*`
  still match; confirm.

**Docs (prose — update where the path is stated as current fact)**
- `CLAUDE.md` and `AGENTS.md` (mirrors) — `client/lib/src/prudent_repository.dart` →
  `client/lib/prudent_repository.dart`; "Each package owns `lib/src/l10n/*.arb`" → `lib/l10n/*.arb`.
- `docs/implemented-plans/prudent-migration-plan.md` — leave the Phase 1 inventory (it describes
  the *original* app); the ADR-026 note in its status block is already there.
- `docs/jzen/README.md` — the `prudent.server.retention.PrudentRetentionCleanupJob` reference is
  already historical (renamed by ADR-022); update the package segment only if you touch the line.
- Do **not** edit `docs/DECISIONS.md` ADR-001's `prudent/server/PrudentStatus.java` reference —
  ADRs are append-only; ADR-026 already records that the file moved.

## Execution order (safe, reviewable)

1. **Branch** — `git worktree add -b refactor/zen-layout <dir> origin/main` (the working tree is
   shared; do not switch branches in place).
2. **Server first** (smaller, self-contained): rename the package, move the files, rewrite
   `package`/`import` lines, update `pom.xml` + `application.properties` + `pmd-ruleset.xml`. Prove:
   `task test:server` green (was 79/79 at ADR-023 — expect the same count).
3. **Client**: move files, delete the emptied directories, rewrite imports, update `Taskfile.yml` +
   `l10n.yaml` + `analysis_options.yaml` + `.gitattributes` + `pubspec.yaml`. Regenerate l10n and
   proto Dart. Prove: `task zen:test:client` green, `flutter analyze` clean.
4. **Gates**: `.claude/hooks/skill-map.json`; verify `scripts/verify_boundaries.py` unchanged.
5. **Docs**: the prose edits above.
6. **Full sweep**: `task sync:contracts && task test:server && task zen:test:client && task verify:boundaries`
   — and a web build (`task build:web` or `cd client && flutter build web --wasm`), because a
   moved conditional import is exactly what a web build catches that unit tests do not.
7. Report the diff stat and every command's result. **Do not commit** until I have reviewed it.

## Constraints

- `git mv` only for the moves — history must survive. No file's *contents* change except its
  `package` / `import` / path-string lines.
- The working tree is shared: stage by explicit path, run `git diff --cached --name-only` before
  any commit, and confirm every entry is a file this session moved.
- Never `git commit` / `git push` without explicit approval. Never commit onto `main`.
- If any suite's test **count** drops, stop — a lost test is a behaviour change and this pass has
  none.
- Commit subject (when approved) ≤ 50 chars, e.g. `Flatten client lib/ and server prudent.*`.

## Deliverable

The restructured tree, all six verification commands green with their output shown, a
`git diff --stat`, and a short note of anything that did not fit the rule cleanly (so ADR-026 can
be amended if needed). Then stop.
