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
├── docs/          the architecture, the plan, and the decision log
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
task zen:deps                 # resolve the client's Dart dependencies

cd client && flutter run      # run the application
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
| `task zen:deps` | `flutter pub get` across the client tier |
| `task zen:generate:l10n` | `flutter gen-l10n` in every package declaring an `l10n.yaml` |
| `task zen:test:client` | Every Dart/Flutter suite |
| `task zen:build:runners` | Every delivery runner this host can build; skips are announced |
| `(cd server && ./mvnw -B package -DskipTests)` | Builds the backend |
| `(cd client && flutter run)` | Runs the application |

The `zen:` tasks come from jZen's `Taskfile.app.yml`, which Prudent **includes rather than copies** —
jZen runs the same file for its own reference application, so these are shared tasks rather than a
lookalike that drifts.

Tasks Prudent still has to write — the contract loop, the server build, the local stack, the deploy
and every gate — are not in that file yet, and arrive with the work they verify. `Taskfile.yml` says
which phase each one belongs to.

## Platforms

Prudent ships **Android, iOS, web, macOS, Linux and Windows**.

**Desktop and Apple builds are host-only**: Flutter refuses `build linux` off a Linux host and
`build windows` off a Windows host, and the Apple targets need Xcode. **No single machine verifies
the full set**, which is why `task zen:build:runners` announces what it skipped instead of passing
silently, and why CI needs more than one operating system. See
[`docs/DECISIONS.md`](docs/DECISIONS.md) ADR-003.

For Android, note that Flutter takes its JDK from a **machine-wide** setting that outranks
`JAVA_HOME`, so no task in this repository can fix it:

```bash
flutter config --jdk-dir /path/to/a/standard/jdk-25   # GraalVM will not work — its jlink
                                                      # cannot run AGP's jdkImage transform
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
