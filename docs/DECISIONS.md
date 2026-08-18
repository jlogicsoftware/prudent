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
