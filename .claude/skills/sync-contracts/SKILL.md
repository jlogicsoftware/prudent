---
name: sync-contracts
description: Prudent's contract-first loop. Use whenever you change a proto model, a REST resource's shape, or need to regenerate/commit generated Java DTOs, Dart messages, openapi.json or admin TypeScript, or when `task sync:contracts` fails with a drift error.
---

# Syncing Prudent's contracts

**Status: the contract does not exist yet.** Until the conversion lands `proto/prudent/v1/` and a
`Taskfile.yml`, this skill describes the loop being built, not one you can run. Do not invent
different commands; if a step is missing, that is conversion work.

`proto/prudent/v1/*.proto` is canonical for **models**; SmallRye-annotated Quarkus resources are
canonical for the **REST surface** (paths, verbs, status codes). Everything else is **derived**:
Java DTOs, Dart messages, `openapi.json`, admin TS. **Never hand-edit a generated file** — fix the
source and regenerate. Editing a derived artifact is a defect.

## What is tracked, and why

Generated output is **committed across a toolchain boundary, regenerated within one**:

- **Tracked**: the Dart messages (`*.pb.dart`, `*.pbjson.dart`, `*.pbenum.dart`) and the admin
  `schema.generated.ts` — a Flutter or frontend developer must not need `protoc` or a JDK.
- **Not tracked**: the Java DTOs and `openapi.json`, which live under `target/` because Maven
  resolves `protoc` itself. Do not "fix" that by checking `target/` in.
- **Not tracked**: generated localizations (`**/l10n/generated/`) — `flutter gen-l10n` ships in the
  Flutter SDK, so it is built, not committed.

## The loop

1. Edit the source: a `proto/prudent/v1/*.proto` file (models) and/or a resource's annotations
   (paths).
2. Regenerate: `task generate:proto generate:api`.
   - `generate:proto` → Java DTOs + Dart messages (needs `protoc` + `protoc-gen-dart`; run
     `task doctor`).
   - `generate:api` → builds the server to emit `openapi.json`, then runs `openapi-typescript` for
     the admin panel (if the panel is in scope).
3. Verify and commit: `task sync:contracts` runs both generators and then fails if any tracked
   generated file differs from what is committed. Commit the regenerated output — **with approval**
   (see CLAUDE.md).

## When it fails

`Contracts are OUT OF SYNC` means either a generated file was hand-edited or a `.proto` changed
without regenerating. Fix by running `task generate:proto generate:api` and committing the result
— **never** by editing generated output. This gate belongs in CI as a required check.

## Proto conventions Prudent follows

- Package/namespace mirrors jZen's bare-namespace rule (jZen ADR-006): pick Prudent's own
  `java_package` once and pin it in an ADR — not `zen.proto.v1`, which is jZen's.
- Timestamps are epoch-ms `int64` with an `_ms` suffix.
- Reuse jZen's cross-cutting shapes from `zen-proto` / `common.proto` (`ZenError`, `PageRequest`)
  rather than redeclaring them.
- Generated JSON is proto3 canonical JSON (lowerCamelCase). Dart's `protoc_plugin` and
  `openapi-typescript` emit the same shape, so all three languages agree — when hand-authoring
  OpenAPI component schemas (see `add-endpoint`), match those camelCase names.
- **No Flutter types in a proto model.** A `Color` or `IconData` field cannot cross the wire; the
  contract carries a portable value and the UI layer resolves it.

## Reference

jZen's own loop is the working example: `../jZen/proto/zen/v1/`, `../jZen/Taskfile.yml`
(`generate:proto`, `generate:api`, `sync:contracts`), and `../jZen/.claude/skills/sync-contracts/`.
Read it; do not copy the framework's files into this repository.
