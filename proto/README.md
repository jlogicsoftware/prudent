# `proto/` — Prudent's wire contract

`proto/prudent/v1/*.proto` is the **canonical source of truth for Prudent's models**. The Java
DTOs and the Dart messages are *generated* from it; a tracked generated file is never
hand-edited. Fix the `.proto` and run `task generate` (`task verify:contracts` is the drift gate).

The directory mirrors the proto package the way `../jZen/proto/zen/v1/` mirrors `zen.v1`.
**`v1` is the API version and is independent of the product version** — Prudent's server is
`0.1.0-SNAPSHOT` and its client is `1.0.0+1`, and neither number appears here.

| File | Package | Java package |
|---|---|---|
| `prudent/v1/records.proto` | `prudent.v1` | `prudent.proto.v1` |
| `prudent/v1/accounts.proto` | `prudent.v1` | `prudent.proto.v1` |
| `prudent/v1/categories.proto` | `prudent.v1` | `prudent.proto.v1` |
| `prudent/v1/settings.proto` | `prudent.v1` | `prudent.proto.v1` |

`settings.proto` is the odd one: a **singleton**, one row per user, with no id and no list message
because the JWT is the entire addressing scheme. It carries `main_currency`, which is a **label and
never a conversion target** — Prudent does no FX, totals stay per-currency, and ADR-009 records
why.

`analytics.proto` is **deliberately absent**. Analytics is new product work with no endpoint and
no agreed arithmetic behind it yet; a message written before either exists is a guess committed
to a contract, and a contract is the one place a guess is expensive to withdraw.

## Where the generated output goes, and why the two sides differ

| Side | Output | Tracked? |
|---|---|---|
| Java | `server/target/generated-sources/protobuf/` | **No** |
| Dart | `client/lib/generated/prudent/v1/*.pb*.dart` | **Yes** |

The split is a **toolchain-boundary** question, not a preference. `protobuf-maven-plugin`
resolves the `protoc` binary from Maven Central, so any consumer with Maven regenerates the Java
side hermetically and committing it would only add a second copy to keep honest. The Dart side
needs a **system `protoc`** plus **`protoc-gen-dart`** (`dart pub global activate protoc_plugin`)
— tools a Flutter developer has no other reason to install — so the output is committed and
`.gitattributes` marks it `linguist-generated`.

## Framework messages are referenced, not imported — and that was measured

Cross-cutting shapes belong to jZen (`../jZen/proto/zen/v1/common.proto`: `ZenError`,
`PageRequest`) and are **never copied into this repository**. Prudent's files reference them in
comments and **do not `import` them**, which is exactly what jZen's own protos do — not one of
`admin.proto`, `demo.proto`, `identity.proto` or `jobs.proto` imports `common.proto` either.
`ZenError` is an error *body*, returned in place of a response rather than embedded in one, and
`PageRequest` is a request shape whose fields are query parameters on a `GET`. Neither has a
place inside a Prudent message.

That is the design reason. There is also a mechanical one, and it is worth recording because it
would otherwise be rediscovered the first time someone tries:

**A cross-repository proto import works on the Java side and breaks on the Dart side.** Both
halves were run before this file was written, against a throwaway `probe.proto` importing
`zen/v1/common.proto` with `-I proto -I ../jZen/proto`:

- **Java — clean.** `protoc --java_out` emitted **only** `prudent/proto/v1/Probe*.java`. The
  `zen.v1` classes are resolved from the `zen-proto` jar already on the classpath, so nothing is
  generated twice and there is no second copy of a framework message.
- **Dart — broken.** `protoc --dart_out` emitted `import '../../zen/v1/common.pb.dart'` — a
  **relative** path. From `client/lib/generated/prudent/v1/` that resolves to
  `client/lib/generated/zen/v1/common.pb.dart`, which does not exist. `protoc_plugin` has no
  package-mapping option, so the only way to satisfy it is to generate the framework's messages
  into Prudent's tree — producing a **second `ZenError` type** alongside the one
  `package:zen_transport` exports. Two Dart classes from one message are not assignable to each
  other, so the transport's decoded error and the app's error would be different types that look
  identical. That is worse than the missing file, because it compiles.

**This is a jZen-side finding, not something to work around here** (it extends the plan's §3.7
finding 1): `protoc_plugin`'s relative imports mean framework proto messages cannot be shared
across repositories on the Dart side at all. The fix belongs in jZen — either its published Dart
package maps generated imports to `package:` URIs, or the framework states that application
protos must not import `zen.v1`. Until then Prudent's contract needs no import, so nothing is
blocked and nothing is duplicated.

### Fixed upstream, and consumed

**That finding is closed.** It was reported as
[jZenDev/jZen#54](https://github.com/jZenDev/jZen/issues/54) and fixed by
[PR #55](https://github.com/jZenDev/jZen/pull/55), which Prudent now consumes — Prudent's
hand-rolled Dart codegen is deleted and `task generate:proto:dart` delegates to
`zen:generate:proto:dart` (see `docs/DECISIONS.md` ADR-007).

**An application proto may now `import "zen/v1/common.proto"`.** jZen moved its messages to the
public `zen_transport/lib/generated`, and the task passes protoc both contract roots with `-I`
while naming only the application's protos as arguments, then rewrites the relative imports protoc
leaves behind into `package:zen_transport/generated/zen/v1/…`. It refuses outright if a `zen/v1`
file lands in the application's tree, so the duplicate-type failure is now enforced rather than
merely warned about.

Verified here rather than taken on trust: a throwaway proto importing `zen/v1/common.proto`
generated one file re-pointed at `package:zen_transport/generated/zen/v1/common.pb.dart`, emitted
no `zen/v1` into `client/`, and analyzed clean. The probe was then deleted.

**Prudent's contract still imports nothing from `zen.v1`, and that is now a design choice rather
than a limitation.** `ZenError` is an error *body* returned in place of a response, and
`PageRequest`'s fields are query parameters on a `GET` — neither belongs inside a Prudent message.
The capability is there the day one does.

## Compatibility

Field numbers are permanent. Adding a field is backward compatible; renumbering, retyping or
reusing a retired number is not. A removed field's number is `reserved`, never recycled.

`Account` and its request messages carry `reserved` entries already, from the change to
multi-currency accounts (ADR-008): `balance_minor` and `currency` were one balance in one
currency, and their numbers are retired rather than reused. **Nothing has ever served this
contract** — there is no deployed server, no persisted row and no shipped client — so those numbers
could technically have been recycled for free. They were not, because the discipline is worth more
than the two field numbers: `reserved` is what makes the retirement visible in the file, and the
moment Phase 2 deploys, guessing wrong about whether a number was ever used stops being free.
