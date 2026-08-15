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
