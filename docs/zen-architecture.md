# 🧘 Zen Architecture

Zen Architecture is the design philosophy **Prudent** is built on. It is not unique to this
product — the same philosophy underlies other Zen-family projects, the jZen framework among them —
and this document states it on its own terms, independent of any one stack.

**This is Prudent's cornerstone, not a reference to someone else's.** It is the document Prudent's
own rules are an instance of, and it is permanent: it stands whether Prudent consumes jZen from a
sibling checkout, from a published package, or not at all.

It is not a framework, not a pattern catalog, and not a layered model. Zen Architecture is a set
of **constraints, defaults, and decisions** that shape how a system is built and how it evolves.

The goal is simple: **reduce cognitive load while staying honest about the real system you are
building.**

## What Zen Architecture is not

Zen Architecture explicitly rejects:

- Clean Architecture
- Hexagonal / Onion / Ports & Adapters
- Domain-Driven Design layers
- Artificial separation into "domain", "contract", and "infrastructure"
- Abstractions created "just in case"

These approaches are powerful in enterprise environments, but they add ceremony, indirection, and
vocabulary that Zen Architecture deliberately avoids. It optimizes for **clarity, speed, and
product reality**, not architectural purity.

## Core principles

### 1. Product-first, not architecture-first

Zen Architecture starts with the product, not with diagrams. Packages represent **product
capabilities**, not architectural layers. If something exists because the product needs it, it
belongs in the system. If something exists only to satisfy an architectural idea, it does not.

### 2. See with your eyes (zero *custom* magic)

Zen Architecture avoids hidden behavior:

- No code generation whose output a developer cannot read
- No implicit wiring
- No runtime magic

What the system does should be visible by reading the code — or, where generation is used, by
reading its generated output, which is committed and readable rather than synthesized invisibly
at runtime. If something happens, you should be able to find it. Predictability is valued over
cleverness.

### 3. Real dependencies are first-class

Zen Architecture does not pretend that external systems are optional. Whatever a product actually
depends on — a database, an identity provider, a cloud platform — is treated as a real, stable,
**named** dependency, not smuggled behind a portability layer that no second implementation will
ever justify. A wrapper around a single implementation is not an abstraction; it is a passthrough
with a plausible name, and it costs a reader one extra indirection every time they follow the
code, forever, in exchange for a flexibility nobody has asked for.

This is not a limitation. It is a deliberate trade-off for simplicity, performance, and developer
experience — and it comes with an obligation: once a dependency is named, its constraints are the
product's constraints, and they belong in a place they can be enforced, not hidden behind a
wrapper where they will surface as a bug.

### 4. No artificial purity

There is no concept of a "pure domain" in Zen Architecture. Business logic, persistence logic, and
integration logic may live close to each other **when that reflects reality**. The goal is not
purity. The goal is **coherence**.

### 5. Utilities over abstractions

Zen Architecture favors small utility packages, explicit helpers, and boring, readable APIs over
deep inheritance trees, generic interfaces, and swap-ready abstractions. If a dependency is not
meant to be swapped, it should not pretend to be.

### 6. Environment is explicit

Zen Architecture embraces environment differences instead of hiding them. Development should run
against the real shape of production — local, cheap, and safe — rather than a "mock world" that
behaves unlike it. Configuration is driven by explicit settings, not implicit detection.

## Packages as capabilities

In Zen Architecture, a package answers one question: **"What capability does this give to the
product?"** Identity, transport, jobs, telemetry — these are things a product *does*. Packages are
not layers, tiers, or technical boundaries; they are **capabilities with clear responsibility**.

## Client and server are one system

Zen Architecture does not treat client and server as separate worlds. They are developed together,
versioned together, and reasoned about together. Consistency between client and server matters
more than theoretical separation — which is why a Zen Architecture system typically has *one*
mechanism, stated once, that keeps them honest with each other, rather than a contract maintained
by convention on both sides.

## One product, two homes for the ledger

Prudent has a second form, **Prudent Local**, in which there is no server at all: the ledger lives
on the person's own devices, in jZen's encrypted store, and syncs between them. How the store
encrypts, syncs and lets a person settle a conflict is jZen's design and is stated there (jZen
ADR-065, ADR-073, ADR-076, ADR-085, through [`jzen/README.md`](jzen/README.md)). What follows is
Prudent's own, and each point is the principles above applied to a ledger with no one else to
enforce its rules.

- **The screens are one capability, written once.** Every screen, view model and string is in
  `packages/prudent_ui`, which both apps link; neither app has a copy (ADR-101, ADR-108). The package
  cannot reach a server or an identity provider, and a gate fails the build if it tries.
- **`PrudentRepository` is an interface because it has two implementations.** Principle 3 forbids
  a wrapper around a single implementation; this one has two real ones — `ServerPrudentRepository`
  over HTTP, `LocalPrudentRepository` over the store — and only each app's composition root names
  its own (ADR-105, ADR-121). The interface earned its place the day the second one existed, not
  before.
- **When the server goes, its rules come with the ledger.** Nothing else is left to enforce them, so
  every rule the server checks is checked on the device, method for method, and held to the server
  by golden vectors and a parity suite that runs one scenario through both and compares every
  figure to the cent (ADR-107, ADR-113). Same product, same numbers.
- **No last-writer-wins.** A balance is never a stored number two devices both edit; it is derived
  from the records, and two devices that each add a record both keep it. Where two devices disagree
  about a value, a person settles it, in words; nothing picks a winner by the clock (ADR-102,
  ADR-111).
- **A figure says what it leaves out.** Until a disagreement is settled, a balance, a budget, an
  envelope or an analytics total does not count the disputed entry, and says beside the figure how
  many it leaves out (`Settled`, ADR-113, ADR-121). A number that silently includes one device's
  guess is worse than a number that admits a gap.
- **The same fact on two devices is one record.** Where a record stands for something in the world
  — a budget slot, a confirmed occurrence, an imported statement row — its id is derived from that
  thing, not minted, so two devices that do the same thing write the same record instead of two
  (ADR-102, ADR-111, ADR-114). An id is never derived from an amount, a name or an account number
  (ADR-100 T7).
- **A rule is checked where the write happens.** A rule checked before a write can be broken by a
  sync that lands in between, so every write carries the rule and the version it was decided
  against as the store's precondition (`expect`), and is refused rather than written over a change
  it did not see (ADR-115, ADR-122).
- **A broken rule is shown, never repaired behind the person's back.** A merge can break a rule no
  single device broke — an envelope below zero, a record on a deleted account. It is listed as an
  issue with actions the person chooses (ADR-102, ADR-111, ADR-120).

## Why "Zen"

Zen Architecture is about removing noise: fewer concepts, fewer files, fewer indirections, fewer
decisions per line of code. This creates space for what matters — product logic, user experience,
reliability, long-term maintainability.

Zen is not minimalism for its own sake. Zen is **clarity through deliberate constraint**.

## Summary

Zen Architecture is:

- Product-driven
- Explicit about its real dependencies
- Free of custom magic
- Boring in the right places
- Optimized for human understanding

If a design decision increases confusion, it is not Zen. If it makes the system easier to reason
about, it probably is.
