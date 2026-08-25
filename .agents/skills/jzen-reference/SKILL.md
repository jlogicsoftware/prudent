---
name: jzen-reference
description: Find the jZen implementation of a pattern in the sibling ../jZen checkout — transport seam, auth, a resource, a client repository, l10n, Taskfile targets, deployment. Use before hand-rolling anything that the framework may already do, or when a jZen rule needs checking. jZen's docs are not copied into this repo; they are read from there.
---

# Reading jZen from Prudent

jZen is a **sibling checkout at `../jZen`** and is **read-only** from this repository: read it for
reference, never write to it, never copy framework source in. If Prudent needs a framework change,
that change is made in the jZen repository and consumed as a dependency — say so explicitly rather
than forking a copy here.

Confirm the checkout before relying on it: `git -C ../jZen rev-parse --short HEAD`. Prudent's path
dependencies pin nothing, so the two repositories move together — if something that worked stops
working, check whether jZen moved.

## Where things are

| Looking for | Read |
|---|---|
| The rules | `../jZen/docs/architecture/{MANIFESTO,BLUEPRINT,STANDARDS}.md` — but ADRs win: `.../DECISIONS.md` (`docs/jzen/README.md` indexes them) |
| Prudent's own cornerstone | `docs/zen-architecture.md` here — Prudent's, permanent, not jZen's |
| A whole application assembled from the framework | `../jZen/apps/zen_demo/` (`zen_demo_client`, `zen_demo_server`, `zen_demo_admin`) |
| The dual-mode transport seam | `../jZen/server/zen-transport/` — filter, message body writers, Jandex setup |
| Auth, the `User` entity, role resolution | `../jZen/server/zen-identity/` (`AuthResource`, `AdminUserResource`, `RoleAugmentor`) |
| Reference resource + tests | `../jZen/apps/zen_demo/zen_demo_server/src/{main,test}/java/zen/demo/` |
| Client repository + providers over `ZenClient` | `../jZen/apps/zen_demo/zen_demo_client/lib/src/{demo_repository,providers}.dart` |
| Client transport, session, secure storage | `../jZen/client/{zen_core,zen_transport,zen_identity,zen_secure_store}/` |
| Login/auth UI, navigation shell | `../jZen/client/{zen_ui_identity,zen_ui_navigation}/` |
| Typed i18n wiring (ARB + `l10n.yaml` + gen-l10n) | any `../jZen/client/zen_ui_*/lib/src/l10n/` and its `l10n.yaml` |
| The proto contract | `../jZen/proto/zen/v1/*.proto` |
| Orchestration Prudent **includes** | `../jZen/Taskfile.app.yml` — app-agnostic tasks, consumed via `includes:` (jZen ADR-046) |
| Orchestration Prudent must write itself | `../jZen/Taskfile.yml`, `../jZen/scripts/` — still zen_demo-shaped; read for the shape, do not copy wholesale |
| Desktop/mobile runner directories | `../jZen/apps/zen_demo/zen_demo_client/{android,ios,macos,linux,windows,web}` (jZen ADR-045) |
| Migrations | `../jZen/server/zen-identity/db/migration/` (and the band Prudent must not collide with) |
| Deployment (native image → Cloud Run) | `../jZen/Taskfile.yml` `deploy:cloudrun`, `apps/zen_demo/zen_demo_server/src/main/docker/` |

## How to use what you find

- **Reuse beats reimplementation.** If a framework library already does it, depend on it. Anything
  auth-shaped almost certainly exists in `zen-identity` already.
- **`zen_demo` is a reference, not a template.** It is jZen's showcase and end-to-end test stand;
  copying its structure wholesale imports choices Prudent has not made. Take the pattern, not the
  file.
- **Names carry jZen's namespace.** `zen.*` packages, `ZEN_*` build defines, `zen-*` artifacts are
  the framework's. Prudent's own code uses Prudent's namespace — decide it once and pin it in an
  ADR.
- **Watch for single-app assumptions.** jZen has only ever had one application; anything hardcoded
  to `zen_demo` (Taskfile variables, service names, scripts) is a jZen-side finding worth reporting
  upstream, not something to work around silently here.
