# `proto/` — Prudent's wire contract

`proto/prudent/v1/*.proto` is the **canonical source of truth for Prudent's models**. The Java
DTOs and the Dart messages are *generated* from it; a tracked generated file is never
hand-edited. Fix the `.proto` and run `task sync:contracts`.

The directory mirrors the proto package the way `../jZen/proto/zen/v1/` mirrors `zen.v1`.
**`v1` is the API version and is independent of the product version** — Prudent's server is
`0.1.0-SNAPSHOT` and its client is `1.0.0+1`, and neither number appears here.

| File | Package | Java package |
|---|---|---|
| `prudent/v1/records.proto` | `prudent.v1` | `prudent.proto.v1` |
| `prudent/v1/accounts.proto` | `prudent.v1` | `prudent.proto.v1` |
| `prudent/v1/categories.proto` | `prudent.v1` | `prudent.proto.v1` |

`analytics.proto` is **deliberately absent**. Analytics is new product work with no endpoint and
no agreed arithmetic behind it yet; a message written before either exists is a guess committed
to a contract, and a contract is the one place a guess is expensive to withdraw.

## Where the generated output goes, and why the two sides differ

| Side | Output | Tracked? |
|---|---|---|
| Java | `server/target/generated-sources/protobuf/` | **No** |
| Dart | `client/lib/src/generated/prudent/v1/*.pb*.dart` | **Yes** |

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
  **relative** path. From `client/lib/src/generated/prudent/v1/` that resolves to
  `client/lib/src/generated/zen/v1/common.pb.dart`, which does not exist. `protoc_plugin` has no
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

## Compatibility

Field numbers are permanent. Adding a field is backward compatible; renumbering, retyping or
reusing a retired number is not. A removed field's number is `reserved`, never recycled.
