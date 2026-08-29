# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this
repository.

## What Prudent is

Prudent is a **minimalist personal-finance application** — accounts, categories, records
(transactions), an overview and analytics. It is its own product and its own git repository.

Prudent is built on **jZen**, a framework/platform for full-stack applications (Java/Quarkus
server + Dart/Flutter client + a contract in Protobuf). Prudent is jZen's *consumer*, not part of
it: jZen's libraries arrive here as declared dependencies, and no work in this repository ever
edits the jZen checkout.

**[`docs/zen-architecture.md`](docs/zen-architecture.md) is Prudent's cornerstone** — the design
philosophy this product is built on. Read it before non-trivial work. It is Prudent's own and it is
permanent: it holds whether jZen arrives as a sibling checkout, as a published package, or not at
all.

**Prudent's rules are Prudent's.** They live in `docs/` and `docs/DECISIONS.md` (Prudent's own ADR
numbering, from ADR-001). jZen's documents constrain this repository only where Prudent actually
consumes the framework — the contract, the transport seam, auth, migrations — and they are read
from the `../jZen` checkout rather than copied here, so they cannot drift.
[`docs/jzen/README.md`](docs/jzen/README.md) is the index of pointers; jZen's ADR archive
(`../jZen/docs/architecture/DECISIONS.md`) wins on conflict with jZen's other documents. Where a
jZen rule and a Prudent rule conflict on something **Prudent** owns, Prudent's wins and the
divergence is recorded as a Prudent ADR.

## Current state: Phases 0-5 have landed; deploy has not

As of 2026-08-23 the repository has a **language-neutral root over four tiers**: `client/` (the
Flutter app), `server/` (a Quarkus backend), `admin/` (the react-admin panel),
`proto/prudent/v1/` (the wire contract), and a `Taskfile.yml` that includes jZen's. The contract,
its generate/verify loop and the round-trip suite that proves it are in place —
`task sync:contracts` and `task zen:test:client` are the commands that check them.

Built and merged: the backend (`AccountResource`, `CategoryResource`, `RecordResource`,
`SettingsResource`, `AnalyticsResource`, `HealthResource` over four Panache entities), the Flyway
migration and its row-level security, and the client rewired onto `ZenClient` with auth and the
navigation shell (`client/lib/prudent_repository.dart`). The third-party backend call the
conversion existed to remove is gone.

**Not built: a deploy path.** `verify:deploy` is written against a real environment "if one ever
exists", and there is no `deploy` task. Treat deploying Prudent as conversion work, not as
something to attempt.

**Done: the structural flattening (ADR-026).** Client code is now flat under `client/lib/` on a
capability-folder layout (`account/ analytics/ auth/ category/ generated/ l10n/ overview/ record/`
plus flat files) — `client/lib/src/` is gone. The server package is `prudent.*` (`prudent/server/`
gone; new `health/` and `error/` capability packages). Tests flattened to match. It was a pure
`git mv` pass with no behaviour change, driven by `docs/prudent-restructure-prompt.md`. Any
`lib/src/…` or `prudent.server.…` path in an older doc or ADR is historical — the current tree is
the one described here.

**Keep this section true.** It is the first thing a session reads, and it was wrong for a week —
it still claimed no resources, no entities, no migrations and no `ZenClient` after all four had
merged, which sends every session looking for work that was already done. When a phase lands,
update it in the same commit.

**`docs/implemented-plans/prudent-migration-plan.md` is the approved plan the remaining phases execute**, and
`docs/implemented-plans/prudent-migration-prompt.md` is the brief behind it — read them before proposing structural
change, and do not invent a different target shape. Check what actually exists before building on
it: parts of the structure described below are built and parts are still the target, `docs/DECISIONS.md`
is the record of which, and a session must not speak about the unbuilt half as if it already exists.

## How Prudent depends on jZen: a sibling checkout, by path

jZen's packages are all `0.1.0` and unpublished (`publish_to: none`, Maven `-SNAPSHOT`, no npm
registry entry). Until they are published, Prudent consumes them from a **sibling checkout at
`../jZen`**:

- **Dart/Flutter** — `path:` dependencies (`../../jZen/client/zen_core`, `zen_transport`,
  `zen_identity`, `zen_secure_store`, `zen_ui_identity`, `zen_ui_navigation`).
- **Java** — Prudent's server module declares `zen-parent` as its parent with an **empty
  `<relativePath/>`**, resolving it and the framework libs (`zen-core`, `zen-proto`,
  `zen-transport`, `zen-identity`, `zen-email`, `zen-jobs`, `zen-ratelimit`) from the **local
  Maven repository**. A build therefore has a prerequisite: `(cd ../jZen/server && ./mvnw -B install
  -DskipTests)`. Never reach across repositories with a filesystem `<relativePath>` — that couples
  the build to a directory layout instead of to a version.
- **Admin (if built)** — `@jzen/admin-core` from `../jZen/admin/src` via a TypeScript `paths`
  alias + Vite `resolve.alias`, not a pnpm dependency edge.

