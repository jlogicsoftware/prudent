# Prudent

A **minimalist personal-finance application** — accounts, categories, records, an overview and
analytics.

Prudent is built on **[jZen](https://github.com/jZenDev/jZen)**, a framework for full-stack
applications: a Quarkus server, a Flutter client, and a contract in Protobuf. jZen is a **declared
dependency** — Prudent is its consumer, not part of it, and nothing here ever edits the jZen
checkout.

## The three tiers

The repository root is **language-neutral** on purpose: no root `pom.xml`, no root `pubspec.yaml`,
no root `package.json`. Each tier owns its own build file, and the root owns none of them.

```
prudent/
├── Taskfile.yml   the single entry point; includes ../jZen/Taskfile.app.yml
├── client/        the Flutter application (Android, iOS, web, macOS, Linux, Windows)
├── server/        the Quarkus backend
├── admin/         the react-admin panel (assembles @jzen/admin-core)
├── proto/         the wire contract (canonical for models)
├── docs/          the architecture, the plan, and the decision log
├── .github/       CI (two operating systems) and the scheduled dependency audit
└── LICENSE
```

> **`flutter run` no longer works from the repository root.** The root is not a Dart package any
> more, so it is `cd client && flutter run`. That is the price of a language-neutral root, and it is
> the one thing that will surprise someone returning to this repository. Every `task` command below
> is run from the root; only the raw `flutter`/`mvnw` ones are run from inside a tier.

## Prerequisite: the jZen checkout

**jZen's packages are unpublished** — every one is `0.1.0`, with `publish_to: none` on the Dart
side, `-SNAPSHOT` on the Maven side, and no npm registry entry. Until they are published, Prudent
consumes them from a **sibling checkout that must be at exactly `../jZen`**:

```
some-folder/
├── jZen/         <- the framework, read-only from here
└── prudent/      <- this repository
```

```bash
git clone https://github.com/jZenDev/jZen.git
git clone https://github.com/jlogicsoftware/prudent.git
cd prudent
```

**There is no version boundary between the two repositories.** They move in lockstep: a `git pull`
in `../jZen` can break this build, with no version to point at. The reasoning, the cost and the exit
are recorded in [`docs/DECISIONS.md`](docs/DECISIONS.md) ADR-001.

## Getting started

```bash
task zen:info                 # run this FIRST — see below
task zen:framework:install    # build jZen's Java libraries into your local Maven repository
task deps                     # resolve every tier's dependencies (Maven + pub + pnpm)

task run:dev                  # Supabase + backend + web client together, one Ctrl-C stops it
```

### Run `task zen:info` first

```
app:        prudent
app root:   /path/to/prudent
tiers:      client=client server=server proto=proto
jZen:       /path/to/jZen
jZen rev:   73e2b18
```

Because the framework arrives by path rather than by version, **the only honest answer to "which
jZen is this?" is a commit** — and the only warning that the answer is unstable is a dirty tree,
which `zen:info` reports as `(DIRTY - uncommitted changes; this build is not reproducible)`. Every
failure mode of a path-consumed framework looks like a broken build rather than a missing sibling,
so check this before reading a stack trace.

### If the server build says the parent POM cannot be resolved

```
Non-resolvable parent POM for prudent:prudent-server:0.1.0-SNAPSHOT:
zen:zen-parent:pom:0.1.0-SNAPSHOT was not found
```

**The POM is not broken.** `server/pom.xml` inherits `zen-parent` with an empty `<relativePath/>`,
which resolves it from your local Maven repository — and something has to put it there first. Maven
cannot express that prerequisite, because a build cannot declare "go build another repository". The
fix is:

```bash
task zen:framework:install
```

Run it again after every `git pull` in `../jZen`. The long version of this reasoning lives in
`server/pom.xml`, next to the `<parent>` block it explains.

## Commands

Everything is driven by [`task`](https://taskfile.dev) (go-task), which **triggers native tools and
never replaces them**: `mvnw` owns Java, `flutter`/`dart pub` owns Dart, `pnpm` owns TypeScript.

| Command | What it does |
|---|---|
| `task zen:info` | Which jZen checkout, which revision, dirty or not |
| `task zen:framework:install` | Installs jZen's Java libraries into the local Maven repository |
| `task deps` | Resolve every tier's dependencies — Maven (server) + pub (client) + pnpm (admin) |
| `task generate` | Regenerate every generated artifact (proto, OpenAPI, admin types, l10n); no gate |
| `task verify:contracts` | `generate`, then fail if a tracked generated file drifted (the CI gate) |
| `task verify:boundaries` | Fails if the client (or the admin panel) reaches past Prudent's own server |
| `task test:server` | The backend suites against a throwaway Postgres |
| `task zen:test:client` | Every Dart/Flutter suite |
| `task test:admin` | Typechecks the admin panel |
| `task test:e2e` | The release gate — the real Supabase + Quarkus stack, no mocks (Linux-only) |
| `task test:native` | Builds the native image and smokes it in Docker — the long check before a deploy |
| `task audit` | Dependency CVE scan (Java + TypeScript); needs network, runs on a schedule, not in CI |
| `task run:dev` | Supabase + backend + web client together, one Ctrl-C tears it down |
| `task run:server` / `task run:client` / `task run:supabase` / `task run:admin` | The tiers separately |
| `task zen:build:runners` | Every delivery runner this host can build; skips are announced |
| `(cd client && flutter run)` | Runs the application |

The `zen:` tasks — and `deps` / `generate` / `verify:contracts` plus the whole `run:*` family,
which are one-line aliases to them — come from jZen's `Taskfile.app.yml`, which Prudent
**includes rather than copies**: jZen runs the same file for its own reference application, so
these are shared tasks rather than a lookalike that drifts (ADR-027 through ADR-029). The build,
the gates and the deploy are Prudent's own, written phase by phase as each phase produced
something for them to act on — see `docs/DECISIONS.md` for what each one found along the way.

## CI

`.github/workflows/ci.yml` runs on `ubuntu-latest` and `windows-latest` — Windows exists only to
build the Windows desktop app, which Flutter refuses to cross-compile. Every job checks out `../jZen`
at a **pinned SHA** (`env.JZEN_REF`) rather than `main`, because a CI runner has no sibling checkout
and no local Maven repository of its own — see `docs/DECISIONS.md` ADR-018 for the full reasoning and
its cost. `.github/workflows/audit.yml` runs `task audit` on a weekly schedule, deliberately outside
the merge gate.

## Deploying

**Nothing is deployed anywhere today.** The deploy path — a native image, a same-origin-staged web
and admin bundle, migration run as a one-shot job ahead of the serving revision — is built and proven
against a throwaway, local Docker + Postgres stack (`task test:native`), not against a real cloud
project. See `docs/DECISIONS.md` ADR-020 for what was built, what a real deploy's secret inventory
looks like, and what stays an explicit `prudent.invalid` placeholder until a real domain exists.

## Platforms

Prudent ships **Android, iOS, web, macOS, Linux and Windows**.

**Desktop and Apple builds are host-only**: Flutter refuses `build linux` off a Linux host and
`build windows` off a Windows host, and the Apple targets need Xcode. **No single machine verifies
the full set**, which is why `task zen:build:runners` announces what it skipped instead of passing
silently, and why CI needs more than one operating system. See
[`docs/DECISIONS.md`](docs/DECISIONS.md) ADR-003.

### Toolchain

**Flutter is pinned to `3.44.2`** in [`.fvmrc`](.fvmrc), matching jZen. This is load-bearing rather
than tidiness: the Android build delegates its NDK version to the SDK (`flutter.ndkVersion`), so two
developers on different Flutter releases resolve different NDKs and hit build failures
asymmetrically. Until CI enforces it, the pin is advisory — check `flutter --version` matches.

**One Java version everywhere; only the distribution differs** — GraalVM 25 for Maven, Quarkus and
the native image; **Temurin 25** for Android, because AGP's `jdkImage` transform shells out to
`jlink` and GraalVM's cannot run it:

```bash
sdk install java 25.0.3-tem
flutter config --jdk-dir "$HOME/.sdkman/candidates/java/25.0.3-tem"
```

That second command is a **machine-wide** setting which outranks `JAVA_HOME` and applies to every
Flutter project on the machine — so no task in this repository can set it, and installing a
*different* Java version to satisfy one project would break the others. See
[`docs/DECISIONS.md`](docs/DECISIONS.md) ADR-005.

If an Android build fails with a message whose entire text is a version number like `25.0.3`, the
Gradle distribution is too old for the JDK. After changing it, kill the daemon — one started under
the old distribution keeps serving it:

```bash
pkill -f GradleDaemon
```

## Documentation

| Document | What it is |
|---|---|
| [`docs/zen-architecture.md`](docs/zen-architecture.md) | **Prudent's cornerstone** — the design philosophy this product is built on. Read it before non-trivial work. |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Prudent's own decision log, numbered from ADR-001, append-only |
| [`docs/prudent-migration-plan.md`](docs/prudent-migration-plan.md) | The approved plan, and the phase sequence |
| [`docs/jzen/README.md`](docs/jzen/README.md) | Where jZen's rules live — pointers into `../jZen`, never copies |

jZen's documents are **read from `../jZen`, not copied here**: a copy drifts, and a drifted rule is
worse than an absent one. `docs/jzen/` is deleted the day jZen publishes its packages, since a
versioned dependency's documentation travels with the package.

## Licence

Apache License 2.0 — see [`LICENSE`](LICENSE).
