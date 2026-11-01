# Persisted Queries — Feature Plan

## Overview

Let generated clients send a hash of an operation instead of the full query text.

- **APQ (Automatic Persisted Queries)** — Apollo protocol, **phase 1**. The client sends `sha256Hash`; on `PersistedQueryNotFound`
  it retries once with the full query and the hash, which makes the server register it. No build step and no server-side manifest.
  The retry is invisible to the caller.
- **Manifest (pre-registered / safelist)** — **deferred**. Needs every possible query at build time. See "Manifest (later)".

Applies to every client target (Dart, Java, Kotlin, TypeScript, Swift). Dart goes first. This document fixes the language-independent
contract and records the decisions taken so far.

The goal is market compatibility: the wire format is exactly what Apollo Client and Apollo Server speak.

---

## Decisions

1. **Phase 1 is APQ only.** Manifest mode needs the opposite assumption (the server rejects unknown queries, so a fallback with the full
   text cannot work) and is parked.
2. **Hashing happens at runtime, over the exact string that is about to be sent.** Not at generation time. Reasons:
   - The query text is not a constant. Fragment bodies are appended at runtime, and `@glCache` splits an operation into partial queries
     whose *remaining* subset is merged into one request. For `n` cached elements there are `2^n − 1` possible texts (order is fixed, so
     combinations, not permutations). Pre-hashing them is exponential, and re-implementing the runtime assembly in the generator risks a
     one-character drift that makes the server reject the registration.
   - Hashing at runtime is O(1) in the number of partials, and cannot disagree with what is sent.
   - Each distinct string is hashed once (per-client memo).
3. **SHA-256 is generated runtime code, with no dependencies.** Each language gets a `GraphLinkSha256.hex(String)` template in its
   `*_client_constants.dart`. Dart, TypeScript, Swift and Kotlin are pure implementations (the Kotlin one uses no `java.*`). Java wraps the
   JDK `MessageDigest`. Every implementation is tested against the same vectors produced by Python's `hashlib` (empty string, `abc`, the
   two-block NIST string, padding boundaries at 55/56/63/64/65 bytes, a 1000-byte input, a non-ASCII string, a real GraphQL document).
4. **`glHash` lives in the shared resolver base class** (`GraphLinkResolverBase` in Dart; the equivalent in the other languages), which
   queries and mutations extend. The base class owns the memo.
5. **Queries and mutations both use persisted queries.** Mutations are always sent over POST. Subscriptions and multipart uploads are
   unchanged in phase 1.
6. **No `persistedQueriesMinLength` option.** Hashing a short query makes the request bigger. The persisted-query payload costs about 112
   characters of JSON (about 144 percent-encoded in a GET), and the hash alone is 64 characters. The rule is internal: skip the hash and
   send the normal query when the assembled string is shorter than that overhead. A single constant derived from the GET overhead serves
   both transports. No Apollo setting for this was found (searched); a knob would only let someone configure a worse request.
7. **The client is stateless about registration.** Every request of an operation starts hash-only. Eviction (server restart, LRU, new
   instance) therefore costs one extra request and nothing else. The only state kept per client instance is "the server does not support
   APQ at all" and "the server does not accept GET", so unsupported servers do not pay a second round trip on every call.
8. **Retries are strict.** The full-query retry happens only on `PersistedQueryNotFound`, and the "stop trying" flags are set only on
   `PersistedQueryNotSupported` or a missing-query / 405 style answer. Never on timeouts, 5xx or other errors. This matters most for
   mutations: not-found is returned before anything runs, so re-sending is safe, but retrying an ambiguous failure could run a
   mutation twice.
9. **A separate GET adapter** (see "Adapters").

---

## Config

New client option, per target, default off:

```json
"clientConfig": {
  "dart": {
    "persistedQueries": "apq",
    "persistedQueriesUseGet": true
  }
}
```

| Option | Values | Default | Behavior |
|--------|--------|---------|----------|
| `persistedQueries` | `false`, `"apq"` | `false` | `false` leaves output unchanged. `"apq"` hashes and retries. Any other value (`true`, `"manifest"`, typos) is rejected with `persistedQueries must be false or "apq"` |
| `persistedQueriesUseGet` | bool | `false` | Send hash-only **queries** through the GET adapter. Requires `persistedQueries: "apq"`; setting it alone is rejected instead of silently ignored |

Both options exist on all five client configs, in `--help`, and in the builder keys. The parser exposes them as booleans
(`GLParser.persistedQueries`, `GLParser.persistedQueriesUseGet`), set in `createGrammar`.

---

## Wire Format

**APQ request, hash only**

```json
{
  "operationName": "GetUser",
  "variables": { "id": "1" },
  "extensions": { "persistedQuery": { "version": 1, "sha256Hash": "<hash>" } }
}
```

The hash is SHA-256 (hex, lowercase) of the query text exactly as it would be sent, including the fragments appended to it.