**This is a temporary shape with a known cost:** the two checkouts must move together, and there
is no version boundary between them. When jZen publishes its packages, replacing every path
dependency with a version range is a deliberate, ADR-worthy step — not a cleanup — and `docs/jzen/`
is deleted as part of it, since a versioned dependency's documentation travels with the package.

**jZen is a dependency, not a donor.** Read `../jZen` freely for reference implementations
(`apps/zen_demo/*` is the reference application), but never write to it, and never copy framework
source into this repository. If Prudent needs a framework change, that change is made in jZen and
consumed — say so explicitly rather than forking a copy here.

## Target structure

The repo root stays **language-neutral** (jZen STANDARDS): no root `pom.xml`, no root
`pubspec.yaml`, no root `package.json`.

```
proto/prudent/v1/*.proto   the contract — canonical for models
server/                    the Quarkus backend (packaging: quarkus)
client/                    the Flutter app (today's root package moves here)
admin/                     react-admin panel (only if in scope)
docs/                      Prudent's docs (zen-architecture.md is the cornerstone)
Taskfile.yml               the single orchestrator; includes ../jZen/Taskfile.app.yml
```

**Platforms.** jZen supports macOS, iOS, Android, web, Linux and Windows (jZen ADR-045). Desktop
builds are **host-only** — Flutter refuses `build linux` off Linux and `build windows` off Windows
— so every desktop target Prudent claims costs a CI runner, and no single machine can verify the
full set. Claim the platforms Prudent actually ships and let CI prove them.

`task` (go-task) is the only entry point, and it **triggers native tools, never replaces them** —
`mvnw` owns Java, `dart pub` owns Dart, `pnpm` owns TypeScript. A task that reimplements a package
manager is a bug.

Prudent's `Taskfile.yml` **includes** jZen's application-facing orchestration rather than copying
it (jZen ADR-046):

```yaml
includes:
  zen:
    taskfile: ../jZen/Taskfile.app.yml
    vars: {APP_NAME: prudent, CLIENT_DIR: client, SERVER_DIR: server, PROTO_DIR: proto}
```

Included tasks run in **this** repository's directory, and jZen consumes the same file for its own
reference app, so it is shared code rather than a lookalike. `task zen:info` reports which jZen
checkout is in use, at which revision, and whether it is dirty — run it first when a build behaves
oddly. Tasks jZen has not yet made app-agnostic (the contract loop, the server build, the local
stack, the deploy) are Prudent's own for now.

## The rules Prudent inherits and cannot bend

These come with the framework Prudent depends on. They are load-bearing, several of them **fail
silently** when broken, and unlike jZen's house style they are not Prudent's to override — a
consumer that bends them stops being a consumer:

- **Contract-first, one direction.** `.proto` is canonical for models; SmallRye-annotated Quarkus
  resources are canonical for the REST surface. Java DTOs, Dart messages, `openapi.json` and admin
  TS are **derived**. A tracked generated file is **never** hand-edited — fix the source and
  regenerate. See the `sync-contracts` skill.
- **The client talks to one server, and it is ours.** No client package calls Supabase, Firebase,
  or any third party directly. Today's Firebase Realtime Database call in `lib/main.dart` /
  `lib/record/records_provider.dart` is exactly what this rule forbids, and removing it is the
  spine of the conversion. This breaks *silently*: an app that authenticates against someone
  else's backend still passes every test.
- **No server-side `quarkus-rest-jackson`.** jZen's JSON is canonical proto3 JSON from
  `JsonFormat`. Jackson hijacks `application/json` at build time and 500s on proto messages, so it
  must be *absent*, not out-prioritized.
- **Every library module contributing CDI beans or JAX-RS providers runs `jandex-maven-plugin`.**
  Without `META-INF/jandex.idx` Quarkus never discovers them — no error, the filters just do
  nothing.
- **Compile-time config on the client.** `String.fromEnvironment` + `if (dart.library.io)` /
  `if (dart.library.html)` conditional imports; build defines are `ZEN_ENV` / `ZEN_PLATFORM`.
  Runtime config on the client is **forbidden** — it is what lets the toolchain tree-shake the
  native-only Protobuf path out of the web bundle. The server is the deliberate opposite: runtime
  MicroProfile config.
- **Typed, generated i18n.** No hardcoded user-facing strings. Each package owns `lib/l10n/*.arb`
  + `l10n.yaml` and generates accessors with `flutter gen-l10n`; the generated output is built, not
  committed. **Prudent supports `{en, uk, pl}`** — its own decision, not the framework's (jZen
  ADR-044). `ZenLocales.shipped` is jZen's inventory (`{en, uk}`) and is a floor, not a ceiling:
  Prudent declares its set as a compile-time `const` on the client and as `zen.i18n.supported` on
  the server, and framework screens degrade to English under `pl` rather than crashing. See
  `docs/implemented-plans/prudent-migration-plan.md` for how Polish is delivered.
- **Flyway is the single migration authority.** Never two migration systems on one database.
  Prudent owns a Flyway version band that cannot collide with jZen's `zen-identity` band — pin the
  band in an ADR before writing the first migration.
