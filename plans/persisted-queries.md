# Persisted Queries — Feature Plan

## Overview

Let generated clients send a hash (or ID) of an operation instead of the full query string. Two modes:

- **APQ (Automatic Persisted Queries)** — Apollo protocol. The client sends `sha256Hash`; on `PersistedQueryNotFound` it retries once with the full query. The server registers it at runtime. No build step, no server-side manifest.
- **Manifest (pre-registered / Relay-style)** — GraphLink emits a manifest (`id → query text`) at generation time. The client sends only the ID. The server loads the manifest and can reject anything not in it (safelist).

Both modes apply to every client target (Dart, Java, Kotlin, TypeScript, Swift). Per-language design is discussed separately; this document fixes the language-independent contract.

---

## Goals

- Smaller requests, and GET-able short URLs (CDN cacheable) for queries.
- Optional safelisting of operations for public APIs.
- Hashes/IDs computed **at generation time** — no runtime hashing code or crypto dependency in generated clients (generated code must stay dependency-free).
- Works with the operations GraphLink already knows statically: hand-written and auto-generated, including divided/partial `@glCache` queries.

## Non-Goals

- Server-side implementation for third-party servers (Apollo Server already supports APQ; we document the manifest format instead).
- Hashing dynamically built query strings at runtime (see Open Questions).
- Persisting subscriptions over WebSocket (phase 2, if wanted).

---

## Config

New client option, per target, default off:

```json
"clientConfig": {
  "dart": {
    "persistedQueries": "apq"
  }
}
```

| Value | Behavior |
|-------|----------|
| `false` (default) | Unchanged: full query string is sent |
| `"apq"` | Send hash; retry with full query on `PersistedQueryNotFound` |
| `"manifest"` | Send ID only; never sends the query text. Emits the manifest file |

Additional options (shared by both modes):

| Option | Default | Meaning |
|--------|---------|---------|
| `persistedQueriesUseGet` | `false` | Send queries (not mutations) as GET with `extensions` in the URL |
| `persistedQueriesManifestPath` | `persisted-queries.json` | Where the manifest is written (manifest mode; also written in `apq` mode if set) |

---

## Hash / ID

- Algorithm: SHA-256 over the **exact query string the client sends** (operation + all fragments it depends on), hex-encoded, lowercase. This is what APQ servers expect.
- Computed by the generator; emitted as a `const` next to each operation.
- Manifest ID = the same hash, so both modes share one identifier.

The hash must be computed over the final serialized string (after fragment inlining/ordering, variable naming, `maxFragmentBodySize` skips). Any change to query serialization changes hashes; that is expected, since manifests are regenerated with the clients.

---

## Wire Format

**APQ request**

```json
{
  "operationName": "GetUser",
  "variables": { "id": "1" },
  "extensions": { "persistedQuery": { "version": 1, "sha256Hash": "<hash>" } }
}
```

On `PersistedQueryNotFound` (an error entry with that message or `extensions.code`), resend once with `"query"` added. A second failure surfaces as a normal error.

**Manifest request**

Same shape, same `extensions.persistedQuery`, never a `query` field. Server answers `PersistedQueryNotFound` for unknown IDs; the client does not retry.

**GET** (when `persistedQueriesUseGet`): `?operationName=…&variables=<json>&extensions=<json>`. Mutations always POST.

---

## Manifest File

```json
{
  "version": 1,
  "operations": {
    "<sha256>": { "name": "GetUser", "type": "query", "body": "query GetUser($id: ID!) { … }" }
  }
}
```

One entry per generated operation, including divided partial queries. Written with the incremental-write hashing so unchanged manifests are not rewritten.

---

## Generator Changes

1. **Config** — add `persistedQueries` (+ options) to each client config in `config.dart` (`fromJson`), following the `captureErrors` / `operationNameAsParameter` pattern.
2. **Hash computation** — one shared helper (not per language), run after the final query strings are built; exposes `hashFor(operation)`.
3. **Extension** — getter on the parser extension layer returning the operation → hash map, so generators never recompute.
4. **Serializers** — each client serializer's execute path reads the hash const and builds the request per mode. The shared `executeFull/Data/Cached` helpers are the single place to branch, not every operation method.
5. **Manifest writer** — in the generator layer (alongside barrel file handling), emitted once per run.

## Interaction With Existing Features

- **`@glCache` partial/divided queries** — each divided sub-query is its own operation with its own hash.
- **`operationNameAsParameter`** — unchanged; operation name stays in the URL/body.
- **`@glCaptureErrors`** — `PersistedQueryNotFound` is protocol-level and must be handled before capture logic, never surfaced as a captured error on the first attempt.
- **Uploads (multipart)** — not persisted in phase 1; always sent with the full query.
- **Subscriptions** — unchanged in phase 1.
- **Dynamically built queries** (see the "missing space between fields" fix) — operations whose string is assembled at runtime cannot have a build-time hash; they fall back to sending the full query. See Open Questions.

---

## Server Targets

- **Express/Apollo** — Apollo Server supports APQ natively; document enabling it. Manifest mode: optionally generate a small loader that reads the manifest and plugs it into the persisted-queries cache/safelist.
- **Spring** — no built-in equivalent that we have verified. Decide whether to generate an interceptor (`WebGraphQlInterceptor`) that resolves hashes from the manifest. APQ registration on Spring is out of scope for phase 1 unless trivial.

---

## Testing

- `test/persisted_queries/` — inline-schema tests asserting: hash const emitted, hash equals SHA-256 of the emitted query string, mode `false` emits nothing new, manifest contains every operation incl. divided ones, bad config value rejected with a clear error.
- Hash stability test: same schema → same hashes across runs.
- Integration: `server_integration_tests` matrix — Express/Apollo server (APQ native) driven by each generated client in `apq` mode; manifest mode against a server that loads the manifest.

---

## Rollout

1. Core: config, hash helper, manifest writer, tests (language-independent).
2. First client (TypeScript — fastest to validate against Apollo Server), then Dart, Java, Kotlin, Swift.
3. Server-side support (Express loader; Spring decision).
4. Docs: new `persisted-queries.md` page, config reference, llms sources.
5. Changelog entry as a new feature (minor version).

---

## Open Questions

1. **Dynamically assembled queries** — fall back to full query, or hash at runtime? Runtime hashing needs SHA-256 in generated code (dependency-free in Java/Kotlin/Swift/Dart stdlib exists, TypeScript does not outside `crypto.subtle`). Leaning: fall back, and make manifest mode reject such operations at generation time with a clear error.
2. **Hash scope for fragments** — confirm the hash covers the full string sent, not just the operation document.
3. **Spring server story** — generate an interceptor or document only.
4. **GET + `@glCache`** — whether GET responses interact with client-side cache keys (likely not; cache keys already derive from operation + variables).
5. **Manifest per language or single** — one manifest per `glink` run vs one per client target when several targets share a schema (leaning: one per run, since hashes are language-independent).
