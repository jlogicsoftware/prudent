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