On `PersistedQueryNotFound` (an error entry whose message is `PersistedQueryNotFound` or whose `extensions.code` is
`PERSISTED_QUERY_NOT_FOUND`), resend once with `"query"` added **and the same `extensions`**. Sending both is what makes the server
register the query. A second failure surfaces as a normal error.

`PersistedQueryNotSupported` means the server has APQ switched off: send the full query now and for the rest of this client's life.

**GET** (queries only, when `persistedQueriesUseGet`): `?operationName=…&variables=<json>&extensions=<json>`. Variables and extensions are
JSON in the URL and must be percent-encoded. The retry that registers the query is always a **POST**, because a full query may not fit
in a URL.

### The flow

| # | Request | Server answer |
|---|---------|---------------|
| 1 | Query: `GET …?operationName&variables&extensions` (hash only). Mutation: `POST` hash only | `PersistedQueryNotFound` on a cold or evicted server |
| 2 | `POST` with `query` + same `extensions` | Runs the operation and registers it |
| 3 | Same as 1 from now on | Data |

---

## Adapters

The existing adapter, `Future<String> Function(String payload)`, is unchanged and is used for POST. It now receives hash-only payloads
(no `query` field) for persisted operations. Custom adapters that forward the body as-is keep working; one that requires `query` must be
updated, so this is documented as a behavior change of enabling the option.

**GET adapter:** `Future<String> Function(String payload) getAdapter`, same signature as the POST adapter.

- The core never knows the base URL, so it cannot build a GET URL. It hands the GET adapter the same JSON payload it would POST
  (`operationName`, `variables`, `extensions`, no `query`), and the adapter turns the fields into the query string.
- A default implementation is generated next to the existing http/dio adapters. It JSON-decodes the payload, percent-encodes the three
  fields, and issues the GET.
- With `persistedQueriesUseGet`, the generated `withHttp` constructors wire both adapters. With `httpAdapter: none`, `getAdapter` is a
  required constructor argument, like `adapter`.
- If the server does not accept GET (for example a 405), the adapter throws `GraphLinkGetNotSupported`. The core then POSTs this request
  and remembers that GET is unsupported for the client. Any other exception from the GET adapter propagates untouched; there is no
  blanket fallback, because that would hide real network errors by sending the request twice.
- Mutations never use the GET adapter.

---

## Generator Changes

1. **Config** — done (see Config). Follows the `captureErrors` / `strictEnums` pattern.
2. **Runtime SHA-256** — done in all five `*_client_constants.dart` files, with tests.
3. **Emission** — when `persistedQueries` is on: emit the SHA-256 file, and add `glHash` with its memo to the shared base class. Output is
   byte-identical when the option is off. Dart is done.
4. **Request flow** — one place in the base class (the `glCallAdapter` / `executeFull/Data/Cached` path), not every operation method:
   decide hash vs full text by length, send hash-only, detect `PersistedQueryNotFound` in the response, retry with the query. This must
   happen before `@glCaptureErrors` logic so a not-found is never surfaced as a captured error on the first attempt.
5. **GET adapter** — constructor wiring, default implementation, `GraphLinkGetNotSupported`.
6. **Other languages** — the same flow once Dart is settled.

## Interaction With Existing Features

- **`@glCache` partial queries** — the merged remaining query is hashed as a whole, after assembly. The hash covers the assembled string,
  never the pieces.
- **`operationNameAsParameter`** — unchanged; the operation name stays in the body or URL.
- **`@glCaptureErrors`** — see step 4 above.
- **Client cache keys** — already derive from operation name and variables, so GET responses do not interact with them.
- **Uploads, subscriptions** — unchanged in phase 1.

---

## Manifest (later)

Language-independent: the hash depends only on the final query string, so a manifest is a list of hashes the generator writes, and
adding it does not change the client fallback logic. Two constraints to settle then:

- Only operations whose text is static can be listed. Cached operations produce `2^n − 1` texts, so a policy is needed (for example, the
  full operation plus the single-element subsets).
- A safelist cannot be combined with the full-query fallback, so it is a different mode, not a threshold. The minimum-length rule does
  not apply there: every operation must be listed.

---

## Server Targets

- **Express/Apollo** — Apollo Server supports APQ natively; document enabling it.
- **Spring** — no turnkey support was found. A hash-only request reaches Spring GraphQL as a placeholder document named
  `PersistedQueryMarker` and fails with a syntax error, so a custom `WebGraphQlInterceptor` is needed to resolve hashes, and Spring GraphQL
  accepts only POST on `/graphql`.
