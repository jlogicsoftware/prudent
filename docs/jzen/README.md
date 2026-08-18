# jZen — where the framework's rules live

**This folder holds no documents, only pointers.** Prudent depends on the jZen framework, and while
that dependency is a **sibling checkout at `../jZen`** rather than a published package, jZen's rules
are read from that checkout directly. Nothing is copied here: a copy drifts, and a drifted rule is
worse than an absent one.

`../jZen` is **read-only** from this repository.

| jZen document | Path | What it is |
|---|---|---|
| `MANIFESTO.md` | `../../../jZen/docs/architecture/MANIFESTO.md` | How jZen applies Zen Architecture to a concrete stack |
| `BLUEPRINT.md` | `../../../jZen/docs/architecture/BLUEPRINT.md` | The jZen architecture as built |
| `STANDARDS.md` | `../../../jZen/docs/architecture/STANDARDS.md` | The rules — the one to check a change against |
| `DECISIONS.md` | `../../../jZen/docs/architecture/DECISIONS.md` | jZen's ADR archive — **wins on conflict with the three above** |
| `ROADMAP.md` | `../../../jZen/docs/architecture/ROADMAP.md` | jZen's build sequence and open backlog |

Reference implementations are in the same checkout; the `jzen-reference` skill maps them.

## Findings Prudent has reported upstream

A framework need is **reported, never forked** — `../jZen` is read-only, and a copy of framework
source in this repository is the thing that drift is made of. Findings are tracked here so a later
session can tell "reported and waiting" from "fixed and consumed" from "nobody has raised this".

