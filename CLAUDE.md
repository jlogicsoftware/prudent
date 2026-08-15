# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
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

## Current state: Phases 0 and 1 are done; the rest is not

As of 2026-08-15 the repository has a **language-neutral root over three tiers**: `client/` (the
Flutter app), `server/` (a Quarkus module that compiles and serves nothing), `proto/prudent/v1/`
(the wire contract), and a `Taskfile.yml` that includes jZen's. The contract, its generate/verify
loop and the round-trip suite that proves it are in place — `task sync:contracts` and
`task zen:test:client` are the commands that check them.

What is **not** built yet: no Quarkus resources, no Panache entities, no migrations, no auth, no
`ZenClient` on the client. The client is still Riverpod state over in-memory seed lists, and it now
persists nothing — the third-party backend call was removed ahead of its replacement (ADR-004).

**`docs/prudent-migration-plan.md` is the approved plan the remaining phases execute**, and
`docs/prudent-migration-prompt.md` is the brief behind it — read them before proposing structural
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
- **Typed, generated i18n.** No hardcoded user-facing strings. Each package owns `lib/src/l10n/*.arb`
  + `l10n.yaml` and generates accessors with `flutter gen-l10n`; the generated output is built, not
  committed. **Prudent supports `{en, uk, pl}`** — its own decision, not the framework's (jZen
  ADR-044). `ZenLocales.shipped` is jZen's inventory (`{en, uk}`) and is a floor, not a ceiling:
  Prudent declares its set as a compile-time `const` on the client and as `zen.i18n.supported` on
  the server, and framework screens degrade to English under `pl` rather than crashing. See
  `docs/prudent-migration-plan.md` for how Polish is delivered.
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
conversion's own record (`docs/DECISIONS.md`, `docs/prudent-migration-prompt.md`) is where the
before-state is discussed.

## Decisions

Architectural decisions are recorded in `docs/DECISIONS.md` — **Prudent's own log, with its own
numbering starting at ADR-001**, append-only (add an entry, never edit an accepted one). It is
distinct from jZen's archive; do not renumber against it or write Prudent decisions into it. Use
the `add-adr` skill.

## Working agreement

**Never run `git commit` or `git push` without explicit approval from the user.**
