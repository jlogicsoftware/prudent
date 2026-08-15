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
