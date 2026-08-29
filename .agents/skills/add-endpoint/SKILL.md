---
name: add-endpoint
description: Add a REST endpoint to Prudent's Quarkus backend the contract-first way. Use when creating or modifying a resource/route, adding a proto message for a payload, or wiring the dual-mode (JSON/Protobuf) transport. Encodes the OpenAPI merge rule, the Jandex rule, and the no-jackson rule.
---

# Adding a Prudent backend endpoint

Prudent is **proto-first and contract-first**. A resource method names only domain/proto types;
jZen's transport seam negotiates the wire format via the `X-Zen-Transport` header
(`json`/`protobuf`), and echoes it back. Read `../jZen/docs/architecture/BLUEPRINT.md` (transport
seam) and `../jZen/docs/architecture/STANDARDS.md` ("OpenAPI and the REST surface") first if unsure
— `docs/jzen/README.md` indexes them. Follow these in order.

## 1. Declare the payload proto

Add request/response messages to `proto/prudent/v1/<domain>.proto` — one message per payload, no
generic envelope. Reuse jZen's cross-cutting shapes (`ZenError`, `PageRequest`) from `common.proto`
rather than redeclaring them. Timestamps are epoch-ms `int64` with an `_ms` suffix.

## 2. Write the resource — return `Response`, not the bare proto

SmallRye cannot introspect protobuf classes: a bare-proto return type emits 130+ garbage builder
schemas and 500s at runtime. So the resource returns `jakarta.ws.rs.core.Response` and points at a
schema by ref:

```java
@GET @Path("/{id}")
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@APIResponse(responseCode = ZenStatus.OK,     // ZenStatus constants, never a raw "200"
    content = {
      @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "MyMessage")),
      @Content(mediaType = "application/x-protobuf", schema = @Schema(ref = "MyMessage"))})
@APIResponse(responseCode = ZenStatus.NOT_FOUND, description = "... (ZenError)")
public Response get(@PathParam("id") String id) {
  return Response.ok(toProto(entity)).build();   // errors: Response.status(...).entity(zenError).build()
}
```

Map the Panache entity ⇄ proto with **MapStruct** (or a hand-written `toProto`). Persistence is
Hibernate Panache in **active-record** style — no repository classes.

Prudent's own resources are the closest examples — `server/src/main/java/prudent/record/
RecordResource.java` with `RecordMapper`, and `settings/SettingsResource.java` with
`SettingsMapper`. Beyond those, the reference implementations live in the jZen checkout:
`../jZen/server/zen-identity/**/AdminUserResource.java` and `**/auth/AuthResource.java`, and the
reference application is `../jZen/apps/zen_demo/zen_demo_server`. Read them; do not copy framework
source into this repository.

## 3. Supply the component schema in the static OpenAPI

The clean model schema is **not** generated from the proto class. Add it to
`server/src/main/resources/META-INF/openapi.yaml` under `components.schemas`, using proto3
camelCase field names. SmallRye merges the annotation-scanned **paths** on top of that base.

## 4. Placement: Prudent's, or jZen's?

Domain resources (accounts, categories, records, analytics) belong in **Prudent's** server. Auth
and user administration already exist in the framework — `zen-identity` supplies `AuthResource` and
`AdminUserResource`, and Prudent inherits them by depending on the library. **Do not reimplement
them here**, and do not widen a jZen library to suit Prudent: a framework change is made in the
jZen repository and consumed by version. Say which of the two a given need is.

Two rules that fail **silently** if broken:

- **Any module contributing a resource/provider/bean must run `jandex-maven-plugin`.** Without
  `META-INF/jandex.idx`, Quarkus never discovers it — no error, it just does nothing.
- **Never add `quarkus-rest-jackson` server-side.** It hijacks `application/json` through a
  build-time path that ignores writer priority and 500s on proto builder internals. jZen's
  `Protobuf`/`ProtoJson` writers own serialization.

## 5. Regenerate and test

Run the `sync-contracts` skill (`task generate:proto generate:api`, then `task sync:contracts`).
Add a `@QuarkusTest` asserting **both** transport modes and the `ZenError` error path, then run the
backend suite. A `@QuarkusTest` needs an assembled app and Docker running (Dev Services Postgres).

## Admin/list endpoints

The react-admin panel lives in `admin/` and is JSON-only. List endpoints return a **bare JSON array
plus a `Content-Range` header** (the `ra-data-simple-rest` convention), each element the declared proto
rendered with `JsonFormat.printer().alwaysPrintFieldsWithNoPresence()`. Add
`Content-Range`/`Accept-Ranges` to the CORS `exposed-headers`.