| Finding | Upstream | State |
|---|---|---|
| `protoc-gen-dart` writes imports as **filesystem-relative paths** and has no equivalent of Go's `M` mapping, so an application proto importing `zen/v1/common.proto` produced code pointing at a path that resolves to nothing inside the application's package. Satisfying it by regenerating `zen.v1` into the application's tree is worse and silently so: the copy is a *different Dart type*, so the framework's own API stops type-checking against it. (The Java side was always clean — `zen.v1` resolves from the `zen-proto` jar.) | [#54](https://github.com/jZenDev/jZen/issues/54) → [PR #55](https://github.com/jZenDev/jZen/pull/55) | **Fixed and consumed.** jZen moved its messages to the public `zen_transport/lib/generated`, and `zen:generate:proto:dart` now passes protoc both contract roots with `-I` but only the application's protos as arguments, rewrites the leftover relative imports to `package:zen_transport/generated/zen/v1/…`, and refuses if a `zen/v1` file lands in the application's tree. |
| The contract loop was hardcoded to jZen's own tree, so `Taskfile.app.yml` could not carry it and an application could not include it. Its `generate:proto:dart` also *skipped* with exit 0 on an empty proto directory — right for a framework skeleton, wrong for an application, where an empty contract root is a broken checkout. | [#54](https://github.com/jZenDev/jZen/issues/54) → [PR #55](https://github.com/jZenDev/jZen/pull/55) | **Fixed and consumed.** Prudent deleted its own `generate:proto:dart` and delegates to `zen:generate:proto:dart` (Prudent ADR-007). The rest of the loop — the server build, the local stack, the deploy, the gates — has not moved yet and is still Prudent's own. |
| Nothing catches a fully-qualified class reference used inline instead of an import (e.g. `new prudent.server.account.AccountBalance(...)` where `AccountBalance` is already, or could be, imported) — both compile identically. Prudent added PMD's `UnnecessaryFullyQualifiedName` rule to its own `server/pom.xml` (Phase 4) and found a real instance doing so (`UserScopingTest.java`). Also flagged that `maven-pmd-plugin`'s *default* resolves PMD 6.55.0, whose bundled ASM cannot parse a Java 25 class file (`Unsupported class file major version 69`) — every file fails to process and the plugin reports `BUILD SUCCESS` anyway, a vacuous gate; 3.27.0 (PMD 7.14.0) parses correctly. | [#61](https://github.com/jZenDev/jZen/issues/61) → [PR #62](https://github.com/jZenDev/jZen/pull/62) | **Fixed and consumed (Phase 5).** jZen took the proposed shape exactly: `zen-parent`'s `pluginManagement` now supplies `maven-pmd-plugin`'s version (`${maven-pmd-plugin.version}` = 3.27.0) and nothing else, pluginManagement-only, so each consuming module still opts in rather than every inheriting module being linted unconditionally. Prudent's `server/pom.xml` **deleted its own `<version>3.27.0</version>` line** and re-ran `./mvnw test-compile`, confirming the version still resolves to 3.27.0/PMD 7.14.0 purely from the inherited `pluginManagement` and the rule still runs (`task test:server` stayed green, 79/79). `server/pmd-ruleset.xml` and the plugin's `<configuration>`/`<executions>` stay Prudent's own — jZen manages the version, not the ruleset content or the decision to run it, which is application-specific by the finding's own proposal. |
| `UserRetentionService.anonymiseExpiredAccounts()` (GDPR Art. 5(1)(e) dormancy retention) mutates a dormant `users` row directly, in its own transaction, and fires **no event** an application could observe — unlike `UserRegistered`, which exists for exactly the symmetric case on the way in (jZen ADR-007). An application whose own tables reference `user_id` has no framework-provided hook to cascade its own cleanup when an account is anonymised, so it either duplicates the framework's anonymisation-marker convention (`anon_<uuid>@deleted.invalid` — currently package-private in `UserRetentionService`, so an application matching it is coupled to a literal that could change silently) or leaves its own rows behind indefinitely. Prudent's workaround (Phase 5 §5, `prudent.server.retention.PrudentRetentionCleanupJob`) is a second `ZenJob` that scans `users` for the marker and sweeps Prudent's own tables — functionally correct, proven by `PrudentRetentionCleanupJobTest`, but a scan is a weaker mechanism than an event and the coupling to a private string literal is exactly the kind of thing that breaks silently. Proposed fix: `UserRetentionService` fires a `UserAnonymised(UUID userId)` CDI event per row, mirroring `UserRegistered`'s shape. | not yet filed | **Reported here; not yet filed upstream.** Prudent's workaround stays until an event exists to replace it. |
| `task zen:generate:l10n` and `task zen:test:client`'s own internal call to it discover localized packages with `git ls-files`, **scoped to the repository the task runs in**. Called from an application's root (Prudent's, via the `zen:` include), it can only ever find *that* application's own `l10n.yaml` files — never a framework package's, since `client/zen_ui_identity/l10n.yaml` etc. belong to a **different git repository** a sibling-checkout `git ls-files` structurally cannot see. Invisible on a developer's machine, where jZen's own local test runs have already generated and cached `zen_ui_identity`'s and `zen_ui_navigation`'s localizations on disk; **a fresh CI clone of both repositories has no such history**, and Prudent's first real CI run failed on exactly this (`IdentityLocalizations isn't a type`) in three separate jobs, because Prudent's own screens reach those types through the framework's `LoginScreen`/`ProfileScreen`/`ZenNavigation` widgets. Worked around per-job (`.github/workflows/ci.yml`): an extra step runs `task zen:generate:l10n` a second time with `working-directory: jZen`, so `git ls-files` resolves against jZen's own tracked files instead. Proposed fix: `zen:generate:l10n` (and any other task discovering by `git ls-files`) should also walk a `../jZen`-relative root when one is configured, or the framework should expose a task an application can call to generate *just* the framework's own localizations without a multi-repo consumer having to `cd` into the sibling checkout by hand. | not yet filed | **Reported here; not yet filed upstream.** Prudent's CI workaround (one extra step per job needing it) stays until the framework grows a multi-repo-aware discovery path. |

**Consuming a fix is a deliberate step, not automatic.** A merged PR upstream does not change this
repository until someone deletes the local workaround and proves the framework's version green
here; and a filed issue is never a reason to pre-emptively reshape Prudent around a change that
does not exist yet. Because jZen is consumed by **path**, "which fix am I on" is a commit — run
`task zen:info`.

## What is Prudent's, and what is jZen's

- **[`docs/zen-architecture.md`](../zen-architecture.md) is Prudent's own cornerstone** — the design
  philosophy this product is built on. It is permanent and does not depend on jZen.
- **Prudent's rules are Prudent's**, in `docs/` and `docs/DECISIONS.md` (its own ADR numbering from
  ADR-001). jZen's documents constrain Prudent only where Prudent actually consumes the framework —
  the transport seam, the contract, auth, migrations. They are not Prudent's house style.
- Where a jZen rule and a Prudent rule conflict on something Prudent owns, **Prudent's wins**, and
  the divergence is recorded as a Prudent ADR.

## This folder is temporary

It exists because jZen is consumed from a filesystem path. **When jZen publishes its packages and
Prudent depends on them by version, this folder is deleted** — a versioned dependency's
documentation travels with the package, and there is no sibling checkout left to point at. That
removal is a step in the publishing ADR, not a cleanup. `docs/zen-architecture.md` is unaffected.
