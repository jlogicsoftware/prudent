---
name: sync-contracts
description: Prudent's contract-first loop. Use whenever you change a proto model, a REST resource's shape, or need to regenerate/commit generated Java DTOs, Dart messages, openapi.json or admin TypeScript, or when `task verify:contracts` fails with a drift error.
---

# Syncing Prudent's contracts

`proto/prudent/v1/*.proto` is canonical for **models**; SmallRye-annotated Quarkus resources are
canonical for the **REST surface** (paths, verbs, status codes). Everything else is **derived**:
Java DTOs, Dart messages, `openapi.json`, admin TS. **Never hand-edit a generated file** — fix the
source and regenerate. Editing a derived artifact is a defect.

## The loop is jZen's now

The whole loop lives in jZen's `Taskfile.app.yml` and Prudent delegates (ADR-027, jZen #74).
Two entry points, both thin local aliases to `zen:<name>`:

- **`task generate`** — regenerate every artifact (proto → Java/Dart, `openapi.json`, admin TS,
  typed l10n). Always exits 0 when the generators succeed. This is what you run after editing a
  `.proto` or a resource.
- **`task verify:contracts`** — runs `generate`, then **fails** if a tracked generated file
  drifted or a built-not-tracked one got committed. The CI gate. (`sync:contracts` / `sync:verify`
  are retired — a stale reference now errors with "task not found".)

## What is tracked, and why

Generated output is **committed across a toolchain boundary, regenerated within one**:

- **Tracked**: the Dart messages (`*.pb.dart`, `*.pbjson.dart`, `*.pbenum.dart`) and the admin
  `schema.generated.ts` — a Flutter or frontend developer must not need `protoc` or a JDK to
  *compile*. `zen:verify:contracts:check` watches:

  ```
  *.generated.ts  *.pb.dart  *.pbjson.dart  *.pbenum.dart  proto/**/*.proto
  ```

- **Not tracked**: `openapi.json`. It is a build output at `server/target/openapi/openapi.json`
  (under gitignored `target/`); the tracked downstream artifact is the admin panel's
  `schema.generated.ts`, which `openapi-typescript` derives from it. ADR-027 dropped the old
  tracked `server/openapi.json` copy — the admin panel now carries that role (ADR-011's "until
  Prudent has an admin panel" clause).
- **Not tracked**: the Java DTOs, generated under `target/` because Maven resolves `protoc`
  itself. Do not "fix" that by checking `target/` in.
- **Not tracked**: generated localizations (`**/l10n/generated/`) — `flutter gen-l10n` ships in the
  Flutter SDK, so it is built, not committed. The gate asserts none are tracked.

## When it fails

`Contracts are OUT OF SYNC` means either a generated file was hand-edited or a `.proto` / resource
changed without regenerating. Fix by running `task generate` and committing the result —
**never** by editing generated output. This gate belongs in CI as a required check.

Regenerating the admin TS now needs a packaged server (a JDK) — `zen:generate:api:schema` writes
`server/target/openapi/openapi.json` first. `schema.generated.ts` is tracked, so *compiling* the
panel never needs this; only a contract change does, and that is a backend change already.

## Proto conventions Prudent follows

- Package and namespace are settled, mirroring jZen's bare-namespace rule (jZen ADR-006):
  `package prudent.v1;` with `option java_package = "prudent.proto.v1";`. Never `zen.proto.v1`,
  which is jZen's.
- Timestamps are epoch-ms `int64` with an `_ms` suffix.
- Reuse jZen's cross-cutting shapes from `zen-proto` / `common.proto` (`ZenError`, `PageRequest`)
  rather than redeclaring them. Prudent's protos document this in a header comment rather than
  importing the file — errors on the wire are a `zen.v1.ZenError` body supplied by the framework.
- Generated JSON is proto3 canonical JSON (lowerCamelCase). Dart's `protoc_plugin` and
  `openapi-typescript` emit the same shape, so all three languages agree — when hand-authoring
  OpenAPI component schemas (see `add-endpoint`), match those camelCase names.
- **No Flutter types in a proto model.** A `Color` or `IconData` field cannot cross the wire; the
  contract carries a portable value and the UI layer resolves it.

## Reference

jZen's own loop is the working example: `../jZen/proto/zen/v1/`, `../jZen/Taskfile.app.yml`
(`generate`, `verify:contracts`, and their `generate:proto*` / `generate:api*` / `generate:l10n`
parts — the same tasks Prudent runs via the `zen:` include), and
`../jZen/.Codex/skills/sync-contracts/`. Read it; do not copy the framework's files into this
repository.