- **Integration test server** (`integration_tests/real/spring_server`, package `apq`), hand-written for tests:
  - `PersistedQueryInterceptor` implements the protocol: hash-only lookup, register on query + hash, `PersistedQueryNotFound`,
    `PersistedQueryNotSupported`, and a check that the hash matches the query.
  - `GraphQlGetFilter` turns `GET /graphql?query|operationName|variables|extensions` into the POST the handler already understands, and
    rejects mutations over GET with 405.
  - Test controls: `GET /test/apq` (counters `hits`, `misses`, `registrations`, `stored`, `supported`), `POST /test/apq/reset`,
    `POST /test/apq/evict` (drops stored queries, keeps counters), `POST /test/apq/supported/{true|false}`.
  - The store is an unbounded in-memory map, fine for tests. A production server needs a bounded cache, since anonymous clients can
    register arbitrary queries; this goes in the docs.

---

## Testing

Unit (inline schemas, `test/persisted_queries/`):

- Config parsing for all five languages: default off, `"apq"`, `false`, GET with apq, rejected values, GET without apq. Done.
- The option reaches the parser through `createGrammar`. Done.
- SHA-256 runtimes against the shared vectors, one test per language that runs the generated code with the real toolchain. Done.
- Generated resolver base has `glHash` and the memo only when the option is on, and nothing new when off. Done for Dart.

Mock integration (`integration_tests/mock/*`):

- `glHash` returns reference hashes, shared through the base class. Done for Dart.
- Fallback with the mock adapter: hash-only attempt, retry with query and hash on `PersistedQueryNotFound`, no retry on other errors, no
  hashing below the length threshold, the unsupported-server flag, GET adapter routing and `GraphLinkGetNotSupported`. The mock adapter
  must accept payloads without a `query` field (it currently reads the operation name from the query text).

Real server (`integration_tests/real/*`, against the Spring test server):

- Cold hash-only GET, POST registration, warm GET, eviction then re-registration (`/test/apq/evict`), unsupported server
  (`/test/apq/supported/false`), mutation over POST, with the counters asserting how many requests were really made.

Each assertion about hashes needs a query longer than the internal threshold, so the integration schemas include deliberately long
queries, and short ones to prove no hash is sent.

---

## Rollout

1. Config, runtime SHA-256, `glHash` in the Dart base class. **Done.**
2. Dart request flow in the base class (queries and mutations), mock-adapter tests first. **Done**
   (`dart_persisted_queries_tests`, a separate project so the call-count assertions of the main Dart mock suite stay untouched).
3. GET adapter for Dart: `getAdapter` constructor wiring, `getCall` on the http and Dio default adapters (shared
   `GraphLinkGetRequest.queryParameters`), `GraphLinkGetNotSupported` on a 405. **Done.** The http adapter is tested against a local
   `HttpServer`; the Dio adapter is covered by generator tests only.
4. Dart real-server tests against the Spring test server.
5. Remaining languages, one at a time, order TypeScript, Kotlin, Swift, then Java and Java reactive. Until a language lands, its
   generator rejects `persistedQueries: "apq"` (`_persistedQueriesLanguages` in `config.dart`).
   - TypeScript: **Done** (`typescript_persisted_queries_tests`; `getAdapter` is a positional argument right after `adapter`;
     `createFetchGetAdapter` / `createAxiosGetAdapter`; fetch adapter tested against a local Node server, axios by generator tests only).
   - Kotlin: **Done** (`kotlin_persisted_queries_tests`; `getAdapter` right after `adapter`; `DefaultGraphLinkGetAdapter` on OkHttp,
     tested against a local JDK `HttpServer`; the resolver base's hash memo is a `ConcurrentHashMap`, which the pure-core plan
     will have to replace together with `tagLocks`).
   - Swift: **Done** (`swift_persisted_queries_tests`; `getAdapter` closure right after `adapter`; hashes and the two refusal flags live
     in a lock-guarded `GraphLinkPersistedQueryState`; `DefaultGraphLinkURLSessionGetAdapter` is tested through a stub `URLProtocol`,
     including `+` escaping in variables).
   - Java (blocking): **Done** (`java_persisted_queries_tests`, Maven + Jackson; `getAdapter` right after `adapter`; the hash memo is a
     `ConcurrentHashMap`, the flags are `volatile`; `GraphLinkGetNotSupported` and `GraphLinkGetRequest` are public classes in their
     own files, because a Java file can hold one public class; `DefaultGraphLinkGetAdapter` exists for the JDK and OkHttp
     transports, the JDK one is tested against a local `HttpServer`, the OkHttp one by generator tests only). Reactive styles
     (`reactor`, `rxjava3`, `mutiny`) are still rejected at config time.
6. Docs: new `persisted-queries.md` page, config reference, `--help`, llms sources; document bounded server caches.
7. Changelog entry as a new feature (minor version).

---

## Open Questions

1. **Mock adapters** across the five suites must learn to read hash-only payloads. Decide whether the shared change is a small helper or
   per-language edits.
2. **Exact internal threshold value** (about 150 characters from the GET overhead). Confirm against the real encoded size per language.
3. **`GraphLinkGetNotSupported` placement** in each language (exception type next to the existing client exception).
4. **Server story for production Spring users**: document the interceptor approach only, or ship a reusable interceptor later.
5. **Subscriptions over WebSocket** — phase 2 if wanted.