- **Nothing swallows a failure.** No `|| true`, no discarded exit code, no null returned where a
  decode failed. If you are about to make a failure quieter, you are about to introduce a bug.
- **All work happens inside this repository.** Nothing reaches outside the repo root to modify a
  file; anything Prudent depends on arrives as a declared dependency. `../jZen` is read-only.

## Explaining things

A comment earns its place by saying *why* a constraint exists, in language a reader with no
history here can follow. Prudent is described on its own terms — as an application built on jZen,
which is a declared dependency, not as anything "ported", "migrated from", or "derived". The
conversion's own record (`docs/DECISIONS.md`, `docs/implemented-plans/prudent-migration-prompt.md`) is where the
before-state is discussed.

## Decisions

Architectural decisions are recorded in `docs/DECISIONS.md` — **Prudent's own log, with its own
numbering starting at ADR-001**, append-only (add an entry, never edit an accepted one). It is
distinct from jZen's archive; do not renumber against it or write Prudent decisions into it. Use
the `add-adr` skill.

## Working agreement

**Never run `git commit` or `git push` without explicit approval from the user.**

**Never commit onto `main`** — branch first, even with approval in hand, and especially right
after a PR merge, when the working copy has just landed back on `main`.

Both rules, and the 50-character subject limit, are enforced by `.Codex/hooks/git_guard.py`
rather than by memory. A fresh clone has no git-side guard until
`sh .Codex/hooks/install-git-hooks.sh` runs, because `.git/hooks` is not tracked.
`.Codex/hooks/skill_guard.py` delivers a skill's rules the first time a file it governs is
edited in a session; the path-to-skill mapping is `.Codex/hooks/skill-map.json`.

Two more guards close the gap between "a rule exists" and "a rule fires":
`.Codex/hooks/verify_guard.py` runs on `Stop` and refuses to end a turn that changed source
without running a suite (config: `verify-rules.json`; docs, `.Codex/` and generated output are
exempt, and it never fires twice in a row). `skill_guard.py` also matches **commands**, not just
paths — so `long-job` arrives on the first slow build and `deploy` on the first `gcloud`, which
are skills no file edit could ever have summoned.

**Branch names are `<type>/<slug>`** — `feature/`, `fix/`, `docs/`.

**When a command fails twice with the same error, escalate instead of retrying** — hand over the
exact command for the user to run with the `!` prefix. Interactive authentication is never a
retry problem.

**There is no deploy path yet.** `verify:deploy` is written against a real environment "if one
ever exists". Do not write skills, plans or docs that describe deploying Prudent as though it
were possible today; say it is conversion work instead.

### What is in `.Codex/`

| | Purpose |
|---|---|
| `skills/add-adr` | record a decision in `docs/DECISIONS.md` (append-only, Prudent's own numbering) |
| `skills/add-endpoint` | add a REST endpoint contract-first (OpenAPI merge, Jandex, no-Jackson) |
| `skills/sync-contracts` | the proto → Java/Dart/TS regeneration loop and its drift gate |
| `skills/jzen-reference` | find a pattern in the sibling `../jZen` checkout, read-only |
| `skills/long-job` | how to wait on a slow command, with this repo's measured durations |
| `agents/visual-verify` | drive a change in a real browser; returns pass/fail + screenshots |
| `agents/regression-guard` | review a diff for what it broke and what it duplicated |
| `hooks/` | the guards above, their config, and their tests |

Run the hook tests with `python3 .Codex/hooks/test_git_guard.py` and
`python3 .Codex/hooks/test_skill_guard.py`.

Permissions are prefix rules in the tracked `.Codex/settings.json` (read-only git, inspection
tools, this repo's own build and test entry points). `settings.local.json` is for genuine
one-offs; it is gitignored and never the place for a rule everyone needs.


## The working tree is shared

The user edits files in this repository while a session runs. A session that
assumes it is alone commits their work by accident.

**Stage by explicit path, and check the index before committing.** `git add -A`
and `git add .` sweep up whatever is there. Even explicit paths are not enough
on their own: run `git diff --cached --name-only` immediately before `git
commit` and confirm every entry is a file you wrote. A file can already be
staged when you arrive.

**Never switch branches while files you did not touch are modified.** A switch
either aborts or carries someone else's work onto another branch, and a stash
taken to get around it pops straight back onto the branch you were leaving.
Use a worktree, which needs no stash and leaves this tree untouched:

    git worktree add -b <branch> <dir> origin/main
    # work, commit, push from <dir>
    git worktree remove <dir>

This applies to `git checkout -b <branch> <start-point>` too: git aborts that
whenever a modified file differs between HEAD and the start point.

**Leave what is not yours exactly as you found it.** If you have to undo your
own commit, verify afterwards that their files are still modified and still
theirs.

`.Codex/hooks/worktree_guard.py` enforces all of this: it recovers the files
this session wrote from the transcript, refuses a commit whose index holds
anything else, and refuses a branch switch under foreign changes. Prefix a
command with `ALLOW_FOREIGN=1` when the foreign files genuinely belong in the
commit.
